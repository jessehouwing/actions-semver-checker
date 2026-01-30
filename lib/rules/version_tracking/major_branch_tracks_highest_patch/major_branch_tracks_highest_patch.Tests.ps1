#############################################################################
# Tests for Rule: major_branch_tracks_highest_patch
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/major_branch_tracks_highest_patch.ps1"
}

Describe "major_branch_tracks_highest_patch" {
    Context "Condition - AppliesWhen floating-versions-use is branches" {
        It "should return major branches when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.Branches += [VersionRef]::new("v2", "refs/heads/v2", "def456", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_MajorBranchTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 2
        }
        
        It "should return empty when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'tags' }
            $result = & $Rule_MajorBranchTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should skip ignored versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $ignored.IsIgnored = $true
            $state.Branches += $ignored
            $state.Branches += [VersionRef]::new("v2", "refs/heads/v2", "def456", "branch")
            $state.IgnoreVersions = @("v1")
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_MajorBranchTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v2"
        }
        
        It "should return multiple major branches" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.Branches += [VersionRef]::new("v2", "refs/heads/v2", "def456", "branch")
            $state.Branches += [VersionRef]::new("v3", "refs/heads/v3", "ghi789", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $result = & $Rule_MajorBranchTracksHighestPatch.Condition $state $config
            
            $result.Count | Should -Be 3
        }
    }
    
    Context "Check - SHA matching" {
        It "should pass when major branch points to highest patch" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $majorBranch = $state.Branches[0]
            $config = @{ 'ignore-preview-releases' = $true }
            
            $result = & $Rule_MajorBranchTracksHighestPatch.Check $majorBranch $state $config
            
            $result | Should -Be $true
        }
        
        It "should fail when major branch points to wrong SHA" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "old123", "branch")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $majorBranch = $state.Branches[0]
            $config = @{ 'ignore-preview-releases' = $true }
            
            $result = & $Rule_MajorBranchTracksHighestPatch.Check $majorBranch $state $config
            
            $result | Should -Be $false
        }
        
        It "should pass when no patches exist (nothing to track)" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.IgnoreVersions = @()
            
            $majorBranch = $state.Branches[0]
            $config = @{ 'ignore-preview-releases' = $true }
            
            $result = & $Rule_MajorBranchTracksHighestPatch.Check $majorBranch $state $config
            
            $result | Should -Be $true
        }
        
        It "should track highest patch across minor versions" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "latest", "branch")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "old123", "tag")
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "latest", "tag")
            $state.IgnoreVersions = @()
            
            $majorBranch = $state.Branches[0]
            $config = @{ 'ignore-preview-releases' = $true }
            
            $result = & $Rule_MajorBranchTracksHighestPatch.Check $majorBranch $state $config
            
            $result | Should -Be $true
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with correct details" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "old123", "branch")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "new456", "tag")
            $state.IgnoreVersions = @()
            
            $majorBranch = $state.Branches[0]
            $config = @{ 'ignore-preview-releases' = $true }
            
            $issue = & $Rule_MajorBranchTracksHighestPatch.CreateIssue $majorBranch $state $config
            
            $issue.Type | Should -Be "incorrect_version"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1"
            $issue.CurrentSha | Should -Be "old123"
            $issue.ExpectedSha | Should -Be "new456"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "UpdateBranchAction"
        }
        
        It "should configure UpdateBranchAction with correct SHA" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v2", "refs/heads/v2", "old123", "branch")
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "old456", "tag")
            $state.Tags += [VersionRef]::new("v2.1.0", "refs/tags/v2.1.0", "new789", "tag")
            $state.IgnoreVersions = @()
            
            $majorBranch = $state.Branches[0]
            $config = @{ 'ignore-preview-releases' = $true }
            
            $issue = & $Rule_MajorBranchTracksHighestPatch.CreateIssue $majorBranch $state $config
            
            $issue.RemediationAction.BranchName | Should -Be "v2"
            $issue.RemediationAction.Sha | Should -Be "new789"
        }
    }

    Context "Prerelease Filtering" {
        It "should pass Check when major branch exists but only prerelease patches exist and ignore-preview-releases is true" {
            # Edge case: v2 branch exists, but only v2.0.0-preview exists (no stable patches)
            # When ignore-preview-releases is true, Get-HighestPatchForMajor returns null
            # The Check should return true (pass) because there's nothing to track
            
            $state = [RepositoryState]::new()
            # v2 exists as branch
            $majorBranch = [VersionRef]::new("v2", "refs/heads/v2", "preview123", "branch")
            $state.Branches += $majorBranch
            # v2.0.0 is prerelease (only patch in v2.x)
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "preview123", "tag")
            $state.IgnoreVersions = @()
            
            # Mark v2.0.0 as prerelease via ReleaseInfo
            $prereleaseData = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 1
                draft = $false
                prerelease = $true
                html_url = "https://github.com/test/test/releases/tag/v2.0.0"
                target_commitish = "preview123"
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($prereleaseData)
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'ignore-preview-releases' = $true
            }
            $result = & $Rule_MajorBranchTracksHighestPatch.Check $majorBranch $state $config
            
            # Should pass because there are no non-prerelease patches to track
            $result | Should -Be $true
        }
        
        It "should exclude prerelease patch when calculating highest (ignore-preview-releases=true)" {
            $state = [RepositoryState]::new()
            # v1 branch points to old stable release
            $majorBranch = [VersionRef]::new("v1", "refs/heads/v1", "stable123", "branch")
            $state.Branches += $majorBranch
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
            $result = & $Rule_MajorBranchTracksHighestPatch.Check $majorBranch $state $config
            
            # v1 branch pointing to v1.0.0 should PASS because v1.1.0 is prerelease and filtered
            $result | Should -Be $true
        }
        
        It "should include prerelease patch when ignore-preview-releases is false" {
            $state = [RepositoryState]::new()
            # v1 branch points to old stable release
            $majorBranch = [VersionRef]::new("v1", "refs/heads/v1", "stable123", "branch")
            $state.Branches += $majorBranch
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
            $result = & $Rule_MajorBranchTracksHighestPatch.Check $majorBranch $state $config
            
            # v1 branch pointing to v1.0.0 should FAIL because v1.1.0 is included (prerelease not filtered)
            $result | Should -Be $false
        }
        
        It "should use non-prerelease SHA in CreateIssue when ignore-preview-releases is true" {
            $state = [RepositoryState]::new()
            $majorBranch = [VersionRef]::new("v1", "refs/heads/v1", "old123", "branch")
            $state.Branches += $majorBranch
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
            $issue = & $Rule_MajorBranchTracksHighestPatch.CreateIssue $majorBranch $state $config
            
            # Should use SHA from v1.0.0 (stable), not v1.1.0 (prerelease)
            $issue.ExpectedSha | Should -Be "stable456"
        }
    }
}
