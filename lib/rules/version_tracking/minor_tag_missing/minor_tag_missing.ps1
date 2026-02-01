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
        
        # Filter out prereleases if ignore-preview-releases is enabled
        $allRefs = $State.Tags + $State.Branches
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $patchVersions = $allRefs | Where-Object { 
            $_.IsPatch -and 
            -not $_.IsIgnored -and
            (-not $ignorePreviewReleases -or -not (Test-IsPrerelease -State $State -VersionRef $_))
        }
        
        $missingMinors = @()
        
        # Case 1: Get all unique major.minor numbers from existing patch versions
        if ($patchVersions.Count -gt 0) {
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
            foreach ($minorVersion in $minorNumbers) {
                $minorTag = $State.Tags | Where-Object { 
                    $_.Version -eq "v$($minorVersion.Major).$($minorVersion.Minor)" 
                }
                if ($null -eq $minorTag) {
                    $missingMinors += $minorVersion
                }
            }
        }
        
        # Case 2: Major version tags without any patches need v{major}.0 minor tag
        # This handles the case where v1 exists but no v1.x.x patches exist yet
        $majorTags = $State.Tags | Where-Object { $_.IsMajor -and -not $_.IsIgnored }
        foreach ($majorTag in $majorTags) {
            $major = $majorTag.Major
            
            # Check if any patches exist for this major version
            $hasPatches = $patchVersions | Where-Object { $_.Major -eq $major }
            if ($hasPatches) {
                continue  # Case 1 handles this
            }
            
            # Check if v{major}.0 minor tag already exists
            $minorTag = $State.Tags | Where-Object { 
                $_.Version -eq "v$major.0" 
            }
            if ($null -eq $minorTag) {
                # Add v{major}.0 as missing - use major tag's SHA as source
                $missingMinors += [PSCustomObject]@{
                    Major = $major
                    Minor = 0
                    SourceSha = $majorTag.Sha  # Store SHA from major tag for CreateIssue
                }
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
        
        # Get the SHA - either from highest patch or from the SourceSha (major tag)
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $highestPatch = Get-HighestPatchForMinor -State $State -Major $Item.Major -Minor $Item.Minor -ExcludePrereleases $ignorePreviewReleases
        
        $targetSha = $null
        $targetVersion = $null
        
        if ($highestPatch) {
            $targetSha = $highestPatch.Sha
            $targetVersion = $highestPatch.Version
        } elseif ($Item.SourceSha) {
            # No patches exist - use the SHA from the major tag
            $targetSha = $Item.SourceSha
            $targetVersion = "v$($Item.Major)"
        } else {
            # Fallback: look up major tag SHA
            $majorTag = $State.Tags | Where-Object { $_.Version -eq "v$($Item.Major)" } | Select-Object -First 1
            if ($majorTag) {
                $targetSha = $majorTag.Sha
                $targetVersion = $majorTag.Version
            }
        }
        
        $checkMinorVersion = $Config.'check-minor-version'
        $severity = if ($checkMinorVersion -eq 'warning') { 'warning' } else { 'error' }
        
        $issue = [ValidationIssue]::new(
            "missing_minor_version",
            $severity,
            "Minor version tag $version does not exist. It should point to $targetVersion at $targetSha"
        )
        $issue.Version = $version
        $issue.ExpectedSha = $targetSha
        $issue.RemediationAction = [CreateTagAction]::new($version, $targetSha)
        
        return $issue
    }
}

# Export the rule
$Rule_MinorTagMissing
