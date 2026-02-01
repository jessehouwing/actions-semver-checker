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
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should not return patch tag with draft release" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $true  # Draft release
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            $result.Count | Should -Be 0  # Should skip because draft release exists
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
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            $result.Count | Should -Be 0  # Should skip because draft exists
        }
        
        It "should not return duplicate results when both vX and vX.Y exist for same patch" {
            $state = [RepositoryState]::new()
            # Both v1 and v1.0 exist pointing to same commit
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.Releases = @()  # No releases
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            # Should only return ONE entry for v1.0.0, not duplicates
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1.0.0"
        }
        
        It "should not return duplicate results when vX.Y.Z tag and vX floating both exist" {
            $state = [RepositoryState]::new()
            # v1.0.0 patch tag exists without release
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            # v1 floating tag also exists
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Releases = @()  # No releases
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            # Should only return ONE entry for v1.0.0 (from existing tag), not from synthetic
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1.0.0"
        }
        
        It "should not return duplicate results when all v0, v0.0, v0.0.0 exist without releases" {
            $state = [RepositoryState]::new()
            # Simulate the actual scenario from the bug report
            $state.Tags += [VersionRef]::new("v0", "refs/tags/v0", "sha0", "tag")
            $state.Tags += [VersionRef]::new("v0.0", "refs/tags/v0.0", "sha0", "tag")
            $state.Tags += [VersionRef]::new("v0.0.0", "refs/tags/v0.0.0", "sha0", "tag")
            $state.Releases = @()  # No releases
            $state.IgnoreVersions = @()
            
            $config = @{ 'check-releases' = 'error' }
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            # Should only return ONE entry for v0.0.0
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v0.0.0"
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
    
    Context "CreateIssue - MakeLatest integration with Test-ShouldBeLatestRelease" {
        It "should set MakeLatest=false when higher version release exists" {
            $versionRef = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
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
            $releaseInfo = [ReleaseInfo]::new($existingRelease)
            $releaseInfo.IsLatest = $true
            $state.Releases = @($releaseInfo)
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_PatchReleaseRequired.CreateIssue $versionRef $state $config
            
            # MakeLatest should be false to prevent overwriting v2.0.0 as latest
            $issue.RemediationAction.MakeLatest | Should -Be $false
        }
        
        It "should NOT set MakeLatest (let GitHub decide) when creating highest version" {
            $versionRef = [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "def456", "tag")
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
            $releaseInfo = [ReleaseInfo]::new($existingRelease)
            $releaseInfo.IsLatest = $true
            $state.Releases = @($releaseInfo)
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_PatchReleaseRequired.CreateIssue $versionRef $state $config
            
            # MakeLatest should be null (not explicitly set) to let GitHub make it latest
            $issue.RemediationAction.MakeLatest | Should -BeNullOrEmpty
        }
        
        It "should NOT set MakeLatest when no releases exist (first release)" {
            $versionRef = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state = [RepositoryState]::new()
            $state.Releases = @()  # No existing releases
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_PatchReleaseRequired.CreateIssue $versionRef $state $config
            
            # MakeLatest should be null to let GitHub make it latest
            $issue.RemediationAction.MakeLatest | Should -BeNullOrEmpty
        }
        
        It "should set MakeLatest=false when creating backport release" {
            $versionRef = [VersionRef]::new("v1.5.1", "refs/tags/v1.5.1", "backport123", "tag")
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
            $releaseInfo = [ReleaseInfo]::new($existingRelease)
            $releaseInfo.IsLatest = $true
            $state.Releases = @($releaseInfo)
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_PatchReleaseRequired.CreateIssue $versionRef $state $config
            
            # MakeLatest should be false to prevent overwriting v2.5.0
            $issue.RemediationAction.MakeLatest | Should -Be $false
        }
        
        It "should NOT set MakeLatest when only prerelease exists at higher version" {
            $versionRef = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state = [RepositoryState]::new()
            
            # v2.0.0 exists but is a prerelease (so v1.0.0 should be latest)
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
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_PatchReleaseRequired.CreateIssue $versionRef $state $config
            
            # MakeLatest should be null - v1.0.0 IS the highest non-prerelease
            $issue.RemediationAction.MakeLatest | Should -BeNullOrEmpty
        }
        
        It "should handle multiple existing releases correctly" {
            $versionRef = [VersionRef]::new("v1.2.0", "refs/tags/v1.2.0", "sha120", "tag")
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
            
            $config = @{ 'check-releases' = 'error' }
            $issue = & $Rule_PatchReleaseRequired.CreateIssue $versionRef $state $config
            
            # Should be false - v2.0.0 is still highest
            $issue.RemediationAction.MakeLatest | Should -Be $false
        }
    }
}
