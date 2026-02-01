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
. "$PSScriptRoot/lib/rules/releases/ReleaseRulesHelper.ps1"
. "$PSScriptRoot/lib/ValidationRules.ps1"
. "$PSScriptRoot/lib/InputValidation.ps1"

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

# Parse and validate inputs using InputValidation module
$inputConfig = Read-ActionInput -State $script:State
if (-not $inputConfig) {
    exit 1
}

# Update State with parsed input configuration
$script:State.Token = $inputConfig.Token
$script:State.CheckMinorVersion = ($inputConfig.CheckMinorVersion -ne "none")
$script:State.CheckReleases = $inputConfig.CheckReleases
$script:State.CheckImmutability = $inputConfig.CheckReleaseImmutability
$script:State.IgnorePreviewReleases = $inputConfig.IgnorePreviewReleases
$script:State.FloatingVersionsUse = $inputConfig.FloatingVersionsUse
$script:State.AutoFix = $inputConfig.AutoFix
$script:State.IgnoreVersions = $inputConfig.IgnoreVersions

# Debug: Show parsed input values
Write-InputDebugInfo -Config $inputConfig

# Validate inputs
$validationErrors = Test-ActionInput -Config $inputConfig
if ($validationErrors.Count -gt 0) {
    foreach ($error in $validationErrors) {
        Write-Output $error
    }
    exit 1
}

# Debug output for repository info
Write-RepositoryDebugInfo -State $script:State -Config $inputConfig

# Validate token is available for auto-fix mode
if (-not (Test-AutoFixRequirement -State $script:State -AutoFix $inputConfig.AutoFix)) {
    $global:returnCode = 1
    exit 1
}

# Fetch tags and branches via GitHub API (no checkout required)
Write-Host "::debug::Fetching tags from GitHub API..."
$apiTags = Get-GitHubTag -State $script:State -Pattern "^v\d+(\.\d+){0,2}$"
$tags = $apiTags | ForEach-Object { $_.name }
Write-Host "::debug::Found $($tags.Count) version tags: $($tags -join ', ')"

Write-Host "::debug::Fetching branches from GitHub API..."
$apiBranches = Get-GitHubBranch -State $script:State -Pattern "^v\d+(\.\d+){0,2}(-.*)?$"
$branches = $apiBranches | ForEach-Object { $_.name }

# Also fetch latest tag and branch via API (for 'latest' alias validation)
$apiLatestTag = Get-GitHubTag -State $script:State -Pattern "^latest$"
$apiLatestBranch = Get-GitHubBranch -State $script:State -Pattern "^latest$"

# Auto-fix tracking variables are initialized in GLOBAL STATE section above

#############################################################################
# MAIN EXECUTION
#############################################################################

# Get repository info for URLs
$repoInfo = Get-GitHubRepoInfo -State $script:State

if ($inputConfig.AutoFix -and $repoInfo) {
    # Note: GitHub API doesn't expose token permissions directly via a simple endpoint
    # The permissions are workflow-level configuration, not token-level metadata
    # We'll validate this at the workflow configuration level in documentation
    # and provide clear error messages when operations fail due to insufficient permissions
    
    Write-Host "::debug::Auto-fix is enabled. Ensure your workflow has 'contents: write' permission."
    Write-Host "::debug::Example workflow permissions:"
    Write-Host "::debug::  permissions:"
    Write-Host "::debug::    contents: write"
}

# Get GitHub releases - always fetch to detect prerelease versions
$releases = @()
$releaseMap = @{}
if ($repoInfo) {
    $releases = Get-GitHubRelease -State $script:State
    # Create a map for quick lookup and set isIgnored property
    foreach ($release in $releases) {
        $release.isIgnored = Test-VersionIgnored -Version $release.tagName -IgnoreVersions $inputConfig.IgnoreVersions
        $releaseMap[$release.tagName] = $release
    }
}

#############################################################################
# POPULATE STATE MODEL
#############################################################################

# Populate State.Tags from API response
foreach ($tag in $tags) {
    # Check if this version should be ignored
    $isIgnored = Test-VersionIgnored -Version $tag -IgnoreVersions $inputConfig.IgnoreVersions
    
    # Get SHA from API response
    $tagInfo = $apiTags | Where-Object { $_.name -eq $tag } | Select-Object -First 1
    $tagSha = if ($tagInfo) { $tagInfo.sha } else { $null }
    
    $vr = [VersionRef]::new($tag, "refs/tags/$tag", $tagSha, "tag")
    $vr.IsIgnored = $isIgnored
    
    $script:State.Tags += $vr
    Write-Host "::debug::Added tag $tag to State (ignored=$isIgnored)"
}

# Add 'latest' tag to State if it exists
if ($apiLatestTag -and $apiLatestTag.Count -gt 0) {
    $latestTagInfo = $apiLatestTag | Select-Object -First 1
    $latestVr = [VersionRef]::new("latest", "refs/tags/latest", $latestTagInfo.sha, "tag")
    $script:State.Tags += $latestVr
}

