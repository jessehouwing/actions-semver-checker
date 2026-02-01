#############################################################################
# Rule: duplicate_floating_version_ref
# Category: ref_type
# Priority: 6
#############################################################################

$Rule_DuplicateFloatingVersionRef = [ValidationRule]@{
    Name = "duplicate_floating_version_ref"
    Description = "Floating versions should not exist as both tag and branch simultaneously"
    Priority = 6
    Category = "ref_type"
    
    # Condition: Floating versions (vX, vX.Y) that exist as both tag and branch
    Condition = {
        param([RepositoryState]$State, [hashtable]$Config)
        
        # Find floating versions that exist as both tag and branch
        $duplicates = @()
        
        $floatingTags = $State.Tags | Where-Object {
            -not $_.IsIgnored -and
            ($_.IsMajor -or $_.IsMinor)
        }
        
        foreach ($tag in $floatingTags) {
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
        
        return , $duplicates
    }
    
    # Check: Both tag and branch should not exist
    Check = {
        param([hashtable]$Item, [RepositoryState]$State, [hashtable]$Config)
        # If we're in the condition output, it's a duplicate
        return $false
    }
    
    # CreateIssue: Create issue with delete action based on config
    CreateIssue = {
        param([hashtable]$Item, [RepositoryState]$State, [hashtable]$Config)
        
        $version = $Item.Version
        $floatingVersionsUse = $Config.'floating-versions-use' ?? "tags"
        
        if ($floatingVersionsUse -eq "tags") {
            # Keep tag, delete branch
            $issue = [ValidationIssue]::new(
                "duplicate_ref",
                "error",
                "Version '$version' exists as both tag and branch. Branch will be deleted (floating-versions-use: tags)"
            )
            $issue.Version = $version
            $issue.RemediationAction = [DeleteBranchAction]::new($version)
        }
        else {
            # Keep branch, delete tag
            $issue = [ValidationIssue]::new(
                "duplicate_ref",
                "error",
                "Version '$version' exists as both tag and branch. Tag will be deleted (floating-versions-use: branches)"
            )
            $issue.Version = $version
            $issue.RemediationAction = [DeleteTagAction]::new($version)
        }
        
        return $issue
    }
}

# Export the rule
$Rule_DuplicateFloatingVersionRef
