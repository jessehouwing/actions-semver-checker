#############################################################################
# Rule: duplicate_latest_ref
# Category: ref_type
# Priority: 6
#############################################################################

$Rule_DuplicateLatestRef = [ValidationRule]@{
    Name = "duplicate_latest_ref"
    Description = "The 'latest' version should not exist as both tag and branch simultaneously"
    Priority = 6
    Category = "ref_type"
    
    # Condition: "latest" exists as both tag and branch
    Condition = {
        param([RepositoryState]$State, [hashtable]$Config)
        
        $latestTag = $State.Tags | Where-Object {
            $_.Version -eq "latest" -and -not $_.IsIgnored
        }
        
        $latestBranch = $State.Branches | Where-Object {
            $_.Version -eq "latest" -and -not $_.IsIgnored
        }
        
        if ($latestTag -and $latestBranch) {
            $item = @{
                Version = "latest"
                Tag = $latestTag
                Branch = $latestBranch
            }
            return @($item)
        }
        
        return @()
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
        
        $floatingVersionsUse = $Config.'floating-versions-use' ?? "tags"
        
        if ($floatingVersionsUse -eq "tags") {
            # Keep tag, delete branch
            $issue = [ValidationIssue]::new(
                "duplicate_latest_ref",
                "error",
                "'latest' exists as both tag and branch. Branch will be deleted (floating-versions-use: tags)"
            )
            $issue.Version = "latest"
            $issue.RemediationAction = [DeleteBranchAction]::new("latest")
        }
        else {
            # Keep branch, delete tag
            $issue = [ValidationIssue]::new(
                "duplicate_latest_ref",
                "error",
                "'latest' exists as both tag and branch. Tag will be deleted (floating-versions-use: branches)"
            )
            $issue.Version = "latest"
            $issue.RemediationAction = [DeleteTagAction]::new("latest")
        }
        
        return $issue
    }
}

# Export the rule
$Rule_DuplicateLatestRef
