#############################################################################
# Rule: latest_tag_tracks_global_highest
# Category: latest
# Priority: 30
#############################################################################

$Rule_LatestTagTracksGlobalHighest = [ValidationRule]@{
    Name = "latest_tag_tracks_global_highest"
    Description = "Latest tag must point to the global highest patch version"
    Priority = 30
    Category = "latest"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when using tags for floating versions (default)
        $floatingVersionsUse = $Config.'floating-versions-use'
        if ($floatingVersionsUse -eq 'branches') {
            return @()
        }
        
        # Find "latest" tag
        $latestTag = $State.Tags | Where-Object { 
            $_.Version -eq 'latest' -and -not $_.IsIgnored 
        }
        
        if ($null -eq $latestTag) {
            return @()
        }
        
        return @($latestTag)
    }
    
    Check = { param([VersionRef]$VersionRef, [RepositoryState]$State, [hashtable]$Config)
        # Get the global highest patch
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $allPatches = ($State.Tags + $State.Branches) | Where-Object { $_.IsPatch -and -not $_.IsIgnored }
        
        if ($ignorePreviewReleases) {
            $allPatches = $allPatches | Where-Object { -not (Test-IsPrerelease -State $State -VersionRef $_) }
        }
        
        if ($allPatches.Count -eq 0) {
            # No patches exist, so "latest" is valid (nothing to track)
            return $true
        }
        
        # Find highest patch
        $highest = $allPatches | Sort-Object Major, Minor, Patch -Descending | Select-Object -First 1
        
        # Check if latest points to the same SHA as the highest patch
        return ($VersionRef.Sha -eq $highest.Sha)
    }
    
    CreateIssue = { param([VersionRef]$VersionRef, [RepositoryState]$State, [hashtable]$Config)
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $allPatches = ($State.Tags + $State.Branches) | Where-Object { $_.IsPatch -and -not $_.IsIgnored }
        
        if ($ignorePreviewReleases) {
            $allPatches = $allPatches | Where-Object { -not (Test-IsPrerelease -State $State -VersionRef $_) }
        }
        
        $highest = $allPatches | Sort-Object Major, Minor, Patch -Descending | Select-Object -First 1
        
        $issue = [ValidationIssue]::new(
            "incorrect_latest_tag",
            "error",
            "latest points to $($VersionRef.Sha) but should point to $($highest.Version) at $($highest.Sha)"
        )
        $issue.Version = "latest"
        $issue.CurrentSha = $VersionRef.Sha
        $issue.ExpectedSha = $highest.Sha
        $issue.RemediationAction = [UpdateTagAction]::new("latest", $highest.Sha, $true)
        
        return $issue
    }
}

# Export the rule
$Rule_LatestTagTracksGlobalHighest
