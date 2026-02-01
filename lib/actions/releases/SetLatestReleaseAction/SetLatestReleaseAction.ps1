#############################################################################
# SetLatestReleaseAction.ps1 - Set a release as the "latest" release
#############################################################################
# This action updates a release to be marked as the "latest" release in GitHub.
# Used when the wrong release is currently marked as latest.
#############################################################################

class SetLatestReleaseAction : ReleaseRemediationAction {
    [int]$ReleaseId
    
    SetLatestReleaseAction([string]$tagName) : base("Set release as latest", $tagName) {
        $this.ReleaseId = 0  # Will be looked up if needed
        $this.Priority = 50  # Run after other release operations
    }
    
    SetLatestReleaseAction([string]$tagName, [int]$releaseId) : base("Set release as latest", $tagName) {
        $this.ReleaseId = $releaseId
        $this.Priority = 50  # Run after other release operations
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Set release $($this.TagName) as latest"
        
        # If ReleaseId is not provided, look it up from state
        $targetReleaseId = $this.ReleaseId
        if (-not $targetReleaseId -or $targetReleaseId -eq 0) {
            $release = $state.Releases | Where-Object { $_.TagName -eq $this.TagName } | Select-Object -First 1
            if ($release) {
                $targetReleaseId = $release.Id
            }
        }
        
        if (-not $targetReleaseId -or $targetReleaseId -eq 0) {
            Write-Host "✗ Failed: Could not find release ID for $($this.TagName)"
            return $false
        }
        
        $result = Set-GitHubReleaseLatest -State $state -TagName $this.TagName -ReleaseId $targetReleaseId
        
        if ($result.Success) {
            Write-Host "✓ Success: Set release $($this.TagName) as latest"
            return $true
        } else {
            if ($this.IsUnfixableError($result)) {
                $this.MarkAsUnfixable($state, "wrong_latest_release", "Cannot set $($this.TagName) as latest release")
            } else {
                Write-Host "✗ Failed: Set release $($this.TagName) as latest"
            }
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        # Check if the issue is unfixable - if so, return empty array
        if ($this.IsIssueUnfixable($state, "wrong_latest_release")) {
            return @()
        }
        
        $repoArg = ""
        if ($state.RepoOwner -and $state.RepoName) {
            $repoArg = " --repo $($state.RepoOwner)/$($state.RepoName)"
        }
        return @("gh release edit $($this.TagName)$repoArg --latest")
    }
}
