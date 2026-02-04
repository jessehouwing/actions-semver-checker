#############################################################################
# RepublishReleaseAction.ps1 - Republish a release to make it immutable
#############################################################################

class RepublishReleaseAction : ReleaseRemediationAction {
    [Nullable[bool]]$MakeLatest = $null  # Controls whether release should become latest ($true, $false, or $null to let GitHub decide)
    
    RepublishReleaseAction([string]$tagName) : base("Republish release for immutability", $tagName) {
        $this.Priority = 45  # Republish after other release operations
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Republish release $($this.TagName) to make it immutable"
        $result = Republish-GitHubRelease -State $state -TagName $this.TagName -MakeLatest $this.MakeLatest
        
        if ($result.Success) {
            # Verify the release is actually immutable after republishing
            $isImmutable = Test-ReleaseImmutability -Owner $state.RepoOwner -Repo $state.RepoName -Tag $this.TagName -Token $state.Token -ApiUrl $state.ApiUrl
            
            if ($isImmutable) {
                Write-Host "✓ Success: Republished release for $($this.TagName) and verified immutability"
                return $true
            } else {
                # Release was republished but is still mutable - repository settings not configured
                $settingsUrl = "$($state.ServerUrl)/$($state.RepoOwner)/$($state.RepoName)/settings#releases-settings"
                $this.MarkAsManualFixRequired($state, "non_immutable_release", "Release $($this.TagName) was republished but is still mutable. Enable 'Release immutability' in repository settings: $settingsUrl")
                Write-Host "::warning::Release $($this.TagName) is still mutable after republishing. Enable 'Release immutability' at: $settingsUrl"
                return $false
            }
        } else {
            # Check if this is an unfixable error (422 - tag used by immutable release)
            if ($this.IsUnfixableError($result)) {
                $this.MarkAsUnfixable($state, "non_immutable_release", "Release $($this.TagName) cannot be republished because this tag was previously used by an immutable release that was deleted. Consider adding this version to the ignore-versions list.")
            } else {
                Write-Host "✗ Failed: Republish release for $($this.TagName) - $($result.Reason)"
            }
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        # Check if the issue is unfixable - if so, return empty array
        if ($this.IsIssueUnfixable($state, "non_immutable_release")) {
            return @()
        }
        
        # Check if manual fix is required specifically because the repository settings need configuration
        # This happens when Execute() was run, republish succeeded, but release is still mutable
        # We detect this by checking if the message indicates the release was republished but still mutable
        # However, if ANY releases in the repo are already immutable, the feature is enabled and we don't need the comment
        if ($this.IsIssueManualFixRequired($state, "non_immutable_release")) {
            $issue = $state.Issues | Where-Object { $_.Version -eq $this.TagName -and $_.Type -eq "non_immutable_release" } | Select-Object -First 1
            $hasImmutableReleases = ($state.Releases | Where-Object { $_.IsImmutable }) | Select-Object -First 1
            if ($issue -and $issue.Message -match "republished but is still mutable" -and -not $hasImmutableReleases) {
                $settingsUrl = "$($state.ServerUrl)/$($state.RepoOwner)/$($state.RepoName)/settings#releases-settings"
                return @("# Enable 'Release immutability' in repository settings: $settingsUrl")
            }
        }

        $repoArg = ""
        if ($state.RepoOwner -and $state.RepoName) {
            $repoArg = " --repo $($state.RepoOwner)/$($state.RepoName)"
        }
        
        $latestArg = ""
        if ($null -ne $this.MakeLatest) {
            $latestArg = if ($this.MakeLatest) { " --latest" } else { " --latest=false" }
        }
        return @(
            "gh release edit $($this.TagName)$repoArg --draft=true",
            "gh release edit $($this.TagName)$repoArg --draft=false$latestArg"
        )
    }
}
