BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/ConvertBranchToTagAction.ps1"
}

Describe "ConvertBranchToTagAction" {
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
            $action = [ConvertBranchToTagAction]::new("v1.0.0", "abc123")
            
            $action.Name | Should -Be "v1.0.0"
            $action.Sha | Should -Be "abc123"
            $action.Priority | Should -Be 25
            $action.Description | Should -Be "Convert branch to tag"
            $action.Version | Should -Be "v1.0.0"
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate delete-only commands when tag already exists" {
            # Set up state with existing tag
            $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $script:state.Tags = @($tag)
            
            $action = [ConvertBranchToTagAction]::new("v1.0.0", "abc123")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Be "git push origin :refs/heads/v1.0.0"
        }
        
        It "Should generate create-then-delete commands when tag does not exist" {
            # No tags in state
            $script:state.Tags = @()
            
            $action = [ConvertBranchToTagAction]::new("v1.0.0", "abc123")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 2
            $commands[0] | Should -Be "git push origin abc123:refs/tags/v1.0.0"
            $commands[1] | Should -Be "git push origin :refs/heads/v1.0.0"
        }
    }
    
    Context "Execute" {
        BeforeEach {
            Mock New-GitHubRef { return @{ Success = $true; RequiresManualFix = $false } }
            Mock Remove-GitHubRef { return $true }
        }
        
        It "Should delete branch only when tag already exists" {
            $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $script:state.Tags = @($tag)
            
            $action = [ConvertBranchToTagAction]::new("v1.0.0", "abc123")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
            Should -Invoke Remove-GitHubRef -Times 1 -ParameterFilter { $RefName -eq "refs/heads/v1.0.0" }
            Should -Not -Invoke New-GitHubRef
        }
        
        It "Should create tag then delete branch when tag does not exist" {
            $script:state.Tags = @()
            
            $action = [ConvertBranchToTagAction]::new("v1.0.0", "abc123")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
            Should -Invoke New-GitHubRef -Times 1 -ParameterFilter { $RefName -eq "refs/tags/v1.0.0" }
            Should -Invoke Remove-GitHubRef -Times 1 -ParameterFilter { $RefName -eq "refs/heads/v1.0.0" }
        }
        
        It "Should mark issue manual_fix_required when workflow permission error occurs" {
            Mock New-GitHubRef { return @{ Success = $false; RequiresManualFix = $true } }
            
            $action = [ConvertBranchToTagAction]::new("v1.0.0", "abc123")
            $issue = [ValidationIssue]::new("wrong_ref_type", "error", "Branch should be tag")
            $issue.Version = "v1.0.0"
            $issue.RemediationAction = $action
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            $script:state.Tags = @()
            
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "manual_fix_required"
            $issue.Message | Should -Match "workflows.*permission"
        }
        
        It "Should return false when tag creation succeeds but branch deletion fails" {
            Mock Remove-GitHubRef { return $false }
            $script:state.Tags = @()
            
            $action = [ConvertBranchToTagAction]::new("v1.0.0", "abc123")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
        }
    }
}
