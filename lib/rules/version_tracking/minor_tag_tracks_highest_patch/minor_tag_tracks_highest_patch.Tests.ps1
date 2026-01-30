#############################################################################
# Tests for Rule: minor_tag_tracks_highest_patch
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/minor_tag_tracks_highest_patch.ps1"
}

Describe "minor_tag_tracks_highest_patch" {
    Context "Condition - AppliesWhen configuration" {
        It "should return minor tags when both settings are enabled" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1.0"
        }
        
        It "should return empty when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when check-minor-version is 'none'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'none'
            }
            $result = & $Rule_MinorTagTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should skip ignored versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $ignored.IsIgnored = $true
            $state.Tags += $ignored
            $state.IgnoreVersions = @("v1.0")
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "Check - SHA matching" {
        It "should pass when minor tag points to highest patch" {
            $state = [RepositoryState]::new()
            $minorTag = [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.Tags += $minorTag
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_MinorTagTracksHighestPatch.Check $minorTag $state $config
            
            $result | Should -Be $true
        }
        
        It "should fail when minor tag points to wrong SHA" {
            $state = [RepositoryState]::new()
            $minorTag = [VersionRef]::new("v1.0", "refs/tags/v1.0", "old123", "tag")
            $state.Tags += $minorTag
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_MinorTagTracksHighestPatch.Check $minorTag $state $config
            
            $result | Should -Be $false
        }
        
        It "should pass when no patches exist (nothing to track)" {
            $state = [RepositoryState]::new()
            $minorTag = [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.Tags += $minorTag
            # No patch versions
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_MinorTagTracksHighestPatch.Check $minorTag $state $config
            
            $result | Should -Be $true
        }
        
        It "should track highest patch within minor series" {
            $state = [RepositoryState]::new()
            $minorTag = [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.Tags += $minorTag
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "old100", "tag")
            $state.Tags += [VersionRef]::new("v1.0.1", "refs/tags/v1.0.1", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "different", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 'ignore-preview-releases' = $true }
            $result = & $Rule_MinorTagTracksHighestPatch.Check $minorTag $state $config
            
            $result | Should -Be $true
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with error severity" {
            $state = [RepositoryState]::new()
            $minorTag = [VersionRef]::new("v1.0", "refs/tags/v1.0", "old123", "tag")
            $state.Tags += $minorTag
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            $issue = & $Rule_MinorTagTracksHighestPatch.CreateIssue $minorTag $state $config
            
            $issue.Type | Should -Be "incorrect_minor_version"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1.0"
            $issue.CurrentSha | Should -Be "old123"
            $issue.ExpectedSha | Should -Be "abc123"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "UpdateTagAction"
        }
        
        It "should create issue with warning severity" {
            $state = [RepositoryState]::new()
            $minorTag = [VersionRef]::new("v1.0", "refs/tags/v1.0", "old123", "tag")
            $state.Tags += $minorTag
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'warning'
            }
            $issue = & $Rule_MinorTagTracksHighestPatch.CreateIssue $minorTag $state $config
            
            $issue.Severity | Should -Be "warning"
        }
        
        It "should configure UpdateTagAction with force flag" {
            $state = [RepositoryState]::new()
            $minorTag = [VersionRef]::new("v2.1", "refs/tags/v2.1", "old123", "tag")
            $state.Tags += $minorTag
            $state.Tags += [VersionRef]::new("v2.1.5", "refs/tags/v2.1.5", "new456", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            $issue = & $Rule_MinorTagTracksHighestPatch.CreateIssue $minorTag $state $config
            
            $issue.RemediationAction.TagName | Should -Be "v2.1"
            $issue.RemediationAction.Sha | Should -Be "new456"
            $issue.RemediationAction.Force | Should -Be $true
        }
    }
    
    Context "Prerelease Filtering" {
        It "should exclude prerelease patch when calculating highest (ignore-preview-releases=true)" {
            $state = [RepositoryState]::new()
            # v1.0 points to old stable release
            $minorTag = [VersionRef]::new("v1.0", "refs/tags/v1.0", "stable123", "tag")
            $state.Tags += $minorTag
            # v1.0.0 is stable
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "stable123", "tag")
            # v1.0.1 is prerelease (newer version but should be excluded)
            $state.Tags += [VersionRef]::new("v1.0.1", "refs/tags/v1.0.1", "prerel456", "tag")
            $state.IgnoreVersions = @()
            
            # Mark v1.0.1 as prerelease via ReleaseInfo
            $prereleaseData = [PSCustomObject]@{
                tag_name = "v1.0.1"
                id = 2
                draft = $false
                prerelease = $true
                html_url = "https://github.com/test/test/releases/tag/v1.0.1"
                target_commitish = "prerel456"
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagTracksHighestPatch.Check $minorTag $state $config
            
            # v1.0 pointing to v1.0.0 should PASS because v1.0.1 is prerelease and filtered
            $result | Should -Be $true
        }
        
        It "should include prerelease patch when ignore-preview-releases is false" {
            $state = [RepositoryState]::new()
            # v1.0 points to old stable release
            $minorTag = [VersionRef]::new("v1.0", "refs/tags/v1.0", "stable123", "tag")
            $state.Tags += $minorTag
            # v1.0.0 is stable
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "stable123", "tag")
            # v1.0.1 is prerelease (should be included)
            $state.Tags += [VersionRef]::new("v1.0.1", "refs/tags/v1.0.1", "prerel456", "tag")
            $state.IgnoreVersions = @()
            
            # Mark v1.0.1 as prerelease via ReleaseInfo
            $prereleaseData = [PSCustomObject]@{
                tag_name = "v1.0.1"
                id = 2
                draft = $false
                prerelease = $true
                html_url = "https://github.com/test/test/releases/tag/v1.0.1"
                target_commitish = "prerel456"
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 
                'ignore-preview-releases' = $false
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagTracksHighestPatch.Check $minorTag $state $config
            
            # v1.0 pointing to v1.0.0 should FAIL because v1.0.1 is included (prerelease not filtered)
            $result | Should -Be $false
        }
        
        It "should use non-prerelease SHA in CreateIssue when ignore-preview-releases is true" {
            $state = [RepositoryState]::new()
            $minorTag = [VersionRef]::new("v1.0", "refs/tags/v1.0", "old123", "tag")
            $state.Tags += $minorTag
            # v1.0.0 is stable
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "stable456", "tag")
            # v1.0.1 is prerelease (higher version but should be excluded)
            $state.Tags += [VersionRef]::new("v1.0.1", "refs/tags/v1.0.1", "prerel789", "tag")
            $state.IgnoreVersions = @()
            
            # Mark v1.0.1 as prerelease via ReleaseInfo
            $prereleaseData = [PSCustomObject]@{
                tag_name = "v1.0.1"
                id = 2
                draft = $false
                prerelease = $true
                html_url = "https://github.com/test/test/releases/tag/v1.0.1"
                target_commitish = "prerel789"
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            $issue = & $Rule_MinorTagTracksHighestPatch.CreateIssue $minorTag $state $config
            
            # Should use SHA from v1.0.0 (stable), not v1.0.1 (prerelease)
            $issue.ExpectedSha | Should -Be "stable456"
        }
    }
}
