#############################################################################
# Tests for Rule: floating_version_no_release
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/../../../GitHubApi.ps1"
    . "$PSScriptRoot/floating_version_no_release.ps1"
}

Describe "floating_version_no_release" {
    Context "Condition - AppliesWhen checks enabled" {
        It "should return results when check-releases is enabled" {
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
            
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'none'
            }
            $result = & $Rule_FloatingVersionNoRelease.Condition $state $config
            
            $result.Count | Should -Be 1
        }
        
        It "should return results when check-release-immutability is enabled" {
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
            
            $config = @{ 
                'check-releases' = 'none'
                'check-release-immutability' = 'error'
            }
            $result = & $Rule_FloatingVersionNoRelease.Condition $state $config
            
            $result.Count | Should -Be 1
        }
        
        It "should return empty when both checks are disabled" {
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
            
            $config = @{ 
                'check-releases' = 'none'
                'check-release-immutability' = 'none'
            }
            $result = & $Rule_FloatingVersionNoRelease.Condition $state $config
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "Condition - Finding floating version releases" {
        It "should return release for major version (v1)" {
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
            
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'none'
            }
            $result = & $Rule_FloatingVersionNoRelease.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].TagName | Should -Be "v1"
        }
        
        It "should return release for minor version (v1.0)" {
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
            
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'none'
            }
            $result = & $Rule_FloatingVersionNoRelease.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].TagName | Should -Be "v1.0"
        }
        
        It "should return release for 'latest'" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "latest"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/latest"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'none'
            }
            $result = & $Rule_FloatingVersionNoRelease.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].TagName | Should -Be "latest"
        }
        
        It "should not return release for patch version (v1.0.0)" {
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
            
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'none'
            }
            $result = & $Rule_FloatingVersionNoRelease.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should skip ignored versions" {
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
            $ignored = [ReleaseInfo]::new($releaseData)
            $ignored.IsIgnored = $true
            $state.Releases = @($ignored)
            $state.IgnoreVersions = @("v1")
            
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'none'
            }
            $result = & $Rule_FloatingVersionNoRelease.Condition $state $config
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "CreateIssue - Mutable releases" {
        It "should create warning for mutable (draft) floating release" {
            $releaseData = [PSCustomObject]@{
                tag_name = "v1"
                id = 123
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $state = [RepositoryState]::new()
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'none'
            }
            
            $issue = & $Rule_FloatingVersionNoRelease.CreateIssue $releaseInfo $state $config
            
            $issue.Type | Should -Be "mutable_floating_release"
            $issue.Severity | Should -Be "warning"
            $issue.Message | Should -BeLike "*v1*"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "DeleteReleaseAction"
            $issue.Status | Should -Not -Be "unfixable"
        }
        
        It "should configure DeleteReleaseAction with release ID" {
            $releaseData = [PSCustomObject]@{
                tag_name = "v2"
                id = 456
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2"
                target_commitish = "abc123"
                immutable = $false
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $state = [RepositoryState]::new()
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'none'
            }
            
            $issue = & $Rule_FloatingVersionNoRelease.CreateIssue $releaseInfo $state $config
            
            $issue.RemediationAction.ReleaseId | Should -Be 456
            $issue.RemediationAction.TagName | Should -Be "v2"
        }
    }
    
    Context "CreateIssue - Immutable releases" {
        It "should create unfixable error for immutable floating release" {
            $releaseData = [PSCustomObject]@{
                tag_name = "v1"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1"
                target_commitish = "abc123"
                immutable = $true
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $state = [RepositoryState]::new()
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'error'
            }
            
            $issue = & $Rule_FloatingVersionNoRelease.CreateIssue $releaseInfo $state $config
            
            $issue.Type | Should -Be "immutable_floating_release"
            $issue.Severity | Should -Be "error"
            $issue.Message | Should -BeLike "*v1*"
            $issue.Status | Should -Be "unfixable"
            $issue.RemediationAction | Should -BeNullOrEmpty
        }
        
        It "should create unfixable error for immutable latest release" {
            $releaseData = [PSCustomObject]@{
                tag_name = "latest"
                id = 789
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/latest"
                target_commitish = "abc123"
                immutable = $true
            }
            $releaseInfo = [ReleaseInfo]::new($releaseData)
            $state = [RepositoryState]::new()
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'error'
            }
            
            $issue = & $Rule_FloatingVersionNoRelease.CreateIssue $releaseInfo $state $config
            
            $issue.Type | Should -Be "immutable_floating_release"
            $issue.Severity | Should -Be "error"
            $issue.Status | Should -Be "unfixable"
        }
    }
}
