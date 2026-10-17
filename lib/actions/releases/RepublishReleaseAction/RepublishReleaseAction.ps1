#############################################################################
# RepublishReleaseAction.ps1 - Republish a release to make it immutable
#############################################################################

class RepublishReleaseAction : ReleaseRemediationAction {
    [Nullable[bool]]$MakeLatest = $null  # Controls whether release should become latest ($true, $false, or $null to let GitHub decide)
    [bool]$TagDeletionFailed = $false  # Set when the release was deleted (422) and removing the tag failed
    [bool]$ImmutabilityEnableFailed = $false  # Set when immutability could not be enabled or confirmed; manual steps must then include the enable command
    [object[]]$BlockingRulesets = @()  # Tag rulesets that prevent deleting the tag
    
    RepublishReleaseAction([string]$tagName) : base("Republish release for immutability", $tagName) {
        $this.Priority = 45  # Republish after other release operations
    }
    
    hidden [string] GetImmutableReleasesEndpoint([RepositoryState]$state) {
        if ($state.RepoOwner -and $state.RepoName) {
            return "repos/$($state.RepoOwner)/$($state.RepoName)/immutable-releases"
        }
        return 'repos/{owner}/{repo}/immutable-releases'
    }

    hidden [void] MarkImmutabilityManualFix([RepositoryState]$state, [string]$reason) {
        $enableCommand = "gh api -X PUT $($this.GetImmutableReleasesEndpoint($state))"
        $this.ImmutabilityEnableFailed = $true
        $this.MarkAsManualFixRequired($state, "non_immutable_release", "$reason Enable 'Release immutability' for the repository (requires repository admin permissions): $enableCommand")
        Write-Host "::warning::Release $($this.TagName) is not immutable. Enable 'Release immutability' with: $enableCommand"
    }

    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Republish release $($this.TagName) to make it immutable"

        # Releases only become immutable when the setting is on while they are published, so enable it first
        if ((Get-GitHubImmutableReleaseStatus -State $state) -eq $false) {
            Write-Host "'Release immutability' is disabled for the repository; enabling it"
            if (-not (Enable-GitHubImmutableRelease -State $state)) {
                $this.MarkImmutabilityManualFix($state, "Release $($this.TagName) is not immutable because 'Release immutability' is disabled for the repository and it could not be enabled automatically (the request failed or the setting was not confirmed in time).")
                return $false
            }
        }

        $result = Republish-GitHubRelease -State $state -TagName $this.TagName -MakeLatest $this.MakeLatest
        
        if ($result.Success) {
            # Verify the release is actually immutable after republishing
            $isImmutable = Test-ReleaseImmutability -Owner $state.RepoOwner -Repo $state.RepoName -Tag $this.TagName -Token $state.Token -ApiUrl $state.ApiUrl
            
            if ($isImmutable) {
                Write-Host "✓ Success: Republished release for $($this.TagName) and verified immutability"
                return $true
            }
            else {
                $this.MarkImmutabilityManualFix($state, "Release $($this.TagName) was republished but is still mutable.")
                return $false
            }
        }
        else {
            # Check if this is an unfixable error (422 - tag used by immutable release)
            if ($this.IsUnfixableError($result)) {
                # The release was deleted (likely for security reasons); remove the tag so nobody can keep referencing it
                Write-Host "Release $($this.TagName) was previously deleted; deleting tag so it can no longer be referenced"
                if ([DeleteTagAction]::new($this.TagName).Execute($state)) {
                    return $true
                }

                $this.TagDeletionFailed = $true
                $this.BlockingRulesets = @(Get-GitHubTagProtection -State $state -TagName $this.TagName)
                $message = "Release $($this.TagName) cannot be republished because this tag was previously used by an immutable release that was deleted, and the tag could not be deleted automatically."
                if ($this.BlockingRulesets.Count -gt 0) {
                    $names = ($this.BlockingRulesets | ForEach-Object { "'$($_.Name)' ($($_.Url))" }) -join ", "
                    $message += " Tag deletion is blocked by ruleset(s): $names. Bypass or disable them and delete the tag."
                }
                else {
                    $message += " Delete the tag manually; check the tag rulesets and the permissions of the token."
                }
                $this.MarkAsManualFixRequired($state, "non_immutable_release", $message)
            }
            else {
                Write-Host "✗ Failed: Republish release for $($this.TagName) - $($result.Reason)"
            }
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        if ($this.TagDeletionFailed) {
            $deleteCommands = @(
                "# The release for $($this.TagName) was deleted, so the tag should be removed to stop people from referencing it."
            )
            foreach ($ruleset in $this.BlockingRulesets) {
                $deleteCommands += "# Tag deletion is blocked by $($ruleset.Source) ruleset '$($ruleset.Name)' ($($ruleset.Enforcement)): add yourself to its bypass list or disable it: $($ruleset.Url)"
            }
            $deleteCommands += "git push origin :refs/tags/$($this.TagName)"
            return $deleteCommands
        }
        
        $commands = @()
        
        # Check if the repository has immutable releases enabled
        # This is true if either:
        # 1. Any existing release is already immutable (from initial state)
        # 2. Any non_immutable_release issue was successfully fixed (auto-fix worked, meaning feature is enabled)
        $hasImmutableReleases = ($state.Releases | Where-Object { $_.IsImmutable }) | Select-Object -First 1
        $anyImmutabilityFixSucceeded = ($state.Issues | Where-Object {
            $_.Type -eq "non_immutable_release" -and $_.Status -eq "fixed"
        }) | Select-Object -First 1
        
        # If no immutable releases exist AND no auto-fix succeeded, add the command to enable the feature
        if ($this.ImmutabilityEnableFailed -or (-not $hasImmutableReleases -and -not $anyImmutabilityFixSucceeded)) {
            $commands += "# Enable 'Release immutability' for the repository (requires repository admin permissions):"
            $commands += "gh api -X PUT $($this.GetImmutableReleasesEndpoint($state))"
        }

        $repoArg = ""
        if ($state.RepoOwner -and $state.RepoName) {
            $repoArg = " --repo $($state.RepoOwner)/$($state.RepoName)"
        }
        
        $latestArg = ""
        if ($null -ne $this.MakeLatest) {
            $latestArg = if ($this.MakeLatest) { " --latest" } else { " --latest=false" }
        }
        
        $commands += "gh release edit $($this.TagName)$repoArg --draft=true"
        $commands += "gh release edit $($this.TagName)$repoArg --draft=false$latestArg"
        
        return $commands
    }
}
