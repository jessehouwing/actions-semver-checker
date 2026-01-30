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
            $commands[0] | Should -Be "gh release edit v1.0.0 --draft=false"
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
}
