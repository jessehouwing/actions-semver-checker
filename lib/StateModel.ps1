#############################################################################
# StateModel.ps1 - Domain Model for Repository State
#############################################################################
# This module defines the domain model classes used to track the current
# and desired state of versions, releases, and remediation actions.
#############################################################################

#############################################################################
# Version Reference Class
# Represents a version reference (tag or branch) with parsed version info
#############################################################################

class VersionRef {
    [string]$Version      # e.g., "v1.0.0"
    [string]$Ref          # e.g., "refs/tags/v1.0.0"
    [string]$Sha          # commit SHA
    [string]$Type         # "tag" or "branch"
    [bool]$IsPatch
    [bool]$IsMinor
    [bool]$IsMajor
    [bool]$IsIgnored      # Whether this version is in the ignore-versions list
    [int]$Major
    [int]$Minor
    [int]$Patch
    
    VersionRef([string]$version, [string]$ref, [string]$sha, [string]$type) {
        $this.Version = $version
        $this.Ref = $ref
        $this.Sha = $sha
        $this.Type = $type
        $this.ParseVersion()
    }
    
    hidden [void]ParseVersion() {
        # Parse version string to determine type and parts
        $versionStr = $this.Version -replace '^v', ''
        
        # Handle non-semver versions like "latest"
        if ($versionStr -notmatch '^\d') {
            $this.IsPatch = $false
            $this.IsMinor = $false
            $this.IsMajor = $false
            $this.Major = 0
            $this.Minor = 0
            $this.Patch = 0
            return
        }
        
        $parts = $versionStr -split '\.'
        
        if ($parts.Count -eq 3) {
            $this.IsPatch = $true
            $this.IsMinor = $false
            $this.IsMajor = $false
            $this.Major = [int]$parts[0]
            $this.Minor = [int]$parts[1]
            $this.Patch = [int]$parts[2]
        }
        elseif ($parts.Count -eq 2) {
            $this.IsPatch = $false
            $this.IsMinor = $true
            $this.IsMajor = $false
            $this.Major = [int]$parts[0]
            $this.Minor = [int]$parts[1]
            $this.Patch = 0
        }
        elseif ($parts.Count -eq 1) {
            $this.IsPatch = $false
            $this.IsMinor = $false
            $this.IsMajor = $true
            $this.Major = [int]$parts[0]
            $this.Minor = 0
            $this.Patch = 0
        }
        # Note: Prerelease status is determined from the GitHub Release API, not version suffix
    }
    
    [string]ToString() {
        return "$($this.Version) -> $($this.Sha) ($($this.Type))"
    }
}

#############################################################################
# Marketplace Metadata Class
# Represents action.yaml/action.yml metadata required for GitHub Marketplace
#############################################################################

class MarketplaceMetadata {
    [bool]$ActionFileExists       # action.yaml or action.yml exists
    [string]$ActionFilePath       # Which file was found (action.yaml or action.yml)
    [bool]$HasName                # 'name' property exists and is non-empty
    [bool]$HasDescription         # 'description' property exists and is non-empty
    [bool]$HasBrandingIcon        # 'branding.icon' property exists and is non-empty
    [bool]$HasBrandingColor       # 'branding.color' property exists and is non-empty
    [bool]$ReadmeExists           # README.md exists (case-insensitive check)
    [string]$Name                 # Value of 'name' property
    [string]$Description          # Value of 'description' property
    [string]$BrandingIcon         # Value of 'branding.icon' property
    [string]$BrandingColor        # Value of 'branding.color' property
    [string[]]$ValidationErrors   # List of validation issues found
    
    MarketplaceMetadata() {
        $this.ActionFileExists = $false
        $this.HasName = $false
        $this.HasDescription = $false
        $this.HasBrandingIcon = $false
        $this.HasBrandingColor = $false
        $this.ReadmeExists = $false
        $this.ValidationErrors = @()
    }
    
