#############################################################################
# Rule: branch_should_be_tag
# Category: ref_type
# Priority: 5
#############################################################################

$Rule_BranchShouldBeTag = [ValidationRule]@{
    Name = "branch_should_be_tag"
    Description = "Floating version and patch version branches should be tags when floating-versions-use is 'tags'"
    Priority = 5
    Category = "ref_type"
    
    # Condition: All branches that are floating versions (vX, vX.Y) or patch versions (vX.Y.Z)
    # when floating-versions-use is 'tags' (default)
    Condition = {
        param([RepositoryState]$State, [hashtable]$Config)
        
        $floatingVersionsUse = $Config.'floating-versions-use' ?? "tags"
        if ($floatingVersionsUse -ne "tags") {
            return @()
        }
        
        return $State.Branches | Where-Object {
            -not $_.IsIgnored -and
            ($_.IsPatch -or $_.IsMajor -or $_.IsMinor)
        }
    }
    
    # Check: Branch should not exist for this version type AND tag should not already exist
    Check = {
        param([VersionRef]$Branch, [RepositoryState]$State, [hashtable]$Config)
        # If a tag already exists for this version, let duplicate rule handle it
        $tagExists = $State.Tags | Where-Object { $_.Version -eq $Branch.Version -and -not $_.IsIgnored }
        if ($tagExists) {
            return $true  # Pass check - let duplicate rule handle this
        }
        # Branch exists but tag doesn't - this is wrong
        return $false
    }
    
    # CreateIssue: Create issue with ConvertBranchToTagAction
    CreateIssue = {
        param([VersionRef]$Branch, [RepositoryState]$State, [hashtable]$Config)
        
        $issue = [ValidationIssue]::new(
            "wrong_ref_type",
            "error",
            "Branch '$($Branch.Version)' should be a tag (floating-versions-use: tags)"
        )
        $issue.Version = $Branch.Version
        $issue.RemediationAction = [ConvertBranchToTagAction]::new($Branch.Version, $Branch.Sha)
        
        return $issue
    }
}

# Export the rule
$Rule_BranchShouldBeTag
