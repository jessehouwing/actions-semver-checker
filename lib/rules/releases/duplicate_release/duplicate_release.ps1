#############################################################################
# Rule: duplicate_release
# Category: releases
# Priority: 9
#############################################################################

$Rule_DuplicateRelease = [ValidationRule]@{
    Name = "duplicate_release"
    Description = "Delete duplicate draft releases that point to the same tag as another release"
    Priority = 9
    Category = "releases"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when check-releases is enabled
        $checkReleases = $Config.'check-releases'
        if ($checkReleases -ne 'error' -and $checkReleases -ne 'warning') {
            return @()
        }
        
        $duplicatesToDelete = @()
        
        # Group releases by tag name (only patch versions)
        $patchReleases = $State.Releases | Where-Object {
            -not $_.IsIgnored -and $_.TagName -match '^v\d+\.\d+\.\d+$'
        }
        
        $releasesByTag = $patchReleases | Group-Object -Property TagName
        
        foreach ($group in $releasesByTag) {
            if ($group.Count -gt 1) {
                # Multiple releases for the same tag - find duplicates to delete
                $releases = $group.Group
                
                # Sort releases to determine which one to keep:
                # 1. Prefer published (non-draft) over draft
                # 2. Prefer immutable over mutable
                # 3. Keep the one with the lowest ID (oldest)
                $sortedReleases = $releases | Sort-Object -Property @(
                    @{ Expression = { -not $_.IsDraft }; Descending = $true }
                    @{ Expression = { $_.IsImmutable }; Descending = $true }
                    @{ Expression = { $_.Id }; Ascending = $true }
                )
                
                # Keep the first one (best candidate), mark others as duplicates
                $keepRelease = $sortedReleases[0]
                $duplicates = $sortedReleases | Select-Object -Skip 1
                
                foreach ($duplicate in $duplicates) {
                    # Only delete draft duplicates - immutable/published releases cannot be deleted
                    if ($duplicate.IsDraft) {
                        $duplicatesToDelete += $duplicate
                    }
                }
            }
        }
        
        return $duplicatesToDelete
    }
    
    Check = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        # If we got here from Condition, the release is a duplicate that should be deleted
        return $false
    }
    
    CreateIssue = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        $version = $ReleaseInfo.TagName
        $severity = if ($Config.'check-releases' -eq 'warning') { 'warning' } else { 'error' }
        
        $issue = [ValidationIssue]::new(
            "duplicate_release",
            $severity,
            "Duplicate draft release found for $version (release ID: $($ReleaseInfo.Id)) - will be deleted"
        )
        $issue.Version = $version
        
        # DeleteReleaseAction constructor: tagName, releaseId
        $issue.RemediationAction = [DeleteReleaseAction]::new($version, $ReleaseInfo.Id)
        
        return $issue
    }
}

# Export the rule
$Rule_DuplicateRelease
