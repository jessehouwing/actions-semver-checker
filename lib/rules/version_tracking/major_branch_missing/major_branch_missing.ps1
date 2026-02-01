#############################################################################
# Rule: major_branch_missing
# Category: version_tracking
# Priority: 21
#############################################################################

$Rule_MajorBranchMissing = [ValidationRule]@{
    Name = "major_branch_missing"
    Description = "Major version branches should exist for all major versions that have patches"
    Priority = 21
    Category = "version_tracking"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when using branches for floating versions
        $floatingVersionsUse = $Config.'floating-versions-use'
        if ($floatingVersionsUse -ne 'branches') {
            return @()
        }
        
        # Get all unique major numbers from patch versions
        # Filter out prereleases if ignore-preview-releases is enabled
        $allRefs = $State.Tags + $State.Branches
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $patchVersions = $allRefs | Where-Object { 
            $_.IsPatch -and 
            -not $_.IsIgnored -and
            (-not $ignorePreviewReleases -or -not (Test-IsPrerelease -State $State -VersionRef $_))
        }
        
        if ($patchVersions.Count -eq 0) {
            return @()
        }
        
        $majorNumbers = $patchVersions | ForEach-Object { $_.Major } | Select-Object -Unique | Sort-Object
        
        # Find which major versions don't have a major branch
        $missingMajors = @()
        foreach ($major in $majorNumbers) {
            $majorBranch = $State.Branches | Where-Object { $_.Version -eq "v$major" }
            if ($null -eq $majorBranch) {
                # Create a synthetic object representing the missing major version
                $missingMajors += [PSCustomObject]@{
                    Major = $major
                }
            }
        }
        
        return $missingMajors
    }
    
    Check = { param([PSCustomObject]$Item, [RepositoryState]$State, [hashtable]$Config)
        # If we got here from Condition, the major branch is missing
        return $false
    }
    
    CreateIssue = { param([PSCustomObject]$Item, [RepositoryState]$State, [hashtable]$Config)
        $version = "v$($Item.Major)"
        
        # Get the highest patch for this major version to determine the SHA
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $highestPatch = Get-HighestPatchForMajor -State $State -Major $Item.Major -ExcludePrereleases $ignorePreviewReleases
        
        $issue = [ValidationIssue]::new(
            "missing_major_version",
            "error",
            "Major version branch $version does not exist. It should point to $($highestPatch.Version) at $($highestPatch.Sha)"
        )
        $issue.Version = $version
        $issue.ExpectedSha = $highestPatch.Sha
        $issue.RemediationAction = [CreateBranchAction]::new($version, $highestPatch.Sha)
        
        return $issue
    }
}

# Export the rule
$Rule_MajorBranchMissing
