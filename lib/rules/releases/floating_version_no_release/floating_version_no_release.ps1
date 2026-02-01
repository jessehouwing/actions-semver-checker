#############################################################################
# Rule: floating_version_no_release
# Category: releases
# Priority: 15
#############################################################################

$Rule_FloatingVersionNoRelease = [ValidationRule]@{
    Name = "floating_version_no_release"
    Description = "Floating versions (vX, vX.Y, latest) should not have GitHub Releases"
    Priority = 15
    Category = "releases"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Apply when either check-releases or check-release-immutability is enabled
        $checkReleases = $Config.'check-releases'
        $checkImmutability = $Config.'check-release-immutability'
        
        if ($checkReleases -eq 'none' -and $checkImmutability -eq 'none') {
            return @()
        }
        
        # Find all releases for floating versions
        $floatingReleases = $State.Releases | Where-Object {
            -not $_.IsIgnored
        }
        
        # Filter to only floating versions (vX, vX.Y, or latest)
        $floatingVersionReleases = $floatingReleases | Where-Object {
            $tagName = $_.TagName
            
            # Match major version (v1, v2, etc.)
            if ($tagName -match '^v(\d+)$') {
                return $true
            }
            
            # Match minor version (v1.0, v2.1, etc.)
            if ($tagName -match '^v(\d+)\.(\d+)$') {
                return $true
            }
            
            # Match "latest"
            if ($tagName -eq 'latest') {
                return $true
            }
            
            return $false
        }
        
        return $floatingVersionReleases
    }
    
    Check = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        # Floating versions should never have releases
        return $false
    }
    
    CreateIssue = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        $version = $ReleaseInfo.TagName
        
        # Check if release is immutable (cannot be deleted)
        $isImmutable = $ReleaseInfo.IsImmutable
        
        if ($isImmutable) {
            # Immutable releases cannot be deleted - mark as unfixable
            $issue = [ValidationIssue]::new(
                "immutable_floating_release",
                "error",
                "Floating version $version has an immutable release that cannot be deleted. Consider using ignore-versions."
            )
            $issue.Version = $version
            $issue.Status = "unfixable"
        } else {
            # Mutable (draft) releases can be deleted
            $issue = [ValidationIssue]::new(
                "mutable_floating_release",
                "warning",
                "Floating version $version has a mutable release that should be removed"
            )
            $issue.Version = $version
            
            # DeleteReleaseAction constructor: tagName, releaseId
            $issue.RemediationAction = [DeleteReleaseAction]::new($version, $ReleaseInfo.Id)
        }
        
        return $issue
    }
}

# Export the rule
$Rule_FloatingVersionNoRelease
