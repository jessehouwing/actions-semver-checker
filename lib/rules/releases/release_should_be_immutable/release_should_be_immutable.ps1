#############################################################################
# Rule: release_should_be_immutable
# Category: releases
# Priority: 12
#############################################################################

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
        
        return $patchPublishedReleases
    }
    
    Check = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        # Check via GraphQL API if the release is truly immutable
        # Note: This requires the Test-ReleaseImmutability function from GitHubApi.ps1
        
        # Check if Test-ReleaseImmutability function is available
        if (Get-Command Test-ReleaseImmutability -ErrorAction SilentlyContinue) {
            $isImmutable = Test-ReleaseImmutability -Owner $State.RepoOwner -Repo $State.RepoName -Tag $ReleaseInfo.TagName -Token $State.Token -ApiUrl $State.ApiUrl
            return $isImmutable
        }
        
        # Fallback: if function not available, assume immutable if published
        return -not $ReleaseInfo.IsDraft
    }
    
    CreateIssue = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        $version = $ReleaseInfo.TagName
        
        # Note: This is always a warning since it requires repository settings to be enabled
        # and cannot be fixed by just republishing if the setting is not enabled
        $issue = [ValidationIssue]::new(
            "non_immutable_release",
            "warning",
            "Release $version is published but not immutable (repository 'Release immutability' setting may not be enabled)"
        )
        $issue.Version = $version
        
        # RepublishReleaseAction constructor: tagName
        $issue.RemediationAction = [RepublishReleaseAction]::new($version)
        
        return $issue
    }
}

# Export the rule
$Rule_ReleaseShouldBeImmutable
