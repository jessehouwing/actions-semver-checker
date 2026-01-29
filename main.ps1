#############################################################################
# Actions SemVer Checker - Main Script
#############################################################################
# This script validates semantic version tags and branches in a GitHub
# repository to ensure proper version management for GitHub Actions.
#
# Key responsibilities:
# 1. Validate that floating versions (v1, v1.0) point to correct patches
# 2. Check that releases exist and are immutable
# 3. Detect ambiguous refs (both tag and branch for same version)
# 4. Auto-fix issues when enabled (requires contents: write permission)
#############################################################################

#############################################################################
# MODULE IMPORTS
#############################################################################

. "$PSScriptRoot/lib/StateModel.ps1"
. "$PSScriptRoot/lib/Logging.ps1"
. "$PSScriptRoot/lib/VersionParser.ps1"
. "$PSScriptRoot/lib/GitHubApi.ps1"
. "$PSScriptRoot/lib/RemediationActions.ps1"
. "$PSScriptRoot/lib/Remediation.ps1"

#############################################################################
# GLOBAL STATE
#############################################################################

# Initialize repository state - this is the ONLY script-level variable
$script:State = [RepositoryState]::new()

#############################################################################
# REPOSITORY DETECTION
#############################################################################

# Set default URLs in State
$script:State.ApiUrl = $env:GITHUB_API_URL ?? "https://api.github.com"
$script:State.ServerUrl = $env:GITHUB_SERVER_URL ?? "https://github.com"
$script:State.Token = $env:GITHUB_TOKEN ?? ""

# Parse repository owner and name from GITHUB_REPOSITORY
if ($env:GITHUB_REPOSITORY) {
    $parts = $env:GITHUB_REPOSITORY -split '/', 2
    if ($parts.Count -eq 2 -and $parts[0] -and $parts[1]) {
        $script:State.RepoOwner = $parts[0]
        $script:State.RepoName = $parts[1]
    }
}

# If still not found, fall back to git remote
if (-not $script:State.RepoOwner -or -not $script:State.RepoName) {
    $remoteUrl = & git config --get remote.origin.url 2>$null
    if ($remoteUrl) {
        # Parse owner/repo from various Git URL formats
        # SSH: git@hostname:owner/repo.git
        # HTTPS: https://hostname/owner/repo.git
        # Handle both github.com and GitHub Enterprise Server
        if ($remoteUrl -match '(?:https?://|git@)([^/:]+)[:/]([^/]+)/([^/]+?)(\.git)?$') {
            $hostname = $matches[1]
            $script:State.RepoOwner = $matches[2]
            $script:State.RepoName = $matches[3]
            
            # Update server URL based on the parsed hostname
            if ($hostname -ne "github.com") {
                $script:State.ServerUrl = "https://$hostname"
                # For GHE, API URL is typically https://hostname/api/v3
                if ($script:State.ApiUrl -eq "https://api.github.com") {
                    $script:State.ApiUrl = "https://$hostname/api/v3"
                }
            }
        }
    }
}

#############################################################################
# INPUT PARSING AND VALIDATION
#############################################################################

# Read inputs from JSON environment variable
if (-not $env:inputs) {
    Write-Host "::error::inputs environment variable is not set"
    exit 1
}

try {
    $inputs = $env:inputs | ConvertFrom-Json
    
    # Helper function to normalize check input values (accept boolean or string)
    function Normalize-CheckInput {
        param(
            [string]$value,
            [string]$default
        )
        
        $normalized = ($value ?? $default).Trim().ToLower()
        
        # Map boolean values to error/none
        if ($normalized -eq "true") {
            return "error"
        } elseif ($normalized -eq "false") {
            return "none"
        }
        
        return $normalized
    }
    
    # Parse inputs with defaults
    $script:State.Token = $inputs.token ?? $script:State.Token
    
    $checkMinorVersion = Normalize-CheckInput -value (($inputs.'check-minor-version' ?? "true") -as [string]) -default "error"
    $checkReleases = Normalize-CheckInput -value (($inputs.'check-releases' ?? "error") -as [string]) -default "error"
    $checkReleaseImmutability = Normalize-CheckInput -value (($inputs.'check-release-immutability' ?? "error") -as [string]) -default "error"
    $ignorePreviewReleases = (($inputs.'ignore-preview-releases' ?? "true") -as [string]).Trim() -eq "true"
    $floatingVersionsUse = (($inputs.'floating-versions-use' ?? "tags") -as [string]).Trim().ToLower()
    $autoFix = (($inputs.'auto-fix' ?? "false") -as [string]).Trim() -eq "true"
    
    # Parse new inputs
    $ignoreVersionsInput = (($inputs.'ignore-versions' ?? "") -as [string]).Trim()
    $ignoreVersions = if ($ignoreVersionsInput) { 
        $ignoreVersionsInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    } else { 
        @() 
    }
    
    # Set configuration in State
    $script:State.CheckMinorVersion = ($checkMinorVersion -ne "none")
    $script:State.CheckReleases = $checkReleases
    $script:State.CheckImmutability = $checkReleaseImmutability
    $script:State.IgnorePreviewReleases = $ignorePreviewReleases
    $script:State.FloatingVersionsUse = $floatingVersionsUse
    $script:State.AutoFix = $autoFix
    $script:State.IgnoreVersions = $ignoreVersions
}
catch {
    Write-Host "::error::Failed to parse inputs JSON"
    exit 1
}

# Debug: Show parsed input values
Write-Host "::debug::=== Parsed Input Values ==="
Write-Host "::debug::auto-fix: $autoFix"
Write-Host "::debug::check-minor-version: $checkMinorVersion"
Write-Host "::debug::check-releases: $checkReleases"
Write-Host "::debug::check-release-immutability: $checkReleaseImmutability"
Write-Host "::debug::ignore-preview-releases: $ignorePreviewReleases"
Write-Host "::debug::floating-versions-use: $floatingVersionsUse"
Write-Host "::debug::ignore-versions: $($ignoreVersions -join ', ')"

# Validate inputs
if ($checkMinorVersion -notin @("error", "warning", "none")) {
    $errorMessage = "::error title=Invalid configuration::check-minor-version must be 'error', 'warning', 'none', 'true', or 'false', got '$checkMinorVersion'"
    Write-Output $errorMessage
    exit 1
}

if ($checkReleases -notin @("error", "warning", "none")) {
    $errorMessage = "::error title=Invalid configuration::check-releases must be 'error', 'warning', 'none', 'true', or 'false', got '$checkReleases'"
    Write-Output $errorMessage
    exit 1
}

if ($checkReleaseImmutability -notin @("error", "warning", "none")) {
    $errorMessage = "::error title=Invalid configuration::check-release-immutability must be 'error', 'warning', 'none', 'true', or 'false', got '$checkReleaseImmutability'"
    Write-Output $errorMessage
    exit 1
}

if ($floatingVersionsUse -notin @("tags", "branches")) {
    $errorMessage = "::error title=Invalid configuration::floating-versions-use must be either 'tags' or 'branches', got '$floatingVersionsUse'"
    Write-Output $errorMessage
    exit 1
}

$useBranches = $floatingVersionsUse -eq "branches"

