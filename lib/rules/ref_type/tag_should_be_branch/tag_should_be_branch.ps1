#############################################################################
# Rule: tag_should_be_branch
# Category: ref_type
# Priority: 5
#############################################################################

$Rule_TagShouldBeBranch = [ValidationRule]@{
    Name = "tag_should_be_branch"
    Description = "Floating version tags should be branches when floating-versions-use is 'branches'"
    Priority = 5
    Category = "ref_type"
    
    # Condition: All tags that are floating versions (vX, vX.Y) - NOT patch versions
    # when floating-versions-use is 'branches'
    Condition = {
        param([RepositoryState]$State, [hashtable]$Config)
        
        $floatingVersionsUse = $Config.'floating-versions-use' ?? "tags"
        if ($floatingVersionsUse -ne "branches") {
            return @()
        }
        
        # Only floating versions (major/minor), NOT patches
        # Patches must always be tags (for immutable releases)
        return $State.Tags | Where-Object {
            -not $_.IsIgnored -and
            ($_.IsMajor -or $_.IsMinor)
        }
    }
    
    # Check: Tag should not exist for floating versions
    Check = {
        param([VersionRef]$Tag, [RepositoryState]$State, [hashtable]$Config)
        # If the tag exists and we got here, it's wrong
        return $false
    }
    
    # CreateIssue: Create issue with ConvertTagToBranchAction
    CreateIssue = {
        param([VersionRef]$Tag, [RepositoryState]$State, [hashtable]$Config)
        
        $issue = [ValidationIssue]::new(
            "wrong_ref_type",
            "error",
            "Tag '$($Tag.Version)' should be a branch (floating-versions-use: branches)"
        )
        $issue.Version = $Tag.Version
        $issue.RemediationAction = [ConvertTagToBranchAction]::new($Tag.Version, $Tag.Sha)
        
        return $issue
    }
}

# Export the rule
$Rule_TagShouldBeBranch
