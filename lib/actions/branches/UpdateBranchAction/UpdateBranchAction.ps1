#############################################################################
# UpdateBranchAction.ps1 - Update an existing Git branch
#############################################################################

class UpdateBranchAction : RemediationAction {
    [string]$BranchName
    [string]$Sha
    [bool]$Force
    
    UpdateBranchAction([string]$branchName, [string]$sha, [bool]$force) : base("Update branch", $branchName) {
        $this.BranchName = $branchName
        $this.Sha = $sha
        $this.Force = $force
        $this.Priority = 20  # Same as create
    }
    
    [bool] Execute([RepositoryState]$state) {
        $forceStr = if ($this.Force) { " (force)" } else { "" }
        Write-Host "Auto-fix: Update branch $($this.BranchName)$forceStr"
        $result = New-GitHubRef -State $state -RefName "refs/heads/$($this.BranchName)" -Sha $this.Sha -Force $this.Force
        
        if ($result.Success) {
            Write-Host "✓ Success: Updated branch $($this.BranchName)"
            return $true
        } else {
            # Check if this requires manual fix due to workflows permission
            if ($result.RequiresManualFix) {
                Write-Host "✗ Manual fix required: Cannot update branch $($this.BranchName) - requires 'workflows' permission to modify workflow files"
                $issue = $state.Issues | Where-Object { $_.Version -eq $this.BranchName -and $_.RemediationAction -eq $this } | Select-Object -First 1
                if ($issue) {
                    $issue.Status = "manual_fix_required"
                    # Update message to be more helpful
                    $issue.Message = "Version $($this.BranchName) cannot be updated by GitHub Actions because it contains workflow file changes and requires the 'workflows' permission. Please update manually."
                }
            } else {
                Write-Host "✗ Failed: Update branch $($this.BranchName)"
            }
            
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        $forceFlag = if ($this.Force) { " --force" } else { "" }
        return @("git push origin $($this.Sha):refs/heads/$($this.BranchName)$forceFlag")
    }
}
