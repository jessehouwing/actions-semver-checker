#############################################################################
# DeleteReleaseAction.ps1 - Delete a GitHub Release
#############################################################################

class DeleteReleaseAction : ReleaseRemediationAction {
    [int]$ReleaseId
    
    DeleteReleaseAction([string]$tagName, [int]$releaseId) : base("Delete release", $tagName) {
        $this.ReleaseId = $releaseId
        $this.Priority = 10  # Delete first
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Remove release for $($this.TagName)"
        $success = Remove-GitHubRelease -State $state -TagName $this.TagName -ReleaseId $this.ReleaseId
        
        if ($success) {
            Write-Host "✓ Success: Removed release for $($this.TagName)"
            return $true
        } else {
            Write-Host "✗ Failed: Remove release for $($this.TagName)"
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        $repoArg = ""
        if ($state.RepoOwner -and $state.RepoName) {
            $repoArg = " --repo $($state.RepoOwner)/$($state.RepoName)"
        }
        return @("gh release delete $($this.TagName)$repoArg --yes")
    }
}