# Populate State.Branches from API response
foreach ($branch in $branches) {
    # Check if this version should be ignored
    $isIgnored = Test-VersionIgnored -Version $branch -IgnoreVersions $inputConfig.IgnoreVersions
    
    # Get SHA from API response
    $branchInfo = $apiBranches | Where-Object { $_.name -eq $branch } | Select-Object -First 1
    $branchSha = if ($branchInfo) { $branchInfo.sha } else { $null }
    
    $vr = [VersionRef]::new($branch, "refs/heads/$branch", $branchSha, "branch")
    $vr.IsIgnored = $isIgnored
    $script:State.Branches += $vr
}

# Add 'latest' branch to State if it exists
if ($apiLatestBranch -and $apiLatestBranch.Count -gt 0) {
    $latestBranchInfo = $apiLatestBranch | Select-Object -First 1
    $latestVr = [VersionRef]::new("latest", "refs/heads/latest", $latestBranchInfo.sha, "branch")
    $script:State.Branches += $latestVr
}

# Populate State.Releases from API response
foreach ($release in $releases) {
    # Convert the release hashtable to PSCustomObject format expected by ReleaseInfo constructor
    # The immutable property is now included directly from the GraphQL response
    $releaseData = [PSCustomObject]@{
        tag_name = $release.tagName
        id = $release.id
        draft = $release.isDraft
        prerelease = $release.isPrerelease
        html_url = $release.htmlUrl
        target_commitish = $release.targetCommitish
        immutable = $release.immutable
    }

    $ri = [ReleaseInfo]::new($releaseData)
    $ri.IsIgnored = $release.isIgnored
    $script:State.Releases += $ri
}

#############################################################################
# VALIDATION ENGINE (Rule-Based)
# Execute validation rules to detect issues. Results are stored in State.Issues.
#############################################################################

Write-Host "##[group]Rule-based Validation Engine"

# Build configuration hashtable from parsed inputs for the rule engine
$ruleConfig = @{
    'check-minor-version'          = $inputConfig.CheckMinorVersion
    'check-releases'               = $inputConfig.CheckReleases
    'check-release-immutability'   = $inputConfig.CheckReleaseImmutability
    'ignore-preview-releases'      = $inputConfig.IgnorePreviewReleases
    'floating-versions-use'        = $inputConfig.FloatingVersionsUse
    'auto-fix'                     = $inputConfig.AutoFix
    'ignore-versions'              = $inputConfig.IgnoreVersions
}

Write-Host "::debug::Rule engine config: $($ruleConfig | ConvertTo-Json -Compress)"

# Load and execute validation rules
$allRules = Get-ValidationRule
Write-Host "::debug::Loaded $($allRules.Count) validation rules"

if ($allRules.Count -gt 0) {
    # Execute rules directly on $script:State - issues are added to State.Issues
    $ruleIssues = Invoke-ValidationRule -State $script:State -Config $ruleConfig -Rules $allRules
    
    Write-Host "::debug::Rule engine found $($ruleIssues.Count) issues"
    
    # Log rule engine results
    if ($ruleIssues.Count -gt 0) {
        Write-Host "::debug::=== Rule Engine Issues ==="
        foreach ($issue in $ruleIssues) {
            Write-Host "::debug::  [$($issue.Type)] $($issue.Version): $($issue.Message)"
        }
    }
}

Write-Host "##[endgroup]"

#############################################################################
# DIFF VISUALIZATION AND AUTO-FIX EXECUTION
#############################################################################

# Display planned changes BEFORE executing any fixes
if ($inputConfig.AutoFix -and $State.Issues.Count -gt 0) {
    $diffs = Get-StateDiff -State $State
    if ($diffs.Count -gt 0) {
        Write-StateDiff -Diffs $diffs
    }
}

# Now execute all auto-fixes (or mark as unfixable when auto-fix is disabled)
if ($inputConfig.AutoFix -and $State.Issues.Count -gt 0) {
    Write-Host "##[group]Verifying potential solutions"
}
Invoke-AutoFix -State $State -AutoFix $inputConfig.AutoFix
if ($inputConfig.AutoFix -and $State.Issues.Count -gt 0) {
    Write-Host "##[endgroup]"
}

#############################################################################
# LOG UNRESOLVED ISSUES
#############################################################################

# Log all unresolved issues (failed or unfixable) as errors/warnings
# This happens AFTER autofix completes, regardless of whether autofix is enabled
Write-UnresolvedIssue -State $State

#############################################################################
# FINAL SUMMARY AND EXIT
#############################################################################

# Display summary based on auto-fix mode
$exitCode = $State.GetReturnCode()

if ($inputConfig.AutoFix)
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
    Get-ManualInstruction -State $State -GroupByType $false
    Write-ManualInstructionsToStepSummary -State $State
}
else
{
    # Not in auto-fix mode, show manual instructions for all issues
    Get-ManualInstruction -State $State -GroupByType $false
    Write-ManualInstructionsToStepSummary -State $State
}

# Set globals for test harness compatibility and exit
$global:returnCode = $exitCode
$global:State = $script:State  # Make State accessible to tests

exit $exitCode

