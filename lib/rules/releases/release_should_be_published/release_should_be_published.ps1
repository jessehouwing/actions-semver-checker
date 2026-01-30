#############################################################################
# Rule: release_should_be_published
# Category: releases
# Priority: 11
#############################################################################

$Rule_ReleaseShouldBePublished = [ValidationRule]@{
    Name = "release_should_be_published"
    Description = "Draft releases for patch versions should be published when check-release-immutability is enabled"
    Priority = 11
    Category = "releases"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when check-release-immutability is enabled
        $checkImmutability = $Config.'check-release-immutability'
        if ($checkImmutability -ne 'error' -and $checkImmutability -ne 'warning') {
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
        
        return $patchDraftReleases
    }
    
    Check = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        # If we got here from Condition, it's a draft that should be published
        return $false
    }
    
    CreateIssue = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        $version = $ReleaseInfo.TagName
        $severity = if ($Config.'check-release-immutability' -eq 'warning') { 'warning' } else { 'error' }
        
        $issue = [ValidationIssue]::new(
            "draft_release",
            $severity,
            "Release $version is still in draft status and should be published"
        )
        $issue.Version = $version
        
        # PublishReleaseAction constructor: tagName, releaseId
        $issue.RemediationAction = [PublishReleaseAction]::new($version, $ReleaseInfo.Id)
        
        return $issue
    }
}

# Export the rule
$Rule_ReleaseShouldBePublished
