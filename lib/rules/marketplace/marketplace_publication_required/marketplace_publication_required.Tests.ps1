#############################################################################
# Tests for marketplace_publication_required rule
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../VersionParser.ps1"
    . "$PSScriptRoot/../MarketplaceRulesHelper.ps1"
    . "$PSScriptRoot/marketplace_publication_required.ps1"
}

Describe "marketplace_publication_required" {
    Context "Rule Properties" {
        It "should have correct name" {
            $Rule_MarketplacePublicationRequired.Name | Should -Be "marketplace_publication_required"
        }
        
        It "should have correct category" {
            $Rule_MarketplacePublicationRequired.Category | Should -Be "marketplace"
        }
        
        It "should have high priority (runs late)" {
            $Rule_MarketplacePublicationRequired.Priority | Should -BeGreaterOrEqual 40
        }
    }
    
    Context "Condition" {
        It "should return empty when check-marketplace is none" {
            $state = [RepositoryState]::new()
            $config = @{ 'check-marketplace' = 'none' }
            
            $result = & $Rule_MarketplacePublicationRequired.Condition $state $config
            
            $result | Should -BeNullOrEmpty
        }
        
        It "should return empty when marketplace metadata is invalid" {
            $state = [RepositoryState]::new()
            $state.MarketplaceMetadata = [MarketplaceMetadata]::new()  # All invalid
            $config = @{ 'check-marketplace' = 'error' }
            
            $result = & $Rule_MarketplacePublicationRequired.Condition $state $config
            
            $result | Should -BeNullOrEmpty
        }
        
        It "should return empty when no latest release exists" {
            $state = [RepositoryState]::new()
            
            # Valid metadata
            $metadata = [MarketplaceMetadata]::new()
            $metadata.ActionFileExists = $true
            $metadata.HasName = $true
            $metadata.HasDescription = $true
            $metadata.HasBrandingIcon = $true
            $metadata.HasBrandingColor = $true
            $metadata.ReadmeExists = $true
            $state.MarketplaceMetadata = $metadata
            
            # No releases
            $state.Releases = @()
            
            $config = @{ 'check-marketplace' = 'error' }
            
            $result = & $Rule_MarketplacePublicationRequired.Condition $state $config
            
            $result | Should -BeNullOrEmpty
        }
        
        It "should return latest release when metadata is valid and latest release exists" {
            $state = [RepositoryState]::new()
            
            # Valid metadata
            $metadata = [MarketplaceMetadata]::new()
            $metadata.ActionFileExists = $true
            $metadata.HasName = $true
            $metadata.HasDescription = $true
            $metadata.HasBrandingIcon = $true
            $metadata.HasBrandingColor = $true
            $metadata.ReadmeExists = $true
            $state.MarketplaceMetadata = $metadata
            
            # Create a release marked as latest
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                is_latest = $true
                immutable = $true
            }
            $release = [ReleaseInfo]::new($releaseData)
            $state.Releases = @($release)
            
            $config = @{ 'check-marketplace' = 'error' }
            
            $result = & $Rule_MarketplacePublicationRequired.Condition $state $config
            
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
            $result[0].TagName | Should -Be "v1.0.0"
        }
    }
    
    Context "Check" {
        BeforeEach {
            # Mock the Test-MarketplaceVersionPublished function for testing
            Mock -CommandName Test-MarketplaceVersionPublished -MockWith {
                param($ActionName, $Version, $ServerUrl)
                return [PSCustomObject]@{
                    IsPublished = $true
                    MarketplaceUrl = "https://github.com/marketplace/actions/test-action?version=$Version"
                    Error = $null
                }
            }
        }
        
        It "should return true when metadata has no name (skip check)" {
            $state = [RepositoryState]::new()
            $state.MarketplaceMetadata = [MarketplaceMetadata]::new()  # HasName = false
            
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                is_latest = $true
            }
            $release = [ReleaseInfo]::new($releaseData)
            $config = @{ 'check-marketplace' = 'error' }
            
            $result = & $Rule_MarketplacePublicationRequired.Check $release $state $config
            
            # Should skip check when no name available
            $result | Should -Be $true
        }
        
        It "should return true when version is published to marketplace" {
            $state = [RepositoryState]::new()
            $state.ServerUrl = "https://github.com"
            
            # Valid metadata with name
            $metadata = [MarketplaceMetadata]::new()
            $metadata.HasName = $true
            $metadata.Name = "Test Action"
            $state.MarketplaceMetadata = $metadata
            
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                is_latest = $true
            }
            $release = [ReleaseInfo]::new($releaseData)
            $config = @{ 'check-marketplace' = 'error' }
            
            Mock -CommandName Test-MarketplaceVersionPublished -MockWith {
                return [PSCustomObject]@{
                    IsPublished = $true
                    MarketplaceUrl = "https://github.com/marketplace/actions/test-action?version=v1.0.0"
                    Error = $null
                }
            }
            
            $result = & $Rule_MarketplacePublicationRequired.Check $release $state $config
            
            $result | Should -Be $true
        }
        
        It "should return false when version is not published to marketplace" {
            $state = [RepositoryState]::new()
            $state.ServerUrl = "https://github.com"
            
            # Valid metadata with name
            $metadata = [MarketplaceMetadata]::new()
            $metadata.HasName = $true
            $metadata.Name = "Test Action"
            $state.MarketplaceMetadata = $metadata
            
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                is_latest = $true
            }
            $release = [ReleaseInfo]::new($releaseData)
            $config = @{ 'check-marketplace' = 'error' }
            
            Mock -CommandName Test-MarketplaceVersionPublished -MockWith {
                return [PSCustomObject]@{
                    IsPublished = $false
                    MarketplaceUrl = "https://github.com/marketplace/actions/test-action?version=v1.0.0"
                    Error = $null
                }
            }
            
            $result = & $Rule_MarketplacePublicationRequired.Check $release $state $config
            
            $result | Should -Be $false
        }
        
        It "should return true when marketplace check has error (avoid false positives)" {
            $state = [RepositoryState]::new()
            $state.ServerUrl = "https://github.com"
            
            # Valid metadata with name
            $metadata = [MarketplaceMetadata]::new()
            $metadata.HasName = $true
            $metadata.Name = "Test Action"
            $state.MarketplaceMetadata = $metadata
            
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                is_latest = $true
            }
            $release = [ReleaseInfo]::new($releaseData)
            $config = @{ 'check-marketplace' = 'error' }
            
            Mock -CommandName Test-MarketplaceVersionPublished -MockWith {
                return [PSCustomObject]@{
                    IsPublished = $null  # Unknown
                    MarketplaceUrl = "https://github.com/marketplace/actions/test-action"
                    Error = "Network error"
                }
            }
            
            $result = & $Rule_MarketplacePublicationRequired.Check $release $state $config
            
            # Should return true to avoid false positives on errors
            $result | Should -Be $true
        }
    }
}

