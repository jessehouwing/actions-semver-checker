#############################################################################
# StateModel.ps1 - Domain Model for Repository State
#############################################################################
# This module defines the domain model classes used to track the current
# and desired state of versions, releases, and remediation actions.
#############################################################################

#############################################################################
# Version Reference Class
#############################################################################

class VersionRef {
    [string]$Version      # e.g., "v1.0.0"
    [string]$Ref          # e.g., "refs/tags/v1.0.0"
    [string]$Sha          # commit SHA
    [string]$Type         # "tag" or "branch"
    [bool]$IsPatch
    [bool]$IsMinor
    [bool]$IsMajor
    [bool]$IsPrerelease
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
        
        # Check for prerelease indicators
        $this.IsPrerelease = $this.Version -match '-(alpha|beta|rc|preview|pre)'
    }
    
    [string]ToString() {
        return "$($this.Version) -> $($this.Sha) ($($this.Type))"
    }
}

#############################################################################
# Release Information Class
#############################################################################

class ReleaseInfo {
    [string]$TagName
    [string]$Sha
    [bool]$IsDraft
    [bool]$IsPrerelease
    [bool]$IsImmutable
    [int]$Id
    [string]$HtmlUrl
    
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
        
        # Determine immutability
        $this.IsImmutable = -not $this.IsDraft
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
    [string]$Status       # "pending", "fixed", "failed", "manual_fix_required", "unfixable"
                          # - pending: Not yet attempted
                          # - fixed: Successfully auto-fixed
                          # - failed: Auto-fix attempted but failed
                          # - manual_fix_required: Can be fixed manually (e.g., workflow permission issues)
                          # - unfixable: Cannot be fixed (e.g., immutable release conflicts)
    
    ValidationIssue([string]$type, [string]$severity, [string]$message) {
        $this.Type = $type
        $this.Severity = $severity
        $this.Message = $message
        $this.IsAutoFixable = $false
        $this.Dependencies = @()
        $this.Status = "pending"
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
# Remediation Plan Class
#############################################################################

class RemediationPlan {
    [ValidationIssue[]]$AllIssues
    [hashtable]$DependencyGraph
    
    RemediationPlan([ValidationIssue[]]$issues) {
        $this.AllIssues = $issues
        $this.DependencyGraph = @{}
        $this.BuildDependencyGraph()
    }
    
    hidden [void]BuildDependencyGraph() {
        # Build a graph of issue dependencies
        foreach ($issue in $this.AllIssues) {
            if ($issue.Dependencies.Count -gt 0) {
                $this.DependencyGraph[$issue.Type + ":" + $issue.Version] = $issue.Dependencies
            }
        }
    }
    
    [ValidationIssue[]]GetExecutionOrder() {
        # Topological sort to determine execution order based on dependencies
        $visited = @{}
        $sorted = [System.Collections.ArrayList]::new()
        
        foreach ($issue in $this.AllIssues) {
            $this.Visit($issue, $visited, $sorted)
        }
        
        return $sorted.ToArray()
    }
    
    hidden [void]Visit([ValidationIssue]$issue, [hashtable]$visited, [System.Collections.ArrayList]$sorted) {
        $key = $issue.Type + ":" + $issue.Version
        
        if ($visited.ContainsKey($key)) {
            return
        }
        
        # Mark as visiting to detect cycles
        $visited[$key] = "visiting"
        
        # Visit dependencies first
        foreach ($dep in $issue.Dependencies) {
            $depIssue = $this.AllIssues | Where-Object { ($_.Type + ":" + $_.Version) -eq $dep } | Select-Object -First 1
            if ($depIssue) {
                $depKey = $depIssue.Type + ":" + $depIssue.Version
                # Check for circular dependency
                if ($visited.ContainsKey($depKey) -and $visited[$depKey] -eq "visiting") {
                    Write-Warning "Circular dependency detected: $key -> $depKey"
                    continue
                }
                $this.Visit($depIssue, $visited, $sorted)
            }
        }
        
        # Mark as fully visited
        $visited[$key] = "visited"
        [void]$sorted.Add($issue)
    }
}

#############################################################################
# State Summary Functions
#############################################################################

function Write-RepositoryStateSummary {
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State
    )
    
    Write-Host "##[group]Current Repository State"
    
    # Tags
    Write-Host "Tags: $($State.Tags.Count)"
    if ($State.Tags.Count -gt 0) {
        $tagsToShow = $State.Tags | Select-Object -First 20
        foreach ($tag in $tagsToShow) {
            $typeLabel = if ($tag.IsMajor) { "major" } elseif ($tag.IsMinor) { "minor" } else { "patch" }
            $sha = if ($tag.Sha) { $tag.Sha.Substring(0, [Math]::Min(7, $tag.Sha.Length)) } else { "null" }
            Write-Host "  $($tag.Version) -> $sha ($typeLabel)"
        }
        if ($State.Tags.Count -gt 20) {
            Write-Host "  ... and $($State.Tags.Count - 20) more"
        }
    }
    Write-Host ""
    
    # Branches
    Write-Host "Branches: $($State.Branches.Count)"
    if ($State.Branches.Count -gt 0) {
        $branchesToShow = $State.Branches | Select-Object -First 15
        foreach ($branch in $branchesToShow) {
            $typeLabel = if ($branch.IsMajor) { "major" } elseif ($branch.IsMinor) { "minor" } else { "patch" }
            $sha = if ($branch.Sha) { $branch.Sha.Substring(0, [Math]::Min(7, $branch.Sha.Length)) } else { "null" }
            Write-Host "  $($branch.Version) -> $sha ($typeLabel)"
        }
        if ($State.Branches.Count -gt 15) {
            Write-Host "  ... and $($State.Branches.Count - 15) more"
        }
    }
    Write-Host ""
    
    # Releases
    Write-Host "Releases: $($State.Releases.Count)"
    if ($State.Releases.Count -gt 0) {
        $releasesToShow = $State.Releases | Select-Object -First 15
        foreach ($release in $releasesToShow) {
            $status = @()
            if ($release.IsDraft) { $status += "draft" }
            if ($release.IsPrerelease) { $status += "prerelease" }
            $statusStr = if ($status.Count -gt 0) { " [$($status -join ', ')]" } else { "" }
            Write-Host "  $($release.TagName)$statusStr"
        }
        if ($State.Releases.Count -gt 15) {
            Write-Host "  ... and $($State.Releases.Count - 15) more"
        }
    }
    Write-Host ""
    
    Write-Host ("=" * 77)
    Write-Host ""
    Write-Host "##[endgroup]"
}

function Write-ValidationSummary {
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State
    )
    
    Write-Host ""
    Write-Host ("=" * 77)
    Write-Host " Validation Summary"
    Write-Host ("=" * 77)
    Write-Host ""
    
    $errors = $State.GetErrorIssues()
    $warnings = $State.GetWarningIssues()
    
    Write-Host "Issues found: $($State.Issues.Count)"
    Write-Host "  Errors: $($errors.Count)"
    Write-Host "  Warnings: $($warnings.Count)"
    Write-Host ""
    
    if ($State.AutoFix) {
        $autoFixable = $State.GetAutoFixableIssues()
        $manualFix = $State.GetManualFixIssues()
        
        Write-Host "Auto-fixable: $($autoFixable.Count)"
        Write-Host "Manual fix required: $($manualFix.Count)"
        Write-Host "Unfixable: $($State.GetUnfixableIssuesCount())"
        Write-Host ""
    }
    
    Write-Host ("=" * 77)
    Write-Host ""
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
