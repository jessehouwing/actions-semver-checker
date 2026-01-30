BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/DeleteTagAction.ps1"
}

Describe "DeleteTagAction" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
    }
    
    Context "Constructor" {
        It "Should have highest priority (delete first)" {
            $action = [DeleteTagAction]::new("v1.0.0")
            
            $action.Priority | Should -Be 10
        }
        
        It "Should set TagName correctly" {
            $action = [DeleteTagAction]::new("v1.0.0")
            
            $action.TagName | Should -Be "v1.0.0"
            $action.Description | Should -Be "Delete tag"
            $action.Version | Should -Be "v1.0.0"
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate correct manual commands" {
            $action = [DeleteTagAction]::new("v1.0.0")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 2
            $commands[0] | Should -Be "git tag -d v1.0.0"
            $commands[1] | Should -Be "git push origin :refs/tags/v1.0.0"
        }
    }
    
    Context "Execute" {
        It "Should call Remove-GitHubRef with correct parameters" {
            Mock Remove-GitHubRef { return $true }
            
            $action = [DeleteTagAction]::new("v1.0.0")
            $action.Execute($script:state)
            
            Should -Invoke Remove-GitHubRef -Times 1 -ParameterFilter {
                $RefName -eq "refs/tags/v1.0.0"
            }
        }
        
        It "Should return true on success" {
            Mock Remove-GitHubRef { return $true }
            
            $action = [DeleteTagAction]::new("v1.0.0")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
        }
        
        It "Should return false on failure" {
            Mock Remove-GitHubRef { return $false }
            
            $action = [DeleteTagAction]::new("v1.0.0")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
        }
    }
}
