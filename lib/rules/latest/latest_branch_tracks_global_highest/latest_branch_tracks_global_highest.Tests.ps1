#############################################################################
# Tests for Rule: latest_branch_tracks_global_highest
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/latest_branch_tracks_global_highest.ps1"
}

Describe "latest_branch_tracks_global_highest" {
    Context "Condition - AppliesWhen floating-versions-use is branches" {
        It "should return latest branch when it exists" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_LatestBranchTracksGlobalHighest.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "latest"
        }
        
        It "should return empty when latest branch doesn't exist" {
            $state = [RepositoryState]::new()
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_LatestBranchTracksGlobalHighest.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when floating-versions-use is tags" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'tags' }
            $result = & $Rule_LatestBranchTracksGlobalHighest.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should skip ignored latest branch" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            $ignored.IsIgnored = $true
            $state.Branches += $ignored
            $state.IgnoreVersions = @("latest")
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_LatestBranchTracksGlobalHighest.Condition $state $config
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "Check - SHA matching" {
        It "should pass when latest points to highest patch" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "def456", "tag")
            $latestBranch = [VersionRef]::new("latest", "refs/heads/latest", "def456", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_LatestBranchTracksGlobalHighest.Check $latestBranch $state $config
            
            $result | Should -Be $true
        }
        
        It "should fail when latest points to wrong SHA" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "def456", "tag")
            $latestBranch = [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_LatestBranchTracksGlobalHighest.Check $latestBranch $state $config
            
            $result | Should -Be $false
        }
        
        It "should pass when no patches exist" {
            $state = [RepositoryState]::new()
            $latestBranch = [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_LatestBranchTracksGlobalHighest.Check $latestBranch $state $config
            
            $result | Should -Be $true
        }
        
        It "should find patches from both tags and branches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v2.0.0", "refs/heads/v2.0.0", "ghi789", "branch")
            $latestBranch = [VersionRef]::new("latest", "refs/heads/latest", "ghi789", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_LatestBranchTracksGlobalHighest.Check $latestBranch $state $config
            
            $result | Should -Be $true
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with correct details" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "def456", "tag")
            $latestBranch = [VersionRef]::new("latest", "refs/heads/latest", "abc123", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $issue = & $Rule_LatestBranchTracksGlobalHighest.CreateIssue $latestBranch $state $config
            
            $issue.Type | Should -Be "incorrect_latest_branch"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "latest"
            $issue.CurrentSha | Should -Be "abc123"
            $issue.ExpectedSha | Should -Be "def456"
            $issue.RemediationAction.GetType().Name | Should -Be "UpdateBranchAction"
        }
        
        It "should configure UpdateBranchAction with correct SHA" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "new789", "tag")
            $latestBranch = [VersionRef]::new("latest", "refs/heads/latest", "old123", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $issue = & $Rule_LatestBranchTracksGlobalHighest.CreateIssue $latestBranch $state $config
            
            $issue.RemediationAction.BranchName | Should -Be "latest"
            $issue.RemediationAction.Sha | Should -Be "new789"
            $issue.RemediationAction.Force | Should -Be $true
        }
    }
    
    Context "Prerelease Filtering" {
        It "should exclude prerelease patch when calculating global highest (ignore-preview-releases=true)" {
            $state = [RepositoryState]::new()
            # latest branch points to old stable release
            $latestBranch = [VersionRef]::new("latest", "refs/heads/latest", "stable123", "branch")
            $state.Branches += $latestBranch
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
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_LatestBranchTracksGlobalHighest.Check $latestBranch $state $config
            
            # latest branch pointing to v1.0.0 should PASS because v2.0.0 is prerelease and filtered
            $result | Should -Be $true
        }
        
        It "should include prerelease patch when ignore-preview-releases is false" {
            $state = [RepositoryState]::new()
            # latest branch points to old stable release
            $latestBranch = [VersionRef]::new("latest", "refs/heads/latest", "stable123", "branch")
            $state.Branches += $latestBranch
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
            
            $config = @{ 'ignore-preview-releases' = $false }
            $result = & $Rule_LatestBranchTracksGlobalHighest.Check $latestBranch $state $config
            
            # latest branch pointing to v1.0.0 should FAIL because v2.0.0 is included (prerelease not filtered)
            $result | Should -Be $false
        }
        
        It "should use non-prerelease SHA in CreateIssue when ignore-preview-releases is true" {
            $state = [RepositoryState]::new()
            $latestBranch = [VersionRef]::new("latest", "refs/heads/latest", "old123", "branch")
            $state.Branches += $latestBranch
            # v1.0.0 is stable
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "stable456", "tag")
            # v2.0.0 is prerelease (higher version but should be excluded)
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "prerel789", "tag")
            $state.IgnoreVersions = @()
            
            # Mark v2.0.0 as prerelease via ReleaseInfo
            $prereleaseData = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 2
                draft = $false
                prerelease = $true
                html_url = "https://github.com/test/test/releases/tag/v2.0.0"
                target_commitish = "prerel789"
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 'ignore-preview-releases' = $true }
            $issue = & $Rule_LatestBranchTracksGlobalHighest.CreateIssue $latestBranch $state $config
            
            # Should use SHA from v1.0.0 (stable), not v2.0.0 (prerelease)
            $issue.ExpectedSha | Should -Be "stable456"
        }
    }
}
