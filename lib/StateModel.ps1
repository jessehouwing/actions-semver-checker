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
    [scriptblock]$AutoFixAction
    [string[]]$Dependencies  # Other issues that must be fixed first
    
    ValidationIssue([string]$type, [string]$severity, [string]$message) {
        $this.Type = $type
        $this.Severity = $severity
        $this.Message = $message
        $this.IsAutoFixable = $false
        $this.Dependencies = @()
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
    
    # Issue tracking
    [ValidationIssue[]]$Issues
    [int]$FixedIssues
    [int]$FailedFixes
    [int]$UnfixableIssues
    
    RepositoryState() {
        $this.Tags = @()
        $this.Branches = @()
        $this.Releases = @()
        $this.Issues = @()
        $this.FixedIssues = 0
        $this.FailedFixes = 0
        $this.UnfixableIssues = 0
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
        
        $visited[$key] = $true
        
        # Visit dependencies first
        foreach ($dep in $issue.Dependencies) {
            $depIssue = $this.AllIssues | Where-Object { ($_.Type + ":" + $_.Version) -eq $dep } | Select-Object -First 1
            if ($depIssue) {
                $this.Visit($depIssue, $visited, $sorted)
            }
        }
        
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
    
    Write-Host ""
    Write-Host ("=" * 77)
    Write-Host " Current Repository State"
    Write-Host ("=" * 77)
    Write-Host ""
    
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
        Write-Host "Unfixable: $($State.UnfixableIssues)"
        Write-Host ""
    }
    
    Write-Host ("=" * 77)
    Write-Host ""
}
