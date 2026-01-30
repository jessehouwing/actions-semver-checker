#############################################################################
# Tests for Rule: latest_branch_missing
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/latest_branch_missing.ps1"
}

Describe "latest_branch_missing" {
    Context "Condition - AppliesWhen floating-versions-use is branches" {
        It "should return missing latest when patches exist but latest branch doesn't" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_LatestBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "latest"
        }
        
        It "should return empty when latest branch exists" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_LatestBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when floating-versions-use is tags" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'tags' }
            $result = & $Rule_LatestBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when no patches exist" {
            $state = [RepositoryState]::new()
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_LatestBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should find patches from both tags and branches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v2.0.0", "refs/heads/v2.0.0", "def456", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_LatestBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 1
        }
    }
    
    Context "CreateIssue" {
        It "should create warning issue with correct details" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $item = [PSCustomObject]@{ Version = 'latest' }
            $config = @{ 'ignore-preview-releases' = $true }
            
            $issue = & $Rule_LatestBranchMissing.CreateIssue $item $state $config
            
            $issue.Type | Should -Be "missing_latest_branch"
            $issue.Severity | Should -Be "warning"
            $issue.Version | Should -Be "latest"
            $issue.ExpectedSha | Should -Be "abc123"
            $issue.RemediationAction.GetType().Name | Should -Be "CreateBranchAction"
        }
        
        It "should configure CreateBranchAction with highest patch SHA" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "old123", "tag")
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "new456", "tag")
            $state.IgnoreVersions = @()
            
            $item = [PSCustomObject]@{ Version = 'latest' }
            $config = @{ 'ignore-preview-releases' = $true }
            
            $issue = & $Rule_LatestBranchMissing.CreateIssue $item $state $config
            
            $issue.RemediationAction.BranchName | Should -Be "latest"
            $issue.RemediationAction.Sha | Should -Be "new456"
        }
    }
    
    Context "Prerelease Filtering" {
        It "should exclude prerelease patch when determining SHA for new latest branch (ignore-preview-releases=true)" {
            $state = [RepositoryState]::new()
            # v1.0.0 is stable
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "stable123", "tag")
            # v2.0.0 is prerelease (newer version but should be excluded)
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "prerel456", "tag")
            $state.IgnoreVersions = @()
            
            # Mark v2.0.0 as prerelease via ReleaseInfo
            $prereleaseData = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 2
                draft = $false
                prerelease = $true
                html_url = "https://github.com/test/test/releases/tag/v2.0.0"
                target_commitish = "prerel456"
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $item = [PSCustomObject]@{ Version = 'latest' }
            $config = @{ 'ignore-preview-releases' = $true }
            
            $issue = & $Rule_LatestBranchMissing.CreateIssue $item $state $config
            
            # Should use SHA from v1.0.0 (stable), not v2.0.0 (prerelease)
            $issue.ExpectedSha | Should -Be "stable123"
            $issue.RemediationAction.Sha | Should -Be "stable123"
        }
        
        It "should include prerelease patch when ignore-preview-releases is false" {
            $state = [RepositoryState]::new()
            # v1.0.0 is stable
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "stable123", "tag")
            # v2.0.0 is prerelease (should be included)
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "prerel456", "tag")
            $state.IgnoreVersions = @()
            
            # Mark v2.0.0 as prerelease via ReleaseInfo
            $prereleaseData = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 2
                draft = $false
                prerelease = $true
                html_url = "https://github.com/test/test/releases/tag/v2.0.0"
                target_commitish = "prerel456"
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $item = [PSCustomObject]@{ Version = 'latest' }
            $config = @{ 'ignore-preview-releases' = $false }
            
            $issue = & $Rule_LatestBranchMissing.CreateIssue $item $state $config
            
            # Should use SHA from v2.0.0 (prerelease included)
            $issue.ExpectedSha | Should -Be "prerel456"
            $issue.RemediationAction.Sha | Should -Be "prerel456"
        }
    }
}
