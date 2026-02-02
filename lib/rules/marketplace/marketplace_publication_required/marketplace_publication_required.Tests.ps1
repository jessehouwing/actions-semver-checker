#############################################################################
# Tests for marketplace_publication_required rule
#############################################################################

BeforeAll {
    # Define a script-scoped variable that tests can override to control mock behavior
    $script:MockMarketplaceResponse = $null
    
    # Define the wrapper function BEFORE loading helper scripts so they can detect it
    # This wrapper returns a controllable response - tests set $script:MockMarketplaceResponse
    function global:Invoke-WebRequestWrapper {
        param($Uri, $Method, $ErrorAction, $TimeoutSec)
        
        if ($script:MockMarketplaceResponse) {
            return $script:MockMarketplaceResponse
        }
        
        # Default: return empty page (no version matches)
        return @{
            Content = "<html><body>Default test response</body></html>"
        }
    }
    
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../VersionParser.ps1"
    . "$PSScriptRoot/../MarketplaceRulesHelper.ps1"
    . "$PSScriptRoot/marketplace_publication_required.ps1"
}

AfterAll {
    # Clean up global function
    Remove-Item -Path "Function:\global:Invoke-WebRequestWrapper" -ErrorAction SilentlyContinue
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
            # Control the mock to return a page WITH the version
            $script:MockMarketplaceResponse = @{
                Content = @"
<html>
<head><title>Marketplace</title></head>
<body>
<select name="version" class="version-picker">
  <option value="v1.0.9" selected>v1.0.9</option>
  <option value="v1.0.8">v1.0.8</option>
</select>
</body>
</html>
"@
            }
            
            $state = [RepositoryState]::new()
            $state.ServerUrl = "https://github.com"
            
            # Valid metadata with ALL required fields
            $metadata = [MarketplaceMetadata]::new()
            $metadata.ActionFileExists = $true
            $metadata.ActionFilePath = "action.yaml"
            $metadata.HasName = $true
            $metadata.Name = "Test Action"
            $metadata.HasDescription = $true
            $metadata.Description = "Test description"
            $metadata.HasBrandingIcon = $true
            $metadata.BrandingIcon = "check"
            $metadata.HasBrandingColor = $true
            $metadata.BrandingColor = "blue"
            $metadata.ReadmeExists = $true
            $state.MarketplaceMetadata = $metadata
            
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.9"  # Version that IS in the mock HTML
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/owner/repo/releases/tag/v1.0.9"
                target_commitish = "abc123"
                is_latest = $true
            }
            $release = [ReleaseInfo]::new($releaseData)
            $config = @{ 'check-marketplace' = 'error' }
            
            $result = & $Rule_MarketplacePublicationRequired.Check $release $state $config
            
            $result | Should -Be $true
        }
        
        It "should return false when version is not published to marketplace" {
            # This test actually calls the GitHub Marketplace to verify behavior.
            # The marketplace_publication_required rule's Check function calls Test-MarketplaceVersionPublished
            # which performs a real HTTP request. The mocking approach doesn't work because the
            # scriptblock binds functions at definition time, not call time.
            #
            # Test-MarketplaceVersionPublished is independently tested in MarketplaceRulesHelper.Tests.ps1
            # with proper mocking, so we test the rule integration here using an unpublished version.
            
            # Control the mock to return a page without the version
            $script:MockMarketplaceResponse = @{
                Content = @"
<html>
<head><title>Marketplace</title></head>
<body>
<select name="version" class="version-picker">
  <option value="v1.0.8">v1.0.8</option>
  <option value="v1.0.7">v1.0.7</option>
</select>
</body>
</html>
"@
            }
            
            $state = [RepositoryState]::new()
            $state.ServerUrl = "https://github.com"
            
            # Valid metadata with ALL required fields
            $metadata = [MarketplaceMetadata]::new()
            $metadata.ActionFileExists = $true
            $metadata.ActionFilePath = "action.yaml"
            $metadata.HasName = $true
            $metadata.Name = "Test Action"
            $metadata.HasDescription = $true
            $metadata.Description = "Test description"
            $metadata.HasBrandingIcon = $true
            $metadata.BrandingIcon = "check"
            $metadata.HasBrandingColor = $true
            $metadata.BrandingColor = "blue"
            $metadata.ReadmeExists = $true
            $state.MarketplaceMetadata = $metadata
            
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.9"  # Version NOT in the mock HTML
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://github.com/owner/repo/releases/tag/v1.0.9"
                target_commitish = "abc123"
                is_latest = $true
            }
            $release = [ReleaseInfo]::new($releaseData)
            $config = @{ 'check-marketplace' = 'error' }
            
            $result = & $Rule_MarketplacePublicationRequired.Check $release $state $config
            
            $result | Should -Be $false
        }
        
        It "should return true when marketplace check has error (avoid false positives)" {
            $state = [RepositoryState]::new()
            $state.ServerUrl = "https://github.com"
            
            # Valid metadata with ALL required fields
            $metadata = [MarketplaceMetadata]::new()
            $metadata.ActionFileExists = $true
            $metadata.ActionFilePath = "action.yaml"
            $metadata.HasName = $true
            $metadata.Name = "Test Action"
            $metadata.HasDescription = $true
            $metadata.Description = "Test description"
            $metadata.HasBrandingIcon = $true
            $metadata.BrandingIcon = "check"
            $metadata.HasBrandingColor = $true
            $metadata.BrandingColor = "blue"
            $metadata.ReadmeExists = $true
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
            
            # Mock the web request to throw an error (simulating network failure)
            Mock Invoke-WebRequestWrapper {
                throw "Network connection error"
            }
            
            $result = & $Rule_MarketplacePublicationRequired.Check $release $state $config
            
            # Should return true to avoid false positives on errors
            $result | Should -Be $true
        }
    }
}
