#############################################################################
# Tests for Rule: tag_should_be_branch
#############################################################################

BeforeAll {
    $global:ProgressPreference = 'SilentlyContinue'
    
    . "$PSScriptRoot/../../../../lib/StateModel.ps1"
    . "$PSScriptRoot/../../../../lib/ValidationRules.ps1"
    . "$PSScriptRoot/../../../../lib/RemediationActions.ps1"
    . "$PSScriptRoot/tag_should_be_branch.ps1"
}

Describe "tag_should_be_branch" {
    Context "Condition" {
        It "returns major tags when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "branches" }
            
            $result = & $Rule_TagShouldBeBranch.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1"
        }
        
        It "returns minor tags when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "branches" }
            
            $result = & $Rule_TagShouldBeBranch.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1.0"
        }
        
        It "does not return patch tags when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "branches" }
            
            $result = & $Rule_TagShouldBeBranch.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "returns empty array when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "tags" }
            
            $result = & $Rule_TagShouldBeBranch.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "excludes ignored versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $ignored.IsIgnored = $true
            $state.Tags += $ignored
            $state.Tags += [VersionRef]::new("v2", "refs/tags/v2", "def456", "tag")
            $config = @{ 'floating-versions-use' = "branches" }
            
            $result = & $Rule_TagShouldBeBranch.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v2"
        }
        
        It "uses 'tags' as default (returns empty) when config is not set" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $config = @{}
            
            $result = & $Rule_TagShouldBeBranch.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "returns both major and minor tags when both exist" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v2", "refs/tags/v2", "def456", "tag")
            $config = @{ 'floating-versions-use' = "branches" }
            
            $result = & $Rule_TagShouldBeBranch.Condition $state $config
            
            $result.Count | Should -Be 3
        }
    }
    
    Context "Check" {
        It "always returns false since tag existence is the issue" {
            $state = [RepositoryState]::new()
            $tag = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $config = @{}
            
            $result = & $Rule_TagShouldBeBranch.Check $tag $state $config
            
            $result | Should -Be $false
        }
    }
    
    Context "CreateIssue" {
        It "creates issue with ConvertTagToBranchAction for major tag" {
            $state = [RepositoryState]::new()
            $tag = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "branches" }
            
            $issue = & $Rule_TagShouldBeBranch.CreateIssue $tag $state $config
            
            $issue | Should -Not -BeNullOrEmpty
            $issue.Type | Should -Be "wrong_ref_type"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "ConvertTagToBranchAction"
            $issue.RemediationAction.Version | Should -Be "v1"
        }
        
        It "creates issue with ConvertTagToBranchAction for minor tag" {
            $state = [RepositoryState]::new()
            $tag = [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "branches" }
            
            $issue = & $Rule_TagShouldBeBranch.CreateIssue $tag $state $config
            
            $issue | Should -Not -BeNullOrEmpty
            $issue.Type | Should -Be "wrong_ref_type"
            $issue.Version | Should -Be "v1.0"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "ConvertTagToBranchAction"
        }
    }
    
    Context "Integration with Invoke-ValidationRules" {
        It "creates issues for floating version tags only" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")  # Patch - should NOT trigger
            $config = @{ 'floating-versions-use' = "branches" }
            
            $issues = Invoke-ValidationRules -State $state -Config $config -Rules @($Rule_TagShouldBeBranch)
            
            $issues.Count | Should -Be 2
            $issues[0].Version | Should -Be "v1"
            $issues[1].Version | Should -Be "v1.0"
        }
        
        It "creates no issues when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "tags" }
            
            $issues = Invoke-ValidationRules -State $state -Config $config -Rules @($Rule_TagShouldBeBranch)
            
            $issues.Count | Should -Be 0
        }
    }
}
