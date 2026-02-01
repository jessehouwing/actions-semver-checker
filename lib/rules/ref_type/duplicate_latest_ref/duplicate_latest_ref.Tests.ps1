#############################################################################
# Tests for Rule: duplicate_latest_ref
#############################################################################

BeforeAll {
    $global:ProgressPreference = 'SilentlyContinue'
    
    . "$PSScriptRoot/../../../../lib/StateModel.ps1"
    . "$PSScriptRoot/../../../../lib/ValidationRules.ps1"
    . "$PSScriptRoot/../../../../lib/RemediationActions.ps1"
    . "$PSScriptRoot/duplicate_latest_ref.ps1"
}

Describe "duplicate_latest_ref" {
    Context "Condition" {
        It "returns 'latest' when it exists as both tag and branch" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $state.Branches += [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicateLatestRef.Condition $state $config
            
            @($result).Count | Should -Be 1
            $result[0].Version | Should -Be "latest"
            $result[0].Tag.Version | Should -Be "latest"
            $result[0].Branch.Version | Should -Be "latest"
        }
        
        It "returns empty when only tag exists" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $config = @{}
            
            $result = & $Rule_DuplicateLatestRef.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "returns empty when only branch exists" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicateLatestRef.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "returns empty when neither exists" {
            $state = [RepositoryState]::new()
            $config = @{}
            
            $result = & $Rule_DuplicateLatestRef.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "excludes ignored latest tag" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $ignored.IsIgnored = $true
            $state.Tags += $ignored
            $state.Branches += [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            $config = @{}
            
            $result = & $Rule_DuplicateLatestRef.Condition $state $config
            
            @($result).Count | Should -Be 0
        }
        
        It "excludes ignored latest branch" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $ignored = [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            $ignored.IsIgnored = $true
            $state.Branches += $ignored
            $config = @{}
            
            $result = & $Rule_DuplicateLatestRef.Condition $state $config
            
            @($result).Count | Should -Be 0
        }
    }
    
    Context "Check" {
        It "always returns false since duplicate existence is the issue" {
            $state = [RepositoryState]::new()
            $item = @{
                Version = "latest"
                Tag = $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
                Branch = $state.Branches += [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            }
            $config = @{}
            
            $result = & $Rule_DuplicateLatestRef.Check $item $state $config
            
            $result | Should -Be $false
        }
    }
    
    Context "CreateIssue" {
        It "creates issue with DeleteBranchAction when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $item = @{
                Version = "latest"
                Tag = $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
                Branch = $state.Branches += [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            }
            $config = @{ 'floating-versions-use' = "tags" }
            
            $issue = & $Rule_DuplicateLatestRef.CreateIssue $item $state $config
            
            $issue | Should -Not -BeNullOrEmpty
            $issue.Type | Should -Be "duplicate_latest_ref"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "latest"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "DeleteBranchAction"
            $issue.RemediationAction.Version | Should -Be "latest"
        }
        
        It "creates issue with DeleteTagAction when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $item = @{
                Version = "latest"
                Tag = $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
                Branch = $state.Branches += [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            }
            $config = @{ 'floating-versions-use' = "branches" }
            
            $issue = & $Rule_DuplicateLatestRef.CreateIssue $item $state $config
            
            $issue | Should -Not -BeNullOrEmpty
            $issue.Type | Should -Be "duplicate_latest_ref"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "latest"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "DeleteTagAction"
            $issue.RemediationAction.Version | Should -Be "latest"
        }
        
        It "defaults to 'tags' mode when config not set" {
            $state = [RepositoryState]::new()
            $item = @{
                Version = "latest"
                Tag = $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
                Branch = $state.Branches += [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            }
            $config = @{}
            
            $issue = & $Rule_DuplicateLatestRef.CreateIssue $item $state $config
            
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "DeleteBranchAction"
        }
    }
    
    Context "Integration with Invoke-ValidationRule" {
        It "creates issue when latest exists as both tag and branch in tags mode" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $state.Branches += [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            $config = @{ 'floating-versions-use' = "tags" }
            
            $issues = Invoke-ValidationRule -State $state -Config $config -Rules @($Rule_DuplicateLatestRef)
            
            $issues.Count | Should -Be 1
            $issues[0].Version | Should -Be "latest"
            $issues[0].RemediationAction.GetType().Name | Should -Be "DeleteBranchAction"
        }
        
        It "creates issue when latest exists as both tag and branch in branches mode" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $state.Branches += [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            $config = @{ 'floating-versions-use' = "branches" }
            
            $issues = Invoke-ValidationRule -State $state -Config $config -Rules @($Rule_DuplicateLatestRef)
            
            $issues.Count | Should -Be 1
            $issues[0].Version | Should -Be "latest"
            $issues[0].RemediationAction.GetType().Name | Should -Be "DeleteTagAction"
        }
        
        It "creates no issues when only one ref type exists" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $config = @{}
            
            $issues = Invoke-ValidationRule -State $state -Config $config -Rules @($Rule_DuplicateLatestRef)
            
            $issues.Count | Should -Be 0
        }
    }
}
