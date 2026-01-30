#############################################################################
# DeleteBranchAction.ps1 - Delete an existing Git branch
#############################################################################

class DeleteBranchAction : RemediationAction {
    [string]$BranchName
    
    DeleteBranchAction([string]$branchName) : base("Delete branch", $branchName) {
        $this.BranchName = $branchName
        $this.Priority = 10  # Delete first
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Delete branch $($this.BranchName)"
        $success = Remove-GitHubRef -State $state -RefName "refs/heads/$($this.BranchName)"
        
        if ($success) {
            Write-Host "✓ Success: Deleted branch $($this.BranchName)"
            return $true
        } else {
            Write-Host "✗ Failed: Delete branch $($this.BranchName)"
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        return @(
            "git branch -d $($this.BranchName)",
            "git push origin :refs/heads/$($this.BranchName)"
        )
    }
}
