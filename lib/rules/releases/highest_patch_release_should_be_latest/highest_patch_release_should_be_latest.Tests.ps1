#############################################################################
# Tests for Rule: highest_patch_release_should_be_latest
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/highest_patch_release_should_be_latest.ps1"
}

Describe "highest_patch_release_should_be_latest" {
    Context "Condition - AppliesWhen check-releases" {
        It "should return results when check-releases is 'error'" {
            $state = [RepositoryState]::new()
            
            # v1.0.0 is a non-prerelease (should be latest)
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($release1))
            $state.Tags = @([VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag"))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            # Returns the release that should be checked for "latest" status
            $result | Should -Not -BeNullOrEmpty
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
            $state.Releases = @([ReleaseInfo]::new($release1))
            $state.Tags = @([VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag"))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'warning' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            $result | Should -Not -BeNullOrEmpty
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
            $state.Releases = @([ReleaseInfo]::new($release1))
            $state.Tags = @([VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag"))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'none' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "Condition - Finding highest non-prerelease patch" {
        It "should identify v2.0.0 as expected latest when v1.0.0 and v2.0.0 exist" {
            $state = [RepositoryState]::new()
            
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            $state.Tags = @(
                [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag"),
                [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "def456", "tag")
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            # Should return the expected latest release info
            $result.ExpectedLatest.TagName | Should -Be "v2.0.0"
        }
        
        It "should skip prereleases when determining latest" {
            $state = [RepositoryState]::new()
            
            # v1.0.0 is stable (should be latest)
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            # v2.0.0 is a prerelease (should NOT be latest)
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $true
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            $state.Tags = @(
                [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag"),
                [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "def456", "tag")
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            # v1.0.0 should be the expected latest (v2.0.0 is prerelease)
            $result.ExpectedLatest.TagName | Should -Be "v1.0.0"
        }
        
        It "should skip draft releases when determining latest" {
            $state = [RepositoryState]::new()
            
            # v1.0.0 is published (should be latest)
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            # v2.0.0 is a draft (should NOT be latest)
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            $state.Tags = @(
                [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag"),
                [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "def456", "tag")
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            # v1.0.0 should be the expected latest (v2.0.0 is draft)
            $result.ExpectedLatest.TagName | Should -Be "v1.0.0"
        }
        
        It "should return empty when no published non-prerelease releases exist" {
            $state = [RepositoryState]::new()
            
            # Only a prerelease exists
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0-beta"
                id = 100
                draft = $false
                prerelease = $true
                html_url = "https://github.com/repo/releases/tag/v1.0.0-beta"
                target_commitish = "abc123"
                immutable = $false
            }
            
            $state.Releases = @([ReleaseInfo]::new($release1))
            $state.Tags = @()
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should skip ignored versions when determining latest" {
            $state = [RepositoryState]::new()
            
            # v1.0.0 is stable
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            # v2.0.0 is stable but ignored
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            $ignored = [ReleaseInfo]::new($release2)
            $ignored.IsIgnored = $true
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                $ignored
            )
            $state.Tags = @(
                [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            )
            $ignoredTag = [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "def456", "tag")
            $ignoredTag.IsIgnored = $true
            $state.Tags += $ignoredTag
            $state.IgnoreVersions = @("v2.0.0")
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            # v1.0.0 should be the expected latest (v2.0.0 is ignored)
            $result.ExpectedLatest.TagName | Should -Be "v1.0.0"
        }
        
        It "should handle version sorting correctly (v10 > v9 > v2)" {
            $state = [RepositoryState]::new()
            
            $releases = @()
            $tags = @()
            foreach ($v in @("v2.0.0", "v9.0.0", "v10.0.0")) {
                $release = [PSCustomObject]@{
                    tag_name = $v
                    id = [int]($v -replace '\D', '')
                    draft = $false
                    prerelease = $false
                    html_url = "https://github.com/repo/releases/tag/$v"
                    target_commitish = "sha$v"
                    immutable = $false
                }
                $releases += [ReleaseInfo]::new($release)
                $tags += [VersionRef]::new($v, "refs/tags/$v", "sha$v", "tag")
            }
            
            $state.Releases = $releases
            $state.Tags = $tags
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            # v10.0.0 should be latest (numeric sorting, not string sorting)
            $result.ExpectedLatest.TagName | Should -Be "v10.0.0"
        }
        
        It "should identify highest minor version correctly (v1.2.0 > v1.1.0)" {
            $state = [RepositoryState]::new()
            
            $release1 = [PSCustomObject]@{
                tag_name = "v1.1.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.1.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v1.2.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.2.0"
                target_commitish = "def456"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            $state.Tags = @(
                [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "abc123", "tag"),
                [VersionRef]::new("v1.2.0", "refs/tags/v1.2.0", "def456", "tag")
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            $result.ExpectedLatest.TagName | Should -Be "v1.2.0"
        }
        
        It "should identify highest patch version correctly (v1.0.2 > v1.0.1)" {
            $state = [RepositoryState]::new()
            
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.1"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.1"
                target_commitish = "abc123"
                immutable = $false
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v1.0.2"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.2"
                target_commitish = "def456"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            $state.Tags = @(
                [VersionRef]::new("v1.0.1", "refs/tags/v1.0.1", "abc123", "tag"),
                [VersionRef]::new("v1.0.2", "refs/tags/v1.0.2", "def456", "tag")
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            $result.ExpectedLatest.TagName | Should -Be "v1.0.2"
        }
    }
    
    Context "Check - validates current latest against expected" {
        It "should return true when expected latest is already marked as latest" {
            $state = [RepositoryState]::new()
            
            $release = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($release)
            $releaseInfo.IsLatest = $true
            $state.Releases = @($releaseInfo)
            
            $item = @{
                ExpectedLatest = $releaseInfo
                CurrentLatest = $releaseInfo
            }
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Check $item $state $config
            
            $result | Should -Be $true
        }
        
        It "should return false when different release is marked as latest" {
            $state = [RepositoryState]::new()
            
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            
            $releaseInfo1 = [ReleaseInfo]::new($release1)
            $releaseInfo1.IsLatest = $true  # Incorrectly marked as latest
            
            $releaseInfo2 = [ReleaseInfo]::new($release2)
            $releaseInfo2.IsLatest = $false  # Should be latest
            
            $state.Releases = @($releaseInfo1, $releaseInfo2)
            
            $item = @{
                ExpectedLatest = $releaseInfo2  # v2.0.0 should be latest
                CurrentLatest = $releaseInfo1   # v1.0.0 is currently latest
            }
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Check $item $state $config
            
            $result | Should -Be $false
        }
        
        It "should return false when no release is marked as latest" {
            $state = [RepositoryState]::new()
            
            $release = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($release)
            $releaseInfo.IsLatest = $false
            $state.Releases = @($releaseInfo)
            
            $item = @{
                ExpectedLatest = $releaseInfo
                CurrentLatest = $null
            }
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Check $item $state $config
            
            $result | Should -Be $false
        }
    }
    
    Context "CreateIssue - generates correct issue" {
        It "should create issue with SetLatestReleaseAction when wrong release is latest" {
            $state = [RepositoryState]::new()
            
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            
            $releaseInfo1 = [ReleaseInfo]::new($release1)
            $releaseInfo1.IsLatest = $true  # Incorrectly marked
            
            $releaseInfo2 = [ReleaseInfo]::new($release2)
            $releaseInfo2.IsLatest = $false  # Should be latest
            
            $state.Releases = @($releaseInfo1, $releaseInfo2)
            
            $item = @{
                ExpectedLatest = $releaseInfo2
                CurrentLatest = $releaseInfo1
            }
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_HighestPatchReleaseShouldBeLatest.CreateIssue $item $state $config
            
            $issue.Type | Should -Be "wrong_latest_release"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v2.0.0"
            $issue.Message | Should -Match "v2.0.0"
            $issue.Message | Should -Match "latest"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "SetLatestReleaseAction"
            $issue.RemediationAction.TagName | Should -Be "v2.0.0"
            $issue.RemediationAction.ReleaseId | Should -Be 200
        }
        
        It "should create issue with warning severity when check-releases is 'warning'" {
            $state = [RepositoryState]::new()
            
            $release = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($release)
            $state.Releases = @($releaseInfo)
            
            $item = @{
                ExpectedLatest = $releaseInfo
                CurrentLatest = $null
            }
            
            $config = @{ 'check-releases' = 'warning' }
            $issue = & $Rule_HighestPatchReleaseShouldBeLatest.CreateIssue $item $state $config
            
            $issue.Severity | Should -Be "warning"
        }
        
        It "should mention current latest release in message when one exists" {
            $state = [RepositoryState]::new()
            
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            
            $releaseInfo1 = [ReleaseInfo]::new($release1)
            $releaseInfo1.IsLatest = $true
            
            $releaseInfo2 = [ReleaseInfo]::new($release2)
            $releaseInfo2.IsLatest = $false
            
            $state.Releases = @($releaseInfo1, $releaseInfo2)
            $item = @{
                ExpectedLatest = $releaseInfo2
                CurrentLatest = $releaseInfo1
            }
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_HighestPatchReleaseShouldBeLatest.CreateIssue $item $state $config
            
            $issue.Message | Should -Match "v1.0.0"  # Should mention current latest
            $issue.Message | Should -Match "v2.0.0"  # Should mention expected latest
        }
    }
    
    Context "Prerelease status - MUST come from GitHub Release API, not tag suffix" {
        # IMPORTANT: GitHub Actions does NOT support -rc, -preview, -beta suffixes on tags
        # to determine prerelease status. The prerelease flag MUST be set on the GitHub Release.
        
        It "should treat v2.0.0-beta as stable if release.prerelease is false (tag suffix ignored)" {
            $state = [RepositoryState]::new()
            
            # v1.0.0 is stable
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false  # Release API says not prerelease
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            # v2.0.0-beta has beta suffix BUT release.prerelease = false
            # This means GitHub considers it a stable release
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0-beta"
                id = 200
                draft = $false
                prerelease = $false  # GitHub Release API says NOT prerelease (user mistake)
                html_url = "https://github.com/repo/releases/tag/v2.0.0-beta"
                target_commitish = "def456"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            # Note: Tags with suffixes like -beta are not valid for VersionRef
            # The rule operates on releases, so we only need the valid tag
            $state.Tags = @(
                [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            # v2.0.0-beta is NOT a patch version (has suffix), so it won't be considered
            # The rule only considers patch versions (vX.Y.Z format)
            $result.ExpectedLatest.TagName | Should -Be "v1.0.0"
        }
        
        It "should use IsPrerelease from release API not from tag name when both match" {
            $state = [RepositoryState]::new()
            
            # v1.0.0 stable release
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            # v2.0.0 looks stable by tag name but IS a prerelease via API
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $true  # GitHub Release API says this IS a prerelease
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            $state.Tags = @(
                [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag"),
                [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "def456", "tag")
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            # v1.0.0 should be latest because v2.0.0 is a prerelease (according to API)
            $result.ExpectedLatest.TagName | Should -Be "v1.0.0"
        }
        
        It "should skip releases with -rc suffix in tag name (not valid patch version)" {
            $state = [RepositoryState]::new()
            
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            # v2.0.0-rc1 won't match the patch version regex even if marked as non-prerelease
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0-rc1"
                id = 200
                draft = $false
                prerelease = $false  # Even if not marked as prerelease in API
                html_url = "https://github.com/repo/releases/tag/v2.0.0-rc1"
                target_commitish = "def456"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            # Note: Tags with suffixes like -rc1 are not valid for VersionRef
            # The rule operates on releases, so we only need the valid tag
            $state.Tags = @(
                [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            # v1.0.0 should be latest - v2.0.0-rc1 is not a valid patch version
            $result.ExpectedLatest.TagName | Should -Be "v1.0.0"
        }
        
        It "should skip releases with -preview suffix in tag name (not valid patch version)" {
            $state = [RepositoryState]::new()
            
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0-preview"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0-preview"
                target_commitish = "def456"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            # Note: Tags with suffixes like -preview are not valid for VersionRef
            # The rule operates on releases, so we only need the valid tag
            $state.Tags = @(
                [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            $result.ExpectedLatest.TagName | Should -Be "v1.0.0"
        }
    }
    
    Context "Integration - full validation flow" {
        It "should not create issue when correct release is already latest" {
            $state = [RepositoryState]::new()
            
            $release = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($release)
            $releaseInfo.IsLatest = $true
            
            $state.Releases = @($releaseInfo)
            $state.Tags = @([VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag"))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            
            # Get items from Condition
            $items = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            if ($items -and $items.Count -gt 0) {
                $isValid = & $Rule_HighestPatchReleaseShouldBeLatest.Check $items $state $config
                $isValid | Should -Be $true
            }
        }
        
        It "should create issue when prerelease is incorrectly marked as latest" {
            $state = [RepositoryState]::new()
            
            # v1.0.0 is stable
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo1 = [ReleaseInfo]::new($release1)
            $releaseInfo1.IsLatest = $false  # Should be latest
            
            # v2.0.0-beta is a prerelease but incorrectly marked as latest
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0-beta"
                id = 200
                draft = $false
                prerelease = $true
                html_url = "https://github.com/repo/releases/tag/v2.0.0-beta"
                target_commitish = "def456"
                immutable = $false
            }
            $releaseInfo2 = [ReleaseInfo]::new($release2)
            $releaseInfo2.IsLatest = $true  # Incorrectly marked
            
            $state.Releases = @($releaseInfo1, $releaseInfo2)
            # Note: Tags with suffixes like -beta are not valid for VersionRef
            # The rule operates on releases, so we only need the valid tag
            $state.Tags = @(
                [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            
            # Get items from Condition
            $items = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            $items | Should -Not -BeNullOrEmpty
            $items.ExpectedLatest.TagName | Should -Be "v1.0.0"
            
            # Check should fail
            $isValid = & $Rule_HighestPatchReleaseShouldBeLatest.Check $items $state $config
            $isValid | Should -Be $false
            
            # CreateIssue should generate remediation
            $issue = & $Rule_HighestPatchReleaseShouldBeLatest.CreateIssue $items $state $config
            $issue.Version | Should -Be "v1.0.0"
            $issue.RemediationAction.TagName | Should -Be "v1.0.0"
        }
    }
    
    Context "Remediation - SetLatestReleaseAction should not create wrong latest" {
        # These tests verify the remediation action is correctly configured
        # to fix the latest release issue without causing new problems
        
        It "should generate remediation that sets higher version as latest (not older)" {
            $state = [RepositoryState]::new()
            
            # v1.0.0 is incorrectly marked as latest
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            # v2.0.0 should be latest
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            
            $releaseInfo1 = [ReleaseInfo]::new($release1)
            $releaseInfo1.IsLatest = $true
            
            $releaseInfo2 = [ReleaseInfo]::new($release2)
            $releaseInfo2.IsLatest = $false
            
            $state.Releases = @($releaseInfo1, $releaseInfo2)
            
            $item = @{
                ExpectedLatest = $releaseInfo2
                CurrentLatest = $releaseInfo1
            }
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_HighestPatchReleaseShouldBeLatest.CreateIssue $item $state $config
            
            # The remediation action should set v2.0.0 as latest, not v1.0.0
            $issue.RemediationAction.TagName | Should -Be "v2.0.0"
            $issue.RemediationAction.ReleaseId | Should -Be 200
        }
        
        It "should not generate remediation to make a prerelease the latest" {
            $state = [RepositoryState]::new()
            
            # v1.0.0 is stable and should be latest
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            # v2.0.0 is a prerelease (higher version but NOT eligible for latest)
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $true  # This is a prerelease!
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            
            $releaseInfo1 = [ReleaseInfo]::new($release1)
            $releaseInfo1.IsLatest = $false
            
            $releaseInfo2 = [ReleaseInfo]::new($release2)
            $releaseInfo2.IsLatest = $true  # Incorrectly marked
            
            $state.Releases = @($releaseInfo1, $releaseInfo2)
            $state.Tags = @(
                [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag"),
                [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "def456", "tag")
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            
            # Get items from Condition (will pick v1.0.0 as expected latest)
            $items = & $Rule_HighestPatchReleaseShouldBeLatest.Condition $state $config
            
            # v1.0.0 should be expected latest, not the prerelease v2.0.0
            $items.ExpectedLatest.TagName | Should -Be "v1.0.0"
            
            # Create issue and verify remediation
            $issue = & $Rule_HighestPatchReleaseShouldBeLatest.CreateIssue $items $state $config
            $issue.RemediationAction.TagName | Should -Be "v1.0.0"
            $issue.RemediationAction.ReleaseId | Should -Be 100
        }
    }
}
