BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/../../base/ReleaseRemediationAction.ps1"
    . "$PSScriptRoot/SetLatestReleaseAction.ps1"
}

Describe "SetLatestReleaseAction" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
    }
    
    Context "Constructor" {
        It "Should create action with tagName only" {
            $action = [SetLatestReleaseAction]::new("v1.0.0")
            
            $action.TagName | Should -Be "v1.0.0"
            $action.ReleaseId | Should -Be 0
            $action.Priority | Should -Be 50  # Runs after other release actions
        }
        
        It "Should create action with tagName and releaseId" {
            $action = [SetLatestReleaseAction]::new("v1.0.0", 123)
            
            $action.TagName | Should -Be "v1.0.0"
            $action.ReleaseId | Should -Be 123
            $action.Priority | Should -Be 50
        }
        
        It "Should have correct description" {
            $action = [SetLatestReleaseAction]::new("v1.0.0", 123)
            
            $action.Description | Should -Match "Set.*latest"
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate correct gh release edit command" {
            $action = [SetLatestReleaseAction]::new("v1.0.0", 123)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "gh release edit v1.0.0"
            $commands[0] | Should -Match "--latest"
        }
        
        It "Should return empty array when issue is unfixable" {
            $action = [SetLatestReleaseAction]::new("v1.0.0", 123)
            
            # Create unfixable issue
            $issue = [ValidationIssue]::new("wrong_latest_release", "error", "Wrong latest release")
            $issue.Version = "v1.0.0"
            $issue.Status = "unfixable"
            $script:state.Issues = @($issue)
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 0
        }
    }
    
    Context "Execute" {
        BeforeEach {
            Mock Set-GitHubReleaseLatest { return @{ Success = $true } }
        }
        
        It "Should call Set-GitHubReleaseLatest with correct parameters" {
            $action = [SetLatestReleaseAction]::new("v1.0.0", 123)
            $action.Execute($script:state)
            
            Should -Invoke Set-GitHubReleaseLatest -Times 1 -ParameterFilter {
                $TagName -eq "v1.0.0" -and $ReleaseId -eq 123
            }
        }
        
        It "Should return true on success" {
            Mock Set-GitHubReleaseLatest { return @{ Success = $true } }
            
            $action = [SetLatestReleaseAction]::new("v1.0.0", 123)
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
        }
        
        It "Should return false on failure" {
            Mock Set-GitHubReleaseLatest { return @{ Success = $false; Unfixable = $false } }
            
            $action = [SetLatestReleaseAction]::new("v1.0.0", 123)
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
        }
        
        It "Should mark issue as unfixable on 422 error" {
            Mock Set-GitHubReleaseLatest { return @{ Success = $false; Unfixable = $true } }
            
            $action = [SetLatestReleaseAction]::new("v1.0.0", 123)
            $issue = [ValidationIssue]::new("wrong_latest_release", "error", "Wrong latest")
            $issue.Version = "v1.0.0"
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "unfixable"
        }
        
        It "Should lookup release ID if not provided" {
            # When ReleaseId is 0, the action should look it up from state
            $release = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 456
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $script:state.Releases = @([ReleaseInfo]::new($release))
            
            Mock Set-GitHubReleaseLatest { return @{ Success = $true } }
            
            $action = [SetLatestReleaseAction]::new("v1.0.0")  # No release ID
            $action.Execute($script:state)
            
            # Should have looked up the release ID
            Should -Invoke Set-GitHubReleaseLatest -Times 1 -ParameterFilter {
                $ReleaseId -eq 456
            }
        }
    }
}
