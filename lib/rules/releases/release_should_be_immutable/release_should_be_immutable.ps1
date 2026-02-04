#############################################################################
# Rule: release_should_be_immutable
# Category: releases
# Priority: 12
#############################################################################

# Load shared release helpers
. "$PSScriptRoot/../ReleaseRulesHelper.ps1"

$Rule_ReleaseShouldBeImmutable = [ValidationRule]@{
    Name = "release_should_be_immutable"
    Description = "Published releases for patch versions should be immutable (via repository settings)"
    Priority = 12
    Category = "releases"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when check-release-immutability is enabled
        $checkImmutability = $Config.'check-release-immutability'
        if ($checkImmutability -ne 'error' -and $checkImmutability -ne 'warning') {
            return @()
        }
        
        # Find all published (non-draft) releases for patch versions
        $publishedReleases = $State.Releases | Where-Object {
            -not $_.IsDraft -and -not $_.IsIgnored
        }
        
        # Filter to only patch versions
        $patchPublishedReleases = $publishedReleases | Where-Object {
            # Parse version to check if it's a patch (vX.Y.Z)
            $tagName = $_.TagName
            if ($tagName -match '^v(\d+)\.(\d+)\.(\d+)') {
                return $true
            }
            return $false
        }
        
        # Exclude releases that are duplicates and will be deleted by duplicate_release rule
        # (rare case: multiple published releases for same tag)
        $duplicateReleaseIds = @()
        $patchReleases = $State.Releases | Where-Object {
            -not $_.IsIgnored -and $_.TagName -match '^v\d+\.\d+\.\d+$'
        }
        $releasesByTag = $patchReleases | Group-Object -Property TagName
        foreach ($group in $releasesByTag) {
            if ($group.Count -gt 1) {
                $releases = $group.Group
                # Sort to find which release to keep (same logic as duplicate_release rule)
                $sortedReleases = $releases | Sort-Object -Property @(
                    @{ Expression = { -not $_.IsDraft }; Descending = $true }
                    @{ Expression = { $_.IsImmutable }; Descending = $true }
                    @{ Expression = { $_.Id }; Ascending = $true }
                )
                # Mark all but the first as duplicates (only drafts can be deleted, but exclude all duplicates from validation)
                $duplicates = $sortedReleases | Select-Object -Skip 1
                $duplicateReleaseIds += $duplicates.Id
            }
        }
        
        # Filter out duplicates
        $patchPublishedReleases = $patchPublishedReleases | Where-Object {
            $_.Id -notin $duplicateReleaseIds
        }
        
        return $patchPublishedReleases
    }
    
    Check = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        return $ReleaseInfo.IsImmutable
    }
    
    CreateIssue = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        $version = $ReleaseInfo.TagName

        $severity = if ($Config.'check-release-immutability' -eq 'warning') { 'warning' } else { 'error' }
        $issue = [ValidationIssue]::new(
            "non_immutable_release",
            $severity,
            "Release $version is published but not immutable (repository 'Release immutability' setting may not be enabled)"
        )
        $issue.Version = $version
        
        # RepublishReleaseAction constructor: tagName
        $action = [RepublishReleaseAction]::new($version)

        # Determine if this release should become "latest" when republished
        # If the release is currently marked as latest, preserve that
        # If it's the highest non-prerelease version, it should become latest
        $shouldBeLatest = $ReleaseInfo.IsLatest -or (Test-ShouldBeLatestRelease -State $State -Version $version -ReleaseInfo $ReleaseInfo)
        $action.MakeLatest = $shouldBeLatest

        $issue.RemediationAction = $action
        
        return $issue
    }
}

# Export the rule
$Rule_ReleaseShouldBeImmutable
