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

# NOTE: Enable strict mode during development for better error detection:
# Set-StrictMode -Version Latest
# Disabled by default to avoid breaking existing test infrastructure.

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

# Track temporary files for cleanup
$script:AskpassScriptPath = $null

#############################################################################
# CLEANUP FUNCTION
# Ensures sensitive data and temporary files are cleaned up even on error
#############################################################################

function Invoke-Cleanup {
    # Cleanup: Remove temporary askpass script if created
    if ($script:AskpassScriptPath -and (Test-Path $script:AskpassScriptPath -ErrorAction SilentlyContinue)) {
        Remove-Item -Path $script:AskpassScriptPath -Force -ErrorAction SilentlyContinue
    }
    
    # Cleanup: Clear sensitive environment variables
    $env:GIT_ASKPASS_TOKEN = $null
    $env:GIT_PASSWORD = $null
    $env:GIT_USERNAME = $null
}

# Register cleanup to run on script termination (handles errors, Ctrl+C, etc.)
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Invoke-Cleanup } -ErrorAction SilentlyContinue

#############################################################################
# REPOSITORY DETECTION
#############################################################################

# Set default URLs in State
$script:State.ApiUrl = $env:GITHUB_API_URL ?? "https://api.github.com"
$script:State.ServerUrl = $env:GITHUB_SERVER_URL ?? "https://github.com"
$script:State.Token = $env:GITHUB_TOKEN ?? ""

# SECURITY: Mask the token to prevent accidental exposure in logs
# Note: GitHub runner should mask GITHUB_TOKEN automatically, but we add this
# for defense-in-depth in case tokens come from other sources
if ($script:State.Token) {
    Write-Host "::add-mask::$($script:State.Token)"
}

# Parse repository owner and name from GITHUB_REPOSITORY
if ($env:GITHUB_REPOSITORY) {
    $parts = $env:GITHUB_REPOSITORY -split '/', 2
    if ($parts.Count -eq 2 -and $parts[0] -and $parts[1]) {
        $script:State.RepoOwner = $parts[0]
        $script:State.RepoName = $parts[1]
    }
}

