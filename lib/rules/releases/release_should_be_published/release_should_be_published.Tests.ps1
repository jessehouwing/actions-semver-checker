#############################################################################
# Tests for Rule: release_should_be_published
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/release_should_be_published.ps1"
}

Describe "release_should_be_published" {
    Context "Condition - AppliesWhen check-release-immutability" {
        It "should return results when check-release-immutability is 'error'" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-release-immutability' = 'error' }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            $result.Count | Should -Be 1
        }
        
        It "should return results when check-release-immutability is 'warning'" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-release-immutability' = 'warning' }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            $result.Count | Should -Be 1
        }
        
        It "should return empty when both check-release-immutability and check-releases are 'none'" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'check-release-immutability' = 'none'
                'check-releases' = 'none'
            }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return results when check-releases is 'error' even if check-release-immutability is 'none'" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'check-release-immutability' = 'none'
                'check-releases' = 'error'
            }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            $result.Count | Should -Be 1
        }
    }
    
    Context "Condition - Finding draft releases" {
        It "should return draft release for patch version" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-release-immutability' = 'error' }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].TagName | Should -Be "v1.0.0"
        }
        
        It "should not return published release" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-release-immutability' = 'error' }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should skip ignored versions" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $ignored = [ReleaseInfo]::new($releaseData)
            $ignored.IsIgnored = $true
            $state.Releases = @($ignored)
            $state.IgnoreVersions = @("v1.0.0")
            
            $config = @{ 'check-release-immutability' = 'error' }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should not return draft release for floating version (major)" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1"
                id = 123
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-release-immutability' = 'error' }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should not return draft release for floating version (minor)" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0"
                id = 123
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-release-immutability' = 'error' }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return only the primary draft release when duplicates exist for same tag" {
            # Scenario: Multiple draft releases exist for the same tag (can happen via API)
            # The duplicate_release rule handles deleting duplicates, so this rule
            # should only return the one that will be kept (lowest ID)
            $state = [RepositoryState]::new()
            
            # Create 3 duplicate draft releases for v1.0.0 (like in the user's repo)
            $release1 = [ReleaseInfo]::new(
                [PSCustomObject]@{
                    tag_name = "v1.0.0"
                    id = 101
                    draft = $true
                    prerelease = $false
                    html_url = "url1"
                    target_commitish = "abc123"
                    immutable = $false
                })
            $release2 = [ReleaseInfo]::new([PSCustomObject]@{
                    tag_name = "v1.0.0"
                    id = 102
                    draft = $true
                    prerelease = $false
                    html_url = "url2"
                    target_commitish = "abc123"
                    immutable = $false
                })
            $release3 = [ReleaseInfo]::new([PSCustomObject]@{
                    tag_name = "v1.0.0"
                    id = 103
                    draft = $true
                    prerelease = $false
                    html_url = "url3"
                    target_commitish = "abc123"
                    immutable = $false
                })
            
            $state.Releases = @($release1, $release2, $release3)
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            # Should return only the primary draft (id 101, lowest ID) - duplicates are handled by duplicate_release rule
            $result.Count | Should -Be 1
            $result[0].Id | Should -Be 101
            $result[0].TagName | Should -Be "v1.0.0"
        }
        
        It "should return one draft per version when duplicates exist across different versions" {
            # Scenario: Multiple draft releases for multiple versions
            # The duplicate_release rule handles deleting duplicates per tag
            $state = [RepositoryState]::new()
            
            # 2 drafts for v1.0.0, 1 draft for v2.0.0
            $state.Releases = @(
                [ReleaseInfo]::new([PSCustomObject]@{
                        tag_name = "v1.0.0"
                        id = 101
                        draft = $true
                        prerelease = $false
                        html_url = "url1"
                        target_commitish = "abc"
                        immutable = $false
                    }),
                [ReleaseInfo]::new([PSCustomObject]@{
                        tag_name = "v1.0.0"
                        id = 102
                        draft = $true
                        prerelease = $false
                        html_url = "url2"
                        target_commitish = "abc"
                        immutable = $false
                    }),
                [ReleaseInfo]::new([PSCustomObject]@{
                        tag_name = "v2.0.0"
                        id = 201
                        draft = $true
                        prerelease = $false
                        html_url = "url3"
                        target_commitish = "def"
                        immutable = $false
                    })
            )
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            # Should return 2 drafts: one for v1.0.0 (id 101) and one for v2.0.0 (id 201)
            $result.Count | Should -Be 2
            ($result | Where-Object { $_.TagName -eq "v1.0.0" }).Count | Should -Be 1
            ($result | Where-Object { $_.TagName -eq "v1.0.0" }).Id | Should -Be 101
            ($result | Where-Object { $_.TagName -eq "v2.0.0" }).Count | Should -Be 1
        }
        
        It "should not return draft when published release already exists for same tag" {
            # Scenario: A published release exists, and a draft duplicate also exists
            # The draft will be deleted by duplicate_release rule, so this rule should not include it
            $state = [RepositoryState]::new()
            
            $published = [ReleaseInfo]::new([PSCustomObject]@{
                    tag_name = "v1.0.0"
                    id = 100
                    draft = $false
                    prerelease = $false
                    html_url = "url1"
                    target_commitish = "abc123"
                    immutable = $true
                })
            $draft = [ReleaseInfo]::new([PSCustomObject]@{
                    tag_name = "v1.0.0"
                    id = 200
                    draft = $true
                    prerelease = $false
                    html_url = "url2"
                    target_commitish = "abc123"
                    immutable = $false
                })
            
            $state.Releases = @($published, $draft)
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            # Draft should be excluded since published release exists (draft will be deleted by duplicate_release)
            $result.Count | Should -Be 0
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with error severity" {
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $state = [RepositoryState]::new()
            $config = @{ 'check-release-immutability' = 'error' }
            
            $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $releaseInfo $state $config
            
            $issue.Type | Should -Be "draft_release"
            $issue.Severity | Should -Be "error"
            $issue.Message | Should -BeLike "*v1.0.0*"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "PublishReleaseAction"
        }
        
        It "should create issue with warning severity" {
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $state = [RepositoryState]::new()
            $config = @{ 'check-release-immutability' = 'warning' }
            
            $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $releaseInfo $state $config
            
            $issue.Severity | Should -Be "warning"
        }
        
        It "should configure PublishReleaseAction with release ID" {
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 456
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $state = [RepositoryState]::new()
            $config = @{ 'check-release-immutability' = 'error' }
            
            $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $releaseInfo $state $config
            
            $issue.RemediationAction.ReleaseId | Should -Be 456
            $issue.RemediationAction.TagName | Should -Be "v1.0.0"
        }
    }
    
    Context "CreateIssue - MakeLatest integration with Test-ShouldBeLatestRelease" {
        It "should set MakeLatest=false when higher version release exists" {
            $state = [RepositoryState]::new()
            
            # v2.0.0 already exists and is latest
            $existingRelease = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            $latestRelease = [ReleaseInfo]::new($existingRelease)
            $latestRelease.IsLatest = $true
            $state.Releases = @($latestRelease)
            
            # Publishing draft for v1.0.0 (lower version)
            $draftRelease = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($draftRelease)
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $releaseInfo $state $config
            
            # MakeLatest should be false to prevent overwriting v2.0.0 as latest
            $issue.RemediationAction.MakeLatest | Should -Be $false
        }
        
        It "should NOT set MakeLatest (let GitHub decide) when publishing highest version" {
            $state = [RepositoryState]::new()
            
            # v1.0.0 already exists
            $existingRelease = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $latestRelease = [ReleaseInfo]::new($existingRelease)
            $latestRelease.IsLatest = $true
            $state.Releases = @($latestRelease)
            
            # Publishing draft for v2.0.0 (higher version - should become latest)
            $draftRelease = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($draftRelease)
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $releaseInfo $state $config
            
            # MakeLatest should be null (not explicitly set) to let GitHub make it latest
            $issue.RemediationAction.MakeLatest | Should -BeNullOrEmpty
        }
        
        It "should NOT set MakeLatest when no other releases exist (first publish)" {
            $state = [RepositoryState]::new()
            
            # Only the draft release exists
            $draftRelease = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($draftRelease)
            $state.Releases = @($releaseInfo)
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $releaseInfo $state $config
            
            # MakeLatest should be null to let GitHub make it latest
            $issue.RemediationAction.MakeLatest | Should -BeNullOrEmpty
        }
        
        It "should set MakeLatest=false when publishing prerelease" {
            $state = [RepositoryState]::new()
            
            # v1.0.0 exists and is latest
            $existingRelease = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $latestRelease = [ReleaseInfo]::new($existingRelease)
            $latestRelease.IsLatest = $true
            $state.Releases = @($latestRelease)
            
            # Publishing draft for v2.0.0 that's marked as prerelease
            $draftRelease = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $true
                prerelease = $true  # This is a prerelease!
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($draftRelease)
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $releaseInfo $state $config
            
            # MakeLatest should be false - prereleases should NOT become latest
            $issue.RemediationAction.MakeLatest | Should -Be $false
        }
        
        It "should set MakeLatest=false when publishing backport release" {
            $state = [RepositoryState]::new()
            
            # v2.5.0 is the current latest
            $existingRelease = [PSCustomObject]@{
                tag_name = "v2.5.0"
                id = 250
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.5.0"
                target_commitish = "sha250"
                immutable = $false
            }
            $latestRelease = [ReleaseInfo]::new($existingRelease)
            $latestRelease.IsLatest = $true
            $state.Releases = @($latestRelease)
            
            # Publishing backport draft for v1.5.1
            $draftRelease = [PSCustomObject]@{
                tag_name = "v1.5.1"
                id = 151
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.5.1"
                target_commitish = "backport123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($draftRelease)
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $releaseInfo $state $config
            
            # MakeLatest should be false to prevent overwriting v2.5.0
            $issue.RemediationAction.MakeLatest | Should -Be $false
        }
        
        It "should NOT set MakeLatest when only prereleases exist at higher versions" {
            $state = [RepositoryState]::new()
            
            # v2.0.0 exists but is a prerelease (so v1.0.0 should become latest)
            $existingRelease = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $true  # This is a prerelease
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($existingRelease))
            
            # Publishing draft for v1.0.0 (lower version but should be latest since v2.0.0 is prerelease)
            $draftRelease = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $true
                prerelease = $false  # Not a prerelease
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($draftRelease)
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $releaseInfo $state $config
            
            # MakeLatest should be null - v1.0.0 IS the highest non-prerelease
            $issue.RemediationAction.MakeLatest | Should -BeNullOrEmpty
        }
        
        It "should handle multiple existing releases correctly" {
            $state = [RepositoryState]::new()
            
            # Multiple releases exist: v1.0.0, v1.5.0, v2.0.0
            $releases = @()
            foreach ($v in @("v1.0.0", "v1.5.0", "v2.0.0")) {
                $release = [PSCustomObject]@{
                    tag_name = $v
                    id = [int]($v -replace '\D', '')
                    draft = $false
                    prerelease = $false
                    html_url = "https://github.com/repo/releases/tag/$v"
                    target_commitish = "sha$v"
                    immutable = $false
                }
                $ri = [ReleaseInfo]::new($release)
                $ri.IsLatest = ($v -eq "v2.0.0")
                $releases += $ri
            }
            $state.Releases = $releases
            
            # Publishing draft for v1.2.0 (between v1.0.0 and v1.5.0 - NOT highest)
            $draftRelease = [PSCustomObject]@{
                tag_name = "v1.2.0"
                id = 120
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.2.0"
                target_commitish = "sha120"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($draftRelease)
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $releaseInfo $state $config
            
            # Should be false - v2.0.0 is still highest
            $issue.RemediationAction.MakeLatest | Should -Be $false
        }
    }
}
