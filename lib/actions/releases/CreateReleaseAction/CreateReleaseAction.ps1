#############################################################################
# CreateReleaseAction.ps1 - Create a new GitHub Release
#############################################################################

class CreateReleaseAction : ReleaseRemediationAction {
    [bool]$AutoPublish = $false  # If true, create directly as published (non-draft)
    [Nullable[bool]]$MakeLatest = $null  # Controls whether release should become latest ($true, $false, or $null to let GitHub decide)
    
    CreateReleaseAction([string]$tagName, [bool]$isDraft) : base("Create release", $tagName) {
        # If isDraft is false, it means we want to publish, so set AutoPublish to true
        $this.AutoPublish = -not $isDraft
        $this.Priority = 30  # Create after tags
    }
    
    CreateReleaseAction([string]$tagName, [bool]$isDraft, [bool]$autoPublish) : base("Create release", $tagName) {
        $this.AutoPublish = $autoPublish
        $this.Priority = 30  # Create after tags
    }
    
    [bool] Execute([RepositoryState]$state) {
        # If AutoPublish is enabled, create directly as published (non-draft)
        # This avoids the issue where a tag locked by a deleted immutable release
        # can't have a draft release published later
        $isDraft = -not $this.AutoPublish
        $actionDesc = if ($this.AutoPublish) { "Create and publish release" } else { "Create draft release" }
        
        Write-Host "Auto-fix: $actionDesc for $($this.TagName)"
        $result = New-GitHubRelease -State $state -TagName $this.TagName -Draft $isDraft -MakeLatest $this.MakeLatest
        
        if ($result.Success) {
            Write-Host "✓ Success: $actionDesc for $($this.TagName)"
            return $true
        } else {
            # Check if this is an unfixable error and mark it accordingly
            if ($this.IsUnfixableError($result)) {
                $this.MarkAsUnfixable($state, "missing_release", "Release $($this.TagName) cannot be created because this tag was previously used by an immutable release that was deleted. Consider adding this version to the ignore-versions list.")
            } else {
                Write-Host "✗ Failed: $actionDesc for $($this.TagName)"
            }
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        # Check if the issue is unfixable - if so, return empty array
        if ($this.IsIssueUnfixable($state, "missing_release")) {
            return @()
        }
        
        $latestArg = ""
        if ($null -ne $this.MakeLatest) {
            $latestArg = if ($this.MakeLatest) { " --latest" } else { " --latest=false" }
        }
        
        if ($this.AutoPublish) {
            # Create and immediately publish
            return @(
                "gh release create $($this.TagName) --title `"$($this.TagName)`" --notes `"Release $($this.TagName)`"$latestArg"
            )
        } else {
            # Create as draft
            return @(
                "gh release create $($this.TagName) --draft --title `"$($this.TagName)`" --notes `"Release $($this.TagName)`"$latestArg"
            )
        }
    }
}