# Debug output
Write-Host "::debug::Repository: $($script:State.RepoOwner)/$($script:State.RepoName)"
Write-Host "::debug::API URL: $($script:State.ApiUrl)"
Write-Host "::debug::Server URL: $($script:State.ServerUrl)"
Write-Host "::debug::Token available: $(if ($script:State.Token) { 'Yes' } else { 'No' })"
Write-Host "::debug::Check releases: $checkReleases"
Write-Host "::debug::Check release immutability: $checkReleaseImmutability"
Write-Host "::debug::Floating versions use: $floatingVersionsUse"

# Validate git repository configuration
Write-Host "::debug::Validating repository configuration..."

# Check if repository is a shallow clone
if (Test-Path ".git/shallow") {
    $errorMessage = "::error title=Shallow clone detected::Repository is a shallow clone (fetch-depth: 1). This action requires full git history. Please configure your checkout action with 'fetch-depth: 0'.%0A%0AExample:%0A  - uses: actions/checkout@v4%0A    with:%0A      fetch-depth: 0%0A      fetch-tags: true"
    Write-Output $errorMessage
    $global:returnCode = 1
    exit 1
}

# Check if tags were fetched
$allTags = & git tag -l 2>$null
if (-not $allTags -or $allTags.Count -eq 0) {
    $warningMessage = "::warning title=No tags found::No git tags found in repository. This could mean:%0A  1. The repository has no tags yet (expected for new repositories)%0A  2. Tags were not fetched (fetch-tags: false)%0A%0AIf you expect tags to exist, please configure your checkout action with 'fetch-tags: true'.%0A%0AExample:%0A  - uses: actions/checkout@v4%0A    with:%0A      fetch-depth: 0%0A      fetch-tags: true"
    Write-Output $warningMessage
}

# Configure git credentials for auto-fix mode if needed
if ($autoFix) {
    Write-Host "::debug::Auto-fix mode enabled, configuring git credentials..."
    
    if (-not $script:State.Token) {
        $errorMessage = "::error title=Auto-fix requires token::Auto-fix mode is enabled but no GitHub token is available. Please provide a token via the 'token' input or ensure GITHUB_TOKEN is available.%0A%0AExample:%0A  - uses: jessehouwing/actions-semver-checker@v2%0A    with:%0A      auto-fix: true%0A      token: `${{ secrets.GITHUB_TOKEN }}"
        Write-Output $errorMessage
        $global:returnCode = 1
        exit 1
    }
    
    # Configure git to use token for authentication
    # This handles cases where checkout action used persist-credentials: false
    try {
        # Configure credential helper to use the token
        & git config --local credential.helper "" 2>$null
        & git config --local credential.helper "!f() { echo username=x-access-token; echo password=$($script:State.Token); }; f" 2>$null
        
        # Configure git user identity for GitHub Actions bot
        & git config --local user.name "github-actions[bot]" 2>$null
        & git config --local user.email "github-actions[bot]@users.noreply.github.com" 2>$null
        
        # Also set up the URL rewrite to use HTTPS with token
        $remoteUrl = & git config --get remote.origin.url 2>$null
        if ($remoteUrl -and $remoteUrl -match '^https://') {
            Write-Host "::debug::Configured git credential helper for HTTPS authentication"
        }
        elseif ($remoteUrl -and $remoteUrl -match '^git@') {
            # Wrap remote URL in stop-commands to prevent workflow command injection
            Write-SafeOutput -Message "$remoteUrl). Auto-fix may fail if SSH credentials are not available. Consider using HTTPS remote with checkout action." -Prefix "::warning title=SSH remote detected::Remote URL uses SSH ("
        }
    }
    catch {
        # Wrap exception message in stop-commands to prevent workflow command injection
        Write-SafeOutput -Message ([string]$_) -Prefix "::warning title=Git configuration warning::Could not configure git credentials: "
    }
}

$tags = & git tag -l v* | Where-Object{ return ($_ -match "^v\d+(\.\d+){0,2}$") }
Write-Host "::debug::Found $($tags.Count) version tags: $($tags -join ', ')"

$branches = & git branch --list --quiet --remotes | Where-Object{ return ($_.Trim() -match "^origin/(v\d+(\.\d+){0,2}(-.*)?)$") } | ForEach-Object{ $_.Trim().Replace("origin/", "")}

$tagVersions = @()
$branchVersions = @()

$suggestedCommands = @()

# Auto-fix tracking variables are initialized in GLOBAL STATE section above

#############################################################################
# UTILITY FUNCTIONS
#############################################################################
# Utility functions have been moved to lib/ modules:
# - Write-SafeOutput, write-actions-* -> lib/Logging.ps1
# - ConvertTo-Version -> lib/VersionParser.ps1
# - Get-ApiHeaders, Get-GitHubRepoInfo, Get-GitHubReleases, etc. -> lib/GitHubApi.ps1
# - Invoke-AutoFix, Get-ImmutableReleaseRemediationCommands -> lib/Remediation.ps1
#############################################################################

#############################################################################
# STATE SUMMARY DISPLAY
#############################################################################

