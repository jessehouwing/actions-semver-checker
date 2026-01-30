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
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-release-immutability' = 'warning' }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            $result.Count | Should -Be 1
        }
        
        It "should return empty when check-release-immutability is 'none'" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-release-immutability' = 'none' }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
            $result.Count | Should -Be 0
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
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-release-immutability' = 'error' }
            $result = & $Rule_ReleaseShouldBePublished.Condition $state $config
            
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
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $state = [RepositoryState]::new()
            $config = @{ 'check-release-immutability' = 'error' }
            
            $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $releaseInfo $state $config
            
            $issue.RemediationAction.ReleaseId | Should -Be 456
            $issue.RemediationAction.TagName | Should -Be "v1.0.0"
        }
    }
}
