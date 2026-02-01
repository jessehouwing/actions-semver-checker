#############################################################################
# CreateBranchAction.ps1 - Create a new Git branch
#############################################################################

class CreateBranchAction : RemediationAction {
    [string]$BranchName
    [string]$Sha
    
    CreateBranchAction([string]$branchName, [string]$sha) : base("Create branch", $branchName) {
        $this.BranchName = $branchName
        $this.Sha = $sha
        $this.Priority = 20  # Create after deletes
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Create branch $($this.BranchName)"
        $result = New-GitHubRef -State $state -RefName "refs/heads/$($this.BranchName)" -Sha $this.Sha -Force $false
        
        if ($result.Success) {
            Write-Host "✓ Success: Created branch $($this.BranchName)"
            return $true
        } else {
            # Check if this requires manual fix due to workflows permission
            if ($result.RequiresManualFix) {
                Write-Host "✗ Manual fix required: Cannot create branch $($this.BranchName) - requires 'workflows' permission to modify workflow files"
                $issue = $state.Issues | Where-Object { $_.Version -eq $this.BranchName -and $_.RemediationAction -eq $this } | Select-Object -First 1
                if ($issue) {
                    $issue.Status = "manual_fix_required"
                    # Update message to be more helpful
                    $issue.Message = "Version $($this.BranchName) cannot be created by GitHub Actions because it contains workflow file changes and requires the 'workflows' permission. Please create manually."
                }
            } else {
                Write-Host "✗ Failed: Create branch $($this.BranchName)"
            }
            
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        return @("git push origin $($this.Sha):refs/heads/$($this.BranchName)")
    }
}
