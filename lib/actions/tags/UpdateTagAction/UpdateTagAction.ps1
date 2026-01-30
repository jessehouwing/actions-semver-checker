#############################################################################
# UpdateTagAction.ps1 - Update an existing Git tag
#############################################################################

class UpdateTagAction : RemediationAction {
    [string]$TagName
    [string]$Sha
    [bool]$Force
    
    UpdateTagAction([string]$tagName, [string]$sha, [bool]$force) : base("Update tag", $tagName) {
        $this.TagName = $tagName
        $this.Sha = $sha
        $this.Force = $force
        $this.Priority = 20  # Same as create
    }
    
    [bool] Execute([RepositoryState]$state) {
        $forceStr = if ($this.Force) { " (force)" } else { "" }
        Write-Host "Auto-fix: Update tag $($this.TagName)$forceStr"
        $result = New-GitHubRef -State $state -RefName "refs/tags/$($this.TagName)" -Sha $this.Sha -Force $this.Force
        
        if ($result.Success) {
            Write-Host "✓ Success: Updated tag $($this.TagName)"
            return $true
        } else {
            # Check if this requires manual fix due to workflows permission
            if ($result.RequiresManualFix) {
                Write-Host "✗ Manual fix required: Cannot update tag $($this.TagName) - requires 'workflows' permission to modify workflow files"
                $issue = $state.Issues | Where-Object { $_.Version -eq $this.TagName -and $_.RemediationAction -eq $this } | Select-Object -First 1
                if ($issue) {
                    $issue.Status = "manual_fix_required"
                    # Update message to be more helpful
                    $issue.Message = "Version $($this.TagName) cannot be updated by GitHub Actions because it contains workflow file changes and requires the 'workflows' permission. Please update manually."
                }
            } else {
                Write-Host "✗ Failed: Update tag $($this.TagName)"
            }
            
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        $forceFlag = if ($this.Force) { " --force" } else { "" }
        return @("git push origin $($this.Sha):refs/tags/$($this.TagName)$forceFlag")
    }
}
