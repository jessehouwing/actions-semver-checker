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
    }
    
    [string]ToString() {
        $status = @()
        if ($this.IsDraft) { $status += "draft" }
        if ($this.IsPrerelease) { $status += "prerelease" }
        if (-not $this.IsImmutable) { $status += "mutable" }
        
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
# State Diff Class
#############################################################################

class StateDiff {
    [string]$Action       # "create", "update", "delete"
    [string]$RefType      # "tag", "branch", "release"
    [string]$Version
    [string]$CurrentSha   # Current SHA (empty for create)
    [string]$DesiredSha   # Desired SHA (empty for delete)
    [string]$Reason
    
    StateDiff([string]$action, [string]$refType, [string]$version, [string]$currentSha, [string]$desiredSha, [string]$reason) {
        $this.Action = $action
        $this.RefType = $refType
        $this.Version = $version
        $this.CurrentSha = $currentSha
        $this.DesiredSha = $desiredSha
        $this.Reason = $reason
    }
    
    [string]ToString() {
        $shaInfo = ""
        if ($this.Action -eq "create") {
            $shortSha = if ($this.DesiredSha) { $this.DesiredSha.Substring(0, [Math]::Min(7, $this.DesiredSha.Length)) } else { "" }
            $shaInfo = " → $shortSha"
        }
        elseif ($this.Action -eq "update") {
            $currentShort = if ($this.CurrentSha) { $this.CurrentSha.Substring(0, [Math]::Min(7, $this.CurrentSha.Length)) } else { "" }
            $desiredShort = if ($this.DesiredSha) { $this.DesiredSha.Substring(0, [Math]::Min(7, $this.DesiredSha.Length)) } else { "" }
            $shaInfo = " $currentShort → $desiredShort"
        }
        elseif ($this.Action -eq "delete") {
            $shortSha = if ($this.CurrentSha) { $this.CurrentSha.Substring(0, [Math]::Min(7, $this.CurrentSha.Length)) } else { "" }
            $shaInfo = " $shortSha"
        }
        
        return "$($this.RefType) $($this.Version)$shaInfo - $($this.Reason)"
    }
}

#############################################################################
# Repository State Class
#############################################################################

class RepositoryState {
    [VersionRef[]]$Tags
    [VersionRef[]]$Branches
    [ReleaseInfo[]]$Releases
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
        # Return 1 if there are unresolved issues (failed, manual_fix_required, or unfixable), 0 otherwise
        # Fixed issues should not cause a failure
        $failedCount = ($this.Issues | Where-Object { $_.Status -eq "failed" }).Count
        $manualFixCount = ($this.Issues | Where-Object { $_.Status -eq "manual_fix_required" }).Count
        $unfixableCount = ($this.Issues | Where-Object { $_.Status -eq "unfixable" }).Count
        
        if ($failedCount -gt 0 -or $manualFixCount -gt 0 -or $unfixableCount -gt 0) {
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

function Get-StateDiff {
    <#
    .SYNOPSIS
    Calculate the difference between current and desired state based on validation issues.
    
    .PARAMETER State
    The repository state object containing issues.
    
    .OUTPUTS
    Array of StateDiff objects representing planned changes.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State
    )
    
    $diffs = @()
    
    # Convert ValidationIssues to StateDiffs
    foreach ($issue in $State.Issues) {
        # Skip issues that don't have a fix command (not fixable)
        if (-not $issue.ManualFixCommand -and -not $issue.Version) {
            continue
        }
        
        # Determine action type based on issue type
        if ($issue.Type -match "missing") {
            # Create action
            $refType = "tag"
            if ($issue.Type -match "branch") {
                $refType = "branch"
            }
            elseif ($issue.Type -match "release") {
                $refType = "release"
            }
            
            $diff = [StateDiff]::new(
                "create",
                $refType,
                $issue.Version,
                "",
                $issue.ExpectedSha,
                $issue.Message
            )
            $diffs += $diff
        }
        elseif ($issue.Type -match "mismatch" -or $issue.Type -match "incorrect") {
            # Update action
            $refType = "tag"
            if ($issue.Type -match "branch") {
                $refType = "branch"
            }
            
            $diff = [StateDiff]::new(
                "update",
                $refType,
                $issue.Version,
                $issue.CurrentSha,
                $issue.ExpectedSha,
                $issue.Message
            )
            $diffs += $diff
        }
        elseif ($issue.Type -eq "draft_release") {
            # Publish draft release (update action)
            $diff = [StateDiff]::new(
                "update",
                "release",
                $issue.Version,
                "",
                "",
                "Publish draft release"
            )
            $diffs += $diff
        }
        elseif ($issue.Type -eq "mutable_floating_release" -or $issue.Type -eq "floating_version_release") {
            # Delete release on floating version
            $diff = [StateDiff]::new(
                "delete",
                "release",
                $issue.Version,
                "",
                "",
                "Remove release from floating version"
            )
            $diffs += $diff
        }
        elseif ($issue.Type -eq "non_immutable_release") {
            # Republish release for immutability (update action)
            $diff = [StateDiff]::new(
                "update",
                "release",
                $issue.Version,
                "",
                "",
                "Republish release for immutability"
            )
            $diffs += $diff
        }
        elseif ($issue.Type -match "delete" -or $issue.Type -match "remove") {
            # Delete action
            $refType = "release"
            if ($issue.Type -match "tag") {
                $refType = "tag"
            }
            elseif ($issue.Type -match "branch") {
                $refType = "branch"
            }
            
            $diff = [StateDiff]::new(
                "delete",
                $refType,
                $issue.Version,
                $issue.CurrentSha,
                "",
                $issue.Message
            )
            $diffs += $diff
        }
    }
    
    return $diffs
}

function Write-StateDiff {
    <#
    .SYNOPSIS
    Display a visual diff of planned changes.
    
    .PARAMETER Diffs
    Array of StateDiff objects to display.
    #>
    param(
        [Parameter(Mandatory)]
        [StateDiff[]]$Diffs
    )
    
    if ($Diffs.Count -eq 0) {
        return
    }
    
    Write-Host "##[group]Planned Changes (Auto-fix Preview)"
    Write-Host ""
    Write-Host ("=" * 77)
    Write-Host " Planned Changes (Auto-fix Preview)"
    Write-Host ("=" * 77)
    Write-Host ""
    
    # Group by action
    $creates = $Diffs | Where-Object { $_.Action -eq "create" }
    $updates = $Diffs | Where-Object { $_.Action -eq "update" }
    $deletes = $Diffs | Where-Object { $_.Action -eq "delete" }
    
    # Show creates (green)
    if ($creates.Count -gt 0) {
        Write-Host "CREATE ($($creates.Count)):" -ForegroundColor Green
        foreach ($diff in $creates) {
            Write-Host "  + $($diff.ToString())" -ForegroundColor Green
        }
        Write-Host ""
    }
    
    # Show updates (yellow)
    if ($updates.Count -gt 0) {
        Write-Host "UPDATE ($($updates.Count)):" -ForegroundColor Yellow
        foreach ($diff in $updates) {
            Write-Host "  ~ $($diff.ToString())" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    # Show deletes (red)
    if ($deletes.Count -gt 0) {
        Write-Host "DELETE ($($deletes.Count)):" -ForegroundColor Red
        foreach ($diff in $deletes) {
            Write-Host "  - $($diff.ToString())" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    # Summary
    Write-Host ("=" * 77)
    Write-Host "Total changes: $($Diffs.Count) " -NoNewline
    if ($creates.Count -gt 0) { Write-Host "(+$($creates.Count) create) " -NoNewline -ForegroundColor Green }
    if ($updates.Count -gt 0) { Write-Host "(~$($updates.Count) update) " -NoNewline -ForegroundColor Yellow }
    if ($deletes.Count -gt 0) { Write-Host "(-$($deletes.Count) delete) " -NoNewline -ForegroundColor Red }
    Write-Host ""
    Write-Host ("=" * 77)
    Write-Host ""
    Write-Host "##[endgroup]"
}
