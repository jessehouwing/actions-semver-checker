#############################################################################
# DeleteTagAction.ps1 - Delete an existing Git tag
#############################################################################

class DeleteTagAction : RemediationAction {
    [string]$TagName
    
    DeleteTagAction([string]$tagName) : base("Delete tag", $tagName) {
        $this.TagName = $tagName
        $this.Priority = 10  # Delete first
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Delete tag $($this.TagName)"
        $success = Remove-GitHubRef -State $state -RefName "refs/tags/$($this.TagName)"
        
        if ($success) {
            Write-Host "✓ Success: Deleted tag $($this.TagName)"
            return $true
        } else {
            Write-Host "✗ Failed: Delete tag $($this.TagName)"
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        return @(
            "git tag -d $($this.TagName)",
            "git push origin :refs/tags/$($this.TagName)"
        )
    }
}
