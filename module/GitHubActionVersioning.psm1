##############################################################################
# GitHubActionVersioning.psm1 - PowerShell Module for CLI Usage
#############################################################################
# This module provides a user-friendly PowerShell cmdlet for running the
# GitHub Action SemVer Checker from the command line.
#############################################################################

# Import CLI-specific logging module
. "$PSScriptRoot/CliLogging.ps1"

# Import core library modules
. "$PSScriptRoot/../lib/StateModel.ps1"
. "$PSScriptRoot/../lib/VersionParser.ps1"
. "$PSScriptRoot/../lib/GitHubApi.ps1"
. "$PSScriptRoot/../lib/RemediationActions.ps1"
. "$PSScriptRoot/../lib/Remediation.ps1"
. "$PSScriptRoot/../lib/ValidationRules.ps1"
. "$PSScriptRoot/../lib/InputValidation.ps1"
. "$PSScriptRoot/../lib/rules/releases/ReleaseRulesHelper.ps1"
. "$PSScriptRoot/../lib/rules/marketplace/MarketplaceRulesHelper.ps1"

function Test-GitHubActionVersioning
{
    <#
    .SYNOPSIS
    Validates semantic versioning tags and branches for GitHub Actions repositories.
    
    .DESCRIPTION
    Checks that version tags follow GitHub's immutable release strategy:
    - Patch versions (v1.0.0) have immutable GitHub Releases
    - Floating versions (v1, v1.0, latest) point to the latest compatible release
    
    .PARAMETER Repository
    Repository in format 'owner/repo'. If not provided, uses GITHUB_REPOSITORY environment variable.
    
    .PARAMETER Token
    GitHub token for API access. If not provided, tries gh auth token, then GITHUB_TOKEN environment variable.
    
    .PARAMETER CheckMinorVersion
    Check minor version tags. Values: error, warning, none. Default: error
    
    .PARAMETER CheckReleases
    Check that patch versions have GitHub Releases. Values: error, warning, none. Default: error
    
    .PARAMETER CheckReleaseImmutability
    Check that releases are immutable (published, not draft). Values: error, warning, none. Default: error
    
    .PARAMETER CheckMarketplace
    Check that the action has valid marketplace metadata (name, description, branding, README) and
    that the latest release is published to the GitHub Marketplace. Values: error, warning, none. Default: error
    
    .PARAMETER IgnorePreviewReleases
    Ignore preview/pre-release versions when calculating floating versions. Default: true
    
    .PARAMETER FloatingVersionsUse
    Use tags or branches for floating versions (v1, v1.0, latest). Values: tags, branches. Default: tags
    
    .PARAMETER AutoFix
    Automatically fix issues by updating tags/branches/releases. Requires write permissions. Default: false
    
    .PARAMETER IgnoreVersions
    Array of version patterns to ignore during validation (e.g., @('v1.0.0', 'v2.*')).
    
    .PARAMETER ApiUrl
    GitHub API URL. Default: https://api.github.com (or GITHUB_API_URL environment variable)
    
    .PARAMETER ServerUrl
    GitHub server URL. Default: https://github.com (or GITHUB_SERVER_URL environment variable)
    
    .PARAMETER Rules
    Array of rule names to run. If not specified, runs all rules. Use this to filter specific validation rules.
    
    .PARAMETER PassThru
    Return an object with detected issues and their statuses instead of just exit code.
    
    .EXAMPLE
    Test-GitHubActionVersioning -Repository 'owner/repo'
    
    Validates the specified repository using default settings.
    
    .EXAMPLE
    Test-GitHubActionVersioning -Repository 'owner/repo' -AutoFix
    
    Validates and automatically fixes any issues found.
    
    .EXAMPLE
    Test-GitHubActionVersioning -Repository 'owner/repo' -PassThru
    
    Returns an object with all validation issues and their statuses.
    
    .EXAMPLE
    Test-GitHubActionVersioning -Repository 'owner/repo' -Rules @('patch_release_required', 'major_tag_tracks_highest_patch')
    
    Runs only the specified validation rules.
    
    .EXAMPLE
    Test-GitHubActionVersioning -Repository 'owner/repo' -CheckMarketplace 'warning'
    
    Validates marketplace metadata and publication status, reporting issues as warnings.
    
    .OUTPUTS
    By default, returns exit code (0 = success, 1 = validation errors).
    With -PassThru, returns a hashtable with Issues, FixedCount, FailedCount, UnfixableCount, and ReturnCode.
    #>
    [CmdletBinding()]
    [OutputType([int], [hashtable])]
    param(
        [Parameter(Position = 0)]
        [string]$Repository,
        
        [Parameter()]
        [string]$Token,
        
        [Parameter()]
        [ValidateSet('error', 'warning', 'none')]
        [string]$CheckMinorVersion = 'error',
        
        [Parameter()]
        [ValidateSet('error', 'warning', 'none')]
        [string]$CheckReleases = 'error',
        
        [Parameter()]
        [ValidateSet('error', 'warning', 'none')]
        [string]$CheckReleaseImmutability = 'error',
        
        [Parameter()]
        [ValidateSet('error', 'warning', 'none')]
        [string]$CheckMarketplace = 'error',
        
        [Parameter()]
        [bool]$IgnorePreviewReleases = $true,
        
        [Parameter()]
        [ValidateSet('tags', 'branches')]
        [string]$FloatingVersionsUse = 'tags',
        
        [Parameter()]
        [switch]$AutoFix,
        
        [Parameter()]
        [string[]]$IgnoreVersions = @(),
        
        [Parameter()]
        [string]$ApiUrl,
        
        [Parameter()]
        [string]$ServerUrl,
        
        [Parameter()]
        [string[]]$Rules,
        
        [Parameter()]
        [switch]$PassThru
    )
    
    #############################################################################
    # Initialize State
    #############################################################################
    
    # Filter out GitHub Actions workflow commands (::debug::, etc.) from output
    # The library modules emit these for GitHub Actions, but they're not appropriate for CLI
    $script:cliMode = $true
    
    # Create a wrapper for Write-Host to filter workflow commands in CLI mode
    function global:Write-Host {
        [CmdletBinding()]
        param(
            [Parameter(Position = 0, ValueFromPipeline)]
            [object]$Object,
            [switch]$NoNewline,
            [object]$Separator,
            [System.ConsoleColor]$ForegroundColor,
            [System.ConsoleColor]$BackgroundColor
        )
        
        # Filter out GitHub Actions workflow commands in CLI mode
        # Matches patterns like ::debug::, ::warning::, ::error::, ::notice::, etc.
        if ($script:cliMode -and $Object -match '^::([a-z-]+)::') {
            # Convert ::debug:: to Write-Verbose, suppress others
            if ($Object -match '^::debug::') {
                $message = $Object -replace '^::debug::', ''
                Write-Verbose $message
            }
            # Suppress all other workflow commands (::warning::, ::error::, ::group::, etc.)
            return
        }
        
        # Pass through to original Write-Host using fully qualified name to avoid recursion
        $params = @{}
        if ($PSBoundParameters.ContainsKey('Object')) { $params['Object'] = $Object }
        if ($NoNewline) { $params['NoNewline'] = $true }
        if ($PSBoundParameters.ContainsKey('Separator')) { $params['Separator'] = $Separator }
        if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $params['ForegroundColor'] = $ForegroundColor }
        if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $params['BackgroundColor'] = $BackgroundColor }
        
        Microsoft.PowerShell.Utility\Write-Host @params
    }
    
    #############################################################################
    # Resolve Token (CLI-specific: try gh auth token before environment)
    #############################################################################
    
    $resolvedToken = $Token
    if (-not $resolvedToken) {
        # Try gh auth token first (CLI-specific)
        try {
            $ghToken = gh auth token 2>$null
            if ($LASTEXITCODE -eq 0 -and $ghToken) {
                $resolvedToken = $ghToken.Trim()
                Write-Verbose "Using token from 'gh auth token'"
            }
        }
        catch {
            Write-Verbose "gh auth token not available or failed: $($_.Exception.Message)"
        }
    }
    
    #############################################################################
    # Initialize State using shared function
    #############################################################################
    
    # Use the shared initialization function (no token masking in CLI mode)
    $state = Initialize-RepositoryState -Repository $Repository -Token $resolvedToken -ApiUrl $ApiUrl -ServerUrl $ServerUrl -MaskToken $false
    
    # Validate repository was provided or resolved
    if (-not $state.RepoOwner -or -not $state.RepoName) {
        # Try to provide helpful error based on whether Repository param was provided
        if (-not $Repository -and -not $env:GITHUB_REPOSITORY) {
            Write-ActionsError -Message "Repository not specified. Provide -Repository parameter or set GITHUB_REPOSITORY environment variable." -State $state
        }
        else {
            $repoValue = if ($Repository) { $Repository } else { $env:GITHUB_REPOSITORY }
            Write-ActionsError -Message "Invalid repository format. Expected 'owner/repo', got '$repoValue'" -State $state
        }
        if ($PassThru) {
            return New-ErrorResult -State $state
        }
        return 1
    }
    
    # Warn if no token available
    if (-not $state.Token) {
        Write-ActionsWarning -Message "No GitHub token available. API rate limits will be restrictive. Consider providing -Token or running 'gh auth login'."
    }
    
    #############################################################################
    # Configure State
    #############################################################################
    
    $state.CheckMinorVersion = ($CheckMinorVersion -ne "none")
    $state.CheckReleases = $CheckReleases
    $state.CheckImmutability = $CheckReleaseImmutability
    $state.CheckMarketplace = $CheckMarketplace
    $state.IgnorePreviewReleases = $IgnorePreviewReleases
    $state.FloatingVersionsUse = $FloatingVersionsUse
    $state.AutoFix = $AutoFix.IsPresent
    $state.IgnoreVersions = $IgnoreVersions
    
    # Validate auto-fix requirements
    if ($AutoFix -and -not $Token) {
        Write-ActionsError -Message "Auto-fix mode requires a GitHub token. Provide -Token or ensure GITHUB_TOKEN is set." -State $state
        if ($PassThru) {
            return New-ErrorResult -State $state
        }
        return 1
    }
    
    #############################################################################
    # Fetch Repository Data
    #############################################################################
    
    Write-Host "Fetching repository data for $Repository..."
    
    try {
        Initialize-RepositoryData -State $state `
            -IgnoreVersions $IgnoreVersions `
            -CheckMarketplace $CheckMarketplace `
            -AutoFix $AutoFix.IsPresent `
            -ScriptRoot "$PSScriptRoot/.."
        
        Write-Host "Found $($state.Tags.Count) version tags"
        if ($FloatingVersionsUse -eq 'branches') {
            Write-Host "Found $($state.Branches.Count) version branches"
        }
        Write-Host "Found $($state.Releases.Count) releases"
        
        if ($CheckMarketplace -ne 'none' -and $state.MarketplaceMetadata) {
            if ($state.MarketplaceMetadata.IsValid()) {
                Write-Host "Marketplace metadata: Valid (name=$($state.MarketplaceMetadata.Name))"
            }
            else {
                $missing = $state.MarketplaceMetadata.GetMissingRequirements()
                Write-Host "Marketplace metadata: Missing requirements - $($missing -join ', ')"
            }
        }
    }
    catch {
        Write-ActionsError -Message "Failed to fetch repository data: $_" -State $state
        if ($PassThru) {
            return New-ErrorResult -State $state
        }
        return 1
    }
    
    #############################################################################
    # Load and Run Validation Rules
    #############################################################################
    
    Write-Host ""
    Write-Host "Running validation rules..."
    
    # Create config hashtable
    $config = @{
        'check-minor-version' = $CheckMinorVersion
        'check-releases' = $CheckReleases
        'check-release-immutability' = $CheckReleaseImmutability
        'check-marketplace' = $CheckMarketplace
        'ignore-preview-releases' = $IgnorePreviewReleases
        'floating-versions-use' = $FloatingVersionsUse
        'auto-fix' = $AutoFix.IsPresent
    }
    
    # Load all rules or filtered rules
    $allRules = Get-ValidationRule -Config $config
    
    if ($Rules -and $Rules.Count -gt 0) {
        Write-Host "Filtering to specified rules: $($Rules -join ', ')"
        $rulesToRun = $allRules | Where-Object { $_.Name -in $Rules }
        
        if ($rulesToRun.Count -eq 0) {
            Write-ActionsWarning -Message "No matching rules found. Available rules: $($allRules.Name -join ', ')"
        }
    }
    else {
        $rulesToRun = $allRules
    }
    
    # Run validation rules
    Invoke-ValidationRule -State $state -Config $config -Rules $rulesToRun | Out-Null
    
    Write-Host "Validation complete. Found $($state.Issues.Count) issue(s)."
    
    #############################################################################
    # Auto-Fix
    #############################################################################
    
    if ($AutoFix -and $state.Issues.Count -gt 0) {
        Write-Host ""
        Write-Host "Auto-fix enabled. Attempting to fix issues..."
        
        Invoke-Remediation -State $state
        
        $fixedCount = $state.GetFixedIssuesCount()
        $failedCount = $state.GetFailedFixesCount()
        $unfixableCount = $state.GetUnfixableIssuesCount()
        
        Write-Host "Auto-fix results: $fixedCount fixed, $failedCount failed, $unfixableCount unfixable"
    }
    
    #############################################################################
    # Display Results
    #############################################################################
    
    Write-Host ""
    if ($state.Issues.Count -eq 0) {
        Write-Host "✓ All validations passed!" -ForegroundColor Green
    }
    else {
        # Group issues by status
        $byStatus = $state.Issues | Group-Object -Property Status
        
        foreach ($group in $byStatus) {
            Write-Host ""
            Write-Host "Issues with status '$($group.Name)': $($group.Count)"
            
            foreach ($issue in $group.Group) {
                $prefix = if ($issue.Severity -eq 'error') { '  ERROR:' } else { '  WARNING:' }
                Write-Host "$prefix $($issue.Message)"
            }
        }
        
        # Show manual fix commands if available
        if ($AutoFix) {
            $pendingIssues = $state.Issues | Where-Object { $_.Status -in @('pending', 'failed', 'unfixable', 'manual_fix_required') }
            if ($pendingIssues.Count -gt 0) {
                Write-Host ""
                Write-Host "Manual fixes required:"
                Get-ManualFixCommands -State $state | ForEach-Object {
                    Write-Host "  $_"
                }
            }
        }
    }
    
    #############################################################################
    # Return Results
    #############################################################################
    
    # Restore original Write-Host
    Remove-Item Function:\Write-Host -ErrorAction SilentlyContinue
    $script:cliMode = $false
    
    # Calculate return code - if AutoFix is disabled, pending issues should cause failure
    # If AutoFix is enabled, only unresolved issues after fixing should cause failure
    $returnCode = $state.GetReturnCode()
    
    # When AutoFix is disabled, pending issues mean validation failed
    if (-not $AutoFix) {
        $pendingCount = ($state.Issues | Where-Object { $_.Status -eq "pending" }).Count
        if ($pendingCount -gt 0) {
            $returnCode = 1
        }
    }
    
    if ($PassThru) {
        return @{
            Issues = $state.Issues
            FixedCount = $state.GetFixedIssuesCount()
            FailedCount = $state.GetFailedFixesCount()
            UnfixableCount = $state.GetUnfixableIssuesCount()
            ReturnCode = $returnCode
        }
    }
    
    return $returnCode
}

# Export the cmdlet
Export-ModuleMember -Function Test-GitHubActionVersioning

# Helper function for creating error result
function New-ErrorResult {
    <#
    .SYNOPSIS
    Creates a standardized error result hashtable for PassThru output.
    
    .DESCRIPTION
    Helper function that generates a consistent error result structure
    containing the current issues and zero counts for fixes. Used when
    early validation fails before processing can begin.
    
    .PARAMETER State
    The RepositoryState object containing accumulated issues.
    
    .OUTPUTS
    Hashtable with Issues, FixedCount, FailedCount, UnfixableCount, and ReturnCode.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State
    )
    
    return @{
        Issues = $State.Issues
        FixedCount = 0
        FailedCount = 0
        UnfixableCount = 0
        ReturnCode = 1
    }
}
