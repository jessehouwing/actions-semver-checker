#############################################################################
# Tests for Rule: duplicate_release
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/duplicate_release.ps1"
}

Describe "duplicate_release" {
    Context "Condition - Configuration checks" {
        It "should return results when check-releases is 'error'" {
            $state = [RepositoryState]::new()
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $true
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 456
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0-draft"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_DuplicateRelease.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Id | Should -Be 456
        }
        
        It "should return results when check-releases is 'warning'" {
            $state = [RepositoryState]::new()
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 456
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0-draft"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'warning' }
            $result = & $Rule_DuplicateRelease.Condition $state $config
            
            $result.Count | Should -Be 1
        }
        
        It "should return empty when check-releases is 'none'" {
            $state = [RepositoryState]::new()
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 456
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0-draft"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'none' }
            $result = & $Rule_DuplicateRelease.Condition $state $config
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "Condition - Finding duplicate releases" {
        It "should return draft duplicate when published release exists" {
            $state = [RepositoryState]::new()
            $published = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $true
            }
            $draft = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 200
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @(
                [ReleaseInfo]::new($published),
                [ReleaseInfo]::new($draft)
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_DuplicateRelease.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Id | Should -Be 200
            $result[0].IsDraft | Should -Be $true
        }
        
        It "should delete newer draft when two drafts exist for same tag" {
            $state = [RepositoryState]::new()
            $draft1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $draft2 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 200
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @(
                [ReleaseInfo]::new($draft1),
                [ReleaseInfo]::new($draft2)
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_DuplicateRelease.Condition $state $config
            
            # Should delete the newer draft (id 200), keep the older one (id 100)
            $result.Count | Should -Be 1
            $result[0].Id | Should -Be 200
        }
        
        It "should delete multiple draft duplicates" {
            $state = [RepositoryState]::new()
            $published = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $true
            }
            $draft1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 200
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $draft2 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 300
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @(
                [ReleaseInfo]::new($published),
                [ReleaseInfo]::new($draft1),
                [ReleaseInfo]::new($draft2)
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_DuplicateRelease.Condition $state $config
            
            $result.Count | Should -Be 2
            $result.Id | Should -Contain 200
            $result.Id | Should -Contain 300
        }
        
        It "should not return anything when no duplicates exist" {
            $state = [RepositoryState]::new()
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $true
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $true
            }
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_DuplicateRelease.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should not return published duplicate (cannot be deleted)" {
            $state = [RepositoryState]::new()
            $published1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $true
            }
            $published2 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $true
            }
            $state.Releases = @(
                [ReleaseInfo]::new($published1),
                [ReleaseInfo]::new($published2)
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_DuplicateRelease.Condition $state $config
            
            # Cannot delete published releases, so no results
            $result.Count | Should -Be 0
        }
        
        It "should skip ignored versions" {
            $state = [RepositoryState]::new()
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $true
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 200
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $r1 = [ReleaseInfo]::new($release1)
            $r1.IsIgnored = $true
            $r2 = [ReleaseInfo]::new($release2)
            $r2.IsIgnored = $true
            $state.Releases = @($r1, $r2)
            $state.IgnoreVersions = @("v1.0.0")
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_DuplicateRelease.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should only match patch versions (not floating versions)" {
            $state = [RepositoryState]::new()
            # Duplicate releases for a major version tag (should be ignored)
            $major1 = [PSCustomObject]@{
                tag_name = "v1"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1"
                target_commitish = "abc123"
                immutable = $false
            }
            $major2 = [PSCustomObject]@{
                tag_name = "v1"
                id = 200
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1"
                target_commitish = "abc123"
                immutable = $false
            }
            # Duplicate releases for a minor version tag (should be ignored)
            $minor1 = [PSCustomObject]@{
                tag_name = "v1.0"
                id = 300
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $minor2 = [PSCustomObject]@{
                tag_name = "v1.0"
                id = 400
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @(
                [ReleaseInfo]::new($major1),
                [ReleaseInfo]::new($major2),
                [ReleaseInfo]::new($minor1),
                [ReleaseInfo]::new($minor2)
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_DuplicateRelease.Condition $state $config
            
            # Floating versions should not be checked
            $result.Count | Should -Be 0
        }
    }
    
    Context "Check" {
        It "should return false for duplicate releases (they are invalid)" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 200
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $release = [ReleaseInfo]::new($releaseData)
            $config = @{ 'check-releases' = 'error' }
            
            $result = & $Rule_DuplicateRelease.Check $release $state $config
            
            $result | Should -Be $false
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with error severity when check-releases is 'error'" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 200
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $release = [ReleaseInfo]::new($releaseData)
            $config = @{ 'check-releases' = 'error' }
            
            $issue = & $Rule_DuplicateRelease.CreateIssue $release $state $config
            
            $issue.Severity | Should -Be "error"
            $issue.Type | Should -Be "duplicate_release"
            $issue.Version | Should -Be "v1.0.0"
            $issue.Message | Should -Match "Duplicate draft release"
            $issue.Message | Should -Match "200"
        }
        
        It "should create issue with warning severity when check-releases is 'warning'" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 200
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $release = [ReleaseInfo]::new($releaseData)
            $config = @{ 'check-releases' = 'warning' }
            
            $issue = & $Rule_DuplicateRelease.CreateIssue $release $state $config
            
            $issue.Severity | Should -Be "warning"
        }
        
        It "should create DeleteReleaseAction with correct release ID" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 12345
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $release = [ReleaseInfo]::new($releaseData)
            $config = @{ 'check-releases' = 'error' }
            
            $issue = & $Rule_DuplicateRelease.CreateIssue $release $state $config
            
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "DeleteReleaseAction"
            $issue.RemediationAction.ReleaseId | Should -Be 12345
            $issue.RemediationAction.TagName | Should -Be "v1.0.0"
        }
    }
    
    Context "Priority ordering with other release rules" {
        It "should have priority lower than release_should_be_published" {
            . "$PSScriptRoot/../release_should_be_published/release_should_be_published.ps1"
            
            $Rule_DuplicateRelease.Priority | Should -BeLessThan $Rule_ReleaseShouldBePublished.Priority
        }
        
        It "should have priority lower than patch_release_required" {
            . "$PSScriptRoot/../patch_release_required/patch_release_required.ps1"
            
            $Rule_DuplicateRelease.Priority | Should -BeLessThan $Rule_PatchReleaseRequired.Priority
        }
    }
}
