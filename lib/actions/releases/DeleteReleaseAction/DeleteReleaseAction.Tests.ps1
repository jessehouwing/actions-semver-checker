BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/../../base/ReleaseRemediationAction.ps1"
    . "$PSScriptRoot/DeleteReleaseAction.ps1"
}

Describe "DeleteReleaseAction" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
    }
    
    Context "Constructor" {
        It "Should have high priority (delete early)" {
            $action = [DeleteReleaseAction]::new("v1.0.0", 12345)
            
            $action.Priority | Should -Be 10
        }
        
        It "Should set properties correctly" {
            $action = [DeleteReleaseAction]::new("v1.0.0", 12345)
            
            $action.TagName | Should -Be "v1.0.0"
            $action.ReleaseId | Should -Be 12345
            $action.Description | Should -Be "Delete release"
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate correct manual commands" {
            $action = [DeleteReleaseAction]::new("v1.0.0", 12345)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "gh release delete v1.0.0"
            $commands[0] | Should -Match "--repo test-owner/test-repo"
            $commands[0] | Should -Match "--yes"
        }
    }
    
    Context "Execute" {
        It "Should call Remove-GitHubRelease with correct parameters" {
            Mock Remove-GitHubRelease { return $true }
            
            $action = [DeleteReleaseAction]::new("v1.0.0", 12345)
            $action.Execute($script:state)
            
            Should -Invoke Remove-GitHubRelease -Times 1 -ParameterFilter {
                $TagName -eq "v1.0.0" -and $ReleaseId -eq 12345
            }
        }
        
        It "Should return true on success" {
            Mock Remove-GitHubRelease { return $true }
            
            $action = [DeleteReleaseAction]::new("v1.0.0", 12345)
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
        }
        
        It "Should return false on failure" {
            Mock Remove-GitHubRelease { return $false }
            
            $action = [DeleteReleaseAction]::new("v1.0.0", 12345)
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
        }
    }
}
