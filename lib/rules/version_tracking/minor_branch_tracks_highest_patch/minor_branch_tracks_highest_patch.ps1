#############################################################################
# Rule: minor_branch_tracks_highest_patch
# Category: version_tracking
# Priority: 22
#############################################################################

$Rule_MinorBranchTracksHighestPatch = [ValidationRule]@{
    Name = "minor_branch_tracks_highest_patch"
    Description = "Minor version branches must point to the highest patch version within that minor series"
    Priority = 22
    Category = "version_tracking"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when using branches for floating versions
        $floatingVersionsUse = $Config.'floating-versions-use'
        if ($floatingVersionsUse -ne 'branches') {
            return @()
        }
        
        # Only apply when minor version checking is enabled
        $checkMinorVersion = $Config.'check-minor-version'
        if ($checkMinorVersion -eq 'none') {
            return @()
        }
        
        # Find all minor version branches
        $minorBranches = $State.Branches | Where-Object { 
            $_.IsMinor -and -not $_.IsIgnored 
        }
        
        return $minorBranches
    }
    
    Check = { param([VersionRef]$VersionRef, [RepositoryState]$State, [hashtable]$Config)
        # Get the highest patch for this minor version
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $highestPatch = Get-HighestPatchForMinor -State $State -Major $VersionRef.Major -Minor $VersionRef.Minor -ExcludePrereleases $ignorePreviewReleases
        
        # If no patches exist, the minor branch is valid (nothing to track)
        if ($null -eq $highestPatch) {
            return $true
        }
        
        # Check if the minor branch points to the same SHA as the highest patch
        return ($VersionRef.Sha -eq $highestPatch.Sha)
    }
    
    CreateIssue = { param([VersionRef]$VersionRef, [RepositoryState]$State, [hashtable]$Config)
        $version = $VersionRef.Version
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $highestPatch = Get-HighestPatchForMinor -State $State -Major $VersionRef.Major -Minor $VersionRef.Minor -ExcludePrereleases $ignorePreviewReleases
        
        $checkMinorVersion = $Config.'check-minor-version'
        $severity = if ($checkMinorVersion -eq 'warning') { 'warning' } else { 'error' }
        
        $issue = [ValidationIssue]::new(
            "incorrect_minor_version",
            $severity,
            "$version points to $($VersionRef.Sha) but should point to $($highestPatch.Version) at $($highestPatch.Sha)"
        )
        $issue.Version = $version
        $issue.CurrentSha = $VersionRef.Sha
        $issue.ExpectedSha = $highestPatch.Sha
        
        # UpdateBranchAction constructor: branchName, newSha, force
        $issue.RemediationAction = [UpdateBranchAction]::new($version, $highestPatch.Sha, $true)
        
        return $issue
    }
}

# Export the rule
$Rule_MinorBranchTracksHighestPatch