function Write-StateSummary {
    param(
        [array]$Tags,
        [array]$Branches,
        [array]$Releases,
        [string]$Title = "Repository State Summary"
    )
    
    Write-Host ""
    Write-Host "=============================================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "=============================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Tags: $($Tags.Count)" -ForegroundColor White
    if ($Tags.Count -gt 0 -and $Tags.Count -le 20) {
        foreach ($tag in ($Tags | Sort-Object version)) {
            $shaShort = if ($tag.sha -and $tag.sha.Length -ge 7) { $tag.sha.Substring(0, 7) } else { "unknown" }
            $versionType = if ($tag.isMajorVersion) { "major" } elseif ($tag.isMinorVersion) { "minor" } else { "patch" }
            Write-Host "  $($tag.version) -> $shaShort ($versionType)" -ForegroundColor Gray
        }
    } elseif ($Tags.Count -gt 20) {
        Write-Host "  (showing first 10 of $($Tags.Count) tags)" -ForegroundColor Gray
        foreach ($tag in ($Tags | Sort-Object version | Select-Object -First 10)) {
            $shaShort = if ($tag.sha -and $tag.sha.Length -ge 7) { $tag.sha.Substring(0, 7) } else { "unknown" }
            $versionType = if ($tag.isMajorVersion) { "major" } elseif ($tag.isMinorVersion) { "minor" } else { "patch" }
            Write-Host "  $($tag.version) -> $shaShort ($versionType)" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "Branches: $($Branches.Count)" -ForegroundColor White
    if ($Branches.Count -gt 0 -and $Branches.Count -le 15) {
        foreach ($branch in ($Branches | Sort-Object version)) {
            $shaShort = if ($branch.sha -and $branch.sha.Length -ge 7) { $branch.sha.Substring(0, 7) } else { "unknown" }
            $versionType = if ($branch.isMajorVersion) { "major" } elseif ($branch.isMinorVersion) { "minor" } else { "patch" }
            Write-Host "  $($branch.version) -> $shaShort ($versionType)" -ForegroundColor Gray
        }
    } elseif ($Branches.Count -gt 15) {
        Write-Host "  (showing first 10 of $($Branches.Count) branches)" -ForegroundColor Gray
        foreach ($branch in ($Branches | Sort-Object version | Select-Object -First 10)) {
            $shaShort = if ($branch.sha -and $branch.sha.Length -ge 7) { $branch.sha.Substring(0, 7) } else { "unknown" }
            $versionType = if ($branch.isMajorVersion) { "major" } elseif ($branch.isMinorVersion) { "minor" } else { "patch" }
            Write-Host "  $($branch.version) -> $shaShort ($versionType)" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "Releases: $($Releases.Count)" -ForegroundColor White
    if ($Releases.Count -gt 0 -and $Releases.Count -le 15) {
        foreach ($release in ($Releases | Sort-Object tagName)) {
            $status = @()
            if ($release.isDraft) { $status += "draft" }
            if ($release.isPrerelease) { $status += "prerelease" }
            $statusStr = if ($status.Count -gt 0) { " [$($status -join ', ')]" } else { "" }
            Write-Host "  $($release.tagName)$statusStr" -ForegroundColor Gray
        }
    } elseif ($Releases.Count -gt 15) {
        Write-Host "  (showing first 10 of $($Releases.Count) releases)" -ForegroundColor Gray
        foreach ($release in ($Releases | Sort-Object tagName | Select-Object -First 10)) {
            $status = @()
            if ($release.isDraft) { $status += "draft" }
            if ($release.isPrerelease) { $status += "prerelease" }
            $statusStr = if ($status.Count -gt 0) { " [$($status -join ', ')]" } else { "" }
            Write-Host "  $($release.tagName)$statusStr" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "=============================================================================" -ForegroundColor Cyan
    Write-Host ""
}

#############################################################################
# MAIN EXECUTION
#############################################################################

# Get repository info for URLs
$repoInfo = Get-GitHubRepoInfo -State $script:State

# Check permissions if auto-fix is enabled
if ($autoFix -and $repoInfo) {
    Write-Host "::debug::Checking GitHub token permissions..."
    
    # For token permission checks, we need to check if the token has appropriate scopes
    # GitHub Actions tokens typically have contents: write by default when permissions are not explicitly set
    # However, actions: write requires explicit permission in the workflow
    
    # Check if GITHUB_TOKEN has necessary permissions by examining the context
    # The GITHUB_TOKEN permissions are set at the workflow/job level
    # We'll provide a helpful error message if auto-fix operations fail
    
    # Note: GitHub API doesn't expose token permissions directly via a simple endpoint
    # The permissions are workflow-level configuration, not token-level metadata
    # We'll validate this at the workflow configuration level in documentation
    # and provide clear error messages when operations fail due to insufficient permissions
    
    Write-Host "::debug::Auto-fix is enabled. Ensure your workflow has 'contents: write' permission."
    Write-Host "::debug::If pushing changes to workflow files, 'actions: write' permission is also required."
    Write-Host "::debug::Example workflow permissions:"
    Write-Host "::debug::  permissions:"
    Write-Host "::debug::    contents: write"
    Write-Host "::debug::    actions: write"
}

# Get GitHub releases if check is enabled
$releases = @()
$releaseMap = @{}
if (($checkReleases -ne "none" -or $checkReleaseImmutability -ne "none" -or $ignorePreviewReleases) -and $repoInfo)
{
    $releases = Get-GitHubReleases -State $script:State
    # Create a map for quick lookup
    foreach ($release in $releases)
    {
        $releaseMap[$release.tagName] = $release
    }
}

foreach ($tag in $tags)
{
    $isPrerelease = $false
    if ($ignorePreviewReleases -and $releaseMap.ContainsKey($tag))
    {
        $isPrerelease = $releaseMap[$tag].isPrerelease
    }
    
    # Determine if this is a patch version (vX.Y.Z) or a floating version (vX or vX.Y)
    # Strip any prerelease suffix (e.g., -beta) before counting parts
    $versionWithoutPrefix = $tag.Substring(1)
    $versionCore = $versionWithoutPrefix -split '-' | Select-Object -First 1
    $versionParts = $versionCore -split '\.'
    $isPatchVersion = $versionParts.Count -eq 3
    $isMinorVersion = $versionParts.Count -eq 2
    $isMajorVersion = $versionParts.Count -eq 1
    
    $tagVersions += @{
        version = $tag
        ref = "refs/tags/$tag"
        sha = & git rev-list -n 1 $tag
        semver = ConvertTo-Version $tag.Substring(1)
        isPrerelease = $isPrerelease
        isPatchVersion = $isPatchVersion
        isMinorVersion = $isMinorVersion
        isMajorVersion = $isMajorVersion
    }
    
    Write-Host "::debug::Parsed tag $tag - isPatch:$isPatchVersion isMinor:$isMinorVersion isMajor:$isMajorVersion parts:$($versionParts.Count)"
}

$latest = & git tag -l latest
$latestBranch = $null
if ($latest)
{
    $latest = @{
        version = "latest"
        ref = "refs/tags/latest"
        sha = & git rev-list -n 1 latest
        semver = $null
    }
}

# Also check for latest branch (regardless of floating-versions-use setting)
# This allows us to warn when latest exists as wrong type
$latestBranchExists = & git branch --list --quiet --remotes origin/latest
if ($latestBranchExists) {
    $latestBranch = @{
        version = "latest"
        ref = "refs/remotes/origin/latest"
        sha = & git rev-parse refs/remotes/origin/latest
        semver = $null
    }
}

foreach ($branch in $branches)
{
    # Determine if this is a patch version (vX.Y.Z) or a floating version (vX or vX.Y)
    # Strip any prerelease suffix (e.g., -beta) before counting parts
    $versionWithoutPrefix = $branch.Substring(1)
    $versionCore = $versionWithoutPrefix -split '-' | Select-Object -First 1
    $versionParts = $versionCore -split '\.'
    $isPatchVersion = $versionParts.Count -eq 3
    $isMinorVersion = $versionParts.Count -eq 2
    $isMajorVersion = $versionParts.Count -eq 1
    
    $branchVersions += @{
        version = $branch
        ref = "refs/remotes/origin/$branch"
        sha = & git rev-parse refs/remotes/origin/$branch
        semver = ConvertTo-Version $branch.Substring(1)
        isPrerelease = $false  # Branches are not considered prereleases
        isPatchVersion = $isPatchVersion
        isMinorVersion = $isMinorVersion
        isMajorVersion = $isMajorVersion
    }
}

foreach ($tagVersion in $tagVersions)
{
    $branchVersion = $branchVersions | Where-Object{ $_.version -eq $tagVersion.version } | Select-Object -First 1

    if ($branchVersion)
    {
        #############################################################################
        # VALIDATION: Ambiguous References
        # Check for versions that exist as both tag AND branch
        # This causes confusion for users and must be resolved
        #############################################################################
        
        $message = "title=Ambiguous version: $($tagVersion.version)::Exists as both tag ($($tagVersion.sha)) and branch ($($branchVersion.sha))"
        
        # Determine which reference to keep based on floating-versions-use setting
        $keepBranch = ($useBranches -eq $true)
        
        if ($branchVersion.sha -eq $tagVersion.sha)
        {
            # Same SHA - can auto-fix by removing the non-preferred reference
            $severity = "warning"
            $issue = [ValidationIssue]::new("ambiguous_reference", $severity, "Version $($tagVersion.version) exists as both tag and branch (same SHA)")
            $issue.Version = $tagVersion.version
            $issue.CurrentSha = $tagVersion.sha
            $State.AddIssue($issue)
            
            if ($keepBranch)
            {
                # Keep branch, remove tag
                $fixCmd = "git push origin :refs/tags/$($tagVersion.version)"
                $fixDescription = "Remove ambiguous tag for $($tagVersion.version) (keeping branch)"
            }
            else
            {
                # Keep tag, remove branch (default)
                $fixCmd = "git push origin :refs/heads/$($tagVersion.version)"
                $fixDescription = "Remove ambiguous branch for $($tagVersion.version) (keeping tag)"
            }
            
            $issue.ManualFixCommand = $fixCmd
            $issue.IsAutoFixable = $true
            # Use RemediationAction class - determine action based on keepBranch
            if ($keepBranch) {
                $issue.RemediationAction = [DeleteTagAction]::new($tagVersion.version)
            } else {
                $issue.RemediationAction = [DeleteBranchAction]::new($tagVersion.version)
            }
            
            if (-not $autoFix)
            {
                write-actions-warning "::warning $message"
                $suggestedCommands += $fixCmd
            }
        }
        else
        {
            # Different SHAs - can auto-fix by removing the non-preferred reference
            $severity = "error"
            $issue = [ValidationIssue]::new("ambiguous_reference", $severity, "Version $($tagVersion.version) exists as both tag and branch (different SHAs)")
            $issue.Version = $tagVersion.version
            $issue.CurrentSha = $tagVersion.sha
            $State.AddIssue($issue)
            
            if ($keepBranch)
            {
                # Keep branch, remove tag
                $fixCmd = "git push origin :refs/tags/$($tagVersion.version)"
                $fixDescription = "Remove ambiguous tag for $($tagVersion.version) (keeping branch at $($branchVersion.sha))"
            }
            else
            {
                # Keep tag, remove branch (default)
                $fixCmd = "git push origin :refs/heads/$($tagVersion.version)"
                $fixDescription = "Remove ambiguous branch for $($tagVersion.version) (keeping tag at $($tagVersion.sha))"
            }
            
            $issue.ManualFixCommand = $fixCmd
            $issue.IsAutoFixable = $true
            # Use RemediationAction class - determine action based on keepBranch
            if ($keepBranch) {
                $issue.RemediationAction = [DeleteTagAction]::new($tagVersion.version)
            } else {
                $issue.RemediationAction = [DeleteBranchAction]::new($tagVersion.version)
            }
            
            if (-not $autoFix)
            {
                write-actions-error "::error $message"
                $suggestedCommands += $fixCmd
            }
        }
    }
}

# Display current repository state summary
Write-StateSummary -Tags $tagVersions -Branches $branchVersions -Releases $releases -Title "Current Repository State"

# Validate that floating versions (vX or vX.Y) have corresponding patch versions
$allVersions = $tagVersions + $branchVersions
Write-Host "::debug::Validating floating versions. Total versions: $($allVersions.Count) (tags: $($tagVersions.Count), branches: $($branchVersions.Count))"

foreach ($version in $allVersions)
{
    Write-Host "::debug::Checking version $($version.version) - isMajor:$($version.isMajorVersion) isMinor:$($version.isMinorVersion) isPatch:$($version.isPatchVersion)"
    
    if ($version.isMajorVersion)
    {
        # Check if any patch versions exist for this major version
        $patchVersionsExist = $allVersions | Where-Object { 
            $_.isPatchVersion -and $_.semver.major -eq $version.semver.major 
        }
        
        Write-Host "::debug::Major version $($version.version) - found $($patchVersionsExist.Count) patch versions"
        
        # Note: Missing patch versions will be detected and auto-fixed in the version consistency checks below
        # We don't need to report errors here to avoid redundant error messages
    }
    elseif ($version.isMinorVersion)
    {
        # Check if any patch versions exist for this minor version
        $patchVersionsExist = $allVersions | Where-Object { 
            $_.isPatchVersion -and 
            $_.semver.major -eq $version.semver.major -and 
            $_.semver.minor -eq $version.semver.minor 
        }
        
        Write-Host "::debug::Minor version $($version.version) - found $($patchVersionsExist.Count) patch versions"
        
        # Note: Missing patch versions will be detected and auto-fixed in the version consistency checks below
        # We don't need to report errors here to avoid redundant error messages
    }
}

#############################################################################
# VALIDATION: Patch Version Releases
# Every patch version (vX.Y.Z) should have a corresponding GitHub Release
#############################################################################

if ($checkReleases -ne "none")
{
    $releaseTagNames = $releases | ForEach-Object { $_.tagName }
    
    foreach ($tagVersion in $tagVersions)
    {
        # Only check patch versions (vX.Y.Z format with 3 parts) - floating versions don't need releases
        if ($tagVersion.isPatchVersion)
        {
            $hasRelease = $releaseTagNames -contains $tagVersion.version
            
            if (-not $hasRelease)
            {
                $messageType = if ($checkReleases -eq "error") { "error" } else { "warning" }
                $messageFunc = if ($checkReleases -eq "error") { "write-actions-error" } else { "write-actions-warning" }
                & $messageFunc "::$messageType title=Missing release::Version $($tagVersion.version) does not have a GitHub Release"
                
                $issue = [ValidationIssue]::new("missing_release", $messageType, "Version $($tagVersion.version) does not have a GitHub Release")
                $issue.Version = $tagVersion.version
                $issue.IsAutoFixable = $true
                $issue.RemediationAction = [CreateReleaseAction]::new($tagVersion.version, $true)
                $State.AddIssue($issue)
                
                # If release immutability checking is enabled, also create a follow-up action to publish the draft
                if ($checkReleaseImmutability -ne "none") {
                    $publishIssue = [ValidationIssue]::new("unpublished_draft", "info", "Draft release $($tagVersion.version) needs to be published")
                    $publishIssue.Version = $tagVersion.version
                    $publishIssue.IsAutoFixable = $true
                    $publishIssue.RemediationAction = [PublishReleaseAction]::new($tagVersion.version)  # ReleaseId will be looked up
                    $State.AddIssue($publishIssue)
                }
                
                if (-not $autoFix)
                {
                    $suggestedCommands += "gh release create $($tagVersion.version) --draft --title `"$($tagVersion.version)`" --notes `"Release $($tagVersion.version)`""
                    if ($repoInfo) {
                        $suggestedCommands += "gh release edit $($tagVersion.version) --draft=false  # Or edit at: $($repoInfo.Url)/releases/edit/$($tagVersion.version)"
                    } else {
                        $suggestedCommands += "gh release edit $($tagVersion.version) --draft=false"
                    }
                }
            }
        }
    }
}

# Check that releases are immutable (not draft, which allows tag changes)
# Use GitHub's immutable field to check if a release is truly immutable
if ($checkReleaseImmutability -ne "none" -and $releases.Count -gt 0)
{
    foreach ($release in $releases)
    {
        # Only check releases for patch versions (vX.Y.Z format)
        if ($release.tagName -match "^v\d+\.\d+\.\d+$")
        {
            if ($release.isDraft)
            {
                $messageType = if ($checkReleaseImmutability -eq "error") { "error" } else { "warning" }
                $messageFunc = if ($checkReleaseImmutability -eq "error") { "write-actions-error" } else { "write-actions-warning" }
                & $messageFunc "::$messageType title=Draft release::Release $($release.tagName) is still in draft status, making it mutable. Publish the release to make it immutable."
                
                $issue = [ValidationIssue]::new("draft_release", $messageType, "Release $($release.tagName) is still in draft status, making it mutable")
                $issue.Version = $release.tagName
                $issue.IsAutoFixable = $true
                $issue.RemediationAction = [PublishReleaseAction]::new($release.tagName, $release.id)
                $State.AddIssue($issue)
                
                if (-not $autoFix)
                {
                    if ($repoInfo) {
                        $suggestedCommands += "gh release edit $($release.tagName) --draft=false  # Or edit at: $($repoInfo.Url)/releases/edit/$($release.tagName)"
                    } else {
                        $suggestedCommands += "gh release edit $($release.tagName) --draft=false"
                    }
                }
            }
            else
            {
                # Check if the release is truly immutable using GraphQL
                # Only check if we have repo info
                if ($repoInfo) {
                    $isImmutable = Test-ReleaseImmutability -Owner $repoInfo.Owner -Repo $repoInfo.Repo -Tag $release.tagName -Token $State.Token -ApiUrl $State.ApiUrl
                    if (-not $isImmutable) {
                        # Non-draft release that is not immutable can still be force-pushed
                        
                        # Check if we should republish for immutability
                        # Only if check-release-immutability is enabled (error or warning)
                        if ($checkReleaseImmutability -ne "none") {
                            # Try to republish the release to make it immutable
                            $issue = [ValidationIssue]::new("non_immutable_release", "warning", "Release $($release.tagName) is not immutable")
                            $issue.Version = $release.tagName
                            $issue.IsAutoFixable = $true
                            $issue.RemediationAction = [RepublishReleaseAction]::new($release.tagName)
                            $State.AddIssue($issue)
                            
                            if (-not $autoFix) {
                                write-actions-warning "::warning title=Mutable release::Release $($release.tagName) is published but remains mutable and can be modified via force-push. Enable 'auto-fix' to automatically republish, or see: https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/preventing-changes-to-your-releases"
                                $suggestedCommands += "# Manually republish release $($release.tagName) to make it immutable"
                                $suggestedCommands += "gh release edit $($release.tagName) --draft=true"
                                $suggestedCommands += "gh release edit $($release.tagName) --draft=false"
                            }
                        }
                    }
                }
            }
        }
    }
}

#############################################################################
# VALIDATION: Floating Version Releases (Should Not Exist)
# Floating versions (v1, v1.0, latest) should not have releases
# as they are mutable by design and releases should be immutable
#############################################################################

if (($checkReleases -ne "none" -or $checkReleaseImmutability -ne "none") -and $releases.Count -gt 0)
{
    foreach ($release in $releases)
    {
        # Check if this is a floating version (vX, vX.Y, or "latest")
        $isFloatingVersion = $release.tagName -match "^v\d+$" -or $release.tagName -match "^v\d+\.\d+$" -or $release.tagName -eq "latest"
        
        if ($isFloatingVersion)
        {
            # Check if the release is truly immutable using GraphQL
            $isImmutable = $false
            if (-not $release.isDraft -and $repoInfo)
            {
                # Check immutability via GitHub's GraphQL API
                $isImmutable = Test-ReleaseImmutability -Owner $repoInfo.Owner -Repo $repoInfo.Repo -Tag $release.tagName -Token $State.Token -ApiUrl $State.ApiUrl
            }
            
            if ($isImmutable)
            {
                # Immutable release on a floating version - this is unfixable
                $messageType = if ($checkReleaseImmutability -eq "error" -or $checkReleases -eq "error") { "error" } else { "warning" }
                $messageFunc = if ($checkReleaseImmutability -eq "error" -or $checkReleases -eq "error") { "write-actions-error" } else { "write-actions-warning" }
                & $messageFunc "::$messageType title=Release on floating version::Floating version $($release.tagName) has an immutable release, which conflicts with its mutable nature. This cannot be auto-fixed."
                
                $issue = [ValidationIssue]::new("immutable_floating_release", $messageType, "Floating version $($release.tagName) has an immutable release")
                $issue.Version = $release.tagName
                $issue.Status = "unfixable"
                $State.AddIssue($issue)
                
                $suggestedCommands += "# WARNING: Cannot delete immutable release for $($release.tagName). Floating versions should not have releases."
            }
            else
            {
                # Mutable release (draft or not immutable) on a floating version - can be auto-fixed by deleting it
                $fixCmd = "gh release delete $($release.tagName) --yes"
                
                $issue = [ValidationIssue]::new("mutable_floating_release", "warning", "Floating version $($release.tagName) has a mutable release")
                $issue.Version = $release.tagName
                $issue.ManualFixCommand = $fixCmd
                $issue.IsAutoFixable = $true
                $issue.RemediationAction = [DeleteReleaseAction]::new($release.tagName, $release.id)
                $State.AddIssue($issue)
                
                if (-not $autoFix)
                {
                    $messageType = if ($checkReleaseImmutability -eq "error" -or $checkReleases -eq "error") { "error" } else { "warning" }
                    $messageFunc = if ($checkReleaseImmutability -eq "error" -or $checkReleases -eq "error") { "write-actions-error" } else { "write-actions-warning" }
                    & $messageFunc "::$messageType title=Release on floating version::Floating version $($release.tagName) has a mutable release, which should be removed."
                    $suggestedCommands += $fixCmd
                }
            }
        }
    }
}

$allVersions = $branchVersions + $tagVersions

# Filter out preview releases if requested
$versionsForCalculation = $allVersions
if ($ignorePreviewReleases)
{
    $versionsForCalculation = $allVersions | Where-Object{ -not $_.isPrerelease }
}

# If all versions are filtered out (e.g., all are prereleases), use all versions
if ($versionsForCalculation.Count -eq 0)
{
    $versionsForCalculation = $allVersions
}

$majorVersions = $versionsForCalculation | 
    ForEach-Object{ ConvertTo-Version "$($_.semver.major)" } | 
    Select-Object -Unique

$minorVersions = $versionsForCalculation | 
    ForEach-Object{ ConvertTo-Version "$($_.semver.major).$($_.semver.minor)" } | 
    Select-Object -Unique

$patchVersions = $versionsForCalculation | 
    ForEach-Object{ ConvertTo-Version "$($_.semver.major).$($_.semver.minor).$($_.semver.build)" } | 
    Select-Object -Unique

#############################################################################
# VALIDATION: Version Consistency
# Ensure floating versions (v1, v1.0) point to the correct patch versions
# Major version v1 should point to latest v1.X.Z
# Minor version v1.0 should point to latest v1.0.Z
#############################################################################

foreach ($majorVersion in $majorVersions)
{
    $highestMinor = ($minorVersions | Where-Object{ $_.major -eq $majorVersion.major } | Measure-Object -Max).Maximum

    # Check if major/minor versions exist (look in all versions)
    $majorVersion_obj = $allVersions | 
        Where-Object{ $_.version -eq "v$($majorVersion.major)" } | 
        Select-Object -First 1
    $majorSha = $majorVersion_obj.sha
    
    # If no minor versions exist for this major version, we need to create v{major}.0.0 and v{major}.0
    if (-not $highestMinor)
    {
        Write-Host "::debug::No minor versions found for major version v$($majorVersion.major), will create v$($majorVersion.major).0.0 and v$($majorVersion.major).0"
        
        # Create v{major}.0.0 using the major version's SHA
        if ($majorSha)
        {
            $fixCmd = "git push origin $majorSha`:refs/tags/v$($majorVersion.major).0.0"
            
            $issue = [ValidationIssue]::new("missing_patch_version", "error", "Version v$($majorVersion.major).0.0 does not exist and must match v$($majorVersion.major)")
            $issue.Version = "v$($majorVersion.major).0.0"
            $issue.ExpectedSha = $majorSha
            $issue.ManualFixCommand = $fixCmd
            $State.AddIssue($issue)
            
            $issue.IsAutoFixable = $true
            # Use RemediationAction class
            $issue.RemediationAction = [CreateTagAction]::new("v$($majorVersion.major).0.0", $majorSha)
            
            if (-not $autoFix)
            {
                write-actions-error "::error title=Missing version::Version: v$($majorVersion.major).0.0 does not exist and must match: v$($majorVersion.major) ref $majorSha"
                $suggestedCommands += $fixCmd
            }
            
            # Create v{major}.0 if check-minor-version is enabled
            if ($checkMinorVersion -ne "none")
            {
                $fixCmd = "git push origin $majorSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($majorVersion.major).0"
                
                $issue = [ValidationIssue]::new("missing_minor_version", $checkMinorVersion, "Version v$($majorVersion.major).0 does not exist and must match v$($majorVersion.major)")
                $issue.Version = "v$($majorVersion.major).0"
                $issue.ExpectedSha = $majorSha
                $issue.ManualFixCommand = $fixCmd
                $State.AddIssue($issue)
                
                $issue.IsAutoFixable = $true
                # Use RemediationAction class
                if ($useBranches) {
                    $issue.RemediationAction = [CreateBranchAction]::new("v$($majorVersion.major).0", $majorSha)
                } else {
                    $issue.RemediationAction = [CreateTagAction]::new("v$($majorVersion.major).0", $majorSha)
                }
                
                if (-not $autoFix)
                {
                    write-actions-message "::$($checkMinorVersion) title=Missing version::Version: v$($majorVersion.major).0 does not exist and must match: v$($majorVersion.major) ref $majorSha" -severity $checkMinorVersion
                    $suggestedCommands += $fixCmd
                }
            }
            else
            {
                # Even if check-minor-version is none, we still need $highestMinor set for the rest of the logic
                $highestMinor = ConvertTo-Version "$($majorVersion.major).0"
            }
        }
        
        # If we still don't have highestMinor, skip this major version
        if (-not $highestMinor)
        {
            continue
        }
    }

    # Determine what they should point to (look in non-prerelease versions)
    $minorVersion_obj = $versionsForCalculation | 
        Where-Object{ $_.version -eq "v$($majorVersion.major).$($highestMinor.minor)" } | 
        Select-Object -First 1
    $minorSha = $minorVersion_obj.sha
    
    # Check if major/minor versions use branches when use-branches is enabled
    if ($useBranches)
    {
        if ($majorVersion_obj -and $majorVersion_obj.ref -match "^refs/tags/")
        {
            $fixCmd = "git branch v$($majorVersion.major) $majorSha && git push origin v$($majorVersion.major):refs/heads/v$($majorVersion.major) && git push origin :refs/tags/v$($majorVersion.major)"
            
            $issue = [ValidationIssue]::new("wrong_ref_type", "error", "Major version v$($majorVersion.major) is a tag but should be a branch")
            $issue.Version = "v$($majorVersion.major)"
            $issue.ManualFixCommand = $fixCmd
            $State.AddIssue($issue)
            
            # Note: Not auto-fixable - requires creating branch AND deleting tag in sequence
            $issue.IsAutoFixable = $false
            
            if (-not $autoFix)
            {
                write-actions-error "::error title=Version should be branch::Major version v$($majorVersion.major) is a tag but should be a branch when use-branches is enabled"
                $suggestedCommands += "git branch v$($majorVersion.major) $majorSha"
                $suggestedCommands += "git push origin v$($majorVersion.major):refs/heads/v$($majorVersion.major)"
                $suggestedCommands += "git push origin :refs/tags/v$($majorVersion.major)"
            }
        }
        
        if ($minorVersion_obj -and $minorVersion_obj.ref -match "^refs/tags/")
        {
            $fixCmd = "git branch v$($majorVersion.major).$($highestMinor.minor) $minorSha && git push origin v$($majorVersion.major).$($highestMinor.minor):refs/heads/v$($majorVersion.major).$($highestMinor.minor) && git push origin :refs/tags/v$($majorVersion.major).$($highestMinor.minor)"
            
            $issue = [ValidationIssue]::new("wrong_ref_type", "error", "Minor version v$($majorVersion.major).$($highestMinor.minor) is a tag but should be a branch")
            $issue.Version = "v$($majorVersion.major).$($highestMinor.minor)"
            $issue.ManualFixCommand = $fixCmd
            $State.AddIssue($issue)
            
            # Note: Not auto-fixable - requires creating branch AND deleting tag in sequence
            $issue.IsAutoFixable = $false
            
            if (-not $autoFix)
            {
                write-actions-error "::error title=Version should be branch::Minor version v$($majorVersion.major).$($highestMinor.minor) is a tag but should be a branch when use-branches is enabled"
                $suggestedCommands += "git branch v$($majorVersion.major).$($highestMinor.minor) $minorSha"
                $suggestedCommands += "git push origin v$($majorVersion.major).$($highestMinor.minor):refs/heads/v$($majorVersion.major).$($highestMinor.minor)"
                $suggestedCommands += "git push origin :refs/tags/v$($majorVersion.major).$($highestMinor.minor)"
            }
        }
    }

    if ($checkMinorVersion -ne "none")
    {
        if (-not $majorSha -and $minorSha)
        {
            $fixCmd = "git push origin $minorSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($majorVersion.major)"
            
            $issue = [ValidationIssue]::new("missing_major_version", $checkMinorVersion, "Version v$($majorVersion.major) does not exist and must match v$($highestMinor.major).$($highestMinor.minor)")
            $issue.Version = "v$($majorVersion.major)"
            $issue.ExpectedSha = $minorSha
            $issue.ManualFixCommand = $fixCmd
            $State.AddIssue($issue)
            
            $issue.IsAutoFixable = $true
            # Use RemediationAction class
            if ($useBranches) {
                $issue.RemediationAction = [CreateBranchAction]::new("v$($majorVersion.major)", $minorSha)
            } else {
                $issue.RemediationAction = [CreateTagAction]::new("v$($majorVersion.major)", $minorSha)
            }
            
            if (-not $autoFix)
            {
                write-actions-message "::$($checkMinorVersion) title=Missing version::Version: v$($majorVersion.major) does not exist and must match: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha" -severity $checkMinorVersion
                $suggestedCommands += $fixCmd
            }
        }

        if ($majorSha -and $minorSha -and ($majorSha -ne $minorSha))
        {
            $fixCmd = "git push origin $minorSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($majorVersion.major) --force"
            
            $issue = [ValidationIssue]::new("incorrect_version", $checkMinorVersion, "Version v$($majorVersion.major) points to wrong SHA")
            $issue.Version = "v$($majorVersion.major)"
            $issue.CurrentSha = $majorSha
            $issue.ExpectedSha = $minorSha
            $issue.ManualFixCommand = $fixCmd
            $State.AddIssue($issue)
            
            $issue.IsAutoFixable = $true
            # Use RemediationAction class
            if ($useBranches) {
                $issue.RemediationAction = [UpdateBranchAction]::new("v$($majorVersion.major)", $minorSha, $true)
            } else {
                $issue.RemediationAction = [UpdateTagAction]::new("v$($majorVersion.major)", $minorSha, $true)
            }
            
            if (-not $autoFix)
            {
                write-actions-message "::$($checkMinorVersion) title=Incorrect version::Version: v$($majorVersion.major) ref $majorSha must match: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha" -severity $checkMinorVersion
                $suggestedCommands += $fixCmd
            }
        }
    }

    $highestPatch = ($patchVersions | 
        Where-Object{ $_.major -eq $highestMinor.major -and $_.minor -eq $highestMinor.minor } | 
        Measure-Object -Max).Maximum
    
    # Check if major/minor/patch versions exist (look in all versions)
    $majorSha = ($allVersions | 
        Where-Object{ $_.version -eq "v$($highestMinor.major)" } | 
        Select-Object -First 1).sha
    $minorSha = ($allVersions | 
        Where-Object{ $_.version -eq "v$($highestMinor.major).$($highestMinor.minor)" } | 
        Select-Object -First 1).sha
    
    # Determine what they should point to (look in non-prerelease versions)
    $patchSha = ($versionsForCalculation | 
        Where-Object{ $_.version -eq "v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)" } | 
        Select-Object -First 1).sha
    
    # Determine the source SHA for the patch version
    # If patchSha doesn't exist, use minorSha if available, otherwise majorSha
    $sourceShaForPatch = $patchSha
    $sourceVersionForPatch = "v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)"
    if (-not $sourceShaForPatch) {
        $sourceShaForPatch = $minorSha
        $sourceVersionForPatch = "v$($highestMinor.major).$($highestMinor.minor)"
    }
    if (-not $sourceShaForPatch) {
        $sourceShaForPatch = $majorSha
        $sourceVersionForPatch = "v$($highestMinor.major)"
    }
    
    if ($majorSha -and $patchSha -and ($majorSha -ne $patchSha))
    {
        $fixCmd = "git push origin $patchSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($highestMinor.major) --force"
        
        $issue = [ValidationIssue]::new("incorrect_version", "error", "Version v$($highestMinor.major) points to wrong SHA")
        $issue.Version = "v$($highestMinor.major)"
        $issue.CurrentSha = $majorSha
        $issue.ExpectedSha = $patchSha
        $issue.ManualFixCommand = $fixCmd
        $State.AddIssue($issue)
        
        $issue.IsAutoFixable = $true
        # Use RemediationAction class
        if ($useBranches) {
            $issue.RemediationAction = [UpdateBranchAction]::new("v$($highestMinor.major)", $patchSha, $true)
        } else {
            $issue.RemediationAction = [UpdateTagAction]::new("v$($highestMinor.major)", $patchSha, $true)
        }
        
        if (-not $autoFix)
        {
            write-actions-error "::error title=Incorrect version::Version: v$($highestMinor.major) ref $majorSha must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha"
            $suggestedCommands += $fixCmd
        }
    }

    if (-not $patchSha -and $sourceShaForPatch)
    {
        $fixCmd = "git push origin $sourceShaForPatch`:refs/tags/v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)"
        
        $issue = [ValidationIssue]::new("missing_patch_version", "error", "Version v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) does not exist")
        $issue.Version = "v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)"
        $issue.ExpectedSha = $sourceShaForPatch
        $issue.ManualFixCommand = $fixCmd
        $State.AddIssue($issue)
        
        $issue.IsAutoFixable = $true
        # Use RemediationAction class
        $issue.RemediationAction = [CreateTagAction]::new("v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)", $sourceShaForPatch)
        
        if (-not $autoFix)
        {
            write-actions-error "::error title=Missing version::Version: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) does not exist and must match: $sourceVersionForPatch ref $sourceShaForPatch"
            $suggestedCommands += $fixCmd
        }
    }

    if (-not $majorSha)
    {
        $fixCmd = "git push origin $sourceShaForPatch`:refs/$($useBranches ? 'heads' : 'tags')/v$($highestPatch.major)"
        
        $issue = [ValidationIssue]::new("missing_major_version", "error", "Version v$($majorVersion.major) does not exist")
        $issue.Version = "v$($majorVersion.major)"
        $issue.ExpectedSha = $sourceShaForPatch
        $issue.ManualFixCommand = $fixCmd
        $State.AddIssue($issue)
        
        $issue.IsAutoFixable = $true
        # Use RemediationAction class
        if ($useBranches) {
            $issue.RemediationAction = [CreateBranchAction]::new("v$($highestPatch.major)", $sourceShaForPatch)
        } else {
            $issue.RemediationAction = [CreateTagAction]::new("v$($highestPatch.major)", $sourceShaForPatch)
        }
        
        if (-not $autoFix)
        {
            write-actions-error "::error title=Missing version::Version: v$($majorVersion.major) does not exist and must match: $sourceVersionForPatch ref $sourceShaForPatch"
            $suggestedCommands += $fixCmd
        }
    }

    if ($checkMinorVersion -ne "none")
    {
        if (-not $minorSha)
        {
            # Determine source for minor version: prefer patch, fall back to major
            $sourceShaForMinor = $patchSha
            $sourceVersionForMinor = "v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)"
            if (-not $sourceShaForMinor) {
                $sourceShaForMinor = $majorSha
                $sourceVersionForMinor = "v$($highestMinor.major)"
            }
            
            if ($sourceShaForMinor) {
                $fixCmd = "git push origin $sourceShaForMinor`:refs/$($useBranches ? 'heads' : 'tags')/v$($highestMinor.major).$($highestMinor.minor)"
                
                $issue = [ValidationIssue]::new("missing_minor_version", $checkMinorVersion, "Version v$($highestMinor.major).$($highestMinor.minor) does not exist")
                $issue.Version = "v$($highestMinor.major).$($highestMinor.minor)"
                $issue.ExpectedSha = $sourceShaForMinor
                $issue.ManualFixCommand = $fixCmd
                $State.AddIssue($issue)
                
                $issue.IsAutoFixable = $true
                # Use RemediationAction class
                if ($useBranches) {
                    $issue.RemediationAction = [CreateBranchAction]::new("v$($highestMinor.major).$($highestMinor.minor)", $sourceShaForMinor)
                } else {
                    $issue.RemediationAction = [CreateTagAction]::new("v$($highestMinor.major).$($highestMinor.minor)", $sourceShaForMinor)
                }
                
                if (-not $autoFix)
                {
                    write-actions-message "::$($checkMinorVersion) title=Missing version::Version: v$($highestMinor.major).$($highestMinor.minor) does not exist and must match: $sourceVersionForMinor ref $sourceShaForMinor" -severity $checkMinorVersion
                    $suggestedCommands += $fixCmd
                }
            }
        }

        if ($minorSha -and $patchSha -and ($minorSha -ne $patchSha))
        {
            $fixCmd = "git push origin $patchSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($highestMinor.major).$($highestMinor.minor) --force"
            
            $issue = [ValidationIssue]::new("incorrect_minor_version", $checkMinorVersion, "Version v$($highestMinor.major).$($highestMinor.minor) points to wrong SHA")
            $issue.Version = "v$($highestMinor.major).$($highestMinor.minor)"
            $issue.CurrentSha = $minorSha
            $issue.ExpectedSha = $patchSha
            $issue.ManualFixCommand = $fixCmd
            $State.AddIssue($issue)
            
            $issue.IsAutoFixable = $true
            # Use RemediationAction class
            if ($useBranches) {
                $issue.RemediationAction = [UpdateBranchAction]::new("v$($highestMinor.major).$($highestMinor.minor)", $patchSha, $true)
            } else {
                $issue.RemediationAction = [UpdateTagAction]::new("v$($highestMinor.major).$($highestMinor.minor)", $patchSha, $true)
            }
            
            if (-not $autoFix)
            {
                write-actions-message "::$($checkMinorVersion) title=Incorrect version::Version: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha" -severity $checkMinorVersion
                $suggestedCommands += $fixCmd
            }
        }
    }
}

# For the "latest" version, use the highest non-prerelease version globally
$globalHighestPatchVersion = ($versionsForCalculation | 
    ForEach-Object{ ConvertTo-Version "$($_.semver.major).$($_.semver.minor).$($_.semver.build)" } | 
    Select-Object -Unique | 
    Measure-Object -Max).Maximum

$highestVersion = $versionsForCalculation | 
    Where-Object{ $_.version -eq "v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build)" } | 
    Select-Object -First 1 

# Check latest based on whether we're using branches or tags
if ($useBranches) {
    # When using branches, check if latest branch exists and points to correct version
    if ($latestBranch -and ($latestBranch.sha -ne $highestVersion.sha)) {
        $fixCmd = "git push origin $($highestVersion.sha):refs/heads/latest --force"
        
        $issue = [ValidationIssue]::new("incorrect_latest_branch", "error", "Latest branch points to wrong SHA")
        $issue.Version = "latest"
        $issue.CurrentSha = $latestBranch.sha
        $issue.ExpectedSha = $highestVersion.sha
        $issue.ManualFixCommand = $fixCmd
        $State.AddIssue($issue)
        
        $issue.IsAutoFixable = $true
        # Use RemediationAction class
        $issue.RemediationAction = [UpdateBranchAction]::new("latest", $highestVersion.sha, $true)
        
        if (-not $autoFix)
        {
            write-actions-error "::error title=Incorrect version::Version: latest (branch) ref $($latestBranch.sha) must match: v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build) ref $($highestVersion.sha)"
            $suggestedCommands += $fixCmd
        }
    } elseif (-not $latestBranch -and $highestVersion) {
        $fixCmd = "git push origin $($highestVersion.sha):refs/heads/latest"
        
        $issue = [ValidationIssue]::new("missing_latest_branch", "error", "Latest branch does not exist")
        $issue.Version = "latest"
        $issue.ExpectedSha = $highestVersion.sha
        $issue.ManualFixCommand = $fixCmd
        $State.AddIssue($issue)
        
        $issue.IsAutoFixable = $true
        # Use RemediationAction class
        $issue.RemediationAction = [CreateBranchAction]::new("latest", $highestVersion.sha)
        
        if (-not $autoFix)
        {
            write-actions-error "::error title=Missing version::Version: latest (branch) does not exist and must match: v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build) ref $($highestVersion.sha)"
            $suggestedCommands += $fixCmd
        }
    }
    
    # Warn if latest exists as a tag when we're using branches
    if ($latest) {
        write-actions-warning "::warning title=Latest should be branch::Version: latest exists as a tag but should be a branch when floating-versions-use is 'branches'"
        $suggestedCommands += "git push origin :refs/tags/latest"
    }
} else {
    # When using tags, check if latest tag exists and points to correct version
    if ($latest -and $highestVersion -and ($latest.sha -ne $highestVersion.sha)) {
        $fixCmd = "git push origin $($highestVersion.sha):refs/tags/latest --force"
        
        $issue = [ValidationIssue]::new("incorrect_latest_tag", "error", "Latest tag points to wrong SHA")
        $issue.Version = "latest"
        $issue.CurrentSha = $latest.sha
        $issue.ExpectedSha = $highestVersion.sha
        $issue.ManualFixCommand = $fixCmd
        $State.AddIssue($issue)
        
        $issue.IsAutoFixable = $true
        # Use RemediationAction class
        $issue.RemediationAction = [UpdateTagAction]::new("latest", $highestVersion.sha, $true)
        
        if (-not $autoFix)
        {
            write-actions-error "::error title=Incorrect version::Version: latest ref $($latest.sha) must match: v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build) ref $($highestVersion.sha)"
            $suggestedCommands += $fixCmd
        }
    }
    
    # Warn if latest exists as a branch when we're using tags
    if ($latestBranch) {
        write-actions-warning "::warning title=Latest should be tag::Version: latest exists as a branch but should be a tag when floating-versions-use is 'tags'"
        $suggestedCommands += "git push origin :refs/heads/latest"
    }
}

#############################################################################
# DIFF VISUALIZATION AND AUTO-FIX EXECUTION
#############################################################################

# Display planned changes BEFORE executing any fixes
if ($autoFix -and $State.Issues.Count -gt 0) {
    $diffs = Get-StateDiff -State $State
    if ($diffs.Count -gt 0) {
        Write-StateDiff -Diffs $diffs
    }
}

# Now execute all auto-fixes
Invoke-AllAutoFixes -State $State -AutoFix $autoFix

#############################################################################
# FINAL SUMMARY AND EXIT
#############################################################################

# Display summary based on auto-fix mode
$exitCode = $State.GetReturnCode()

if ($autoFix)
{
    Write-Output ""
    Write-Output "### Auto-fix Summary"
    Write-Output "✓ Fixed issues: $($State.GetFixedIssuesCount())"
    Write-Output "✗ Failed fixes: $($State.GetFailedFixesCount())"
    Write-Output "⚠ Unfixable issues: $($State.GetUnfixableIssuesCount())"
    
    # Only fail if there are failed fixes or unfixable issues
    if ($State.GetFailedFixesCount() -gt 0 -or $State.GetUnfixableIssuesCount() -gt 0)
    {
        $exitCode = 1
        Write-Output ""
        if ($State.GetFailedFixesCount() -gt 0) {
            Write-Output "::error::Some fixes failed. Please review the errors above and fix manually."
        }
        if ($State.GetUnfixableIssuesCount() -gt 0) {
            Write-Output "::error::Some issues cannot be auto-fixed (draft releases must be published manually, or immutable releases on floating versions). Please fix manually."
        }
    }
    elseif ($State.GetFixedIssuesCount() -gt 0)
    {
        # Issues were found and all were fixed successfully
        Write-Output ""
        Write-Output "::notice::All issues were successfully fixed!"
    }
    else
    {
        # No issues were found
        Write-Output ""
        Write-Output "::notice::No issues found!"
    }
    
    # Show suggested commands for unfixable issues or failed fixes
    if ($suggestedCommands -ne "")
    {
        $suggestedCommands = $suggestedCommands | Select-Object -unique
        Write-Output ""
        Write-Output "### Manual fixes required for unfixable or failed issues:"
        Write-Output ($suggestedCommands -join "`n")
        write-output "### Manual fixes required:`n```````n$($suggestedCommands -join "`n")`n``````" >> $env:GITHUB_STEP_SUMMARY
    }
}
else
{
    # Not in auto-fix mode, just show suggested commands if any
    if ($suggestedCommands -ne "")
    {
        $suggestedCommands = $suggestedCommands | Select-Object -unique
        Write-Output ($suggestedCommands -join "`n")
        write-output "### Suggested fix:`n```````n$($suggestedCommands -join "`n")`n``````" >> $env:GITHUB_STEP_SUMMARY
    }
}

# Set global for test harness compatibility and exit
$global:returnCode = $exitCode
exit $exitCode