    [bool] IsValid() {
        return $this.ActionFileExists -and $this.HasName -and $this.HasDescription `
            -and $this.HasBrandingIcon -and $this.HasBrandingColor -and $this.ReadmeExists
    }
    
    [string[]] GetMissingRequirements() {
        $missing = @()
        if (-not $this.HasName) { $missing += "name property in action.yaml" }
        if (-not $this.HasDescription) { $missing += "description property in action.yaml" }
        if (-not $this.HasBrandingIcon) { $missing += "branding.icon property in action.yaml" }
        if (-not $this.HasBrandingColor) { $missing += "branding.color property in action.yaml" }
        if (-not $this.ReadmeExists) { $missing += "README.md file in repository root" }
        return $missing
    }
    
    [string]ToString() {
        if ($this.IsValid()) {
            return "Marketplace metadata: Valid (name=$($this.Name))"
        } else {
            $missing = $this.GetMissingRequirements()
            return "Marketplace metadata: Invalid (missing: $($missing -join ', '))"
        }
    }
}

#############################################################################
# Release Information Class
# Represents a GitHub Release with immutability and prerelease status
#############################################################################

class ReleaseInfo {
    [string]$TagName
    [string]$Sha
    [bool]$IsDraft
    [bool]$IsPrerelease
    [bool]$IsImmutable
    [bool]$IsIgnored      # Whether this release's tag is in the ignore-versions list
    [bool]$IsLatest       # Whether this release is marked as "latest" in GitHub
    [int]$Id
    [string]$HtmlUrl
    
    # Constructor with separate isImmutable parameter (legacy, for backwards compatibility)
    ReleaseInfo([PSCustomObject]$apiResponse, [bool]$isImmutable) {
        $this.TagName = $apiResponse.tag_name
        $this.Id = $apiResponse.id
        $this.IsDraft = $apiResponse.draft
        $this.IsPrerelease = $apiResponse.prerelease
        $this.HtmlUrl = $apiResponse.html_url
        
        # Extract SHA from target_commitish
        if ($apiResponse.target_commitish) {
            $this.Sha = $apiResponse.target_commitish
        }
        
        # Set immutability from explicit input
        $this.IsImmutable = $isImmutable
        
        # Set IsLatest from response property (if available)
        # The GitHub API returns is_latest on release objects
        if ($null -ne $apiResponse.is_latest) {
            $this.IsLatest = $apiResponse.is_latest
        } elseif ($null -ne $apiResponse.isLatest) {
            $this.IsLatest = $apiResponse.isLatest
        } else {
            $this.IsLatest = $false
        }
    }
    
    # Constructor with immutable property in the response object (GraphQL response)
    ReleaseInfo([PSCustomObject]$apiResponse) {
        $this.TagName = $apiResponse.tag_name
        $this.Id = $apiResponse.id
        $this.IsDraft = $apiResponse.draft
        $this.IsPrerelease = $apiResponse.prerelease
        $this.HtmlUrl = $apiResponse.html_url
        
        # Extract SHA from target_commitish
        if ($apiResponse.target_commitish) {
            $this.Sha = $apiResponse.target_commitish
        }
        
        # Set immutability from response property (if available)
        if ($null -ne $apiResponse.immutable) {
            $this.IsImmutable = $apiResponse.immutable
        } else {
            $this.IsImmutable = $false
        }
        
        # Set IsLatest from response property (if available)
        if ($null -ne $apiResponse.is_latest) {
            $this.IsLatest = $apiResponse.is_latest
        } elseif ($null -ne $apiResponse.isLatest) {
            $this.IsLatest = $apiResponse.isLatest
        } else {
            $this.IsLatest = $false
        }
    }
    
    [string]ToString() {
        $status = @()
        if ($this.IsDraft) { $status += "draft" }
        if ($this.IsPrerelease) { $status += "prerelease" }
        if (-not $this.IsImmutable) { $status += "mutable" }
        if ($this.IsLatest) { $status += "latest" }
        
        $statusStr = if ($status.Count -gt 0) { " [$($status -join ', ')]" } else { "" }
        return "$($this.TagName)$statusStr"
    }
}

#############################################################################
# Validation Issue Class
#############################################################################

class ValidationIssue {
    [string]$Type         # "missing_version", "mismatched_sha", etc.
    [string]$Severity     # "error", "warning"
    [string]$Message
    [string]$Version      # The version this issue relates to
    [string]$CurrentSha   # Current SHA (if any)
    [string]$ExpectedSha  # Expected SHA (if applicable)
    [bool]$IsAutoFixable
    [string]$FixCategory  # "create_tag", "update_tag", "delete_release", etc.
    [string]$ManualFixCommand
    [object]$RemediationAction  # RemediationAction instance
    [string[]]$Dependencies  # Other issues that must be fixed first
    # Status values: "pending", "fixed", "failed", "manual_fix_required", "unfixable"
    # - pending: Not yet attempted
    # - fixed: Successfully auto-fixed
    # - failed: Auto-fix attempted but failed
    # - manual_fix_required: Can be fixed manually (e.g., workflow permission issues)
    # - unfixable: Cannot be fixed (e.g., immutable release conflicts)
    [string]$Status
    
    ValidationIssue([string]$type, [string]$severity, [string]$message) {
        $this.Type = $type
        $this.Severity = $severity
        $this.Message = $message
        $this.IsAutoFixable = $false
        $this.Dependencies = @()
        $this.Status = "pending"
    }

    [void]SetRemediationAction([object]$remediationAction) {
        $this.RemediationAction = $remediationAction
        $this.IsAutoFixable = $null -ne $remediationAction
    }
    
    [string]ToString() {
        return "$($this.Severity.ToUpper()): $($this.Message)"
    }
}

#############################################################################
# Repository State Class
#############################################################################

class RepositoryState {
    [VersionRef[]]$Tags
    [VersionRef[]]$Branches
    [ReleaseInfo[]]$Releases
    [MarketplaceMetadata]$MarketplaceMetadata  # Action metadata for marketplace validation
    [string]$RepoOwner
    [string]$RepoName
    [string]$ApiUrl
    [string]$ServerUrl
    [string]$Token
    
    # Configuration from inputs
    [bool]$AutoFix
    [bool]$CheckMinorVersion
    [string]$CheckReleases       # "error", "warning", "none"
    [string]$CheckImmutability   # "error", "warning", "none"
    [string]$CheckMarketplace    # "error", "warning", "none"
    [bool]$IgnorePreviewReleases
    [string]$FloatingVersionsUse # "tags", "branches", "both"
    [string[]]$IgnoreVersions    # List of versions to ignore
    
    # Issue tracking
    [ValidationIssue[]]$Issues
    
    RepositoryState() {
        $this.Tags = @()
        $this.Branches = @()
        $this.Releases = @()
        $this.Issues = @()
        $this.MarketplaceMetadata = [MarketplaceMetadata]::new()
    }
    
    [void]AddIssue([ValidationIssue]$issue) {
        $this.Issues += $issue
    }
    
    [ValidationIssue[]]GetErrorIssues() {
        return $this.Issues | Where-Object { $_.Severity -eq "error" }
    }
    
    [ValidationIssue[]]GetWarningIssues() {
        return $this.Issues | Where-Object { $_.Severity -eq "warning" }
    }
    
    [ValidationIssue[]]GetAutoFixableIssues() {
        return $this.Issues | Where-Object { $_.IsAutoFixable }
    }
    
    [ValidationIssue[]]GetManualFixIssues() {
        return $this.Issues | Where-Object { -not $_.IsAutoFixable -and $_.ManualFixCommand }
    }
    
    # Calculated properties (derived from issue statuses)
    [int]GetFixedIssuesCount() {
        return ($this.Issues | Where-Object { $_.Status -eq "fixed" }).Count
    }
    
    [int]GetFailedFixesCount() {
        return ($this.Issues | Where-Object { $_.Status -eq "failed" }).Count
    }
    
    [int]GetUnfixableIssuesCount() {
        return ($this.Issues | Where-Object { $_.Status -eq "unfixable" }).Count
    }
    
    [int]GetManualFixRequiredCount() {
        return ($this.Issues | Where-Object { $_.Status -eq "manual_fix_required" }).Count
    }
    
    [int]GetReturnCode() {
        # Return 1 if there are unresolved ERROR-severity issues (failed, manual_fix_required, or unfixable)
        # Fixed issues and WARNING-severity issues should not cause a failure
        $errorIssues = $this.Issues | Where-Object { 
            $_.Severity -eq "error" -and 
            $_.Status -in @("failed", "manual_fix_required", "unfixable") 
        }
        
        if ($errorIssues.Count -gt 0) {
            return 1
        } else {
            return 0
        }
    }
    
    [VersionRef[]]GetPatchVersions() {
        return ($this.Tags + $this.Branches) | Where-Object { $_.IsPatch }
    }
    
    [VersionRef[]]GetMinorVersions() {
        return ($this.Tags + $this.Branches) | Where-Object { $_.IsMinor }
    }
    
    [VersionRef[]]GetMajorVersions() {
        return ($this.Tags + $this.Branches) | Where-Object { $_.IsMajor }
    }
    
    [VersionRef]FindVersion([string]$version, [string]$type) {
        if ($type -eq "tag") {
            return $this.Tags | Where-Object { $_.Version -eq $version } | Select-Object -First 1
        }
        elseif ($type -eq "branch") {
            return $this.Branches | Where-Object { $_.Version -eq $version } | Select-Object -First 1
        }
        else {
            # Search both
            $found = $this.Tags | Where-Object { $_.Version -eq $version } | Select-Object -First 1
            if (-not $found) {
                $found = $this.Branches | Where-Object { $_.Version -eq $version } | Select-Object -First 1
            }
            return $found
        }
    }
    
    [ReleaseInfo]FindRelease([string]$tagName) {
        return $this.Releases | Where-Object { $_.TagName -eq $tagName } | Select-Object -First 1
    }
}

#############################################################################
# State Initialization Functions
#############################################################################

function Initialize-RepositoryState {
    <#
    .SYNOPSIS
    Initializes a RepositoryState object with common configuration from environment variables.
    
    .DESCRIPTION
    Creates and configures a RepositoryState object with:
    - API URLs from environment variables (GITHUB_API_URL, GITHUB_SERVER_URL) or defaults
    - Token from environment variable (GITHUB_TOKEN)
    - Repository owner/name parsed from GITHUB_REPOSITORY
    
    This function consolidates initialization logic shared between the GitHub Action 
    entry point (main.ps1) and the CLI module (GitHubActionVersioning.psm1).
    
    .PARAMETER Repository
    Optional repository in format 'owner/repo'. If not provided, uses GITHUB_REPOSITORY 
    environment variable.
    
    .PARAMETER Token
    Optional GitHub token for API access. If not provided, uses GITHUB_TOKEN environment 
    variable. For CLI usage, the caller may also try 'gh auth token' before calling this.
    
    .PARAMETER ApiUrl
    Optional GitHub API URL. If not provided, uses GITHUB_API_URL environment variable 
    or defaults to https://api.github.com.
    
    .PARAMETER ServerUrl
    Optional GitHub server URL. If not provided, uses GITHUB_SERVER_URL environment 
    variable or defaults to https://github.com.
    
    .PARAMETER MaskToken
    If true (default for GitHub Actions context), emits ::add-mask:: for the token.
    Set to false for CLI usage where workflow commands aren't appropriate.
    
    .OUTPUTS
    [RepositoryState] A new RepositoryState instance with basic configuration applied.
    
    .EXAMPLE
    # GitHub Actions context (uses environment variables)
    $state = Initialize-RepositoryState
    
    .EXAMPLE
    # CLI context with explicit parameters
    $state = Initialize-RepositoryState -Repository 'owner/repo' -Token $myToken -MaskToken:$false
    #>
    [CmdletBinding()]
    [OutputType([RepositoryState])]
    param(
        [Parameter()]
        [string]$Repository,
        
        [Parameter()]
        [string]$Token,
        
        [Parameter()]
        [string]$ApiUrl,
        
        [Parameter()]
        [string]$ServerUrl,
        
        [Parameter()]
        [bool]$MaskToken = $true
    )
    
    # Create new state instance
    $state = [RepositoryState]::new()
    
    # Set API URLs (parameter > environment > default)
    if ($ApiUrl) {
        $state.ApiUrl = $ApiUrl
    }
    elseif ($env:GITHUB_API_URL) {
        $state.ApiUrl = $env:GITHUB_API_URL
    }
    else {
        $state.ApiUrl = "https://api.github.com"
    }
    
    if ($ServerUrl) {
        $state.ServerUrl = $ServerUrl
    }
    elseif ($env:GITHUB_SERVER_URL) {
        $state.ServerUrl = $env:GITHUB_SERVER_URL
    }
    else {
        $state.ServerUrl = "https://github.com"
    }
    
    # Set token (parameter > environment > empty)
    if ($Token) {
        $state.Token = $Token
    }
    elseif ($env:GITHUB_TOKEN) {
        $state.Token = $env:GITHUB_TOKEN
    }
    else {
        $state.Token = ""
    }
    
    # SECURITY: Mask the token to prevent accidental exposure in logs
    # Only do this in GitHub Actions context (MaskToken = true)
    if ($MaskToken -and $state.Token) {
        Write-Host "::add-mask::$($state.Token)"
    }
    
    # Parse repository owner and name
    $repoToUse = if ($Repository) { $Repository } else { $env:GITHUB_REPOSITORY }
    
    if ($repoToUse) {
        $parts = $repoToUse -split '/', 2
        if ($parts.Count -eq 2 -and $parts[0] -and $parts[1]) {
            $state.RepoOwner = $parts[0]
            $state.RepoName = $parts[1]
        }
    }
    
    return $state
}

function Initialize-RepositoryData {
    <#
    .SYNOPSIS
    Populates a RepositoryState object with repository data (tags, branches, releases, marketplace metadata).
    
    .DESCRIPTION
    Fetches and populates the RepositoryState with:
    - Version tags and 'latest' tag from GitHub API
    - Version branches and 'latest' branch from GitHub API
    - GitHub releases with prerelease/draft/immutability metadata
    - Marketplace metadata (action.yaml, README) when marketplace checks are enabled
    
    This function consolidates data fetching logic from main.ps1 to enable reuse
    and keep the main script focused on validation logic.
    
    .PARAMETER State
    The RepositoryState object to populate with data.
    
    .PARAMETER IgnoreVersions
    Array of version patterns to ignore (supports wildcards like 'v1.*').
    
    .PARAMETER CheckMarketplace
    The marketplace check level ('none', 'warn', 'error'). When not 'none', 
    marketplace metadata will be fetched.
    
    .PARAMETER AutoFix
    If true, outputs debug information about required permissions.
    
    .PARAMETER ScriptRoot
    The root path for loading additional modules (e.g., MarketplaceRulesHelper.ps1).
    Required when CheckMarketplace is not 'none'.
    
    .OUTPUTS
    [void] The function modifies the State object in place.
    
    .EXAMPLE
    Initialize-RepositoryData -State $state -IgnoreVersions @() -CheckMarketplace 'error' -AutoFix $false
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        
        [Parameter()]
        [string[]]$IgnoreVersions = @(),
        
        [Parameter()]
        [string]$CheckMarketplace = 'error',
        
        [Parameter()]
        [bool]$AutoFix = $false,
        
        [Parameter()]
        [string]$ScriptRoot
    )
    
    #############################################################################
    # Fetch tags and branches via GitHub API
    #############################################################################
    
    Write-Host "::debug::Fetching tags from GitHub API..."
    $apiTags = Get-GitHubTag -State $State -Pattern "^v\d+(\.\d+){0,2}$" -IgnoreVersions $IgnoreVersions
    $tags = $apiTags | ForEach-Object { $_.Version }
    Write-Host "::debug::Found $($tags.Count) version tags: $($tags -join ', ')"
    
    Write-Host "::debug::Fetching branches from GitHub API..."
    $apiBranches = Get-GitHubBranch -State $State -Pattern "^v\d+(\.\d+){0,2}(-.*)?$" -IgnoreVersions $IgnoreVersions
    $branches = $apiBranches | ForEach-Object { $_.Version }
    Write-Host "::debug::Found $($branches.Count) version branches: $($branches -join ', ')"
    
    # Also fetch latest tag and branch via API (for 'latest' alias validation)
    $apiLatestTag = Get-GitHubTag -State $State -Pattern "^latest$"
    $apiLatestBranch = Get-GitHubBranch -State $State -Pattern "^latest$"
    
    #############################################################################
    # Fetch releases
    #############################################################################
    
    # Get repository info for URLs
    $repoInfo = Get-GitHubRepoInfo -State $State
    
    if ($AutoFix -and $repoInfo) {
        Write-Host "::debug::Auto-fix is enabled. Ensure your workflow has 'contents: write' permission."
        Write-Host "::debug::Example workflow permissions:"
        Write-Host "::debug::  permissions:"
        Write-Host "::debug::    contents: write"
    }
    
    # Get GitHub releases - returns ReleaseInfo[] directly with IsIgnored set
    $releases = @()
    if ($repoInfo) {
        $releases = Get-GitHubRelease -State $State -IgnoreVersions $IgnoreVersions
        Write-Host "::debug::Found $($releases.Count) releases: $(($releases | ForEach-Object { $_.TagName + $(if ($_.IsDraft) { ' (draft)' } else { '' }) }) -join ', ')"
    }
    
    #############################################################################
    # Populate State Model
    #############################################################################
    
    # Populate State.Tags from API response (already VersionRef objects)
    $State.Tags = $apiTags
    foreach ($tag in $State.Tags) {
        Write-Host "::debug::Added tag $($tag.Version) to State (ignored=$($tag.IsIgnored))"
    }
    
    # Add 'latest' tag to State if it exists
    if ($apiLatestTag -and $apiLatestTag.Count -gt 0) {
        $State.Tags += $apiLatestTag | Select-Object -First 1
    }
    
    # Populate State.Branches from API response (already VersionRef objects)
    $State.Branches = $apiBranches
    
    # Add 'latest' branch to State if it exists
    if ($apiLatestBranch -and $apiLatestBranch.Count -gt 0) {
        $State.Branches += $apiLatestBranch | Select-Object -First 1
    }
    
    # Populate State.Releases from API response (already ReleaseInfo objects)
    $State.Releases = $releases
    
    Write-Host "::debug::State.Releases contains $($State.Releases.Count) releases"
    if ($State.Releases.Count -gt 0) {
        $draftReleases = $State.Releases | Where-Object { $_.IsDraft }
        Write-Host "::debug::Draft releases in State: $(($draftReleases | ForEach-Object { $_.TagName }) -join ', ')"
    }
    
    #############################################################################
    # Marketplace metadata
    #############################################################################
    
    if ($CheckMarketplace -ne 'none') {
        Write-Host "::debug::Fetching marketplace metadata..."
        
        # Load the marketplace helper to get metadata
        if ($ScriptRoot) {
            . "$ScriptRoot/lib/rules/marketplace/MarketplaceRulesHelper.ps1"
        }
        
        $State.MarketplaceMetadata = Get-ActionMarketplaceMetadata -State $State
        Write-Host "::debug::Marketplace metadata: $($State.MarketplaceMetadata.ToString())"
    }
}

#############################################################################
# State Summary Functions
#############################################################################

function Write-RepositoryStateSummary {
    <#
    .SYNOPSIS
    Writes a summary of the repository state (tags, branches, releases) to the console.
    
    .PARAMETER Tags
    Array of tag objects (hashtables or VersionRef objects) with version, sha, isMajorVersion/IsMajor, isMinorVersion/IsMinor properties.
    
    .PARAMETER Branches
    Array of branch objects (hashtables or VersionRef objects) with version, sha, isMajorVersion/IsMajor, isMinorVersion/IsMinor properties.
    
    .PARAMETER Releases
    Array of release objects (hashtables or ReleaseInfo objects) with tagName/TagName, isDraft/IsDraft, isPrerelease/IsPrerelease, isImmutable/IsImmutable properties.
    
    .PARAMETER Title
    Optional title for the grouped output. Default is "Current Repository State".
    #>
    param(
        [array]$Tags = @(),
        [array]$Branches = @(),
        [array]$Releases = @(),
        [string]$Title = "Current Repository State"
    )
    
    Write-Host "##[group]$Title"
    
    # Tags
    Write-Host "Tags: $($Tags.Count)" -ForegroundColor White
    if ($Tags.Count -gt 0) {
        $maxToShow = if ($Tags.Count -gt 20) { 10 } else { $Tags.Count }
        if ($Tags.Count -gt 20) {
            Write-Host "  (showing first $maxToShow of $($Tags.Count) tags)" -ForegroundColor Gray
        }
        $tagsToShow = $Tags | Sort-Object { $_.version ?? $_.Version } | Select-Object -First $maxToShow
        foreach ($tag in $tagsToShow) {
            $version = $tag.version ?? $tag.Version
            $sha = $tag.sha ?? $tag.Sha
            $shaShort = if ($sha -and $sha.Length -ge 7) { $sha.Substring(0, 7) } else { "unknown" }
            $isMajor = $tag.isMajorVersion ?? $tag.IsMajor
            $isMinor = $tag.isMinorVersion ?? $tag.IsMinor
            $isIgnored = $tag.isIgnored ?? $tag.IsIgnored
            $typeLabel = if ($isMajor) { "major" } elseif ($isMinor) { "minor" } else { "patch" }
            $ignoredStr = if ($isIgnored) { " [ignored]" } else { "" }
            Write-Host "  $version -> $shaShort ($typeLabel)$ignoredStr" -ForegroundColor Gray
        }
    }
    Write-Host ""
    
    # Branches
    Write-Host "Branches: $($Branches.Count)" -ForegroundColor White
    if ($Branches.Count -gt 0) {
        $maxToShow = if ($Branches.Count -gt 15) { 10 } else { $Branches.Count }
        if ($Branches.Count -gt 15) {
            Write-Host "  (showing first $maxToShow of $($Branches.Count) branches)" -ForegroundColor Gray
        }
        $branchesToShow = $Branches | Sort-Object { $_.version ?? $_.Version } | Select-Object -First $maxToShow
        foreach ($branch in $branchesToShow) {
            $version = $branch.version ?? $branch.Version
            $sha = $branch.sha ?? $branch.Sha
            $shaShort = if ($sha -and $sha.Length -ge 7) { $sha.Substring(0, 7) } else { "unknown" }
            $isMajor = $branch.isMajorVersion ?? $branch.IsMajor
            $isMinor = $branch.isMinorVersion ?? $branch.IsMinor
            $isIgnored = $branch.isIgnored ?? $branch.IsIgnored
            $typeLabel = if ($isMajor) { "major" } elseif ($isMinor) { "minor" } else { "patch" }
            $ignoredStr = if ($isIgnored) { " [ignored]" } else { "" }
            Write-Host "  $version -> $shaShort ($typeLabel)$ignoredStr" -ForegroundColor Gray
        }
    }
    Write-Host ""
    
    # Releases
    Write-Host "Releases: $($Releases.Count)" -ForegroundColor White
    if ($Releases.Count -gt 0) {
        $maxToShow = if ($Releases.Count -gt 15) { 10 } else { $Releases.Count }
        if ($Releases.Count -gt 15) {
            Write-Host "  (showing first $maxToShow of $($Releases.Count) releases)" -ForegroundColor Gray
        }
        $releasesToShow = $Releases | Sort-Object { $_.tagName ?? $_.TagName } | Select-Object -First $maxToShow
        foreach ($release in $releasesToShow) {
            $tagName = $release.tagName ?? $release.TagName
            $isDraft = $release.isDraft ?? $release.IsDraft
            $isPrerelease = $release.isPrerelease ?? $release.IsPrerelease
            $isImmutable = $release.isImmutable ?? $release.IsImmutable
            $isIgnored = $release.isIgnored ?? $release.IsIgnored
            $status = @()
            if ($isDraft) { $status += "draft" }
            if ($isPrerelease) { $status += "prerelease" }
            if ($isIgnored) { $status += "ignored" }
            $statusStr = if ($status.Count -gt 0) { " [$($status -join ', ')]" } else { "" }
            $immutableSymbol = if ($isImmutable) { "🔒" } else { "🔓" }
            Write-Host "  $immutableSymbol $tagName$statusStr" -ForegroundColor Gray
        }
    }
    
    Write-Host "##[endgroup]"
}
