#############################################################################
# Tests for Rule: release_should_be_immutable
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/release_should_be_immutable.ps1"
}

Describe "release_should_be_immutable" {
    Context "Condition - AppliesWhen check-release-immutability" {
        It "should return results when check-release-immutability is 'error'" {
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
            $result = & $Rule_ReleaseShouldBeImmutable.Condition $state $config
            
            $result.Count | Should -Be 1
        }
        
        It "should return results when check-release-immutability is 'warning'" {
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
            
            $config = @{ 'check-release-immutability' = 'warning' }
            $result = & $Rule_ReleaseShouldBeImmutable.Condition $state $config
            
            $result.Count | Should -Be 1
        }
        
        It "should return empty when check-release-immutability is 'none'" {
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
            
            $config = @{ 'check-release-immutability' = 'none' }
            $result = & $Rule_ReleaseShouldBeImmutable.Condition $state $config
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "Condition - Finding published releases" {
        It "should return published release for patch version" {
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
            $result = & $Rule_ReleaseShouldBeImmutable.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].TagName | Should -Be "v1.0.0"
        }
        
        It "should not return draft release" {
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
            $result = & $Rule_ReleaseShouldBeImmutable.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should skip ignored versions" {
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
            $ignored = [ReleaseInfo]::new($releaseData)
            $ignored.IsIgnored = $true
            $state.Releases = @($ignored)
            $state.IgnoreVersions = @("v1.0.0")
            
            $config = @{ 'check-release-immutability' = 'error' }
            $result = & $Rule_ReleaseShouldBeImmutable.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should not return published release for floating version (major)" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-release-immutability' = 'error' }
            $result = & $Rule_ReleaseShouldBeImmutable.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should not return published release for floating version (minor)" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-release-immutability' = 'error' }
            $result = & $Rule_ReleaseShouldBeImmutable.Condition $state $config
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "Check - Immutability verification" {
        It "should return true when release is immutable" {
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $true
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $state = [RepositoryState]::new()
            $state.RepoOwner = "owner"
            $state.RepoName = "repo"
            $state.Token = "token"
            $state.ApiUrl = "https://api.github.com"
            $config = @{ 'check-release-immutability' = 'error' }
            
            $result = & $Rule_ReleaseShouldBeImmutable.Check $releaseInfo $state $config
            
            $result | Should -Be $true
        }
        
        It "should return false when release is not immutable" {
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $state = [RepositoryState]::new()
            $state.RepoOwner = "owner"
            $state.RepoName = "repo"
            $state.Token = "token"
            $state.ApiUrl = "https://api.github.com"
            $config = @{ 'check-release-immutability' = 'error' }
            
            $result = & $Rule_ReleaseShouldBeImmutable.Check $releaseInfo $state $config
            
            $result | Should -Be $false
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with error severity when configured as error" {
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $state = [RepositoryState]::new()
            $config = @{ 'check-release-immutability' = 'error' }
            
            $issue = & $Rule_ReleaseShouldBeImmutable.CreateIssue $releaseInfo $state $config
            
            $issue.Type | Should -Be "non_immutable_release"
            $issue.Severity | Should -Be "error"
            $issue.Message | Should -BeLike "*v1.0.0*"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "RepublishReleaseAction"
        }

        It "should create issue with warning severity when configured as warning" {
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.1"
                id = 124
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.1"
                target_commitish = "abc124"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $state = [RepositoryState]::new()
            $config = @{ 'check-release-immutability' = 'warning' }

            $issue = & $Rule_ReleaseShouldBeImmutable.CreateIssue $releaseInfo $state $config

            $issue.Type | Should -Be "non_immutable_release"
            $issue.Severity | Should -Be "warning"
        }
        
        It "should configure RepublishReleaseAction with tag name" {
            $releaseData = [PSCustomObject]@{
                tag_name = "v2.5.3"
                id = 456
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.5.3"
                target_commitish = "def789"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $state = [RepositoryState]::new()
            $config = @{ 'check-release-immutability' = 'warning' }
            
            $issue = & $Rule_ReleaseShouldBeImmutable.CreateIssue $releaseInfo $state $config
            
            $issue.RemediationAction.TagName | Should -Be "v2.5.3"
        }

        It "should set MakeLatest=false when higher version release exists" {
            $existingRelease = [PSCustomObject]@{
                tag_name = "v3.0.0"
                id = 500
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v3.0.0"
                target_commitish = "sha500"
                immutable = $false
            }
            $state = [RepositoryState]::new()
            $state.Releases = @([ReleaseInfo]::new($existingRelease))

            $releaseData = [PSCustomObject]@{
                tag_name = "v2.5.3"
                id = 456
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.5.3"
                target_commitish = "def789"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $config = @{ 'check-release-immutability' = 'error' }

            $issue = & $Rule_ReleaseShouldBeImmutable.CreateIssue $releaseInfo $state $config

            $issue.RemediationAction.MakeLatest | Should -Be $false
        }
    }
}
