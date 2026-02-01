BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/../../base/ReleaseRemediationAction.ps1"
    . "$PSScriptRoot/PublishReleaseAction.ps1"
}

Describe "PublishReleaseAction" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
    }
    
    Context "Constructor" {
        It "Should create action with release ID" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            
            $action.TagName | Should -Be "v1.0.0"
            $action.ReleaseId | Should -Be 12345
            $action.Priority | Should -Be 40
        }
        
        It "Should create action without release ID" {
            $action = [PublishReleaseAction]::new("v1.0.0")
            
            $action.ReleaseId | Should -Be 0
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate correct manual commands" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "gh release edit v1.0.0"
            $commands[0] | Should -Match "--repo test-owner/test-repo"
            $commands[0] | Should -Match "--draft=false"
            $commands[0] | Should -Not -Match "^#"
            $commands[0] | Should -Not -Match "# Or edit at"
        }
        
        It "Should return empty array when issue is unfixable" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            $issue = [ValidationIssue]::new("draft_release", "error", "Release is draft")
            $issue.Version = "v1.0.0"
            $issue.Status = "unfixable"
            $script:state.Issues = @($issue)
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 0
        }
    }
    
    Context "Execute" {
        BeforeEach {
            Mock Publish-GitHubRelease { return @{ Success = $true } }
        }
        
        It "Should call Publish-GitHubRelease with correct parameters" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            $action.Execute($script:state)
            
            Should -Invoke Publish-GitHubRelease -Times 1 -ParameterFilter {
                $TagName -eq "v1.0.0" -and $ReleaseId -eq 12345
            }
        }
        
        It "Should return true on success" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
        }
        
        It "Should mark issue as unfixable on 422 error" {
            Mock Publish-GitHubRelease { return @{ Success = $false; Unfixable = $true } }
            
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            $issue = [ValidationIssue]::new("draft_release", "error", "Release is draft")
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
            Mock Publish-GitHubRelease { return @{ Success = $true } }
        }
        
        It "Should default MakeLatest to null (let GitHub decide)" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            
            $action.MakeLatest | Should -BeNullOrEmpty
        }
        
        It "Should allow explicit MakeLatest=false to prevent becoming latest" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            $action.MakeLatest = $false
            
            $action.MakeLatest | Should -Be $false
        }
        
        It "Should pass MakeLatest=false to Publish-GitHubRelease when explicitly set" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            $action.MakeLatest = $false
            
            $action.Execute($script:state)
            
            Should -Invoke Publish-GitHubRelease -Times 1 -ParameterFilter {
                $MakeLatest -eq $false
            }
        }
        
        It "Should not pass MakeLatest parameter when null (let GitHub use default)" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            # MakeLatest is null by default
            
            $action.Execute($script:state)
            
            # When MakeLatest is null, Publish-GitHubRelease should not receive a specific MakeLatest value
            Should -Invoke Publish-GitHubRelease -Times 1 -ParameterFilter {
                $null -eq $MakeLatest -or $MakeLatest -eq $true
            }
        }
        
        It "Should use MakeLatest=false when publishing release for older version" {
            # Scenario: v2.0.0 exists as latest, we're publishing v1.1.0 draft
            # Publishing v1.1.0 should NOT become latest
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
            
            $action = [PublishReleaseAction]::new("v1.1.0", 111)
            $action.MakeLatest = $false  # Explicitly prevent becoming latest
            
            $action.Execute($script:state)
            
            Should -Invoke Publish-GitHubRelease -Times 1 -ParameterFilter {
                $MakeLatest -eq $false
            }
        }
        
        It "Should use MakeLatest=false when publishing prerelease version" {
            # Scenario: v1.0.0 exists as latest (stable), we're publishing v2.0.0 draft that will be marked as prerelease
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
            
            # Publishing v2.0.0 as a prerelease - should NOT become latest
            $action = [PublishReleaseAction]::new("v2.0.0", 200)
            $action.MakeLatest = $false  # Explicitly prevent becoming latest for prerelease
            
            $action.Execute($script:state)
            
            Should -Invoke Publish-GitHubRelease -Times 1 -ParameterFilter {
                $MakeLatest -eq $false
            }
        }
    }
    
    Context "MakeLatest - GetManualCommands output" {
        It "Should include --latest=false in manual command when MakeLatest is false" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            $action.MakeLatest = $false
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands[0] | Should -Match "--latest=false"
        }
        
        It "Should include --latest in manual command when MakeLatest is true" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            $action.MakeLatest = $true
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands[0] | Should -Match "--latest"
            $commands[0] | Should -Not -Match "--latest=false"
        }
        
        It "Should not include --latest in manual command when MakeLatest is null" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            # MakeLatest is null by default
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands[0] | Should -Not -Match "--latest"
        }
    }
}
