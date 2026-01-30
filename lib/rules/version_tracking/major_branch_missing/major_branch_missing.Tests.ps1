#############################################################################
# Tests for Rule: major_branch_missing
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/major_branch_missing.ps1"
}

Describe "major_branch_missing" {
    Context "Condition - AppliesWhen floating-versions-use is branches" {
        It "should return missing major when patch exists but major branch doesn't" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            # No v1 branch
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_MajorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Major | Should -Be 1
        }
        
        It "should not return major when major branch exists" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_MajorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            # No v1 branch
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'tags' }
            $result = & $Rule_MajorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when no patches exist" {
            $state = [RepositoryState]::new()
            # No patch versions at all
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_MajorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return multiple missing majors" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "def456", "tag")
            # No v1 or v2 branches
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_MajorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 2
        }
        
        It "should skip ignored patch versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $ignored.IsIgnored = $true
            $state.Tags += $ignored
            $state.IgnoreVersions = @("v1.0.0")
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_MajorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should find patches from both tags and branches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v2.0.0", "refs/heads/v2.0.0", "def456", "branch")
            # No v1 or v2 major branches
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_MajorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 2
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with correct details" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $item = [PSCustomObject]@{ Major = 1 }
            $config = @{ 'ignore-preview-releases' = $true }
            
            $issue = & $Rule_MajorBranchMissing.CreateIssue $item $state $config
            
            $issue.Type | Should -Be "missing_major_version"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1"
            $issue.ExpectedSha | Should -Be "abc123"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "CreateBranchAction"
        }
        
        It "should configure CreateBranchAction with highest patch SHA" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "old123", "tag")
            $state.Tags += [VersionRef]::new("v2.1.0", "refs/tags/v2.1.0", "new456", "tag")
            $state.IgnoreVersions = @()
            
            $item = [PSCustomObject]@{ Major = 2 }
            $config = @{ 'ignore-preview-releases' = $true }
            
            $issue = & $Rule_MajorBranchMissing.CreateIssue $item $state $config
            
            $issue.RemediationAction.BranchName | Should -Be "v2"
            $issue.RemediationAction.Sha | Should -Be "new456"
        }
    }
    
    Context "Prerelease Filtering" {
        It "should use non-prerelease SHA in CreateIssue when ignore-preview-releases is true" {
            $state = [RepositoryState]::new()
            # v1.0.0 is stable
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "stable123", "tag")
            # v1.1.0 is prerelease (higher version but should be excluded)
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "prerel456", "tag")
            $state.IgnoreVersions = @()
            
            # Mark v1.1.0 as prerelease via ReleaseInfo
            $prereleaseData = [PSCustomObject]@{
                tag_name = "v1.1.0"
                id = 2
                draft = $false
                prerelease = $true
                html_url = "https://github.com/test/test/releases/tag/v1.1.0"
                target_commitish = "prerel456"
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $item = [PSCustomObject]@{ Major = 1 }
            $config = @{ 'ignore-preview-releases' = $true }
            
            $issue = & $Rule_MajorBranchMissing.CreateIssue $item $state $config
            
            # Should use SHA from v1.0.0 (stable), not v1.1.0 (prerelease)
            $issue.ExpectedSha | Should -Be "stable123"
        }
        
        It "should use prerelease SHA in CreateIssue when ignore-preview-releases is false" {
            $state = [RepositoryState]::new()
            # v1.0.0 is stable
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "stable123", "tag")
            # v1.1.0 is prerelease (should be included)
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "prerel456", "tag")
            $state.IgnoreVersions = @()
            
            # Mark v1.1.0 as prerelease via ReleaseInfo
            $prereleaseData = [PSCustomObject]@{
                tag_name = "v1.1.0"
                id = 2
                draft = $false
                prerelease = $true
                html_url = "https://github.com/test/test/releases/tag/v1.1.0"
                target_commitish = "prerel456"
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $item = [PSCustomObject]@{ Major = 1 }
            $config = @{ 'ignore-preview-releases' = $false }
            
            $issue = & $Rule_MajorBranchMissing.CreateIssue $item $state $config
            
            # Should use SHA from v1.1.0 (prerelease included)
            $issue.ExpectedSha | Should -Be "prerel456"
        }
    }
}
