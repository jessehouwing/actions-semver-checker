#############################################################################
# Tests for Rule: duplicate_patch_version_ref
#############################################################################

BeforeAll {
    $global:ProgressPreference = 'SilentlyContinue'
    
    # Note: StateModel.ps1 is loaded by ValidationRules.ps1, no need to load it separately
    . "$PSScriptRoot/../../../../lib/ValidationRules.ps1"
    . "$PSScriptRoot/../../../../lib/RemediationActions.ps1"
    . "$PSScriptRoot/duplicate_patch_version_ref.ps1"
}

Describe "duplicate_patch_version_ref" {
    Context "Condition" {
        It "returns patch versions that exist as both tag and branch" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicatePatchVersionRef.Condition $state $config
            
            @($result).Count | Should -Be 1
            $result[0].Version | Should -Be "v1.0.0"
            $result[0].Tag.Version | Should -Be "v1.0.0"
            $result[0].Branch.Version | Should -Be "v1.0.0"
        }
        
        It "returns empty when only tag exists" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $config = @{}
            
            $result = & $Rule_DuplicatePatchVersionRef.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "returns empty when only branch exists" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicatePatchVersionRef.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "excludes ignored versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $ignored.IsIgnored = $true
            $state.Tags += $ignored
            $state.Branches += [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicatePatchVersionRef.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "excludes ignored branches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $ignoredBranch = [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $ignoredBranch.IsIgnored = $true
            $state.Branches += $ignoredBranch
            $config = @{}
            
            $result = & $Rule_DuplicatePatchVersionRef.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "finds multiple duplicate patches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "def456", "tag")
            $state.Branches += [VersionRef]::new("v2.0.0", "refs/heads/v2.0.0", "def456", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicatePatchVersionRef.Condition $state $config
            
            $result.Count | Should -Be 2
        }
        
        It "does not return floating versions" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "def456", "tag")
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "def456", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicatePatchVersionRef.Condition $state $config
            
            # Floating versions are handled by duplicate_floating_version_ref rule
            $result.Count | Should -Be 0
        }
    }
    
    Context "Check" {
        It "always returns false since duplicate existence is the issue" {
            $state = [RepositoryState]::new()
            $item = @{
                Version = "v1.0.0"
                Tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
                Branch = [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            }
            $config = @{}
            
            $result = & $Rule_DuplicatePatchVersionRef.Check $item $state $config
            
            $result | Should -Be $false
        }
    }
    
    Context "CreateIssue" {
        It "creates issue with DeleteBranchAction (always delete branch)" {
            $state = [RepositoryState]::new()
            $item = @{
                Version = "v1.0.0"
                Tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
                Branch = [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            }
            $config = @{ 'floating-versions-use' = "tags" }
            
            $issue = & $Rule_DuplicatePatchVersionRef.CreateIssue $item $state $config
            
            $issue | Should -Not -BeNullOrEmpty
            $issue.Type | Should -Be "duplicate_patch_ref"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1.0.0"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "DeleteBranchAction"
            $issue.RemediationAction.Version | Should -Be "v1.0.0"
        }
        
        It "always deletes branch regardless of floating-versions-use setting" {
            $state = [RepositoryState]::new()
            $item = @{
                Version = "v1.0.0"
                Tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
                Branch = [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            }
            $config = @{ 'floating-versions-use' = "branches" }
            
            $issue = & $Rule_DuplicatePatchVersionRef.CreateIssue $item $state $config
            
            $issue | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "DeleteBranchAction"
        }
    }
    
    Context "Integration with Invoke-ValidationRules" {
        It "creates issues for all duplicate patches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "def456", "tag")
            $state.Branches += [VersionRef]::new("v2.0.0", "refs/heads/v2.0.0", "def456", "branch")
            $config = @{ 'floating-versions-use' = "tags" }
            
            $issues = Invoke-ValidationRules -State $state -Config $config -Rules @($Rule_DuplicatePatchVersionRef)
            
            $issues.Count | Should -Be 2
            $issues[0].Version | Should -Be "v1.0.0"
            $issues[1].Version | Should -Be "v2.0.0"
        }
        
        It "creates no issues when no duplicates exist" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "def456", "tag")
            $config = @{}
            
            $issues = Invoke-ValidationRules -State $state -Config $config -Rules @($Rule_DuplicatePatchVersionRef)
            
            $issues.Count | Should -Be 0
        }
    }
}
