BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/CreateBranchAction.ps1"
}

Describe "CreateBranchAction" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
    }
    
    Context "Constructor" {
        It "Should create branch action with correct properties" {
            $action = [CreateBranchAction]::new("v1", "abc123")
            
            $action.BranchName | Should -Be "v1"
            $action.Sha | Should -Be "abc123"
            $action.Priority | Should -Be 20
            $action.Description | Should -Be "Create branch"
            $action.Version | Should -Be "v1"
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate correct branch commands" {
            $action = [CreateBranchAction]::new("v1", "abc123")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Be "git push origin abc123:refs/heads/v1"
        }
    }
    
    Context "Execute" {
        BeforeEach {
            Mock New-GitHubRef { return @{ Success = $true; RequiresManualFix = $false } }
        }
        
        It "Should call New-GitHubRef with refs/heads/ prefix" {
            $action = [CreateBranchAction]::new("v1", "abc123")
            $action.Execute($script:state)
            
            Should -Invoke New-GitHubRef -Times 1 -ParameterFilter {
                $RefName -eq "refs/heads/v1" -and
                $Sha -eq "abc123" -and
                $Force -eq $false
            }
        }
        
        It "Should return true on success" {
            $action = [CreateBranchAction]::new("v1", "abc123")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
        }
        
        It "Should mark issue as manual_fix_required when workflow permission error occurs" {
            Mock New-GitHubRef { return @{ Success = $false; RequiresManualFix = $true } }
            
            $action = [CreateBranchAction]::new("v1", "abc123")
            $issue = [ValidationIssue]::new("missing_branch", "error", "Branch missing")
            $issue.Version = "v1"
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
