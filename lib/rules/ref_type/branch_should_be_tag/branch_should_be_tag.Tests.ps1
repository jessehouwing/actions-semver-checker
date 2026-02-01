#############################################################################
# Tests for Rule: branch_should_be_tag
#############################################################################

BeforeAll {
    $global:ProgressPreference = 'SilentlyContinue'
    
    . "$PSScriptRoot/../../../../lib/StateModel.ps1"
    . "$PSScriptRoot/../../../../lib/ValidationRules.ps1"
    . "$PSScriptRoot/../../../../lib/RemediationActions.ps1"
    . "$PSScriptRoot/branch_should_be_tag.ps1"
}

Describe "branch_should_be_tag" {
    Context "Condition" {
        It "returns patch branches when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $config = @{ 'floating-versions-use' = "tags" }
            
            $result = & $Rule_BranchShouldBeTag.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1.0.0"
        }
        
        It "returns major branches when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $config = @{ 'floating-versions-use' = "tags" }
            
            $result = & $Rule_BranchShouldBeTag.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1"
        }
        
        It "returns minor branches when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "abc123", "branch")
            $config = @{ 'floating-versions-use' = "tags" }
            
            $result = & $Rule_BranchShouldBeTag.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1.0"
        }
        
        It "returns empty array when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "abc123", "branch")
            $state.Branches += [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $config = @{ 'floating-versions-use' = "branches" }
            
            $result = & $Rule_BranchShouldBeTag.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "excludes ignored versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $ignored.IsIgnored = $true
            $state.Branches += $ignored
            $state.Branches += [VersionRef]::new("v2.0.0", "refs/heads/v2.0.0", "def456", "branch")
            $config = @{ 'floating-versions-use' = "tags" }
            
            $result = & $Rule_BranchShouldBeTag.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v2.0.0"
        }
        
        It "uses 'tags' as default when config is not set" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $config = @{}
            
            $result = & $Rule_BranchShouldBeTag.Condition $state $config
            
            $result.Count | Should -Be 1
        }
    }
    
    Context "Check" {
        It "returns false when branch exists but tag does not" {
            $state = [RepositoryState]::new()
            $branch = [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $state.Branches += $branch
            $config = @{}
            
            $result = & $Rule_BranchShouldBeTag.Check $branch $state $config
            
            $result | Should -Be $false
        }
        
        It "returns true when both branch and tag exist (let duplicate rule handle)" {
            $state = [RepositoryState]::new()
            $branch = [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Branches += $branch
            $state.Tags += $tag
            $config = @{}
            
            $result = & $Rule_BranchShouldBeTag.Check $branch $state $config
            
            $result | Should -Be $true
        }
        
        It "returns false when branch exists, tag exists but is ignored" {
            $state = [RepositoryState]::new()
            $branch = [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $tag.IsIgnored = $true
            $state.Branches += $branch
            $state.Tags += $tag
            $config = @{}
            
            $result = & $Rule_BranchShouldBeTag.Check $branch $state $config
            
            $result | Should -Be $false
        }
    }
    
    Context "CreateIssue" {
        It "creates issue with ConvertBranchToTagAction for patch branch" {
            $state = [RepositoryState]::new()
            $branch = [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $config = @{ 'floating-versions-use' = "tags" }
            
            $issue = & $Rule_BranchShouldBeTag.CreateIssue $branch $state $config
            
            $issue | Should -Not -BeNullOrEmpty
            $issue.Type | Should -Be "wrong_ref_type"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1.0.0"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "ConvertBranchToTagAction"
            $issue.RemediationAction.Version | Should -Be "v1.0.0"
        }
        
        It "creates issue with ConvertBranchToTagAction for major branch" {
            $state = [RepositoryState]::new()
            $branch = [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $config = @{ 'floating-versions-use' = "tags" }
            
            $issue = & $Rule_BranchShouldBeTag.CreateIssue $branch $state $config
            
            $issue | Should -Not -BeNullOrEmpty
            $issue.Type | Should -Be "wrong_ref_type"
            $issue.Version | Should -Be "v1"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "ConvertBranchToTagAction"
        }
        
        It "creates issue with ConvertBranchToTagAction for minor branch" {
            $state = [RepositoryState]::new()
            $branch = [VersionRef]::new("v1.0", "refs/heads/v1.0", "abc123", "branch")
            $config = @{ 'floating-versions-use' = "tags" }
            
            $issue = & $Rule_BranchShouldBeTag.CreateIssue $branch $state $config
            
            $issue | Should -Not -BeNullOrEmpty
            $issue.Type | Should -Be "wrong_ref_type"
            $issue.Version | Should -Be "v1.0"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "ConvertBranchToTagAction"
        }
    }
    
    Context "Integration with Invoke-ValidationRule" {
        It "creates issues for all problematic branches" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "abc123", "branch")
            $state.Branches += [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $config = @{ 'floating-versions-use' = "tags" }
            
            $issues = Invoke-ValidationRule -State $state -Config $config -Rules @($Rule_BranchShouldBeTag)
            
            $issues.Count | Should -Be 3
            $issues[0].Version | Should -Be "v1"
            $issues[1].Version | Should -Be "v1.0"
            $issues[2].Version | Should -Be "v1.0.0"
        }
        
        It "creates no issues when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "abc123", "branch")
            $config = @{ 'floating-versions-use' = "branches" }
            
            $issues = Invoke-ValidationRule -State $state -Config $config -Rules @($Rule_BranchShouldBeTag)
            
            $issues.Count | Should -Be 0
        }
    }
}
