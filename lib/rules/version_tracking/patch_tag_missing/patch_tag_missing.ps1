#############################################################################
# Rule: patch_tag_missing
# Category: version_tracking
# Priority: 25
#############################################################################

$Rule_PatchTagMissing = [ValidationRule]@{
    Name = "patch_tag_missing"
    Description = "Patch version tags should exist for all floating versions"
    Priority = 25
    Category = "version_tracking"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when check-releases is 'none' (otherwise release creation handles tags)
        $checkReleases = $Config.'check-releases'
        if ($checkReleases -ne 'none') {
            return @()
        }
        
        # Get floating versions use setting
        $floatingVersionsUse = $Config.'floating-versions-use'
        
        # Collect all floating versions (tags or branches depending on config)
        $floatingVersions = @()
        if ($floatingVersionsUse -eq 'tags') {
            $floatingVersions = $State.Tags | Where-Object { 
                ($_.IsMajor -or $_.IsMinor) -and -not $_.IsIgnored 
            }
        } else {
            $floatingVersions = $State.Branches | Where-Object { 
                ($_.IsMajor -or $_.IsMinor) -and -not $_.IsIgnored 
            }
        }
        
        # Also check if "latest" exists
        $latestVersion = $null
        if ($floatingVersionsUse -eq 'tags') {
            $latestVersion = $State.Tags | Where-Object { $_.Version -eq 'latest' }
        } else {
            $latestVersion = $State.Branches | Where-Object { $_.Version -eq 'latest' }
        }
        if ($latestVersion) {
            $floatingVersions += $latestVersion
        }
        
        # For each floating version, check if a corresponding patch exists
        $missingPatches = @()
        $allRefs = $State.Tags + $State.Branches
        
        foreach ($floating in $floatingVersions) {
            if ($floating.Version -eq 'latest') {
                # For "latest", we just need to ensure at least one patch exists
                $patches = $allRefs | Where-Object { $_.IsPatch -and -not $_.IsIgnored }
                if ($patches.Count -eq 0) {
                    $missingPatches += [PSCustomObject]@{
                        FloatingVersion = $floating
                        ExpectedPatchVersion = 'v1.0.0'  # Suggest starting version
                    }
                }
            } elseif ($floating.IsMajor) {
                # Check if any patch exists for this major version
                $patches = $allRefs | Where-Object { 
                    $_.IsPatch -and $_.Major -eq $floating.Major -and -not $_.IsIgnored 
                }
                if ($patches.Count -eq 0) {
                    $missingPatches += [PSCustomObject]@{
                        FloatingVersion = $floating
                        ExpectedPatchVersion = "v$($floating.Major).0.0"
                    }
                }
            } elseif ($floating.IsMinor) {
                # Check if any patch exists for this minor version
                $patches = $allRefs | Where-Object { 
                    $_.IsPatch -and 
                    $_.Major -eq $floating.Major -and 
                    $_.Minor -eq $floating.Minor -and 
                    -not $_.IsIgnored 
                }
                if ($patches.Count -eq 0) {
                    $missingPatches += [PSCustomObject]@{
                        FloatingVersion = $floating
                        ExpectedPatchVersion = "v$($floating.Major).$($floating.Minor).0"
                    }
                }
            }
        }
        
        return $missingPatches
    }
    
    Check = { param([PSCustomObject]$Item, [RepositoryState]$State, [hashtable]$Config)
        # If we got here from Condition, a patch is missing
        return $false
    }
    
    CreateIssue = { param([PSCustomObject]$Item, [RepositoryState]$State, [hashtable]$Config)
        $floatingVersion = $Item.FloatingVersion.Version
        $expectedPatch = $Item.ExpectedPatchVersion
        
        $issue = [ValidationIssue]::new(
            "missing_patch_version",
            "error",
            "Floating version $floatingVersion exists but no corresponding patch version found. Expected: $expectedPatch"
        )
        $issue.Version = $expectedPatch
        $issue.RemediationAction = [CreateTagAction]::new($expectedPatch, $Item.FloatingVersion.Sha)
        
        return $issue
    }
}

# Export the rule
$Rule_PatchTagMissing
