#############################################################################
# PublishReleaseAction.ps1 - Publish a draft GitHub Release
#############################################################################

class PublishReleaseAction : ReleaseRemediationAction {
    [int]$ReleaseId
    
    PublishReleaseAction([string]$tagName) : base("Publish release", $tagName) {
        $this.ReleaseId = 0  # Will be looked up if needed
        $this.Priority = 40  # Publish after creation
    }
    
    PublishReleaseAction([string]$tagName, [int]$releaseId) : base("Publish release", $tagName) {
        $this.ReleaseId = $releaseId
        $this.Priority = 40  # Publish after creation
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Publish draft release for $($this.TagName)"
        $result = Publish-GitHubRelease -State $state -TagName $this.TagName -ReleaseId $this.ReleaseId
        
        if ($result.Success) {
            Write-Host "✓ Success: Published release for $($this.TagName)"
            return $true
        } else {
            # Check if this is an unfixable error (422 - tag used by immutable release)
            if ($this.IsUnfixableError($result)) {
                $this.MarkAsUnfixable($state, "draft_release", "Release $($this.TagName) cannot be published because this tag was previously used by an immutable release that was deleted. Consider adding this version to the ignore-versions list.")
            } else {
                Write-Host "✗ Failed: Publish release for $($this.TagName)"
            }
            
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        # Check if the issue is unfixable - if so, return empty array
        if ($this.IsIssueUnfixable($state, "draft_release")) {
            return @()
        }
        return @("gh release edit $($this.TagName) --draft=false")
    }
}
