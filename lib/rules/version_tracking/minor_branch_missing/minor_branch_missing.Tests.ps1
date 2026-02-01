#############################################################################
# Tests for Rule: minor_branch_missing
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/minor_branch_missing.ps1"
}

Describe "minor_branch_missing" {
    Context "Condition - AppliesWhen floating-versions-use is branches and check-minor-version is enabled" {
        It "should return missing minor when patch exists but minor branch doesn't" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            # No v1.0 branch
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Major | Should -Be 1
            $result[0].Minor | Should -Be 0
        }
        
        It "should not return minor when minor branch exists" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "abc123", "branch")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            # No v1.0 branch
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when check-minor-version is 'none'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            # No v1.0 branch
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'none'
            }
            $result = & $Rule_MinorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when no patches exist" {
            $state = [RepositoryState]::new()
            # No patch versions at all
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return multiple missing minors" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "def456", "tag")
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "ghi789", "tag")
            # No v1.0, v1.1, or v2.0 branches
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 3
        }
        
        It "should skip ignored patch versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $ignored.IsIgnored = $true
            $state.Tags += $ignored
            $state.IgnoreVersions = @("v1.0.0")
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should NOT return missing minor when only prerelease patches exist in that series and ignore-preview-releases is true" {
            # This test demonstrates the bug where Condition returns a missing minor branch
            # even though the only patches in that minor series are prereleases.
            
            $state = [RepositoryState]::new()
            # v1.0.0 is stable
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "stable123", "tag")
            # v1.0 branch exists
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "stable123", "branch")
            # v1 branch exists
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "stable123", "branch")
            # v1.1.0 exists but is a prerelease
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "preview456", "tag")
            $state.IgnoreVersions = @()
            
            # Mark v1.1.0 as prerelease via ReleaseInfo
            $prereleaseData = [PSCustomObject]@{
                tag_name = "v1.1.0"
                id = 2
                draft = $false
                prerelease = $true
                html_url = "https://github.com/test/test/releases/tag/v1.1.0"
                target_commitish = "preview456"
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'error'
                'ignore-preview-releases' = $true
            }
            $result = & $Rule_MinorBranchMissing.Condition $state $config
            
            # Should NOT return missing minor when only prerelease patches exist
            # because prereleases are filtered out when ignore-preview-releases is true
            $result.Count | Should -Be 0
        }
        
        It "should find patches from both tags and branches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v2.0.0", "refs/heads/v2.0.0", "def456", "branch")
            # No v1.0 or v2.0 branches
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorBranchMissing.Condition $state $config
            
            $result.Count | Should -Be 2
        }
        
        It "should handle multiple patches in same minor series correctly" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0.1", "refs/tags/v1.0.1", "abc124", "tag")
            $state.Tags += [VersionRef]::new("v1.0.2", "refs/tags/v1.0.2", "abc125", "tag")
            # No v1.0 branch
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorBranchMissing.Condition $state $config
            
            # Should only report v1.0 once despite multiple patches
            $result.Count | Should -Be 1
            $result[0].Major | Should -Be 1
            $result[0].Minor | Should -Be 0
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
            
            $issue = & $Rule_MinorBranchMissing.CreateIssue $item $state $config
            
            $issue.Type | Should -Be "missing_minor_version"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1.0"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "CreateBranchAction"
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
            
            $issue = & $Rule_MinorBranchMissing.CreateIssue $item $state $config
            
            $issue.Severity | Should -Be "warning"
        }
        
        It "should configure CreateBranchAction with highest patch SHA in minor series" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v2.1.0", "refs/tags/v2.1.0", "old123", "tag")
            $state.Tags += [VersionRef]::new("v2.1.1", "refs/tags/v2.1.1", "new456", "tag")
            $state.IgnoreVersions = @()
            
            $item = [PSCustomObject]@{ Major = 2; Minor = 1 }
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            
            $issue = & $Rule_MinorBranchMissing.CreateIssue $item $state $config
            
            $issue.RemediationAction.BranchName | Should -Be "v2.1"
            $issue.RemediationAction.Sha | Should -Be "new456"
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
            
            $issue = & $Rule_MinorBranchMissing.CreateIssue $item $state $config
            
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
            
            $issue = & $Rule_MinorBranchMissing.CreateIssue $item $state $config
            
            # Should use SHA from v1.0.1 (prerelease included)
            $issue.ExpectedSha | Should -Be "prerel456"
        }
    }
}
