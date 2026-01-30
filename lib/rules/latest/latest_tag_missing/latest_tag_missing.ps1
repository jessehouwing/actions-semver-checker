#############################################################################
# Rule: latest_tag_missing
# Category: latest
# Priority: 31
#############################################################################

$Rule_LatestTagMissing = [ValidationRule]@{
    Name = "latest_tag_missing"
    Description = "Latest tag should exist when patches are present"
    Priority = 31
    Category = "latest"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when using tags for floating versions (default)
        $floatingVersionsUse = $Config.'floating-versions-use'
        if ($floatingVersionsUse -eq 'branches') {
            return @()
        }
        
        # Check if "latest" tag already exists
        $latestTag = $State.Tags | Where-Object { $_.Version -eq 'latest' }
        if ($null -ne $latestTag) {
            return @()
        }
        
        # Check if at least one patch exists
        $allPatches = ($State.Tags + $State.Branches) | Where-Object { $_.IsPatch -and -not $_.IsIgnored }
        
        if ($allPatches.Count -eq 0) {
            return @()
        }
        
        # Return a synthetic object representing the missing "latest" tag
        return @([PSCustomObject]@{ Version = 'latest' })
    }
    
    Check = { param([PSCustomObject]$Item, [RepositoryState]$State, [hashtable]$Config)
        # If we got here from Condition, the latest tag is missing
        return $false
    }
    
    CreateIssue = { param([PSCustomObject]$Item, [RepositoryState]$State, [hashtable]$Config)
        # Get the global highest patch to determine the SHA
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $allPatches = ($State.Tags + $State.Branches) | Where-Object { $_.IsPatch -and -not $_.IsIgnored }
        
        if ($ignorePreviewReleases) {
            $allPatches = $allPatches | Where-Object { -not (Test-IsPrerelease -State $State -VersionRef $_) }
        }
        
        $highest = $allPatches | Sort-Object Major, Minor, Patch -Descending | Select-Object -First 1
        
        $issue = [ValidationIssue]::new(
            "missing_latest_tag",
            "warning",
            "Latest tag is missing but patch versions exist. Consider creating 'latest' tag pointing to $($highest.Version)"
        )
        $issue.Version = "latest"
        $issue.ExpectedSha = $highest.Sha
        $issue.RemediationAction = [CreateTagAction]::new("latest", $highest.Sha)
        
        return $issue
    }
}

# Export the rule
$Rule_LatestTagMissing