# If still not found, warn user to configure GITHUB_REPOSITORY
if (-not $script:State.RepoOwner -or -not $script:State.RepoName) {
    Write-Host "::warning::Could not determine repository owner/name. Ensure GITHUB_REPOSITORY environment variable is set."
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
    
    # SECURITY: Mask the token if it was provided via input (may be different from env var)
    if ($inputs.token -and $inputs.token -ne $env:GITHUB_TOKEN) {
        Write-Host "::add-mask::$($inputs.token)"
    }
    
    $checkMinorVersion = Normalize-CheckInput -value (($inputs.'check-minor-version' ?? "true") -as [string]) -default "error"
    $checkReleases = Normalize-CheckInput -value (($inputs.'check-releases' ?? "error") -as [string]) -default "error"
    $checkReleaseImmutability = Normalize-CheckInput -value (($inputs.'check-release-immutability' ?? "error") -as [string]) -default "error"
    $ignorePreviewReleases = (($inputs.'ignore-preview-releases' ?? "true") -as [string]).Trim() -eq "true"
    $floatingVersionsUse = (($inputs.'floating-versions-use' ?? "tags") -as [string]).Trim().ToLower()
    $autoFix = (($inputs.'auto-fix' ?? "false") -as [string]).Trim() -eq "true"
    
    # Parse new inputs with validation
    # Supports multiple formats:
    # 1. Comma-separated: "v1.0.0, v2.0.0"
    # 2. Line-separated (newlines): "v1.0.0\nv2.0.0"
    # 3. JSON array: ["v1.0.0", "v2.0.0"]
    $ignoreVersionsRaw = $inputs.'ignore-versions'
    $ignoreVersions = @()
    
    if ($ignoreVersionsRaw) {
        $rawVersions = @()
        
        # Check if it's a JSON array (either already parsed or as string)
        if ($ignoreVersionsRaw -is [array]) {
            # Already parsed as array by ConvertFrom-Json
            $rawVersions = $ignoreVersionsRaw
        }
        elseif ($ignoreVersionsRaw -is [string]) {
            $trimmedInput = $ignoreVersionsRaw.Trim()
            
            # Check if it looks like a JSON array
            if ($trimmedInput.StartsWith('[') -and $trimmedInput.EndsWith(']')) {
                try {
                    $parsed = $trimmedInput | ConvertFrom-Json
                    if ($parsed -is [array]) {
                        $rawVersions = $parsed
                    }
                }
                catch {
                    Write-Host "::warning title=Invalid JSON in ignore-versions::Failed to parse JSON array. Treating as comma/newline-separated list."
                    # Fall through to comma/newline parsing
                }
            }
            
            # If not parsed as JSON array, split by comma and newline
            if ($rawVersions.Count -eq 0 -and $trimmedInput) {
                $rawVersions = $trimmedInput -split '[,\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            }
        }
        
        # Validate each version pattern using Test-ValidVersionPattern for ReDoS prevention
        foreach ($ver in $rawVersions) {
            $verTrimmed = "$ver".Trim()
            if (-not $verTrimmed) { continue }
            
            # Use safe validation function that prevents ReDoS attacks
            if (Test-ValidVersionPattern -Pattern $verTrimmed) {
                $ignoreVersions += $verTrimmed
            } else {
                Write-Host "::warning title=Invalid ignore-versions pattern::Pattern '$verTrimmed' does not match expected format (vX, vX.Y, vX.Y.Z, or wildcard like v1.*). Skipping."
            }
        }
    }
    
    if ($ignoreVersions.Count -gt 0) {
        Write-Host "::debug::Ignoring versions: $($ignoreVersions -join ', ')"
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

# Validate token is available for auto-fix mode
if ($autoFix) {
    if (-not $script:State.Token) {
        $errorMessage = "::error title=Auto-fix requires token::Auto-fix mode is enabled but no GitHub token is available. Please provide a token via the 'token' input or ensure GITHUB_TOKEN is available.%0A%0AExample:%0A  - uses: jessehouwing/actions-semver-checker@v2%0A    with:%0A      auto-fix: true%0A      token: `${{ secrets.GITHUB_TOKEN }}"
        Write-Output $errorMessage
        $global:returnCode = 1
        exit 1
    }
    Write-Host "::debug::Auto-fix mode enabled with token"
}

# Fetch tags and branches via GitHub API (no checkout required)
Write-Host "::debug::Fetching tags from GitHub API..."
$apiTags = Get-GitHubTags -State $script:State -Pattern "^v\d+(\.\d+){0,2}$"
$tags = $apiTags | ForEach-Object { $_.name }
Write-Host "::debug::Found $($tags.Count) version tags: $($tags -join ', ')"

Write-Host "::debug::Fetching branches from GitHub API..."
$apiBranches = Get-GitHubBranches -State $script:State -Pattern "^v\d+(\.\d+){0,2}(-.*)?$"
$branches = $apiBranches | ForEach-Object { $_.name }

# Also fetch latest tag and branch via API (for 'latest' alias validation)
$apiLatestTag = Get-GitHubTags -State $script:State -Pattern "^latest$"
$apiLatestBranch = Get-GitHubBranches -State $script:State -Pattern "^latest$"

# Legacy arrays for backward compatibility during transition
$tagVersions = @()
$branchVersions = @()


# Auto-fix tracking variables are initialized in GLOBAL STATE section above

#############################################################################
# UTILITY FUNCTIONS
#############################################################################
# Utility functions have been moved to lib/ modules:
# - Write-SafeOutput, Write-Actions* -> lib/Logging.ps1
# - ConvertTo-Version, Test-ValidVersionPattern -> lib/VersionParser.ps1
# - Get-ApiHeaders, Get-GitHubRepoInfo, Get-GitHubReleases, etc. -> lib/GitHubApi.ps1
# - Invoke-AllAutoFixes, Get-ManualInstructions -> lib/Remediation.ps1
# - Write-RepositoryStateSummary -> lib/StateModel.ps1
#############################################################################

function Test-VersionIgnored {
    <#
    .SYNOPSIS
    Check if a version should be ignored based on the ignore-versions configuration.
    
    .PARAMETER Version
    The version string to check (e.g., "v1.0.0").
    
    .PARAMETER IgnoreVersions
    Array of version patterns to ignore.
    
    .OUTPUTS
    Returns $true if the version should be ignored, $false otherwise.
    #>
    param(
        [string]$Version,
        [string[]]$IgnoreVersions
    )
    
    if (-not $IgnoreVersions -or $IgnoreVersions.Count -eq 0) {
        return $false
    }
    
    foreach ($pattern in $IgnoreVersions) {
        # Exact match
        if ($Version -eq $pattern) {
            Write-Host "::debug::Ignoring version $Version (matches ignore pattern: $pattern)"
            return $true
        }
        
        # Support wildcard patterns (e.g., "v1.*" matches "v1.0.0", "v1.1.0", etc.)
        if ($pattern -match '\*') {
            $regexPattern = '^' + [regex]::Escape($pattern).Replace('\*', '.*') + '$'
            if ($Version -match $regexPattern) {
                Write-Host "::debug::Ignoring version $Version (matches wildcard pattern: $pattern)"
                return $true
            }
        }
    }
    
    return $false
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
    # Create a map for quick lookup and set isIgnored property
    foreach ($release in $releases)
    {
        $release.isIgnored = Test-VersionIgnored -Version $release.tagName -IgnoreVersions $ignoreVersions
        $releaseMap[$release.tagName] = $release
    }
}

# Helper function to check if a draft release exists for a given tag
# When a draft release exists, publishing it will create the tag automatically
function Test-DraftReleaseExists {
    param([string]$TagName)
    
    if ($releaseMap.ContainsKey($TagName)) {
        return $releaseMap[$TagName].isDraft -eq $true
    }
    return $false
}

foreach ($tag in $tags)
{
    # Skip ignored versions
    if (Test-VersionIgnored -Version $tag -IgnoreVersions $ignoreVersions) {
        continue
    }
    
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
    
    # Get SHA from API response (already fetched)
    $tagInfo = $apiTags | Where-Object { $_.name -eq $tag } | Select-Object -First 1
    $tagSha = if ($tagInfo) { $tagInfo.sha } else { $null }
    
    $tagVersions += @{
        version = $tag
        ref = "refs/tags/$tag"
        sha = $tagSha
        semver = ConvertTo-Version $tag.Substring(1)
        isPrerelease = $isPrerelease
        isPatchVersion = $isPatchVersion
        isMinorVersion = $isMinorVersion
        isMajorVersion = $isMajorVersion
    }
    
    Write-Host "::debug::Parsed tag $tag - isPatch:$isPatchVersion isMinor:$isMinorVersion isMajor:$isMajorVersion parts:$($versionParts.Count)"
}

# Check for 'latest' tag via API (already fetched above)
$latest = $null
$latestBranch = $null
if ($apiLatestTag -and $apiLatestTag.Count -gt 0)
{
    $latestTagInfo = $apiLatestTag | Select-Object -First 1
    $latest = @{
        version = "latest"
        ref = "refs/tags/latest"
        sha = $latestTagInfo.sha
        semver = $null
    }
}

# Also check for latest branch (regardless of floating-versions-use setting)
# This allows us to warn when latest exists as wrong type
if ($apiLatestBranch -and $apiLatestBranch.Count -gt 0) {
    $latestBranchInfo = $apiLatestBranch | Select-Object -First 1
    $latestBranch = @{
        version = "latest"
        ref = "refs/heads/latest"
        sha = $latestBranchInfo.sha
        semver = $null
    }
}

foreach ($branch in $branches)
{
    # Check if this version should be ignored
    $isIgnored = Test-VersionIgnored -Version $branch -IgnoreVersions $ignoreVersions
    
    # Determine if this is a patch version (vX.Y.Z) or a floating version (vX or vX.Y)
    # Strip any prerelease suffix (e.g., -beta) before counting parts
    $versionWithoutPrefix = $branch.Substring(1)
    $versionCore = $versionWithoutPrefix -split '-' | Select-Object -First 1
    $versionParts = $versionCore -split '\.'
    $isPatchVersion = $versionParts.Count -eq 3
    $isMinorVersion = $versionParts.Count -eq 2
    $isMajorVersion = $versionParts.Count -eq 1
    
    # Get SHA from API response (already fetched)
    $branchInfo = $apiBranches | Where-Object { $_.name -eq $branch } | Select-Object -First 1
    $branchSha = if ($branchInfo) { $branchInfo.sha } else { $null }
    
    $branchVersions += @{
        version = $branch
        ref = "refs/heads/$branch"
        sha = $branchSha
        semver = ConvertTo-Version $branch.Substring(1)
        isPrerelease = $false  # Branches are not considered prereleases
        isPatchVersion = $isPatchVersion
        isMinorVersion = $isMinorVersion
        isMajorVersion = $isMajorVersion
        isIgnored = $isIgnored
    }
}

# Populate StateModel with VersionRef objects for typed access
foreach ($tv in $tagVersions) {
    $vr = [VersionRef]::new($tv.version, $tv.ref, $tv.sha, "tag")
    $vr.IsPrerelease = $tv.isPrerelease
    $vr.IsIgnored = $tv.isIgnored
    $script:State.Tags += $vr
}
foreach ($bv in $branchVersions) {
    $vr = [VersionRef]::new($bv.version, $bv.ref, $bv.sha, "branch")
    $vr.IsIgnored = $bv.isIgnored
    $script:State.Branches += $vr
}

foreach ($tagVersion in $tagVersions)
{
    # Skip ignored versions
    if ($tagVersion.isIgnored) {
        continue
    }
    
    $branchVersion = $branchVersions | Where-Object{ $_.version -eq $tagVersion.version } | Select-Object -First 1

    if ($branchVersion)
    {
        #############################################################################
        # VALIDATION: Ambiguous References
        # Check for versions that exist as both tag AND branch
        # This causes confusion for users and must be resolved
        #############################################################################
        
        # Determine which reference to keep based on floating-versions-use setting
        $keepBranch = ($useBranches -eq $true)
        
        if ($branchVersion.sha -eq $tagVersion.sha)
        {
            # Same SHA - can auto-fix by removing the non-preferred reference
            $severity = "warning"
            $issue = [ValidationIssue]::new("ambiguous_reference", $severity, "Version $($tagVersion.version) exists as both tag ($($tagVersion.sha)) and branch ($($branchVersion.sha)) - same SHA")
            $issue.Version = $tagVersion.version
            $issue.CurrentSha = $tagVersion.sha
            $State.AddIssue($issue)
            
            # Use RemediationAction class - determine action based on keepBranch
            if ($keepBranch) {
                $issue.SetRemediationAction([DeleteTagAction]::new($tagVersion.version))
            } else {
                $issue.SetRemediationAction([DeleteBranchAction]::new($tagVersion.version))
            }
        }
        else
        {
            # Different SHAs - can auto-fix by removing the non-preferred reference
            $severity = "error"
            $issue = [ValidationIssue]::new("ambiguous_reference", $severity, "Version $($tagVersion.version) exists as both tag ($($tagVersion.sha)) and branch ($($branchVersion.sha)) - different SHAs")
            $issue.Version = $tagVersion.version
            $issue.CurrentSha = $tagVersion.sha
            $State.AddIssue($issue)
            
            # Use RemediationAction class - determine action based on keepBranch
            if ($keepBranch) {
                $issue.SetRemediationAction([DeleteTagAction]::new($tagVersion.version))
            } else {
                $issue.SetRemediationAction([DeleteBranchAction]::new($tagVersion.version))
            }
        }
    }
}

# Display current repository state summary
Write-RepositoryStateSummary -Tags $tagVersions -Branches $branchVersions -Releases $releases -Title "Current Repository State"

# Validate that floating versions (vX or vX.Y) have corresponding patch versions
$allVersions = $tagVersions + $branchVersions
Write-Host "::debug::Validating floating versions. Total versions: $($allVersions.Count) (tags: $($tagVersions.Count), branches: $($branchVersions.Count))"

foreach ($version in $allVersions)
{
    # Skip ignored versions
    if ($version.isIgnored) {
        Write-Host "::debug::Skipping ignored version $($version.version)"
        continue
    }
    
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
        # Skip ignored versions
        if ($tagVersion.isIgnored) {
            continue
        }
        
        # Only check patch versions (vX.Y.Z format with 3 parts) - floating versions don't need releases
        if ($tagVersion.isPatchVersion)
        {
            $hasRelease = $releaseTagNames -contains $tagVersion.version
            
            if (-not $hasRelease)
            {
                $messageType = if ($checkReleases -eq "error") { "error" } else { "warning" }
                
                $issue = [ValidationIssue]::new("missing_release", $messageType, "Version $($tagVersion.version) does not have a GitHub Release")
                $issue.Version = $tagVersion.version
                
                # If release immutability checking is enabled, create and publish in one action
                # Otherwise just create as draft
                $shouldAutoPublish = ($checkReleaseImmutability -ne "none")
                $issue.SetRemediationAction([CreateReleaseAction]::new($tagVersion.version, $true, $shouldAutoPublish))
                $State.AddIssue($issue)
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
        # Skip ignored releases
        if ($release.isIgnored) {
            Write-Host "::debug::Skipping ignored release $($release.tagName)"
            continue
        }
        
        # Only check releases for patch versions (vX.Y.Z format)
        if ($release.tagName -match "^v\d+\.\d+\.\d+$")
        {
            if ($release.isDraft)
            {
                $messageType = if ($checkReleaseImmutability -eq "error") { "error" } else { "warning" }
                
                $issue = [ValidationIssue]::new("draft_release", $messageType, "Release $($release.tagName) is still in draft status, publish it.")
                $issue.Version = $release.tagName
                $issue.SetRemediationAction([PublishReleaseAction]::new($release.tagName, $release.id))
                $State.AddIssue($issue)
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
                            $issue = [ValidationIssue]::new("non_immutable_release", "warning", "Release $($release.tagName) is published but remains mutable and can be modified via force-push. See: https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/preventing-changes-to-your-releases")
                            $issue.Version = $release.tagName
                            $issue.SetRemediationAction([RepublishReleaseAction]::new($release.tagName))
                            $State.AddIssue($issue)
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
        # Skip ignored releases
        if ($release.isIgnored) {
            Write-Host "::debug::Skipping ignored floating version release $($release.tagName)"
            continue
        }
        
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
                
                $issue = [ValidationIssue]::new("immutable_floating_release", $messageType, "Floating version $($release.tagName) has an immutable release, which conflicts with its mutable nature. This cannot be auto-fixed.")
                $issue.Version = $release.tagName
                $issue.Status = "unfixable"
                $State.AddIssue($issue)
            }
            else
            {
                # Mutable release (draft or not immutable) on a floating version - can be auto-fixed by deleting it
                $issue = [ValidationIssue]::new("mutable_floating_release", "warning", "Floating version $($release.tagName) has a mutable release, which should be removed.")
                $issue.Version = $release.tagName
                $issue.SetRemediationAction([DeleteReleaseAction]::new($release.tagName, $release.id))
                $State.AddIssue($issue)
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
    
    # Skip if this major version is ignored
    if ($majorVersion_obj -and $majorVersion_obj.isIgnored) {
        Write-Host "::debug::Skipping ignored major version v$($majorVersion.major)"
        continue
    }
    
    # If no minor versions exist for this major version, we need to create v{major}.0.0 and v{major}.0
    if (-not $highestMinor)
    {
        Write-Host "::debug::No minor versions found for major version v$($majorVersion.major), will create v$($majorVersion.major).0.0 and v$($majorVersion.major).0"
        
        # Create v{major}.0.0 using the major version's SHA
        # Skip if a draft release exists - publishing the release will create the tag
        $patchVersionTag = "v$($majorVersion.major).0.0"
        if ($majorSha -and -not (Test-DraftReleaseExists -TagName $patchVersionTag))
        {
            $issue = [ValidationIssue]::new("missing_patch_version", "error", "Version: $patchVersionTag does not exist and must match: v$($majorVersion.major) ref $majorSha")
            $issue.Version = $patchVersionTag
            $issue.ExpectedSha = $majorSha
            $State.AddIssue($issue)
            
            # Use RemediationAction class
            $issue.SetRemediationAction([CreateTagAction]::new($patchVersionTag, $majorSha))
        }
        elseif ($majorSha -and (Test-DraftReleaseExists -TagName $patchVersionTag))
        {
            Write-Host "::debug::Skipping missing tag issue for $patchVersionTag - a draft release exists and will create the tag when published"
        }
        
        # Create v{major}.0 if check-minor-version is enabled (this is a floating version, not affected by draft releases)
        if ($majorSha -and $checkMinorVersion -ne "none")
        {
            $issue = [ValidationIssue]::new("missing_minor_version", $checkMinorVersion, "Version: v$($majorVersion.major).0 does not exist and must match: v$($majorVersion.major) ref $majorSha")
            $issue.Version = "v$($majorVersion.major).0"
            $issue.ExpectedSha = $majorSha
            $State.AddIssue($issue)
            
            # Use RemediationAction class
            if ($useBranches) {
                $issue.SetRemediationAction([CreateBranchAction]::new("v$($majorVersion.major).0", $majorSha))
            } else {
                $issue.SetRemediationAction([CreateTagAction]::new("v$($majorVersion.major).0", $majorSha))
            }
        }
        elseif (-not $majorSha -or $checkMinorVersion -eq "none")
        {
            # Even if check-minor-version is none, we still need $highestMinor set for the rest of the logic
            $highestMinor = ConvertTo-Version "$($majorVersion.major).0"
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
            
            $issue = [ValidationIssue]::new("wrong_ref_type", "error", "Major version v$($majorVersion.major) is a tag but should be a branch when use-branches is enabled")
            $issue.Version = "v$($majorVersion.major)"
            $issue.ManualFixCommand = $fixCmd
            $State.AddIssue($issue)
            
            # Note: Not auto-fixable - requires creating branch AND deleting tag in sequence
            $issue.IsAutoFixable = $false
        }
        
        if ($minorVersion_obj -and $minorVersion_obj.ref -match "^refs/tags/")
        {
            $fixCmd = "git branch v$($majorVersion.major).$($highestMinor.minor) $minorSha && git push origin v$($majorVersion.major).$($highestMinor.minor):refs/heads/v$($majorVersion.major).$($highestMinor.minor) && git push origin :refs/tags/v$($majorVersion.major).$($highestMinor.minor)"
            
            $issue = [ValidationIssue]::new("wrong_ref_type", "error", "Minor version v$($majorVersion.major).$($highestMinor.minor) is a tag but should be a branch when use-branches is enabled")
            $issue.Version = "v$($majorVersion.major).$($highestMinor.minor)"
            $issue.ManualFixCommand = $fixCmd
            $State.AddIssue($issue)
            
            # Note: Not auto-fixable - requires creating branch AND deleting tag in sequence
            $issue.IsAutoFixable = $false
        }
    }

    if ($checkMinorVersion -ne "none")
    {
        if (-not $majorSha -and $minorSha)
        {
            $issue = [ValidationIssue]::new("missing_major_version", $checkMinorVersion, "Version: v$($majorVersion.major) does not exist and must match: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha")
            $issue.Version = "v$($majorVersion.major)"
            $issue.ExpectedSha = $minorSha
            $State.AddIssue($issue)
            
            # Use RemediationAction class
            if ($useBranches) {
                $issue.SetRemediationAction([CreateBranchAction]::new("v$($majorVersion.major)", $minorSha))
            } else {
                $issue.SetRemediationAction([CreateTagAction]::new("v$($majorVersion.major)", $minorSha))
            }
        }

        if ($majorSha -and $minorSha -and ($majorSha -ne $minorSha))
        {
            $issue = [ValidationIssue]::new("incorrect_version", $checkMinorVersion, "Version: v$($majorVersion.major) ref $majorSha must match: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha")
            $issue.Version = "v$($majorVersion.major)"
            $issue.CurrentSha = $majorSha
            $issue.ExpectedSha = $minorSha
            $State.AddIssue($issue)
            
            # Use RemediationAction class
            if ($useBranches) {
                $issue.SetRemediationAction([UpdateBranchAction]::new("v$($majorVersion.major)", $minorSha, $true))
            } else {
                $issue.SetRemediationAction([UpdateTagAction]::new("v$($majorVersion.major)", $minorSha, $true))
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
        $issue = [ValidationIssue]::new("incorrect_version", "error", "Version: v$($highestMinor.major) ref $majorSha must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha")
        $issue.Version = "v$($highestMinor.major)"
        $issue.CurrentSha = $majorSha
        $issue.ExpectedSha = $patchSha
        $State.AddIssue($issue)
        
        # Use RemediationAction class
        if ($useBranches) {
            $issue.SetRemediationAction([UpdateBranchAction]::new("v$($highestMinor.major)", $patchSha, $true))
        } else {
            $issue.SetRemediationAction([UpdateTagAction]::new("v$($highestMinor.major)", $patchSha, $true))
        }
    }

    if (-not $patchSha -and $sourceShaForPatch)
    {
        $patchVersionTag = "v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)"
        
        # Skip if a draft release exists - publishing the release will create the tag
        if (-not (Test-DraftReleaseExists -TagName $patchVersionTag))
        {
            $issue = [ValidationIssue]::new("missing_patch_version", "error", "Version: $patchVersionTag does not exist and must match: $sourceVersionForPatch ref $sourceShaForPatch")
            $issue.Version = $patchVersionTag
            $issue.ExpectedSha = $sourceShaForPatch
            $State.AddIssue($issue)
            
            # Use RemediationAction class
            $issue.SetRemediationAction([CreateTagAction]::new($patchVersionTag, $sourceShaForPatch))
        }
        else
        {
            Write-Host "::debug::Skipping missing tag issue for $patchVersionTag - a draft release exists and will create the tag when published"
        }
    }

    if (-not $majorSha)
    {
        $issue = [ValidationIssue]::new("missing_major_version", "error", "Version: v$($majorVersion.major) does not exist and must match: $sourceVersionForPatch ref $sourceShaForPatch")
        $issue.Version = "v$($majorVersion.major)"
        $issue.ExpectedSha = $sourceShaForPatch
        $State.AddIssue($issue)
        
        # Use RemediationAction class
        if ($useBranches) {
            $issue.SetRemediationAction([CreateBranchAction]::new("v$($highestPatch.major)", $sourceShaForPatch))
        } else {
            $issue.SetRemediationAction([CreateTagAction]::new("v$($highestPatch.major)", $sourceShaForPatch))
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
                $issue = [ValidationIssue]::new("missing_minor_version", $checkMinorVersion, "Version: v$($highestMinor.major).$($highestMinor.minor) does not exist and must match: $sourceVersionForMinor ref $sourceShaForMinor")
                $issue.Version = "v$($highestMinor.major).$($highestMinor.minor)"
                $issue.ExpectedSha = $sourceShaForMinor
                $State.AddIssue($issue)
                
                # Use RemediationAction class
                if ($useBranches) {
                    $issue.SetRemediationAction([CreateBranchAction]::new("v$($highestMinor.major).$($highestMinor.minor)", $sourceShaForMinor))
                } else {
                    $issue.SetRemediationAction([CreateTagAction]::new("v$($highestMinor.major).$($highestMinor.minor)", $sourceShaForMinor))
                }
            }
        }

        if ($minorSha -and $patchSha -and ($minorSha -ne $patchSha))
        {
            $issue = [ValidationIssue]::new("incorrect_minor_version", $checkMinorVersion, "Version: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha")
            $issue.Version = "v$($highestMinor.major).$($highestMinor.minor)"
            $issue.CurrentSha = $minorSha
            $issue.ExpectedSha = $patchSha
            $State.AddIssue($issue)
            
            # Use RemediationAction class
            if ($useBranches) {
                $issue.SetRemediationAction([UpdateBranchAction]::new("v$($highestMinor.major).$($highestMinor.minor)", $patchSha, $true))
            } else {
                $issue.SetRemediationAction([UpdateTagAction]::new("v$($highestMinor.major).$($highestMinor.minor)", $patchSha, $true))
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
        $issue = [ValidationIssue]::new("incorrect_latest_branch", "error", "Version: latest (branch) ref $($latestBranch.sha) must match: v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build) ref $($highestVersion.sha)")
        $issue.Version = "latest"
        $issue.CurrentSha = $latestBranch.sha
        $issue.ExpectedSha = $highestVersion.sha
        $State.AddIssue($issue)
        
        # Use RemediationAction class
        $issue.SetRemediationAction([UpdateBranchAction]::new("latest", $highestVersion.sha, $true))
    } elseif (-not $latestBranch -and $highestVersion) {
        $issue = [ValidationIssue]::new("missing_latest_branch", "error", "Version: latest (branch) does not exist and must match: v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build) ref $($highestVersion.sha)")
        $issue.Version = "latest"
        $issue.ExpectedSha = $highestVersion.sha
        $State.AddIssue($issue)
        
        # Use RemediationAction class
        $issue.SetRemediationAction([CreateBranchAction]::new("latest", $highestVersion.sha))
    }
    
    # Warn if latest exists as a tag when we're using branches
    if ($latest) {
        Write-ActionsWarning "::warning title=Latest should be branch::Version: latest exists as a tag but should be a branch when floating-versions-use is 'branches'"
    }
} else {
    # When using tags, check if latest tag exists and points to correct version
    if ($latest -and $highestVersion -and ($latest.sha -ne $highestVersion.sha)) {
        $issue = [ValidationIssue]::new("incorrect_latest_tag", "error", "Version: latest ref $($latest.sha) must match: v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build) ref $($highestVersion.sha)")
        $issue.Version = "latest"
        $issue.CurrentSha = $latest.sha
        $issue.ExpectedSha = $highestVersion.sha
        $State.AddIssue($issue)
        
        # Use RemediationAction class
        $issue.SetRemediationAction([UpdateTagAction]::new("latest", $highestVersion.sha, $true))
    }
    
    # Warn if latest exists as a branch when we're using tags
    if ($latestBranch) {
        Write-ActionsWarning "::warning title=Latest should be tag::Version: latest exists as a branch but should be a tag when floating-versions-use is 'tags'"
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

# Now execute all auto-fixes (or mark as unfixable when auto-fix is disabled)
if ($autoFix -and $State.Issues.Count -gt 0) {
    Write-Host "##[group]Verifying potential solutions"
}
Invoke-AllAutoFixes -State $State -AutoFix $autoFix
if ($autoFix -and $State.Issues.Count -gt 0) {
    Write-Host "##[endgroup]"
}

#############################################################################
# LOG UNRESOLVED ISSUES
#############################################################################

# Log all unresolved issues (failed or unfixable) as errors/warnings
# This happens AFTER autofix completes, regardless of whether autofix is enabled
Write-UnresolvedIssues -State $State

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
    Write-Output "⚠ Manual fix required: $($State.GetManualFixRequiredCount())"
    Write-Output "⛔ Unfixable issues: $($State.GetUnfixableIssuesCount())"
    
    # Only fail if there are failed fixes, manual fixes required, or unfixable issues
    if ($State.GetFailedFixesCount() -gt 0 -or $State.GetManualFixRequiredCount() -gt 0 -or $State.GetUnfixableIssuesCount() -gt 0)
    {
        $exitCode = 1
        Write-Output ""
        if ($State.GetManualFixRequiredCount() -gt 0) {
            Write-Output "::error::Some issues require manual intervention (e.g., workflow permission issues). Please fix manually."
        }
        if ($State.GetUnfixableIssuesCount() -gt 0) {
            Write-Output "::error::Some issues cannot be fixed (e.g., immutable release conflicts). Consider adding affected versions to the ignore-versions list."
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
    
    # Use new function to show manual remediation instructions
    Get-ManualInstructions -State $State -GroupByType $false
    Write-ManualInstructionsToStepSummary -State $State
}
else
{
    # Not in auto-fix mode, show manual instructions for all issues
    Get-ManualInstructions -State $State -GroupByType $false
    Write-ManualInstructionsToStepSummary -State $State
}

# Set globals for test harness compatibility and exit
$global:returnCode = $exitCode
$global:State = $script:State  # Make State accessible to tests

# Cleanup sensitive data and temporary files
Invoke-Cleanup

exit $exitCode

