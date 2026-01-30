BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/CreateTagAction.ps1"
}

Describe "CreateTagAction" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
    }
    
    Context "Constructor" {
        It "Should create action with correct properties" {
            $action = [CreateTagAction]::new("v1.0.0", "abc123")
            
            $action.TagName | Should -Be "v1.0.0"
            $action.Sha | Should -Be "abc123"
            $action.Priority | Should -Be 20
            $action.Description | Should -Be "Create tag"
            $action.Version | Should -Be "v1.0.0"
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate correct manual commands" {
            $action = [CreateTagAction]::new("v1.0.0", "abc123")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Be "git push origin abc123:refs/tags/v1.0.0"
        }
        
        It "Should include full SHA in command" {
            $action = [CreateTagAction]::new("v2.1.3", "deadbeef1234567890")
            $commands = $action.GetManualCommands($script:state)
            
            $commands[0] | Should -Match "deadbeef1234567890:refs/tags/v2.1.3"
        }
    }
    
    Context "Execute" {
        BeforeEach {
            Mock New-GitHubRef { return @{ Success = $true; RequiresManualFix = $false } }
        }
        
        It "Should call New-GitHubRef with correct parameters" {
            $action = [CreateTagAction]::new("v1.0.0", "abc123")
            $action.Execute($script:state)
            
            Should -Invoke New-GitHubRef -Times 1 -ParameterFilter {
                $RefName -eq "refs/tags/v1.0.0" -and
                $Sha -eq "abc123" -and
                $Force -eq $false
            }
        }
        
        It "Should return true on success" {
            $action = [CreateTagAction]::new("v1.0.0", "abc123")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
        }
        
        It "Should return false on failure" {
            Mock New-GitHubRef { return @{ Success = $false; RequiresManualFix = $false } }
            
            $action = [CreateTagAction]::new("v1.0.0", "abc123")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
        }
        
        It "Should mark issue as manual_fix_required when workflow permission error occurs" {
            Mock New-GitHubRef { return @{ Success = $false; RequiresManualFix = $true } }
            
            # Create issue for the action
            $action = [CreateTagAction]::new("v1.0.0", "abc123")
            $issue = [ValidationIssue]::new("missing_tag", "error", "Tag missing")
            $issue.Version = "v1.0.0"
            $issue.RemediationAction = $action
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "manual_fix_required"
            $issue.Message | Should -Match "workflows.*permission"
        }
    }
}
