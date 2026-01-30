#############################################################################
# Tests for Rule: minor_tag_missing
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/minor_tag_missing.ps1"
}

Describe "minor_tag_missing" {
    Context "Condition - AppliesWhen floating-versions-use is tags and check-minor-version is enabled" {
        It "should return missing minor when patch exists but minor tag doesn't" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            # No v1.0 tag
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Major | Should -Be 1
            $result[0].Minor | Should -Be 0
        }
        
        It "should not return minor when minor tag exists" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            # No v1.0 tag
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when check-minor-version is 'none'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            # No v1.0 tag
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'none'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when no patches exist" {
            $state = [RepositoryState]::new()
            # No patch versions at all
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return multiple missing minors" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "def456", "tag")
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "ghi789", "tag")
            # No v1.0, v1.1, or v2.0 tags
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            $result.Count | Should -Be 3
        }
        
        It "should skip ignored patch versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $ignored.IsIgnored = $true
            $state.Tags += $ignored
            $state.IgnoreVersions = @("v1.0.0")
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should find patches from both tags and branches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v2.0.0", "refs/heads/v2.0.0", "def456", "branch")
            # No v1.0 or v2.0 tags
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            $result.Count | Should -Be 2
        }
        
        It "should handle multiple patches in same minor series correctly" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0.1", "refs/tags/v1.0.1", "abc124", "tag")
            $state.Tags += [VersionRef]::new("v1.0.2", "refs/tags/v1.0.2", "abc125", "tag")
            # No v1.0 tag
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            # Should only report v1.0 once despite multiple patches
            $result.Count | Should -Be 1
            $result[0].Major | Should -Be 1
            $result[0].Minor | Should -Be 0
        }
        
        It "should return v{major}.0 when major tag exists without patches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "major123", "tag")
            # No v1.x.x patches exist
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Major | Should -Be 1
            $result[0].Minor | Should -Be 0
            $result[0].SourceSha | Should -Be "major123"
        }
        
        It "should not return v{major}.0 when major tag has patches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "major123", "tag")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "patch456", "tag")
            # Patch exists, so Case 1 applies - missing minor should be from patch, not major tag
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            # Should still find v1.0 missing from Case 1 (patch exists)
            $result.Count | Should -Be 1
            $result[0].Major | Should -Be 1
            $result[0].Minor | Should -Be 0
            # Case 1 doesn't set SourceSha (it uses highestPatch lookup in CreateIssue)
            $result[0].PSObject.Properties.Name | Should -Not -Contain "SourceSha"
            
            # Verify CreateIssue uses patch SHA (v1.0.0), not major tag SHA (v1)
            $config.'ignore-preview-releases' = $true
            $issue = & $Rule_MinorTagMissing.CreateIssue $result[0] $state $config
            $issue.ExpectedSha | Should -Be "patch456"
            $issue.RemediationAction.Sha | Should -Be "patch456"
        }
        
        It "should not return v{major}.0 when minor tag already exists" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "major123", "tag")
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "minor456", "tag")
            # Major tag exists, minor tag exists, no patches
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should handle multiple major tags without patches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "major1", "tag")
            $state.Tags += [VersionRef]::new("v2", "refs/tags/v2", "major2", "tag")
            # No patches for either major
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            $result.Count | Should -Be 2
            $v1Result = $result | Where-Object { $_.Major -eq 1 }
            $v2Result = $result | Where-Object { $_.Major -eq 2 }
            $v1Result.Minor | Should -Be 0
            $v1Result.SourceSha | Should -Be "major1"
            $v2Result.Minor | Should -Be 0
            $v2Result.SourceSha | Should -Be "major2"
        }
        
        It "should skip ignored major tags" {
            $state = [RepositoryState]::new()
            $ignoredMajor = [VersionRef]::new("v1", "refs/tags/v1", "major123", "tag")
            $ignoredMajor.IsIgnored = $true
            $state.Tags += $ignoredMajor
            $state.IgnoreVersions = @("v1")
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorTagMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with correct details" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $item = [PSCustomObject]@{ Major = 1; Minor = 0 }
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            
            $issue = & $Rule_MinorTagMissing.CreateIssue $item $state $config
            
            $issue.Type | Should -Be "missing_minor_version"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1.0"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "CreateTagAction"
        }
        
        It "should create warning severity when check-minor-version is warning" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $item = [PSCustomObject]@{ Major = 1; Minor = 0 }
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'warning'
            }
            
            $issue = & $Rule_MinorTagMissing.CreateIssue $item $state $config
            
            $issue.Severity | Should -Be "warning"
        }
        
        It "should configure CreateTagAction with highest patch SHA in minor series" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v2.1.0", "refs/tags/v2.1.0", "old123", "tag")
            $state.Tags += [VersionRef]::new("v2.1.1", "refs/tags/v2.1.1", "new456", "tag")
            $state.IgnoreVersions = @()
            
            $item = [PSCustomObject]@{ Major = 2; Minor = 1 }
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            
            $issue = & $Rule_MinorTagMissing.CreateIssue $item $state $config
            
            $issue.RemediationAction.TagName | Should -Be "v2.1"
            $issue.RemediationAction.Sha | Should -Be "new456"
        }
        
        It "should use SourceSha when major tag exists without patches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "major123", "tag")
            # No patches exist
            $state.IgnoreVersions = @()
            
            # Item from Condition includes SourceSha for major tag case
            $item = [PSCustomObject]@{ Major = 1; Minor = 0; SourceSha = "major123" }
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            
            $issue = & $Rule_MinorTagMissing.CreateIssue $item $state $config
            
            $issue.Type | Should -Be "missing_minor_version"
            $issue.Version | Should -Be "v1.0"
            $issue.ExpectedSha | Should -Be "major123"
            $issue.RemediationAction.TagName | Should -Be "v1.0"
            $issue.RemediationAction.Sha | Should -Be "major123"
        }
        
        It "should fallback to major tag lookup when no SourceSha and no patches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "major123", "tag")
            # No patches exist
            $state.IgnoreVersions = @()
            
            # Item without SourceSha (edge case - shouldn't normally happen with updated Condition)
            $item = [PSCustomObject]@{ Major = 1; Minor = 0 }
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            
            $issue = & $Rule_MinorTagMissing.CreateIssue $item $state $config
            
            $issue.Type | Should -Be "missing_minor_version"
            $issue.Version | Should -Be "v1.0"
            $issue.ExpectedSha | Should -Be "major123"
            $issue.RemediationAction.Sha | Should -Be "major123"
        }
    }
    
    Context "Prerelease Filtering" {
        It "should use non-prerelease SHA in CreateIssue when ignore-preview-releases is true" {
            $state = [RepositoryState]::new()
            # v1.0.0 is stable
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "stable123", "tag")
            # v1.0.1 is prerelease (higher version in same minor series but should be excluded)
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
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $item = [PSCustomObject]@{ Major = 1; Minor = 0 }
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            
            $issue = & $Rule_MinorTagMissing.CreateIssue $item $state $config
            
            # Should use SHA from v1.0.0 (stable), not v1.0.1 (prerelease)
            $issue.ExpectedSha | Should -Be "stable123"
        }
        
        It "should use prerelease SHA in CreateIssue when ignore-preview-releases is false" {
            $state = [RepositoryState]::new()
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
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $item = [PSCustomObject]@{ Major = 1; Minor = 0 }
            $config = @{ 
                'ignore-preview-releases' = $false
                'check-minor-version' = 'error'
            }
            
            $issue = & $Rule_MinorTagMissing.CreateIssue $item $state $config
            
            # Should use SHA from v1.0.1 (prerelease included)
            $issue.ExpectedSha | Should -Be "prerel456"
        }
    }
}
