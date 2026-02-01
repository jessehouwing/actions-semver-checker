#############################################################################
# Tests for ReleaseRulesHelper.ps1 - Shared helper functions for release rules
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../StateModel.ps1"
    . "$PSScriptRoot/ReleaseRulesHelper.ps1"
}

Describe "Test-ShouldBeLatestRelease" {
    Context "Invalid version formats" {
        It "should return false for non-patch versions (major only)" {
            $state = [RepositoryState]::new()
            $state.Releases = @()
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1"
            
            $result | Should -Be $false
        }
        
        It "should return false for non-patch versions (minor only)" {
            $state = [RepositoryState]::new()
            $state.Releases = @()
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.0"
            
            $result | Should -Be $false
        }
        
        It "should return false for 'latest' version" {
            $state = [RepositoryState]::new()
            $state.Releases = @()
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "latest"
            
            $result | Should -Be $false
        }
        
        It "should return false for versions with suffixes" {
            $state = [RepositoryState]::new()
            $state.Releases = @()
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.0.0-beta"
            
            $result | Should -Be $false
        }
    }
    
    Context "No existing releases" {
        It "should return true when no releases exist" {
            $state = [RepositoryState]::new()
            $state.Releases = @()
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.0.0"
            
            $result | Should -Be $true
        }
        
        It "should return true when only draft releases exist" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $true  # Draft - not eligible
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.0.0"
            
            $result | Should -Be $true
        }
        
        It "should return true when only prerelease releases exist" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $true  # Prerelease - not eligible
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.0.0"
            
            $result | Should -Be $true
        }
        
        It "should return true when only ignored releases exist" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            $release = [ReleaseInfo]::new($releaseData)
            $release.IsIgnored = $true  # Ignored - not eligible
            $state.Releases = @($release)
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.0.0"
            
            $result | Should -Be $true
        }
    }
    
    Context "Version comparison - higher version should be latest" {
        It "should return true when target is higher major version" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v2.0.0"
            
            $result | Should -Be $true
        }
        
        It "should return true when target is higher minor version" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.1.0"
            
            $result | Should -Be $true
        }
        
        It "should return true when target is higher patch version" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.0.1"
            
            $result | Should -Be $true
        }
        
        It "should handle numeric sorting correctly (v10 > v9)" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v9.0.0"
                id = 900
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v9.0.0"
                target_commitish = "sha900"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v10.0.0"
            
            $result | Should -Be $true
        }
    }
    
    Context "Version comparison - lower version should NOT be latest" {
        It "should return false when target is lower major version" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.0.0"
            
            $result | Should -Be $false
        }
        
        It "should return false when target is lower minor version" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.2.0"
                id = 120
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.2.0"
                target_commitish = "sha120"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.1.0"
            
            $result | Should -Be $false
        }
        
        It "should return false when target is lower patch version" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.2"
                id = 102
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.2"
                target_commitish = "sha102"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.0.1"
            
            $result | Should -Be $false
        }
        
        It "should return false when target equals existing version" {
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($releaseData))
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.0.0"
            
            $result | Should -Be $false
        }
    }
    
    Context "Prerelease handling via ReleaseInfo parameter" {
        It "should return false when ReleaseInfo indicates prerelease" {
            $state = [RepositoryState]::new()
            $state.Releases = @()  # No existing releases
            
            # The release being created/published is marked as prerelease
            $prereleaseData = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $true  # This is a prerelease
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            $prereleaseInfo = [ReleaseInfo]::new($prereleaseData)
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v2.0.0" -ReleaseInfo $prereleaseInfo
            
            $result | Should -Be $false
        }
        
        It "should return true when ReleaseInfo indicates non-prerelease and version is highest" {
            $state = [RepositoryState]::new()
            $existingRelease = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($existingRelease))
            
            # The release being created/published is NOT a prerelease
            $newReleaseData = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $true
                prerelease = $false  # Not a prerelease
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "def456"
                immutable = $false
            }
            $newReleaseInfo = [ReleaseInfo]::new($newReleaseData)
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v2.0.0" -ReleaseInfo $newReleaseInfo
            
            $result | Should -Be $true
        }
    }
    
    Context "Multiple existing releases" {
        It "should correctly identify highest among multiple releases" {
            $state = [RepositoryState]::new()
            
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "sha100"
                immutable = $false
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v1.5.0"
                id = 150
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.5.0"
                target_commitish = "sha150"
                immutable = $false
            }
            $release3 = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "sha200"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2),
                [ReleaseInfo]::new($release3)
            )
            
            # v2.1.0 should be latest (higher than v2.0.0)
            $result = Test-ShouldBeLatestRelease -State $state -Version "v2.1.0"
            $result | Should -Be $true
            
            # v1.6.0 should NOT be latest (lower than v2.0.0)
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.6.0"
            $result | Should -Be $false
        }
        
        It "should ignore prerelease releases when finding highest" {
            $state = [RepositoryState]::new()
            
            $stableRelease = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false  # Stable
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "sha100"
                immutable = $false
            }
            $prereleaseRelease = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $true  # Prerelease - should be ignored
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "sha200"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($stableRelease),
                [ReleaseInfo]::new($prereleaseRelease)
            )
            
            # v1.1.0 should be latest because v2.0.0 is a prerelease
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.1.0"
            
            $result | Should -Be $true
        }
    }
    
    Context "Real-world scenarios" {
        It "should handle backporting older version (should NOT become latest)" {
            $state = [RepositoryState]::new()
            
            # v2.0.0 is the current latest
            $release = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "sha200"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($release))
            
            # Backporting a security fix to v1.x line
            $result = Test-ShouldBeLatestRelease -State $state -Version "v1.0.1"
            
            $result | Should -Be $false
        }
        
        It "should handle new major version (should become latest)" {
            $state = [RepositoryState]::new()
            
            # v1.5.3 is the current latest
            $release = [PSCustomObject]@{
                tag_name = "v1.5.3"
                id = 153
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.5.3"
                target_commitish = "sha153"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($release))
            
            # Releasing v2.0.0
            $result = Test-ShouldBeLatestRelease -State $state -Version "v2.0.0"
            
            $result | Should -Be $true
        }
        
        It "should handle prerelease for next version (should NOT become latest)" {
            $state = [RepositoryState]::new()
            
            # v1.0.0 is the current stable latest
            $release = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "sha100"
                immutable = $false
            }
            $state.Releases = @([ReleaseInfo]::new($release))
            
            # Creating v2.0.0 as a prerelease (via ReleaseInfo)
            $prereleaseData = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $true  # Prerelease
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "sha200"
                immutable = $false
            }
            $prereleaseInfo = [ReleaseInfo]::new($prereleaseData)
            
            $result = Test-ShouldBeLatestRelease -State $state -Version "v2.0.0" -ReleaseInfo $prereleaseInfo
            
            $result | Should -Be $false
        }
    }
}

