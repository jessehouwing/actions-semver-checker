BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/UpdateTagAction.ps1"
}

Describe "UpdateTagAction" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
    }
    
    Context "Constructor" {
        It "Should create action with force flag" {
            $action = [UpdateTagAction]::new("v1.0.0", "abc123", $true)
            
            $action.TagName | Should -Be "v1.0.0"
            $action.Sha | Should -Be "abc123"
            $action.Force | Should -Be $true
            $action.Priority | Should -Be 20
        }
        
        It "Should create action without force flag" {
            $action = [UpdateTagAction]::new("v1.0.0", "abc123", $false)
            
            $action.Force | Should -Be $false
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate correct manual commands with force" {
            $action = [UpdateTagAction]::new("v1.0.0", "abc123", $true)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "--force"
            $commands[0] | Should -Match "abc123:refs/tags/v1.0.0"
        }
        
        It "Should generate correct manual commands without force" {
            $action = [UpdateTagAction]::new("v1.0.0", "abc123", $false)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Not -Match "--force"
        }
    }
    
    Context "Execute" {
        BeforeEach {
            Mock New-GitHubRef { return @{ Success = $true; RequiresManualFix = $false } }
        }
        
        It "Should call New-GitHubRef with force=true when specified" {
            $action = [UpdateTagAction]::new("v1.0.0", "abc123", $true)
            $action.Execute($script:state)
            
            Should -Invoke New-GitHubRef -Times 1 -ParameterFilter {
                $RefName -eq "refs/tags/v1.0.0" -and
                $Sha -eq "abc123" -and
                $Force -eq $true
            }
        }
        
        It "Should call New-GitHubRef with force=false when not specified" {
            $action = [UpdateTagAction]::new("v1.0.0", "abc123", $false)
            $action.Execute($script:state)
            
            Should -Invoke New-GitHubRef -Times 1 -ParameterFilter {
                $Force -eq $false
            }
        }
        
        It "Should return true on success" {
            $action = [UpdateTagAction]::new("v1.0.0", "abc123", $true)
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
        }
        
        It "Should mark issue as manual_fix_required when workflow permission error occurs" {
            Mock New-GitHubRef { return @{ Success = $false; RequiresManualFix = $true } }
            
            $action = [UpdateTagAction]::new("v1", "abc123", $true)
            $issue = [ValidationIssue]::new("floating_version_mismatch", "error", "Tag points to wrong commit")
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
