#############################################################################
# Rule: minor_tag_missing
# Category: version_tracking
# Priority: 23
#############################################################################

$Rule_MinorTagMissing = [ValidationRule]@{
    Name = "minor_tag_missing"
    Description = "Minor version tags should exist for all major.minor versions that have patches"
    Priority = 23
    Category = "version_tracking"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when using tags for floating versions (default)
        $floatingVersionsUse = $Config.'floating-versions-use'
        if ($floatingVersionsUse -eq 'branches') {
            return @()
        }
        
        # Only apply when minor version checking is enabled
        $checkMinorVersion = $Config.'check-minor-version'
        if ($checkMinorVersion -eq 'none') {
            return @()
        }
        
        # Get all unique major.minor numbers from patch versions
        $allRefs = $State.Tags + $State.Branches
        $patchVersions = $allRefs | Where-Object { $_.IsPatch -and -not $_.IsIgnored }
        
        if ($patchVersions.Count -eq 0) {
            return @()
        }
        
        # Group by major.minor
        $minorNumbers = $patchVersions | ForEach-Object { 
            [PSCustomObject]@{
                Major = $_.Major
                Minor = $_.Minor
            }
        } | Group-Object -Property { "$($_.Major).$($_.Minor)" } | ForEach-Object {
            $parts = $_.Name -split '\.'
            [PSCustomObject]@{
                Major = [int]$parts[0]
                Minor = [int]$parts[1]
            }
        } | Sort-Object { $_.Major }, { $_.Minor }
        
        # Find which minor versions don't have a minor tag
        $missingMinors = @()
        foreach ($minorVersion in $minorNumbers) {
            $minorTag = $State.Tags | Where-Object { 
                $_.Version -eq "v$($minorVersion.Major).$($minorVersion.Minor)" 
            }
            if ($null -eq $minorTag) {
                $missingMinors += $minorVersion
            }
        }
        
        return $missingMinors
    }
    
    Check = { param([PSCustomObject]$Item, [RepositoryState]$State, [hashtable]$Config)
        # If we got here from Condition, the minor tag is missing
        return $false
    }
    
    CreateIssue = { param([PSCustomObject]$Item, [RepositoryState]$State, [hashtable]$Config)
        $version = "v$($Item.Major).$($Item.Minor)"
        
        # Get the highest patch for this minor version to determine the SHA
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $highestPatch = Get-HighestPatchForMinor -State $State -Major $Item.Major -Minor $Item.Minor -ExcludePrereleases $ignorePreviewReleases
        
        $checkMinorVersion = $Config.'check-minor-version'
        $severity = if ($checkMinorVersion -eq 'warning') { 'warning' } else { 'error' }
        
        $issue = [ValidationIssue]::new(
            "missing_minor_version",
            $severity,
            "Minor version tag $version is missing but patch versions exist"
        )
        $issue.Version = $version
        $issue.ExpectedSha = $highestPatch.Sha
        $issue.RemediationAction = [CreateTagAction]::new($version, $highestPatch.Sha)
        
        return $issue
    }
}

# Export the rule
$Rule_MinorTagMissing
