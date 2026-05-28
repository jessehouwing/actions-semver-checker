#############################################################################
# CreateTagAction.ps1 - Create a new Git tag
#############################################################################

class CreateTagAction : RemediationAction {
    [string]$TagName
    [string]$Sha
    
    CreateTagAction([string]$tagName, [string]$sha) : base("Create tag", $tagName) {
        $this.TagName = $tagName
        $this.Sha = $sha
        $this.Priority = 20  # Create after deletes
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Create tag $($this.TagName)"
        $result = New-GitHubRef -State $state -RefName "refs/tags/$($this.TagName)" -Sha $this.Sha -Force $false
        
        if ($result.Success) {
            Write-Host "✓ Success: Created tag $($this.TagName)"
            return $true
        } else {
            # Check if this requires manual fix due to workflows permission
            if ($result.RequiresManualFix) {
                Write-Host "✗ Manual fix required: Cannot create tag $($this.TagName) - requires 'workflows' permission to modify workflow files"
                # Find this issue in the state and mark it as requiring manual fix
                $issue = $state.Issues | Where-Object { $_.Version -eq $this.TagName -and $_.RemediationAction -eq $this } | Select-Object -First 1
                if ($issue) {
                    $issue.Status = "manual_fix_required"
                    # Update message to be more helpful
                    $issue.Message = "Version $($this.TagName) cannot be created by GitHub Actions because it contains workflow file changes and requires the 'workflows' permission. Please create manually."
                }
            } else {
                Write-Host "✗ Failed: Create tag $($this.TagName)"
            }
            
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        return @("git push origin $($this.Sha):refs/tags/$($this.TagName)")
    }
}