Describe "Get-DuplicateReleaseId" {
    Context "No duplicates" {
        It "should return empty array when no releases" {
            $state = [RepositoryState]::new()
            $state.Releases = @()
            
            $result = Get-DuplicateReleaseId -State $state
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty array when no duplicates exist" {
            $state = [RepositoryState]::new()
            
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "sha100"
                immutable = $false
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v2.0.0"
                target_commitish = "sha200"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            
            $result = Get-DuplicateReleaseId -State $state
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "With duplicates" {
        It "should return duplicate IDs keeping published over draft" {
            $state = [RepositoryState]::new()
            
            $publishedRelease = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false  # Published - should be kept
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "sha100"
                immutable = $false
            }
            $draftRelease = [PSCustomObject]@{
                tag_name = "v1.0.0"  # Same tag - duplicate
                id = 101
                draft = $true  # Draft - should be marked as duplicate
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "sha100"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($publishedRelease),
                [ReleaseInfo]::new($draftRelease)
            )
            
            $result = Get-DuplicateReleaseId -State $state
            
            $result.Count | Should -Be 1
            $result | Should -Contain 101
        }
        
        It "should ignore non-patch versions" {
            $state = [RepositoryState]::new()
            
            # Two releases with major version tag (not patch format)
            $release1 = [PSCustomObject]@{
                tag_name = "v1"  # Not a patch version
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1"
                target_commitish = "sha100"
                immutable = $false
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v1"  # Not a patch version - duplicate
                id = 101
                draft = $true
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1"
                target_commitish = "sha100"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            
            $result = Get-DuplicateReleaseId -State $state
            
            # Should not find duplicates since v1 is not a patch version
            $result.Count | Should -Be 0
        }
    }
}

Describe "Get-DuplicateDraftRelease" {
    Context "No duplicates" {
        It "should return empty array when no releases" {
            $state = [RepositoryState]::new()
            $state.Releases = @()
            
            $result = Get-DuplicateDraftRelease -State $state
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "With duplicates" {
        It "should only return draft duplicates (not published)" {
            $state = [RepositoryState]::new()
            
            $publishedRelease = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false  # Published - should be kept
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "sha100"
                immutable = $false
            }
            $draftRelease = [PSCustomObject]@{
                tag_name = "v1.0.0"  # Same tag - duplicate
                id = 101
                draft = $true  # Draft - can be deleted
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "sha100"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($publishedRelease),
                [ReleaseInfo]::new($draftRelease)
            )
            
            $result = Get-DuplicateDraftRelease -State $state
            
            $result.Count | Should -Be 1
            $result[0].Id | Should -Be 101
            $result[0].IsDraft | Should -Be $true
        }
        
        It "should not return published duplicates even if they would be deleted" {
            $state = [RepositoryState]::new()
            
            # Two published releases - published releases cannot be deleted
            $release1 = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false  # Published
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "sha100"
                immutable = $true
            }
            $release2 = [PSCustomObject]@{
                tag_name = "v1.0.0"  # Same tag - duplicate
                id = 101
                draft = $false  # Also published - cannot be deleted
                prerelease = $false
                html_url = "https://github.com/repo/releases/tag/v1.0.0"
                target_commitish = "sha100"
                immutable = $false
            }
            
            $state.Releases = @(
                [ReleaseInfo]::new($release1),
                [ReleaseInfo]::new($release2)
            )
            
            $result = Get-DuplicateDraftRelease -State $state
            
            # No drafts to delete
            $result.Count | Should -Be 0
        }
    }
}
