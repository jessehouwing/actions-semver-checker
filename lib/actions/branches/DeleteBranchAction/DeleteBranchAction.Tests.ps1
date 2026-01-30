BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/DeleteBranchAction.ps1"
}

Describe "DeleteBranchAction" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
    }
    
    Context "Constructor" {
        It "Should delete branch with high priority" {
            $action = [DeleteBranchAction]::new("v1")
            
            $action.Priority | Should -Be 10
        }
        
        It "Should set BranchName correctly" {
            $action = [DeleteBranchAction]::new("v1")
            
            $action.BranchName | Should -Be "v1"
            $action.Description | Should -Be "Delete branch"
            $action.Version | Should -Be "v1"
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate correct manual commands" {
            $action = [DeleteBranchAction]::new("v1")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 2
            $commands[0] | Should -Be "git branch -d v1"
            $commands[1] | Should -Be "git push origin :refs/heads/v1"
        }
    }
    
    Context "Execute" {
        It "Should call Remove-GitHubRef with refs/heads/ prefix" {
            Mock Remove-GitHubRef { return $true }
            
            $action = [DeleteBranchAction]::new("v1")
            $action.Execute($script:state)
            
            Should -Invoke Remove-GitHubRef -Times 1 -ParameterFilter {
                $RefName -eq "refs/heads/v1"
            }
        }
        
        It "Should return true on success" {
            Mock Remove-GitHubRef { return $true }
            
            $action = [DeleteBranchAction]::new("v1")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
        }
        
        It "Should return false on failure" {
            Mock Remove-GitHubRef { return $false }
            
            $action = [DeleteBranchAction]::new("v1")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
        }
    }
}
