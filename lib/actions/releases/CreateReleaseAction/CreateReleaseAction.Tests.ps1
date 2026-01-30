BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/../../base/ReleaseRemediationAction.ps1"
    . "$PSScriptRoot/CreateReleaseAction.ps1"
}

Describe "CreateReleaseAction" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
    }
    
    Context "Constructor" {
        It "Should create action for draft release (isDraft=true)" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true)
            
            $action.TagName | Should -Be "v1.0.0"
            $action.AutoPublish | Should -Be $false
            $action.Priority | Should -Be 30
        }
        
        It "Should create action for published release (isDraft=false)" {
            $action = [CreateReleaseAction]::new("v1.0.0", $false)
            
            $action.AutoPublish | Should -Be $true
        }
        
        It "Should create action with explicit auto-publish" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true, $true)
            
            $action.TagName | Should -Be "v1.0.0"
            $action.AutoPublish | Should -Be $true
            $action.Priority | Should -Be 30
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate correct manual commands for draft" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true, $false)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "gh release create v1.0.0 --draft"
            $commands[0] | Should -Not -Match "^#"
        }
        
        It "Should generate correct manual commands for auto-publish" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true, $true)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "gh release create v1.0.0"
            $commands[0] | Should -Not -Match "--draft"
            $commands[0] | Should -Not -Match "^#"
        }
        
        It "Should return empty array when issue is unfixable" {
            # Create unfixable issue
            $action = [CreateReleaseAction]::new("v1.0.0", $false)
            $issue = [ValidationIssue]::new("missing_release", "error", "Release missing")
            $issue.Version = "v1.0.0"
            $issue.Status = "unfixable"
            $script:state.Issues = @($issue)
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 0
        }
    }
    
    Context "Execute" {
        BeforeEach {
            Mock New-GitHubRelease { return @{ Success = $true } }
        }
        
        It "Should call New-GitHubRelease with draft=true when AutoPublish is false" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true, $false)
            $action.Execute($script:state)
            
            Should -Invoke New-GitHubRelease -Times 1 -ParameterFilter {
                $TagName -eq "v1.0.0" -and $Draft -eq $true
            }
        }
        
        It "Should call New-GitHubRelease with draft=false when AutoPublish is true" {
            $action = [CreateReleaseAction]::new("v1.0.0", $false, $true)
            $action.Execute($script:state)
            
            Should -Invoke New-GitHubRelease -Times 1 -ParameterFilter {
                $TagName -eq "v1.0.0" -and $Draft -eq $false
            }
        }
        
        It "Should mark issue as unfixable on 422 error" {
            Mock New-GitHubRelease { return @{ Success = $false; Unfixable = $true } }
            
            $action = [CreateReleaseAction]::new("v1.0.0", $false)
            $issue = [ValidationIssue]::new("missing_release", "error", "Release missing")
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
