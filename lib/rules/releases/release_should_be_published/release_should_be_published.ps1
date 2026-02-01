#############################################################################
# Rule: release_should_be_published
# Category: releases
# Priority: 11
#############################################################################

# Load shared release helpers
. "$PSScriptRoot/../ReleaseRulesHelper.ps1"

$Rule_ReleaseShouldBePublished = [ValidationRule]@{
    Name = "release_should_be_published"
    Description = "Draft releases for patch versions should be published when check-releases or check-release-immutability is enabled"
    Priority = 11
    Category = "releases"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Apply when either check-releases OR check-release-immutability is enabled
        # When check-releases is enabled, draft releases should be published to complete the release
        # When check-release-immutability is enabled, draft releases should be published to become immutable
        $checkReleases = $Config.'check-releases'
        $checkImmutability = $Config.'check-release-immutability'
        
        $releasesEnabled = ($checkReleases -eq 'error' -or $checkReleases -eq 'warning')
        $immutabilityEnabled = ($checkImmutability -eq 'error' -or $checkImmutability -eq 'warning')
        
        if (-not $releasesEnabled -and -not $immutabilityEnabled) {
            return @()
        }
        
        # Find all draft releases for patch versions
        $draftReleases = $State.Releases | Where-Object {
            $_.IsDraft -and -not $_.IsIgnored
        }
        
        # Filter to only patch versions
        $patchDraftReleases = $draftReleases | Where-Object {
            # Parse version to check if it's a patch (vX.Y.Z)
            $tagName = $_.TagName
            if ($tagName -match '^v(\d+)\.(\d+)\.(\d+)') {
                return $true
            }
            return $false
        }
        
        # Exclude draft releases that are duplicates and will be deleted by duplicate_release rule
        $duplicateDrafts = Get-DuplicateDraftRelease -State $State
        $duplicateReleaseIds = $duplicateDrafts.Id
        
        # Filter out duplicates that will be deleted
        $patchDraftReleases = $patchDraftReleases | Where-Object {
            $_.Id -notin $duplicateReleaseIds
        }
        
        return $patchDraftReleases
    }
    
    Check = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        # If we got here from Condition, it's a draft that should be published
        return $false
    }
    
    CreateIssue = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        $version = $ReleaseInfo.TagName
        
        # Determine severity based on which check is enabled (prioritize immutability check level)
        $checkReleases = $Config.'check-releases'
        $checkImmutability = $Config.'check-release-immutability'
        
        $severity = 'error'
        if ($checkImmutability -eq 'warning' -or $checkReleases -eq 'warning') {
            $severity = 'warning'
        }
        
        $issue = [ValidationIssue]::new(
            "draft_release",
            $severity,
            "Release $version is still in draft status and should be published"
        )
        $issue.Version = $version
        
        # PublishReleaseAction constructor: tagName, releaseId
        $action = [PublishReleaseAction]::new($version, $ReleaseInfo.Id)
        
        # Determine if this release should become "latest" when published
        # Only set MakeLatest=false explicitly if it should NOT be latest
        # to prevent overwriting a correct latest release
        $shouldBeLatest = Test-ShouldBeLatestRelease -State $State -Version $version -ReleaseInfo $ReleaseInfo
        if (-not $shouldBeLatest) {
            $action.MakeLatest = $false
        }
        
        $issue.RemediationAction = $action
        
        return $issue
    }
}

# Export the rule
$Rule_ReleaseShouldBePublished
