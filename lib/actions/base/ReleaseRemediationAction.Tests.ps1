BeforeAll {
    . "$PSScriptRoot/../../StateModel.ps1"
    . "$PSScriptRoot/../../Logging.ps1"
    . "$PSScriptRoot/../../GitHubApi.ps1"
    . "$PSScriptRoot/RemediationAction.ps1"
    . "$PSScriptRoot/ReleaseRemediationAction.ps1"
    
    # Load a concrete implementation to test base class methods
    . "$PSScriptRoot/../releases/CreateReleaseAction/CreateReleaseAction.ps1"
}

Describe "ReleaseRemediationAction Base Class" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
    }
    
    Context "Constructor" {
        It "Should set TagName property" {
            # Use CreateReleaseAction as a concrete implementation
            $action = [CreateReleaseAction]::new("v1.0.0", $true)
            
            $action.TagName | Should -Be "v1.0.0"
            $action.Version | Should -Be "v1.0.0"
        }
    }
    
    Context "Issue Status Helpers" {
        It "Should mark issue as unfixable when Execute encounters 422 error" {
            # Create issue in state
            $issue = [ValidationIssue]::new("missing_release", "error", "Release missing")
            $issue.Version = "v1.0.0"
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            
            # Mock the API to return an unfixable error
            Mock New-GitHubRelease { @{ Success = $false; Unfixable = $true } }
            
            $action = [CreateReleaseAction]::new("v1.0.0", $true)
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "unfixable"
        }
        
        It "Should not return manual commands when issue is unfixable" {
            # Create unfixable issue
            $issue = [ValidationIssue]::new("missing_release", "error", "Release missing")
            $issue.Version = "v1.0.0"
            $issue.Status = "unfixable"
            $script:state.Issues = @($issue)
            
            $action = [CreateReleaseAction]::new("v1.0.0", $true)
            $commands = $action.GetManualCommands($script:state)
            
            $commands | Should -HaveCount 0
        }
        
        It "Should return manual commands when issue is not unfixable" {
            # Create pending issue
            $issue = [ValidationIssue]::new("missing_release", "error", "Release missing")
            $issue.Version = "v1.0.0"
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            
            $action = [CreateReleaseAction]::new("v1.0.0", $true)
            $commands = $action.GetManualCommands($script:state)
            
            $commands | Should -Not -BeNullOrEmpty
        }
    }
}
