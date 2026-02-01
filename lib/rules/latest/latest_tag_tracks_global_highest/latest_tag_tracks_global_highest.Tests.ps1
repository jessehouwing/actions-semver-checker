#############################################################################
# Tests for Rule: latest_tag_tracks_global_highest
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/latest_tag_tracks_global_highest.ps1"
}

Describe "latest_tag_tracks_global_highest" {
    Context "Condition - AppliesWhen floating-versions-use is tags" {
        It "should return latest tag when it exists" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'tags' }
            $result = & $Rule_LatestTagTracksGlobalHighest.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "latest"
        }
        
        It "should return empty when latest tag doesn't exist" {
            $state = [RepositoryState]::new()
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'tags' }
            $result = & $Rule_LatestTagTracksGlobalHighest.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when floating-versions-use is branches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_LatestTagTracksGlobalHighest.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should skip ignored latest tag" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $ignored.IsIgnored = $true
            $state.Tags += $ignored
            $state.IgnoreVersions = @("latest")
            
            $config = @{ 'floating-versions-use' = 'tags' }
            $result = & $Rule_LatestTagTracksGlobalHighest.Condition $state $config
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "Check - SHA matching" {
        It "should pass when latest points to highest patch" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "def456", "tag")
            $latestTag = [VersionRef]::new("latest", "refs/tags/latest", "def456", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_LatestTagTracksGlobalHighest.Check $latestTag $state $config
            
            $result | Should -Be $true
        }
        
        It "should fail when latest points to wrong SHA" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "def456", "tag")
            $latestTag = [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_LatestTagTracksGlobalHighest.Check $latestTag $state $config
            
            $result | Should -Be $false
        }
        
        It "should pass when no patches exist" {
            $state = [RepositoryState]::new()
            $latestTag = [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_LatestTagTracksGlobalHighest.Check $latestTag $state $config
            
            $result | Should -Be $true
        }
        
        It "should find patches from both tags and branches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v2.0.0", "refs/heads/v2.0.0", "ghi789", "branch")
            $latestTag = [VersionRef]::new("latest", "refs/tags/latest", "ghi789", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_LatestTagTracksGlobalHighest.Check $latestTag $state $config
            
            $result | Should -Be $true
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with correct details" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "def456", "tag")
            $latestTag = [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $issue = & $Rule_LatestTagTracksGlobalHighest.CreateIssue $latestTag $state $config
            
            $issue.Type | Should -Be "incorrect_latest_tag"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "latest"
            $issue.CurrentSha | Should -Be "abc123"
            $issue.ExpectedSha | Should -Be "def456"
            $issue.RemediationAction.GetType().Name | Should -Be "UpdateTagAction"
        }
        
        It "should configure UpdateTagAction with force flag" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "new789", "tag")
            $latestTag = [VersionRef]::new("latest", "refs/tags/latest", "old123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $issue = & $Rule_LatestTagTracksGlobalHighest.CreateIssue $latestTag $state $config
            
            $issue.RemediationAction.TagName | Should -Be "latest"
            $issue.RemediationAction.Sha | Should -Be "new789"
            $issue.RemediationAction.Force | Should -Be $true
        }
    }
    
    Context "Prerelease Filtering" {
        It "should exclude prerelease patch when calculating global highest (ignore-preview-releases=true)" {
            $state = [RepositoryState]::new()
            # latest points to old stable release
            $latestTag = [VersionRef]::new("latest", "refs/tags/latest", "stable123", "tag")
            $state.Tags += $latestTag
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
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_LatestTagTracksGlobalHighest.Check $latestTag $state $config
            
            # latest pointing to v1.0.0 should PASS because v2.0.0 is prerelease and filtered
            $result | Should -Be $true
        }
        
        It "should include prerelease patch when ignore-preview-releases is false" {
            $state = [RepositoryState]::new()
            # latest points to old stable release
            $latestTag = [VersionRef]::new("latest", "refs/tags/latest", "stable123", "tag")
            $state.Tags += $latestTag
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
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 'ignore-preview-releases' = $false }
            $result = & $Rule_LatestTagTracksGlobalHighest.Check $latestTag $state $config
            
            # latest pointing to v1.0.0 should FAIL because v2.0.0 is included (prerelease not filtered)
            $result | Should -Be $false
        }
        
        It "should use non-prerelease SHA in CreateIssue when ignore-preview-releases is true" {
            $state = [RepositoryState]::new()
            $latestTag = [VersionRef]::new("latest", "refs/tags/latest", "old123", "tag")
            $state.Tags += $latestTag
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
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 'ignore-preview-releases' = $true }
            $issue = & $Rule_LatestTagTracksGlobalHighest.CreateIssue $latestTag $state $config
            
            # Should use SHA from v1.0.0 (stable), not v2.0.0 (prerelease)
            $issue.ExpectedSha | Should -Be "stable456"
        }
    }
}
