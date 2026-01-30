BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../Logging.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/../../base/RemediationAction.ps1"
    . "$PSScriptRoot/../../base/ReleaseRemediationAction.ps1"
    . "$PSScriptRoot/RepublishReleaseAction.ps1"
}

Describe "RepublishReleaseAction" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
    }
    
    Context "Constructor" {
        It "Should create action with correct priority" {
            $action = [RepublishReleaseAction]::new("v1.0.0")
            
            $action.TagName | Should -Be "v1.0.0"
            $action.Priority | Should -Be 45
            $action.Description | Should -Be "Republish release for immutability"
        }
    }
    
    Context "GetManualCommands" {
        It "Should generate manual commands without comments" {
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 2
            $commands[0] | Should -Be "gh release edit v1.0.0 --draft=true"
            $commands[1] | Should -Be "gh release edit v1.0.0 --draft=false"
        }
        
        It "Should return empty array when issue is unfixable" {
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $issue = [ValidationIssue]::new("non_immutable_release", "error", "Release not immutable")
            $issue.Version = "v1.0.0"
            $issue.Status = "unfixable"
            $script:state.Issues = @($issue)
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 0
        }
        
        It "Should return settings URL when manual_fix_required" {
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $issue = [ValidationIssue]::new("non_immutable_release", "error", "Release not immutable")
            $issue.Version = "v1.0.0"
            $issue.Status = "manual_fix_required"
            $script:state.Issues = @($issue)
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "^# Enable 'Release immutability'"
            $commands[0] | Should -Match "settings#releases-settings"
        }
    }
    
    Context "Execute" {
        BeforeEach {
            Mock Republish-GitHubRelease { return @{ Success = $true } }
            Mock Test-ReleaseImmutability { return $true }
        }
        
        It "Should republish and verify immutability" {
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
            Should -Invoke Republish-GitHubRelease -Times 1
            Should -Invoke Test-ReleaseImmutability -Times 1
        }
        
        It "Should mark as manual_fix_required when republish succeeds but still mutable" {
            Mock Test-ReleaseImmutability { return $false }
            
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $issue = [ValidationIssue]::new("non_immutable_release", "error", "Release not immutable")
            $issue.Version = "v1.0.0"
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "manual_fix_required"
            $issue.Message | Should -Match "Enable 'Release immutability'"
        }
        
        It "Should mark as unfixable on 422 error" {
            Mock Republish-GitHubRelease { return @{ Success = $false; Unfixable = $true } }
            
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $issue = [ValidationIssue]::new("non_immutable_release", "error", "Release not immutable")
            $issue.Version = "v1.0.0"
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "unfixable"
        }
    }
}
