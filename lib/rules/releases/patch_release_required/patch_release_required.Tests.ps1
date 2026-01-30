#############################################################################
# Tests for Rule: patch_release_required
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/patch_release_required.ps1"
}

Describe "patch_release_required" {
    Context "Condition - AppliesWhen check-releases" {
        It "should return results when check-releases is 'error'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Releases = @()
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            $result.Count | Should -Be 1
        }
        
        It "should return results when check-releases is 'warning'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Releases = @()
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'warning' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            $result.Count | Should -Be 1
        }
        
        It "should return empty when check-releases is 'none'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Releases = @()
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'none' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "Condition - Finding missing releases" {
        It "should return patch tag without release" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.Releases = @()  # No releases
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1.0.0"
        }
        
        It "should not return patch tag with release" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
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
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should skip ignored versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $ignored.IsIgnored = $true
            $state.Tags += $ignored
            $state.Releases = @()
            $state.IgnoreVersions = @("v1.0.0")
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return expected patch when v1 exists but v1.0.0 doesn't" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Releases = @()  # No releases
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1.0.0"
            $result[0].SHA | Should -Be "abc123"  # Should use floating version's SHA
        }
        
        It "should return expected patch when v1.0 exists but v1.0.0 doesn't" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "def456", "tag")
            $state.Releases = @()  # No releases
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1.0.0"
            $result[0].SHA | Should -Be "def456"
        }
        
        It "should skip when draft release exists for expected patch" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
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
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            $result.Count | Should -Be 0  # Should skip because draft exists
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with error severity" {
            $versionRef = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state = [RepositoryState]::new()
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'none'
            }
            
            $issue = & $Rule_PatchReleaseRequired.CreateIssue $versionRef $state $config
            
            $issue.Type | Should -Be "missing_release"
            $issue.Severity | Should -Be "error"
            $issue.Message | Should -BeLike "*v1.0.0*"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "CreateReleaseAction"
        }
        
        It "should create issue with warning severity" {
            $versionRef = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state = [RepositoryState]::new()
            $config = @{ 
                'check-releases' = 'warning'
                'check-release-immutability' = 'none'
            }
            
            $issue = & $Rule_PatchReleaseRequired.CreateIssue $versionRef $state $config
            
            $issue.Severity | Should -Be "warning"
        }
        
        It "should configure CreateReleaseAction to auto-publish when immutability check is error" {
            $versionRef = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state = [RepositoryState]::new()
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'error'
            }
            
            $issue = & $Rule_PatchReleaseRequired.CreateIssue $versionRef $state $config
            
            $issue.RemediationAction.AutoPublish | Should -Be $true
        }
        
        It "should configure CreateReleaseAction to NOT auto-publish when immutability check is none" {
            $versionRef = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state = [RepositoryState]::new()
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'none'
            }
            
            $issue = & $Rule_PatchReleaseRequired.CreateIssue $versionRef $state $config
            
            $issue.RemediationAction.AutoPublish | Should -Be $false
        }
    }
}
