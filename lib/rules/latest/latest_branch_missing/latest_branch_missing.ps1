#############################################################################
# Rule: latest_branch_missing
# Category: latest
# Priority: 31
#############################################################################

$Rule_LatestBranchMissing = [ValidationRule]@{
    Name = "latest_branch_missing"
    Description = "Latest branch should exist when patches are present"
    Priority = 31
    Category = "latest"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when using branches for floating versions
        $floatingVersionsUse = $Config.'floating-versions-use'
        if ($floatingVersionsUse -ne 'branches') {
            return @()
        }
        
        # Check if "latest" branch already exists
        $latestBranch = $State.Branches | Where-Object { $_.Version -eq 'latest' }
        if ($null -ne $latestBranch) {
            return @()
        }
        
        # Check if at least one patch exists
        $allPatches = ($State.Tags + $State.Branches) | Where-Object { $_.IsPatch -and -not $_.IsIgnored }
        
        if ($allPatches.Count -eq 0) {
            return @()
        }
        
        # Return a synthetic object representing the missing "latest" branch
        return @([PSCustomObject]@{ Version = 'latest' })
    }
    
    Check = { param([PSCustomObject]$Item, [RepositoryState]$State, [hashtable]$Config)
        # If we got here from Condition, the latest branch is missing
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
            "missing_latest_branch",
            "warning",
            "Latest branch is missing but patch versions exist. Consider creating 'latest' branch pointing to $($highest.Version)"
        )
        $issue.Version = "latest"
        $issue.ExpectedSha = $highest.Sha
        $issue.RemediationAction = [CreateBranchAction]::new("latest", $highest.Sha)
        
        return $issue
    }
}

# Export the rule
$Rule_LatestBranchMissing