Describe "Test-IsHighestNonPrereleaseVersion" {
    It "should return true for highest non-prerelease version" {
        $state = [RepositoryState]::new()
        
        # Create multiple releases
        $release1 = [ReleaseInfo]::new([PSCustomObject]@{ tag_name = "v1.0.0"; id = 1; draft = $false; prerelease = $false; html_url = "url1"; target_commitish = "sha1" })
        $release2 = [ReleaseInfo]::new([PSCustomObject]@{ tag_name = "v1.1.0"; id = 2; draft = $false; prerelease = $false; html_url = "url2"; target_commitish = "sha2" })
        $release3 = [ReleaseInfo]::new([PSCustomObject]@{ tag_name = "v2.0.0"; id = 3; draft = $false; prerelease = $false; html_url = "url3"; target_commitish = "sha3" })
        $state.Releases = @($release1, $release2, $release3)
        
        $result = Test-IsHighestNonPrereleaseVersion -State $state -ReleaseInfo $release3
        
        $result | Should -Be $true
    }
    
    It "should return false for non-highest version" {
        $state = [RepositoryState]::new()
        
        $release1 = [ReleaseInfo]::new([PSCustomObject]@{ tag_name = "v1.0.0"; id = 1; draft = $false; prerelease = $false; html_url = "url1"; target_commitish = "sha1" })
        $release2 = [ReleaseInfo]::new([PSCustomObject]@{ tag_name = "v2.0.0"; id = 2; draft = $false; prerelease = $false; html_url = "url2"; target_commitish = "sha2" })
        $state.Releases = @($release1, $release2)
        
        $result = Test-IsHighestNonPrereleaseVersion -State $state -ReleaseInfo $release1
        
        $result | Should -Be $false
    }
    
    It "should exclude prerelease versions from highest calculation" {
        $state = [RepositoryState]::new()
        
        $release1 = [ReleaseInfo]::new([PSCustomObject]@{ tag_name = "v1.0.0"; id = 1; draft = $false; prerelease = $false; html_url = "url1"; target_commitish = "sha1" })
        $release2 = [ReleaseInfo]::new([PSCustomObject]@{ tag_name = "v2.0.0"; id = 2; draft = $false; prerelease = $true; html_url = "url2"; target_commitish = "sha2" })  # prerelease
        $state.Releases = @($release1, $release2)
        
        # v1.0.0 should be highest because v2.0.0 is prerelease
        $result = Test-IsHighestNonPrereleaseVersion -State $state -ReleaseInfo $release1
        
        $result | Should -Be $true
    }
    
    It "should exclude draft releases from highest calculation" {
        $state = [RepositoryState]::new()
        
        $release1 = [ReleaseInfo]::new([PSCustomObject]@{ tag_name = "v1.0.0"; id = 1; draft = $false; prerelease = $false; html_url = "url1"; target_commitish = "sha1" })
        $release2 = [ReleaseInfo]::new([PSCustomObject]@{ tag_name = "v2.0.0"; id = 2; draft = $true; prerelease = $false; html_url = "url2"; target_commitish = "sha2" })  # draft
        $state.Releases = @($release1, $release2)
        
        # v1.0.0 should be highest because v2.0.0 is draft
        $result = Test-IsHighestNonPrereleaseVersion -State $state -ReleaseInfo $release1
        
        $result | Should -Be $true
    }
}
