#############################################################################
# Tests for Rule: duplicate_floating_version_ref
#############################################################################

BeforeAll {
    $global:ProgressPreference = 'SilentlyContinue'
    
    . "$PSScriptRoot/../../../../lib/StateModel.ps1"
    . "$PSScriptRoot/../../../../lib/ValidationRules.ps1"
    . "$PSScriptRoot/../../../../lib/RemediationActions.ps1"
    . "$PSScriptRoot/duplicate_floating_version_ref.ps1"
}

Describe "duplicate_floating_version_ref" {
    Context "Condition" {
        It "returns versions that exist as both tag and branch" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicateFloatingVersionRef.Condition $state $config
            
            @($result).Count | Should -Be 1
            $result[0].Version | Should -Be "v1"
            $result[0].Tag.Version | Should -Be "v1"
            $result[0].Branch.Version | Should -Be "v1"
        }
        
        It "returns empty when only tag exists" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $config = @{}
            
            $result = & $Rule_DuplicateFloatingVersionRef.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "returns empty when only branch exists" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicateFloatingVersionRef.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "works for minor versions" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "def456", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicateFloatingVersionRef.Condition $state $config
            
            @($result).Count | Should -Be 1
            $result[0].Version | Should -Be "v1.0"
        }
        
        It "excludes ignored versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $ignored.IsIgnored = $true
            $state.Tags += $ignored
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicateFloatingVersionRef.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "finds multiple duplicates" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.Tags += [VersionRef]::new("v2", "refs/tags/v2", "def456", "tag")
            $state.Branches += [VersionRef]::new("v2", "refs/heads/v2", "def456", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicateFloatingVersionRef.Condition $state $config
            
            $result.Count | Should -Be 2
        }
        
        It "does not return patch versions" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicateFloatingVersionRef.Condition $state $config
            
            # Patch versions are handled by branch_should_be_tag rule
            $result.Count | Should -Be 0
        }
    }
    
    Context "Check" {
        It "always returns false since duplicate existence is the issue" {
            $state = [RepositoryState]::new()
            $item = @{
                Version = "v1"
                Tag = $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
                Branch = $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            }
            $config = @{}
            
            $result = & $Rule_DuplicateFloatingVersionRef.Check $item $state $config
            
            $result | Should -Be $false
        }
    }
    
    Context "CreateIssue" {
        It "creates issue with DeleteBranchAction when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $item = @{
                Version = "v1"
                Tag = $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
                Branch = $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            }
            $config = @{ 'floating-versions-use' = "tags" }
            
            $issue = & $Rule_DuplicateFloatingVersionRef.CreateIssue $item $state $config
            
            $issue | Should -Not -BeNullOrEmpty
            $issue.Type | Should -Be "duplicate_ref"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "DeleteBranchAction"
            $issue.RemediationAction.Version | Should -Be "v1"
        }
        
        It "creates issue with DeleteTagAction when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $item = @{
                Version = "v1"
                Tag = $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
                Branch = $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            }
            $config = @{ 'floating-versions-use' = "branches" }
            
            $issue = & $Rule_DuplicateFloatingVersionRef.CreateIssue $item $state $config
            
            $issue | Should -Not -BeNullOrEmpty
            $issue.Type | Should -Be "duplicate_ref"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "DeleteTagAction"
            $issue.RemediationAction.Version | Should -Be "v1"
        }
        
        It "defaults to 'tags' mode when config not set" {
            $state = [RepositoryState]::new()
            $item = @{
                Version = "v1"
                Tag = $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
                Branch = $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            }
            $config = @{}
            
            $issue = & $Rule_DuplicateFloatingVersionRef.CreateIssue $item $state $config
            
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "DeleteBranchAction"
        }
    }
    
    Context "Integration with Invoke-ValidationRule" {
        It "creates issues for all duplicate floating versions in tags mode" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "def456", "tag")
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "def456", "branch")
            $config = @{ 'floating-versions-use' = "tags" }
            
            $issues = Invoke-ValidationRule -State $state -Config $config -Rules @($Rule_DuplicateFloatingVersionRef)
            
            $issues.Count | Should -Be 2
            $issues[0].RemediationAction.GetType().Name | Should -Be "DeleteBranchAction"
            $issues[1].RemediationAction.GetType().Name | Should -Be "DeleteBranchAction"
        }
        
        It "creates issues for all duplicate floating versions in branches mode" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.Tags += [VersionRef]::new("v2", "refs/tags/v2", "def456", "tag")
            $state.Branches += [VersionRef]::new("v2", "refs/heads/v2", "def456", "branch")
            $config = @{ 'floating-versions-use' = "branches" }
            
            $issues = Invoke-ValidationRule -State $state -Config $config -Rules @($Rule_DuplicateFloatingVersionRef)
            
            $issues.Count | Should -Be 2
            $issues[0].RemediationAction.GetType().Name | Should -Be "DeleteTagAction"
            $issues[1].RemediationAction.GetType().Name | Should -Be "DeleteTagAction"
        }
        
        It "creates no issues when no duplicates exist" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v2", "refs/heads/v2", "def456", "branch")
            $config = @{}
            
            $issues = Invoke-ValidationRule -State $state -Config $config -Rules @($Rule_DuplicateFloatingVersionRef)
            
            $issues.Count | Should -Be 0
        }
    }
}
