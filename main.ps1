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
. "$PSScriptRoot/lib/rules/marketplace/MarketplaceRulesHelper.ps1"
. "$PSScriptRoot/lib/ValidationRules.ps1"
. "$PSScriptRoot/lib/InputValidation.ps1"

#############################################################################
# GLOBAL STATE
#############################################################################

# Initialize repository state using the shared initialization function
# This handles API URLs, token, and repository parsing from environment variables
$script:State = Initialize-RepositoryState -MaskToken $true

# If repository could not be determined, warn user to configure GITHUB_REPOSITORY
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
$script:State.CheckMarketplace = $inputConfig.CheckMarketplace
$script:State.IgnorePreviewReleases = $inputConfig.IgnorePreviewReleases
$script:State.FloatingVersionsUse = $inputConfig.FloatingVersionsUse
$script:State.AutoFix = $inputConfig.AutoFix
$script:State.IgnoreVersions = $inputConfig.IgnoreVersions

# Debug: Show parsed input values
Write-InputDebugInfo -Config $inputConfig

# Validate inputs
$validationErrors = Test-ActionInput -Config $inputConfig
if ($validationErrors.Count -gt 0) {
    foreach ($validationError in $validationErrors) {
        Write-Output $validationError
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

#############################################################################
# FETCH REPOSITORY DATA
# Populate State with tags, branches, releases, and marketplace metadata
#############################################################################

Initialize-RepositoryData -State $script:State `
    -IgnoreVersions $inputConfig.IgnoreVersions `
    -CheckMarketplace $inputConfig.CheckMarketplace `
    -AutoFix $inputConfig.AutoFix `
    -ScriptRoot $PSScriptRoot

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
    'check-marketplace'            = $inputConfig.CheckMarketplace
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
# AUTO-FIX EXECUTION
#############################################################################

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
    
    # Only fail if there are ERROR-severity issues that are failed, manual fixes required, or unfixable
    # Warning-severity issues should not cause failure even with auto-fix
    $errorFailedCount = ($State.Issues | Where-Object { $_.Severity -eq "error" -and $_.Status -eq "failed" }).Count
    $errorManualFixCount = ($State.Issues | Where-Object { $_.Severity -eq "error" -and $_.Status -eq "manual_fix_required" }).Count
    $errorUnfixableCount = ($State.Issues | Where-Object { $_.Severity -eq "error" -and $_.Status -eq "unfixable" }).Count
    
    if ($errorFailedCount -gt 0 -or $errorManualFixCount -gt 0 -or $errorUnfixableCount -gt 0)
    {
        $exitCode = 1
        Write-Output ""
        if ($errorManualFixCount -gt 0) {
            Write-Output "::error::Some issues require manual intervention (e.g., workflow permission issues). Please fix manually."
        }
        if ($errorUnfixableCount -gt 0) {
            Write-Output "::error::Some issues cannot be fixed (e.g., immutable release conflicts). Consider adding affected versions to the ignore-versions list."
        }
    }
    elseif ($State.GetFixedIssuesCount() -gt 0)
    {
        # Issues were found and all were fixed successfully
        Write-Output ""
        Write-Output "::notice::All issues were successfully fixed!"
    }
    elseif ($State.GetManualFixRequiredCount() -gt 0 -or $State.GetUnfixableIssuesCount() -gt 0)
    {
        # Only warning-severity issues remain that need manual attention
        Write-Output ""
        Write-Output "::notice::Some warning-level issues require manual attention. See remediation steps below."
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

