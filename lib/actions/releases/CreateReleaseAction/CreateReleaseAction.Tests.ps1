BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/../../base/ReleaseRemediationAction.ps1"
    . "$PSScriptRoot/CreateReleaseAction.ps1"
}

Describe "CreateReleaseAction" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
    }
    
    Context "Constructor" {
        It "Should create action for draft release (isDraft=true)" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true)
            
            $action.TagName | Should -Be "v1.0.0"
            $action.AutoPublish | Should -Be $false
            $action.Priority | Should -Be 30
        }
        
        It "Should create action for published release (isDraft=false)" {
            $action = [CreateReleaseAction]::new("v1.0.0", $false)
            
            $action.AutoPublish | Should -Be $true
        }
        
        It "Should create action with explicit auto-publish" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true, $true)
            
            $action.TagName | Should -Be "v1.0.0"
            $action.AutoPublish | Should -Be $true
            $action.Priority | Should -Be 30
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate correct manual commands for draft" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true, $false)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "gh release create v1.0.0 --draft"
            $commands[0] | Should -Not -Match "^#"
        }
        
        It "Should generate correct manual commands for auto-publish" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true, $true)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "gh release create v1.0.0"
            $commands[0] | Should -Not -Match "--draft"
            $commands[0] | Should -Not -Match "^#"
        }
        
        It "Should return empty array when issue is unfixable" {
            # Create unfixable issue
            $action = [CreateReleaseAction]::new("v1.0.0", $false)
            $issue = [ValidationIssue]::new("missing_release", "error", "Release missing")
            $issue.Version = "v1.0.0"
            $issue.Status = "unfixable"
            $script:state.Issues = @($issue)
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 0
        }
    }
    
    Context "Execute" {
        BeforeEach {
            Mock New-GitHubRelease { return @{ Success = $true } }
        }
        
        It "Should call New-GitHubRelease with draft=true when AutoPublish is false" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true, $false)
            $action.Execute($script:state)
            
            Should -Invoke New-GitHubRelease -Times 1 -ParameterFilter {
                $TagName -eq "v1.0.0" -and $Draft -eq $true
            }
        }
        
        It "Should call New-GitHubRelease with draft=false when AutoPublish is true" {
            $action = [CreateReleaseAction]::new("v1.0.0", $false, $true)
            $action.Execute($script:state)
            
            Should -Invoke New-GitHubRelease -Times 1 -ParameterFilter {
                $TagName -eq "v1.0.0" -and $Draft -eq $false
            }
        }
        
        It "Should mark issue as unfixable on 422 error" {
            Mock New-GitHubRelease { return @{ Success = $false; Unfixable = $true } }
            
            $action = [CreateReleaseAction]::new("v1.0.0", $false)
            $issue = [ValidationIssue]::new("missing_release", "error", "Release missing")
            $issue.Version = "v1.0.0"
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "unfixable"
            $issue.Message | Should -Match "immutable release"
        }
    }
    
    Context "MakeLatest - prevents overwriting correct latest release" {
        BeforeEach {
            Mock New-GitHubRelease { return @{ Success = $true } }
        }
        
        It "Should default MakeLatest to null (let GitHub decide)" {
            $action = [CreateReleaseAction]::new("v1.0.0", $false)
            
            $action.MakeLatest | Should -BeNullOrEmpty
        }
        
        It "Should allow explicit MakeLatest=false to prevent becoming latest" {
            $action = [CreateReleaseAction]::new("v1.0.0", $false)
            $action.MakeLatest = $false
            
            $action.MakeLatest | Should -Be $false
        }
        
        It "Should pass MakeLatest=false to New-GitHubRelease when explicitly set" {
            $action = [CreateReleaseAction]::new("v1.0.0", $false)
            $action.MakeLatest = $false
            
            $action.Execute($script:state)
            
            Should -Invoke New-GitHubRelease -Times 1 -ParameterFilter {
                $MakeLatest -eq $false
            }
        }
        
        It "Should not pass MakeLatest parameter when null (let GitHub use default)" {
            $action = [CreateReleaseAction]::new("v1.0.0", $false)
            # MakeLatest is null by default
            
            $action.Execute($script:state)
            
            # When MakeLatest is null, New-GitHubRelease should not receive a specific MakeLatest value
            Should -Invoke New-GitHubRelease -Times 1 -ParameterFilter {
                $null -eq $MakeLatest -or $MakeLatest -eq $true
            }
        }
        
        It "Should use MakeLatest=false when creating release for older version" {
            # Scenario: v2.0.0 exists as latest, we're creating v1.1.0
            # Creating v1.1.0 should NOT become latest
            $release = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($release)
            $releaseInfo.IsLatest = $true
            $script:state.Releases = @($releaseInfo)
            $script:state.Tags = @([VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "def456", "tag"))
            
            $action = [CreateReleaseAction]::new("v1.1.0", $false)
            $action.MakeLatest = $false  # Explicitly prevent becoming latest
            
            $action.Execute($script:state)
            
            Should -Invoke New-GitHubRelease -Times 1 -ParameterFilter {
                $MakeLatest -eq $false
            }
        }
        
        It "Should use MakeLatest=false when creating release for prerelease version" {
            # Scenario: v1.0.0 exists as latest (stable), we're creating v2.0.0 marked as prerelease
            # The prerelease should NOT become latest
            $release = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($release)
            $releaseInfo.IsLatest = $true
            $script:state.Releases = @($releaseInfo)
            $script:state.Tags = @([VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag"))
            
            # Creating v2.0.0 as a prerelease - should NOT become latest
            $action = [CreateReleaseAction]::new("v2.0.0", $false)
            $action.MakeLatest = $false  # Explicitly prevent becoming latest for prerelease
            
            $action.Execute($script:state)
            
            Should -Invoke New-GitHubRelease -Times 1 -ParameterFilter {
                $MakeLatest -eq $false
            }
        }
    }
    
    Context "MakeLatest - GetManualCommands output" {
        It "Should include --latest=false in manual command when MakeLatest is false" {
            $action = [CreateReleaseAction]::new("v1.0.0", $false)
            $action.MakeLatest = $false
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands[0] | Should -Match "--latest=false"
        }
        
        It "Should include --latest in manual command when MakeLatest is true" {
            $action = [CreateReleaseAction]::new("v1.0.0", $false)
            $action.MakeLatest = $true
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands[0] | Should -Match "--latest"
            $commands[0] | Should -Not -Match "--latest=false"
        }
        
        It "Should not include --latest in manual command when MakeLatest is null" {
            $action = [CreateReleaseAction]::new("v1.0.0", $false)
            # MakeLatest is null by default
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands[0] | Should -Not -Match "--latest"
        }
    }
}
