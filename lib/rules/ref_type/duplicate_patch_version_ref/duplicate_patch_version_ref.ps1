#############################################################################
# Rule: duplicate_patch_version_ref
# Category: ref_type
# Priority: 6
#############################################################################

$Rule_DuplicatePatchVersionRef = [ValidationRule]@{
    Name = "duplicate_patch_version_ref"
    Description = "Patch versions must be tags only - branches with same version should be deleted"
    Priority = 6
    Category = "ref_type"
    
    # Condition: Patch versions (vX.Y.Z) that exist as both tag and branch
    Condition = {
        param([RepositoryState]$State, [hashtable]$Config)
        
        # Find patch versions that exist as both tag and branch
        $duplicates = @()
        
        $patchTags = $State.Tags | Where-Object {
            -not $_.IsIgnored -and
            $_.IsPatch
        }
        
        foreach ($tag in $patchTags) {
            $matchingBranch = $State.Branches | Where-Object {
                $_.Version -eq $tag.Version -and
                -not $_.IsIgnored
            }
            
            if ($matchingBranch) {
                # Return a hashtable with both refs
                $duplicates += @{
                    Version = $tag.Version
                    Tag = $tag
                    Branch = $matchingBranch
                }
            }
        }
        
        return ,$duplicates
    }
    
    # Check: Both tag and branch should not exist for patches
    Check = {
        param([hashtable]$Item, [RepositoryState]$State, [hashtable]$Config)
        # If we're in the condition output, it's a duplicate
        return $false
    }
    
    # CreateIssue: Create issue with DeleteBranchAction (patches must always be tags)
    CreateIssue = {
        param([hashtable]$Item, [RepositoryState]$State, [hashtable]$Config)
        
        $version = $Item.Version
        
        # Patch versions must always be tags (for immutable releases)
        # Always delete the branch, regardless of floating-versions-use setting
        $issue = [ValidationIssue]::new(
            "duplicate_patch_ref",
            "error",
            "Patch version '$version' exists as both tag and branch. Branch will be deleted (patches must be tags for immutable releases)"
        )
        $issue.Version = $version
        $issue.RemediationAction = [DeleteBranchAction]::new($version)
        
        return $issue
    }
}

# Export the rule
$Rule_DuplicatePatchVersionRef
