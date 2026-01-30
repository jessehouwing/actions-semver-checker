#############################################################################
# Tests for Rule: minor_branch_tracks_highest_patch
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/minor_branch_tracks_highest_patch.ps1"
}

Describe "minor_branch_tracks_highest_patch" {
    Context "Condition - AppliesWhen configuration" {
        It "should return minor branches when both settings are enabled" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "abc123", "branch")
            $state.Branches += [VersionRef]::new("v1.1", "refs/heads/v1.1", "def456", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorBranchTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 2
        }
        
        It "should return empty when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "abc123", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorBranchTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when check-minor-version is 'none'" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "abc123", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'none'
            }
            $result = & $Rule_MinorBranchTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should skip ignored versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1.0", "refs/heads/v1.0", "abc123", "branch")
            $ignored.IsIgnored = $true
            $state.Branches += $ignored
            $state.Branches += [VersionRef]::new("v1.1", "refs/heads/v1.1", "def456", "branch")
            $state.IgnoreVersions = @("v1.0")
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorBranchTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 1
        }
    }
    
    Context "Check - SHA matching" {
        It "should pass when minor branch points to highest patch" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "abc123", "branch")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $minorBranch = $state.Branches[0]
            $config = @{ 'ignore-preview-releases' = $true }
            
            $result = & $Rule_MinorBranchTracksHighestPatch.Check $minorBranch $state $config
            
            $result | Should -Be $true
        }
        
        It "should fail when minor branch points to wrong SHA" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "old123", "branch")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $minorBranch = $state.Branches[0]
            $config = @{ 'ignore-preview-releases' = $true }
            
            $result = & $Rule_MinorBranchTracksHighestPatch.Check $minorBranch $state $config
            
            $result | Should -Be $false
        }
        
        It "should pass when no patches exist (nothing to track)" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "abc123", "branch")
            $state.IgnoreVersions = @()
            
            $minorBranch = $state.Branches[0]
            $config = @{ 'ignore-preview-releases' = $true }
            
            $result = & $Rule_MinorBranchTracksHighestPatch.Check $minorBranch $state $config
            
            $result | Should -Be $true
        }
        
        It "should track highest patch within minor series" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "latest", "branch")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "old123", "tag")
            $state.Tags += [VersionRef]::new("v1.0.1", "refs/tags/v1.0.1", "latest", "tag")
            $state.IgnoreVersions = @()
            
            $minorBranch = $state.Branches[0]
            $config = @{ 'ignore-preview-releases' = $true }
            
            $result = & $Rule_MinorBranchTracksHighestPatch.Check $minorBranch $state $config
            
            $result | Should -Be $true
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with error severity" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "old123", "branch")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "new456", "tag")
            $state.IgnoreVersions = @()
            
            $minorBranch = $state.Branches[0]
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            
            $issue = & $Rule_MinorBranchTracksHighestPatch.CreateIssue $minorBranch $state $config
            
            $issue.Type | Should -Be "incorrect_minor_version"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1.0"
            $issue.RemediationAction.GetType().Name | Should -Be "UpdateBranchAction"
        }
        
        It "should create issue with warning severity" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1.0", "refs/heads/v1.0", "old123", "branch")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "new456", "tag")
            $state.IgnoreVersions = @()
            
            $minorBranch = $state.Branches[0]
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'warning'
            }
            
            $issue = & $Rule_MinorBranchTracksHighestPatch.CreateIssue $minorBranch $state $config
            
            $issue.Severity | Should -Be "warning"
        }
        
        It "should configure UpdateBranchAction with correct SHA" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v2.1", "refs/heads/v2.1", "old123", "branch")
            $state.Tags += [VersionRef]::new("v2.1.0", "refs/tags/v2.1.0", "old456", "tag")
            $state.Tags += [VersionRef]::new("v2.1.1", "refs/tags/v2.1.1", "new789", "tag")
            $state.IgnoreVersions = @()
            
            $minorBranch = $state.Branches[0]
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            
            $issue = & $Rule_MinorBranchTracksHighestPatch.CreateIssue $minorBranch $state $config
            
            $issue.RemediationAction.BranchName | Should -Be "v2.1"
            $issue.RemediationAction.Sha | Should -Be "new789"
        }
    }
    
    Context "Prerelease Filtering" {
        It "should pass Check when minor branch exists but only prerelease patches exist in series and ignore-preview-releases is true" {
            # Edge case: v1.1 branch exists, but only v1.1.0-preview exists (no stable patches in v1.1.x)
            # When ignore-preview-releases is true, Get-HighestPatchForMinor returns null
            # The Check should return true (pass) because there's nothing to track
            
            $state = [RepositoryState]::new()
            # v1.1 exists as branch
            $minorBranch = [VersionRef]::new("v1.1", "refs/heads/v1.1", "preview456", "branch")
            $state.Branches += $minorBranch
            # v1.1.0 is prerelease (only patch in v1.1.x)
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "preview456", "tag")
            # Also have stable v1.0.0 for context
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "stable123", "tag")
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
            $result = & $Rule_MinorBranchTracksHighestPatch.Check $minorBranch $state $config
            
            # Should pass because there are no non-prerelease patches in v1.1.x to track
            $result | Should -Be $true
        }
        
        It "should exclude prerelease patch when calculating highest (ignore-preview-releases=true)" {
            $state = [RepositoryState]::new()
            # v1.0 branch points to old stable release
            $minorBranch = [VersionRef]::new("v1.0", "refs/heads/v1.0", "stable123", "branch")
            $state.Branches += $minorBranch
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
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorBranchTracksHighestPatch.Check $minorBranch $state $config
            
            # v1.0 branch pointing to v1.0.0 should PASS because v1.0.1 is prerelease and filtered
            $result | Should -Be $true
        }
        
        It "should include prerelease patch when ignore-preview-releases is false" {
            $state = [RepositoryState]::new()
            # v1.0 branch points to old stable release
            $minorBranch = [VersionRef]::new("v1.0", "refs/heads/v1.0", "stable123", "branch")
            $state.Branches += $minorBranch
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
            
            $config = @{ 
                'ignore-preview-releases' = $false
                'check-minor-version' = 'error'
            }
            $result = & $Rule_MinorBranchTracksHighestPatch.Check $minorBranch $state $config
            
            # v1.0 branch pointing to v1.0.0 should FAIL because v1.0.1 is included (prerelease not filtered)
            $result | Should -Be $false
        }
        
        It "should use non-prerelease SHA in CreateIssue when ignore-preview-releases is true" {
            $state = [RepositoryState]::new()
            $minorBranch = [VersionRef]::new("v1.0", "refs/heads/v1.0", "old123", "branch")
            $state.Branches += $minorBranch
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
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 
                'ignore-preview-releases' = $true
                'check-minor-version' = 'error'
            }
            $issue = & $Rule_MinorBranchTracksHighestPatch.CreateIssue $minorBranch $state $config
            
            # Should use SHA from v1.0.0 (stable), not v1.0.1 (prerelease)
            $issue.ExpectedSha | Should -Be "stable456"
        }
    }
}
