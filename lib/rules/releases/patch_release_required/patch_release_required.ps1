#############################################################################
# Rule: patch_release_required
# Category: releases
# Priority: 10
#############################################################################

$Rule_PatchReleaseRequired = [ValidationRule]@{
    Name = "patch_release_required"
    Description = "Patch versions must have GitHub Releases when check-releases is enabled"
    Priority = 10
    Category = "releases"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when check-releases is enabled
        $checkReleases = $Config.'check-releases'
        if ($checkReleases -ne 'error' -and $checkReleases -ne 'warning') {
            return @()
        }
        
        $results = @()
        
        # Get all patch versions from both tags and branches
        $allPatches = ($State.Tags + $State.Branches) | Where-Object { $_.IsPatch }
        
        # 1. Find existing patch tags without releases
        $existingPatchesWithoutRelease = $allPatches | Where-Object {
            $version = $_.Version
            
            # Skip ignored versions
            if ($_.IsIgnored) {
                return $false
            }
            
            # Check if release exists
            $release = $State.Releases | Where-Object { $_.TagName -eq $version }
            return $null -eq $release
        }
        
        $results += $existingPatchesWithoutRelease
        
        # 2. Find expected patch versions from floating versions (e.g., v1 exists but v1.0.0 doesn't)
        $floatingVersions = ($State.Tags + $State.Branches) | Where-Object { 
            -not $_.IsPatch -and $_.Version -ne 'latest' 
        }
        
        foreach ($floatingRef in $floatingVersions) {
            $version = $floatingRef.Version
            
            # Skip ignored versions
            if ($floatingRef.IsIgnored) {
                continue
            }
            
            # Determine expected patch version
            $expectedPatchVersion = $null
            if ($floatingRef.IsMajor) {
                # For v1, expect v1.0.0
                $expectedPatchVersion = "v$($floatingRef.Major).0.0"
            } elseif ($floatingRef.IsMinor) {
                # For v1.0, expect v1.0.0
                $expectedPatchVersion = "v$($floatingRef.Major).$($floatingRef.Minor).0"
            }
            
            if ($expectedPatchVersion) {
                # Check if this patch version already exists
                $existingPatch = $allPatches | Where-Object { $_.Version -eq $expectedPatchVersion }
                
                # Check if release exists for this expected version
                $release = $State.Releases | Where-Object { $_.TagName -eq $expectedPatchVersion }
                
                # If patch doesn't exist OR patch exists but release doesn't, create expected entry
                if ($null -eq $existingPatch -or $null -eq $release) {
                    # Check if there's already a draft release that just needs publishing
                    $draftRelease = $State.Releases | Where-Object { 
                        $_.TagName -eq $expectedPatchVersion -and $_.IsDraft 
                    }
                    
                    # Skip if draft exists (publish action will handle it)
                    if ($null -eq $draftRelease) {
                        # Create a synthetic VersionRef for the expected patch
                        # Use a dummy ref path since this version doesn't exist yet
                        $syntheticRef = [VersionRef]::new($expectedPatchVersion, "refs/tags/$expectedPatchVersion", $floatingRef.Sha, "tag")
                        $results += $syntheticRef
                    }
                }
            }
        }
        
        return $results
    }
    
    Check = { param([VersionRef]$VersionRef, [RepositoryState]$State, [hashtable]$Config)
        # If we got here from Condition, the release is missing
        return $false
    }
    
    CreateIssue = { param([VersionRef]$VersionRef, [RepositoryState]$State, [hashtable]$Config)
        $version = $VersionRef.Version
        $severity = if ($Config.'check-releases' -eq 'warning') { 'warning' } else { 'error' }
        
        # Determine if we should auto-publish (make immutable)
        $checkImmutability = $Config.'check-release-immutability'
        $shouldAutoPublish = ($checkImmutability -eq 'error' -or $checkImmutability -eq 'warning')
        
        $issue = [ValidationIssue]::new(
            "missing_release",
            $severity,
            "Release required for patch version $version"
        )
        $issue.Version = $version
        
        # CreateReleaseAction constructor: tagName, isDraft, autoPublish
        # isDraft should be opposite of shouldAutoPublish
        $isDraft = -not $shouldAutoPublish
        $issue.RemediationAction = [CreateReleaseAction]::new($version, $isDraft, $shouldAutoPublish)
        
        return $issue
    }
}

# Export the rule
$Rule_PatchReleaseRequired
