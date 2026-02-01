BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/ConvertTagToBranchAction.ps1"
}

Describe "ConvertTagToBranchAction" {
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
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            
            $action.Name | Should -Be "v1"
            $action.Sha | Should -Be "abc123"
            $action.Priority | Should -Be 25
            $action.Description | Should -Be "Convert tag to branch"
            $action.Version | Should -Be "v1"
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate delete-only commands when branch already exists" {
            # Set up state with existing branch
            $branch = [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $script:state.Branches = @($branch)
            
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Be "git push origin :refs/tags/v1"
        }
        
        It "Should generate create-then-delete commands when branch does not exist" {
            # No branches in state
            $script:state.Branches = @()
            
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 2
            $commands[0] | Should -Be "git push origin abc123:refs/heads/v1"
            $commands[1] | Should -Be "git push origin :refs/tags/v1"
        }
        
        It "Should return empty commands when issue is unfixable" {
            # Create an issue marked as unfixable
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            $issue = [ValidationIssue]::new("wrong_ref_type", "error", "Tag has immutable release")
            $issue.Version = "v1"
            $issue.RemediationAction = $action
            $issue.Status = "unfixable"
            $script:state.Issues = @($issue)
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 0
        }
    }
    
    Context "Execute" {
        BeforeEach {
            Mock Test-ReleaseImmutability { return $false }
            Mock New-GitHubRef { return @{ Success = $true; RequiresManualFix = $false } }
            Mock Remove-GitHubRef { return $true }
        }
        
        It "Should mark issue unfixable when tag has immutable release" {
            Mock Test-ReleaseImmutability { return $true }
            
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            $issue = [ValidationIssue]::new("wrong_ref_type", "error", "Tag should be branch")
            $issue.Version = "v1"
            $issue.RemediationAction = $action
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "unfixable"
            $issue.Message | Should -Match "immutable"
        }
        
        It "Should delete tag only when branch already exists" {
            $branch = [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $script:state.Branches = @($branch)
            
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
            Should -Invoke Remove-GitHubRef -Times 1 -ParameterFilter { $RefName -eq "refs/tags/v1" }
            Should -Not -Invoke New-GitHubRef
        }
        
        It "Should create branch then delete tag when branch does not exist" {
            $script:state.Branches = @()
            
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
            Should -Invoke New-GitHubRef -Times 1 -ParameterFilter { $RefName -eq "refs/heads/v1" }
            Should -Invoke Remove-GitHubRef -Times 1 -ParameterFilter { $RefName -eq "refs/tags/v1" }
        }
        
        It "Should mark issue manual_fix_required when workflow permission error occurs" {
            Mock New-GitHubRef { return @{ Success = $false; RequiresManualFix = $true } }
            
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            $issue = [ValidationIssue]::new("wrong_ref_type", "error", "Tag should be branch")
            $issue.Version = "v1"
            $issue.RemediationAction = $action
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            $script:state.Branches = @()
            
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "manual_fix_required"
            $issue.Message | Should -Match "workflows.*permission"
        }
    }
}
