#############################################################################
# Rule: major_branch_tracks_highest_patch
# Category: version_tracking
# Priority: 20
#############################################################################

$Rule_MajorBranchTracksHighestPatch = [ValidationRule]@{
    Name = "major_branch_tracks_highest_patch"
    Description = "Major version branches must point to the highest patch version"
    Priority = 20
    Category = "version_tracking"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when using branches for floating versions
        $floatingVersionsUse = $Config.'floating-versions-use'
        if ($floatingVersionsUse -ne 'branches') {
            return @()
        }
        
        # Find all major version branches
        $majorBranches = $State.Branches | Where-Object { 
            $_.IsMajor -and -not $_.IsIgnored 
        }
        
        return $majorBranches
    }
    
    Check = { param([VersionRef]$VersionRef, [RepositoryState]$State, [hashtable]$Config)
        # Get the highest patch for this major version
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $highestPatch = Get-HighestPatchForMajor -State $State -Major $VersionRef.Major -ExcludePrereleases $ignorePreviewReleases
        
        # If no patches exist, the major branch is valid (nothing to track)
        if ($null -eq $highestPatch) {
            return $true
        }
        
        # Check if the major branch points to the same SHA as the highest patch
        return ($VersionRef.Sha -eq $highestPatch.Sha)
    }
    
    CreateIssue = { param([VersionRef]$VersionRef, [RepositoryState]$State, [hashtable]$Config)
        $version = $VersionRef.Version
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $highestPatch = Get-HighestPatchForMajor -State $State -Major $VersionRef.Major -ExcludePrereleases $ignorePreviewReleases
        
        $issue = [ValidationIssue]::new(
            "incorrect_version",
            "error",
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
$Rule_MajorBranchTracksHighestPatch
