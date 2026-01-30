#############################################################################
# Tests for Rule: major_tag_tracks_highest_patch
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/major_tag_tracks_highest_patch.ps1"
}

Describe "major_tag_tracks_highest_patch" {
    Context "Condition - AppliesWhen floating-versions-use is tags" {
        It "should return major tags when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'tags' }
            $result = & $Rule_MajorTagTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1"
        }
        
        It "should return empty when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_MajorTagTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should skip ignored versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $ignored.IsIgnored = $true
            $state.Tags += $ignored
            $state.IgnoreVersions = @("v1")
            
            $config = @{ 'floating-versions-use' = 'tags' }
            $result = & $Rule_MajorTagTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return multiple major tags" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v2", "refs/tags/v2", "def456", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'tags' }
            $result = & $Rule_MajorTagTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 2
        }
    }
    
    Context "Check - SHA matching" {
        It "should pass when major tag points to highest patch" {
            $state = [RepositoryState]::new()
            $majorTag = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += $majorTag
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_MajorTagTracksHighestPatch.Check $majorTag $state $config
            
            $result | Should -Be $true
        }
        
        It "should fail when major tag points to wrong SHA" {
            $state = [RepositoryState]::new()
            $majorTag = [VersionRef]::new("v1", "refs/tags/v1", "old123", "tag")
            $state.Tags += $majorTag
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_MajorTagTracksHighestPatch.Check $majorTag $state $config
            
            $result | Should -Be $false
        }
        
        It "should pass when no patches exist (nothing to track)" {
            $state = [RepositoryState]::new()
            $majorTag = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += $majorTag
            # No patch versions
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_MajorTagTracksHighestPatch.Check $majorTag $state $config
            
            $result | Should -Be $true
        }
        
        It "should track highest patch across minor versions" {
            $state = [RepositoryState]::new()
            $majorTag = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += $majorTag
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "old100", "tag")
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_MajorTagTracksHighestPatch.Check $majorTag $state $config
            
            $result | Should -Be $true
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with correct details" {
            $state = [RepositoryState]::new()
            $majorTag = [VersionRef]::new("v1", "refs/tags/v1", "old123", "tag")
            $state.Tags += $majorTag
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $issue = & $Rule_MajorTagTracksHighestPatch.CreateIssue $majorTag $state $config
            
            $issue.Type | Should -Be "incorrect_version"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1"
            $issue.CurrentSha | Should -Be "old123"
            $issue.ExpectedSha | Should -Be "abc123"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "UpdateTagAction"
        }
        
        It "should configure UpdateTagAction with force flag" {
            $state = [RepositoryState]::new()
            $majorTag = [VersionRef]::new("v2", "refs/tags/v2", "old123", "tag")
            $state.Tags += $majorTag
            $state.Tags += [VersionRef]::new("v2.5.3", "refs/tags/v2.5.3", "new456", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $issue = & $Rule_MajorTagTracksHighestPatch.CreateIssue $majorTag $state $config
            
            $issue.RemediationAction.TagName | Should -Be "v2"
            $issue.RemediationAction.Sha | Should -Be "new456"
            $issue.RemediationAction.Force | Should -Be $true
        }
    }
    
    Context "Prerelease Filtering" {
        It "should exclude prerelease patch when calculating highest (ignore-preview-releases=true)" {
            $state = [RepositoryState]::new()
            # v1 points to old stable release
            $majorTag = [VersionRef]::new("v1", "refs/tags/v1", "stable123", "tag")
            $state.Tags += $majorTag
            # v1.0.0 is stable
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "stable123", "tag")
            # v1.1.0 is prerelease (newer version but should be excluded)
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
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_MajorTagTracksHighestPatch.Check $majorTag $state $config
            
            # v1 pointing to v1.0.0 should PASS because v1.1.0 is prerelease and filtered
            $result | Should -Be $true
        }
        
        It "should include prerelease patch when ignore-preview-releases is false" {
            $state = [RepositoryState]::new()
            # v1 points to old stable release
            $majorTag = [VersionRef]::new("v1", "refs/tags/v1", "stable123", "tag")
            $state.Tags += $majorTag
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
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 'ignore-preview-releases' = $false }
            $result = & $Rule_MajorTagTracksHighestPatch.Check $majorTag $state $config
            
            # v1 pointing to v1.0.0 should FAIL because v1.1.0 is included (prerelease not filtered)
            $result | Should -Be $false
        }
        
        It "should use non-prerelease SHA in CreateIssue when ignore-preview-releases is true" {
            $state = [RepositoryState]::new()
            $majorTag = [VersionRef]::new("v1", "refs/tags/v1", "old123", "tag")
            $state.Tags += $majorTag
            # v1.0.0 is stable
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "stable456", "tag")
            # v1.1.0 is prerelease (higher version but should be excluded)
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "prerel789", "tag")
            $state.IgnoreVersions = @()
            
            # Mark v1.1.0 as prerelease via ReleaseInfo
            $prereleaseData = [PSCustomObject]@{
                tag_name = "v1.1.0"
                id = 2
                draft = $false
                prerelease = $true
                html_url = "https://github.com/test/test/releases/tag/v1.1.0"
                target_commitish = "prerel789"
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 'ignore-preview-releases' = $true }
            $issue = & $Rule_MajorTagTracksHighestPatch.CreateIssue $majorTag $state $config
            
            # Should use SHA from v1.0.0 (stable), not v1.1.0 (prerelease)
            $issue.ExpectedSha | Should -Be "stable456"
        }
    }
}
