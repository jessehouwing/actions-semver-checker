BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/../../base/ReleaseRemediationAction.ps1"
    . "$PSScriptRoot/../../tags/DeleteTagAction/DeleteTagAction.ps1"
    . "$PSScriptRoot/RepublishReleaseAction.ps1"
}

Describe "RepublishReleaseAction" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
        Mock Get-GitHubImmutableReleaseStatus { return $true }
    }
    
    Context "Constructor" {
        It "Should create action with correct priority" {
            $action = [RepublishReleaseAction]::new("v1.0.0")
            
            $action.TagName | Should -Be "v1.0.0"
            $action.Priority | Should -Be 45
            $action.Description | Should -Be "Republish release for immutability"
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate manual commands without latest flag by default" {
            # Add an immutable release so the settings URL is not shown
            $immutableRelease = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 456
                draft = $false
                prerelease = $false
                html_url = "https://github.com/test-owner/test-repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $true
            }
            $script:state.Releases = @([ReleaseInfo]::new($immutableRelease))
            
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 2
            $commands[0] | Should -Match "gh release edit v1.0.0"
            $commands[0] | Should -Match "--repo test-owner/test-repo"
            $commands[0] | Should -Match "--draft=true"
            $commands[1] | Should -Match "gh release edit v1.0.0"
            $commands[1] | Should -Match "--repo test-owner/test-repo"
            $commands[1] | Should -Match "--draft=false"
            $commands[1] | Should -Not -Match "--latest"
        }

        It "Should include --latest when MakeLatest is true" {
            # Add an immutable release so the settings URL is not shown
            $immutableRelease = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 456
                draft = $false
                prerelease = $false
                html_url = "https://github.com/test-owner/test-repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $true
            }
            $script:state.Releases = @([ReleaseInfo]::new($immutableRelease))
            
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $action.MakeLatest = $true
            $commands = $action.GetManualCommands($script:state)

            $commands[1] | Should -Match "gh release edit v1.0.0"
            $commands[1] | Should -Match "--repo test-owner/test-repo"
            $commands[1] | Should -Match "--draft=false --latest"
        }

        It "Should include --latest=false when MakeLatest is false" {
            # Add an immutable release so the settings URL is not shown
            $immutableRelease = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 456
                draft = $false
                prerelease = $false
                html_url = "https://github.com/test-owner/test-repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $true
            }
            $script:state.Releases = @([ReleaseInfo]::new($immutableRelease))
            
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $action.MakeLatest = $false
            $commands = $action.GetManualCommands($script:state)

            $commands[1] | Should -Match "gh release edit v1.0.0"
            $commands[1] | Should -Match "--repo test-owner/test-repo"
            $commands[1] | Should -Match "--draft=false --latest=false"
        }
        
        It "Should return the remote tag delete command and ruleset guidance after tag deletion failed" {
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $action.TagDeletionFailed = $true
            $action.BlockingRulesets = @([PSCustomObject]@{ Name = "Protect tags"; Enforcement = "active"; Source = "repository test-owner/test-repo"; Url = "https://github.com/test-owner/test-repo/rules/1" })
            
            $commands = $action.GetManualCommands($script:state)
            
            ($commands -join "`n") | Should -Match "Protect tags"
            ($commands -join "`n") | Should -Match "bypass list"
            $commands | Should -Contain "git push origin :refs/tags/v1.0.0"
            ($commands -join "`n") | Should -Not -Match "gh release"
        }
        
        It "Should return the enable-immutability command AND remediation commands when no immutable releases exist" {
            # When no immutable releases exist, show both the gh api enable command AND the gh release edit commands
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $issue = [ValidationIssue]::new("non_immutable_release", "error", "Release v1.0.0 was republished but is still mutable. Enable 'Release immutability' for the repository")
            $issue.Version = "v1.0.0"
            $issue.Status = "manual_fix_required"
            $script:state.Issues = @($issue)
            $script:state.Releases = @()  # No immutable releases exist
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 4
            $commands[0] | Should -Match "^# Enable 'Release immutability'"
            $commands[0] | Should -Match "admin"
            $commands[1] | Should -Be "gh api -X PUT repos/test-owner/test-repo/immutable-releases"
            $commands[2] | Should -Match "gh release edit v1.0.0"
            $commands[2] | Should -Match "--draft=true"
            $commands[3] | Should -Match "gh release edit v1.0.0"
            $commands[3] | Should -Match "--draft=false"
        }
        
        It "Should return the enable-immutability command AND remediation commands when auto-fix is false" {
            # Show the enable command AND remediation commands when no immutable releases exist
            # This ensures users see the comment even in non-autofix mode
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $issue = [ValidationIssue]::new("non_immutable_release", "error", "Release v1.0.0 is published but not immutable")
            $issue.Version = "v1.0.0"
            $issue.Status = "pending"  # Not yet processed
            $script:state.Issues = @($issue)
            $script:state.Releases = @()  # No immutable releases exist
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 4
            $commands[0] | Should -Match "^# Enable 'Release immutability'"
            $commands[0] | Should -Match "admin"
            $commands[1] | Should -Be "gh api -X PUT repos/test-owner/test-repo/immutable-releases"
            $commands[2] | Should -Match "gh release edit v1.0.0"
            $commands[2] | Should -Match "--draft=true"
            $commands[3] | Should -Match "gh release edit v1.0.0"
            $commands[3] | Should -Match "--draft=false"
        }
        
        It "Should return gh release edit commands when repo already has immutable releases" {
            # If the repo already has immutable releases, the feature is enabled - no need for the enable command
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $issue = [ValidationIssue]::new("non_immutable_release", "error", "Release v1.0.0 was republished but is still mutable. Enable 'Release immutability' for the repository")
            $issue.Version = "v1.0.0"
            $issue.Status = "manual_fix_required"
            $script:state.Issues = @($issue)
            
            # Add an immutable release to the state - feature is already enabled
            $immutableRelease = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 456
                draft = $false
                prerelease = $false
                html_url = "https://github.com/test-owner/test-repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $true
            }
            $script:state.Releases = @([ReleaseInfo]::new($immutableRelease))
            
            $commands = $action.GetManualCommands($script:state)
            
            # Should return gh release edit commands since feature is already enabled
            $commands.Count | Should -Be 2
            $commands[0] | Should -Match "gh release edit v1.0.0"
            $commands[0] | Should -Match "--draft=true"
            $commands[1] | Should -Match "gh release edit v1.0.0"
            $commands[1] | Should -Match "--draft=false"
        }
        
        It "Should return gh release edit commands when repo has immutable releases even in manual_fix_required state" {
            # When auto-fix: false, Invoke-AutoFix marks ALL pending issues as
            # manual_fix_required before GetManualCommands is called. 
            # If the repo has immutable releases, show gh release edit commands.
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $issue = [ValidationIssue]::new("non_immutable_release", "error", "Release v1.0.0 is published but not immutable (repository 'Release immutability' setting may not be enabled)")
            $issue.Version = "v1.0.0"
            $issue.Status = "manual_fix_required"  # Set by Invoke-AutoFix when auto-fix: false
            $script:state.Issues = @($issue)
            
            # Add an immutable release - feature is already enabled
            $immutableRelease = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 456
                draft = $false
                prerelease = $false
                html_url = "https://github.com/test-owner/test-repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $true
            }
            $script:state.Releases = @([ReleaseInfo]::new($immutableRelease))
            
            $commands = $action.GetManualCommands($script:state)
            
            # Should return gh release edit commands, NOT the settings URL
            $commands.Count | Should -Be 2
            $commands[0] | Should -Match "gh release edit v1.0.0"
            $commands[0] | Should -Match "--draft=true"
            $commands[1] | Should -Match "gh release edit v1.0.0"
            $commands[1] | Should -Match "--draft=false"
        }
        
        It "Should not show settings URL when another immutability fix already succeeded" {
            # If auto-fix succeeded for one release (status=fixed), the feature is enabled
            # So we shouldn't show the settings URL for subsequent failed fixes
            $action = [RepublishReleaseAction]::new("v1.0.7")
            
            # v1.0.8 was successfully fixed (status=fixed)
            $fixedIssue = [ValidationIssue]::new("non_immutable_release", "error", "Release v1.0.8 was fixed")
            $fixedIssue.Version = "v1.0.8"
            $fixedIssue.Status = "fixed"
            
            # v1.0.7 failed to fix
            $failedIssue = [ValidationIssue]::new("non_immutable_release", "error", "Release v1.0.7 failed")
            $failedIssue.Version = "v1.0.7"
            $failedIssue.Status = "failed"
            
            $script:state.Issues = @($fixedIssue, $failedIssue)
            $script:state.Releases = @()  # No immutable releases in original state
            
            $commands = $action.GetManualCommands($script:state)
            
            # Should NOT show settings URL since another fix succeeded (feature is enabled)
            $commands.Count | Should -Be 2
            $commands[0] | Should -Match "gh release edit v1.0.7"
            $commands[0] | Should -Match "--draft=true"
            $commands[1] | Should -Match "gh release edit v1.0.7"
            $commands[1] | Should -Match "--draft=false"
        }
    }
    
    Context "Execute" {
        BeforeEach {
            Mock Republish-GitHubRelease { return @{ Success = $true } }
            Mock Test-ReleaseImmutability { return $true }
        }
        
        It "Should republish and verify immutability" {
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
            Should -Invoke Republish-GitHubRelease -Times 1
            Should -Invoke Test-ReleaseImmutability -Times 1
        }
        
        It "Should mark as manual_fix_required when republish succeeds but still mutable" {
            Mock Test-ReleaseImmutability { return $false }
            
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $issue = [ValidationIssue]::new("non_immutable_release", "error", "Release not immutable")
            $issue.Version = "v1.0.0"
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "manual_fix_required"
            $issue.Message | Should -Match "Enable 'Release immutability'"
            $issue.Message | Should -Match "gh api -X PUT repos/test-owner/test-repo/immutable-releases"
        }
        
        It "Should enable release immutability before republishing when it is disabled" {
            Mock Get-GitHubImmutableReleaseStatus { return $false }
            Mock Enable-GitHubImmutableRelease { return $true }
            Mock Republish-GitHubRelease { return @{ Success = $true } }
            Mock Test-ReleaseImmutability { return $true }

            $action = [RepublishReleaseAction]::new("v1.0.0")
            $result = $action.Execute($script:state)

            $result | Should -Be $true
            Should -Invoke Enable-GitHubImmutableRelease -Times 1
            Should -Invoke Republish-GitHubRelease -Times 1
        }

        It "Should require manual fix with the gh api command when immutability cannot be enabled" {
            Mock Get-GitHubImmutableReleaseStatus { return $false }
            Mock Enable-GitHubImmutableRelease { return $false }
            Mock Republish-GitHubRelease { return @{ Success = $true } }

            $action = [RepublishReleaseAction]::new("v1.0.0")
            $issue = [ValidationIssue]::new("non_immutable_release", "error", "Release not immutable")
            $issue.Version = "v1.0.0"
            $issue.Status = "pending"
            $script:state.Issues = @($issue)

            $result = $action.Execute($script:state)

            $result | Should -Be $false
            $issue.Status | Should -Be "manual_fix_required"
            $issue.Message | Should -Match "gh api -X PUT repos/test-owner/test-repo/immutable-releases"
            Should -Invoke Republish-GitHubRelease -Times 0
        }

        It "Should list the enable command in manual steps after an enablement failure even if other releases are immutable" {
            Mock Get-GitHubImmutableReleaseStatus { return $false }
            Mock Enable-GitHubImmutableRelease { return $false }

            $action = [RepublishReleaseAction]::new("v1.0.0")
            $issue = [ValidationIssue]::new("non_immutable_release", "error", "Release not immutable")
            $issue.Version = "v1.0.0"
            $script:state.Issues = @($issue)
            $immutable = [ReleaseInfo]::new([PSCustomObject]@{ id = 1; tag_name = "v0.9.0"; draft = $false; prerelease = $false; immutable = $true; html_url = "u" })
            $script:state.Releases = @($immutable)

            $action.Execute($script:state) | Should -Be $false
            $commands = $action.GetManualCommands($script:state)
            ($commands -join "`n") | Should -Match "gh api -X PUT repos/test-owner/test-repo/immutable-releases"
        }

        It "Should delete the tag on 422 error" {
            Mock Republish-GitHubRelease { return @{ Success = $false; Unfixable = $true } }
            Mock Remove-GitHubRef { return $true }

            $action = [RepublishReleaseAction]::new("v1.0.0")
            $result = $action.Execute($script:state)

            $result | Should -Be $true
            Should -Invoke Remove-GitHubRef -Times 1 -ParameterFilter {
                $RefName -eq "refs/tags/v1.0.0"
            }
        }

        It "Should require manual fix and report blocking rulesets when tag deletion fails" {
            Mock Republish-GitHubRelease { return @{ Success = $false; Unfixable = $true } }
            Mock Remove-GitHubRef { return $false }
            Mock Get-GitHubTagProtection { return @([PSCustomObject]@{ Name = "Protect tags"; Enforcement = "active"; Source = "repository test-owner/test-repo"; Url = "https://github.com/test-owner/test-repo/rules/1" }) }
            
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $issue = [ValidationIssue]::new("non_immutable_release", "error", "Release not immutable")
            $issue.Version = "v1.0.0"
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "manual_fix_required"
            $issue.Message | Should -Match "Protect tags"
            $action.TagDeletionFailed | Should -Be $true
        }
    }
}
