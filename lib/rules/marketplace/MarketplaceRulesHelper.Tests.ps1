#############################################################################
# Tests for MarketplaceRulesHelper functions
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../StateModel.ps1"
    . "$PSScriptRoot/../../Logging.ps1"
    . "$PSScriptRoot/../../GitHubApi.ps1"
    . "$PSScriptRoot/MarketplaceRulesHelper.ps1"
}

Describe "ConvertTo-MarketplaceSlug" {
    It "should convert simple name to lowercase slug" {
        $result = ConvertTo-MarketplaceSlug -ActionName "Test Action"
        $result | Should -Be "test-action"
    }
    
    It "should handle multiple spaces" {
        $result = ConvertTo-MarketplaceSlug -ActionName "Actions   SemVer   Checker"
        $result | Should -Be "actions-semver-checker"
    }
    
    It "should remove special characters" {
        $result = ConvertTo-MarketplaceSlug -ActionName "My Action! (v2.0)"
        $result | Should -Be "my-action-v20"
    }
    
    It "should handle already-lowercase names" {
        $result = ConvertTo-MarketplaceSlug -ActionName "my-action"
        $result | Should -Be "my-action"
    }
    
    It "should trim leading and trailing hyphens" {
        $result = ConvertTo-MarketplaceSlug -ActionName "  Test Action  "
        $result | Should -Be "test-action"
    }
    
    It "should convert 'Actions SemVer Checker' to 'actions-semver-checker'" {
        $result = ConvertTo-MarketplaceSlug -ActionName "Actions SemVer Checker"
        $result | Should -Be "actions-semver-checker"
    }
}

Describe "Test-MarketplaceVersionPublished" {
    BeforeAll {
        # Define the wrapper function so the helper uses it (and we can mock it)
        function global:Invoke-WebRequestWrapper {
            param($Uri, $Method, $ErrorAction, $TimeoutSec)
            throw "Invoke-WebRequestWrapper should be mocked in tests"
        }
    }
    
    AfterAll {
        # Clean up global function
        Remove-Item -Path "Function:\global:Invoke-WebRequestWrapper" -ErrorAction SilentlyContinue
    }
    
    Context "Successful marketplace query" {
        It "should return IsPublished=true when version is published" {
            # Mock Invoke-WebRequestWrapper to return a page with version in option value
            Mock Invoke-WebRequestWrapper {
                return @{
                    Content = @"
<html>
<head><title>Test Action</title></head>
<body>
<select>
<option value="v1.0.0">v1.0.0</option>
</select>
</body>
</html>
"@
                }
            }
            
            $result = Test-MarketplaceVersionPublished -ActionName "Test Action" -Version "v1.0.0"
            
            $result.IsPublished | Should -Be $true
            $result.Error | Should -BeNullOrEmpty
            $result.MarketplaceUrl | Should -Match "marketplace/actions/test-action.*version=v1.0.0"
        }
        
        It "should return IsPublished=false when version shows 'latest'" {
            # Mock Invoke-WebRequestWrapper to return a page showing "Use latest version"
            Mock Invoke-WebRequestWrapper {
                return @{
                    Content = @"
<html>
<head><title>Test Action</title></head>
<body>
<span>Use latest version</span>
</body>
</html>
"@
                }
            }
            
            $result = Test-MarketplaceVersionPublished -ActionName "Test Action" -Version "v99.0.0"
            
            $result.IsPublished | Should -Be $false
            $result.Error | Should -BeNullOrEmpty
        }
    }
    
    Context "Network errors" {
        It "should return error when request fails with 404" {
            Mock Invoke-WebRequestWrapper {
                $response = New-Object System.Net.Http.HttpResponseMessage([System.Net.HttpStatusCode]::NotFound)
                $exception = [System.Net.Http.HttpRequestException]::new("Not Found")
                $exception | Add-Member -NotePropertyName 'Response' -NotePropertyValue $response -Force
                throw $exception
            }
            
            $result = Test-MarketplaceVersionPublished -ActionName "Nonexistent Action" -Version "v1.0.0"
            
            $result.IsPublished | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }
        
        It "should return error with null IsPublished for network errors" {
            Mock Invoke-WebRequestWrapper {
                throw [System.Net.WebException]::new("Network error")
            }
            
            $result = Test-MarketplaceVersionPublished -ActionName "Test Action" -Version "v1.0.0"
            
            $result.IsPublished | Should -BeNullOrEmpty
            $result.Error | Should -Not -BeNullOrEmpty
            $result.Error | Should -Match "Failed to check marketplace"
        }
    }
    
    Context "Custom server URL" {
        It "should use custom server URL when provided" {
            Mock Invoke-WebRequestWrapper {
                return @{
                    Content = "Use v1.0.0"
                }
            }
            
            $result = Test-MarketplaceVersionPublished -ActionName "Test Action" -Version "v1.0.0" -ServerUrl "https://github.mycompany.com"
            
            $result.MarketplaceUrl | Should -Match "github.mycompany.com"
        }
    }
}

Describe "Get-ActionMarketplaceMetadata" {
    Context "YAML parsing" {
        BeforeAll {
            # Mock Get-GitHubFileContents to return test YAML
            Mock Get-GitHubFileContents {
                param($State, $Path, $Ref)
                
                if ($Path -eq 'action.yaml') {
                    return @"
name: 'Test Action'
description: 'A test action for unit testing'
branding:
  icon: 'check-circle'
  color: 'blue'
inputs:
  test-input:
    description: 'A test input'
runs:
  using: composite
  steps:
    - run: echo test
      shell: bash
"@
                }
                return $null
            }
            
            Mock Test-GitHubFileExists {
                param($State, $Path, $Ref)
                return $Path -eq 'README.md'
            }
            
            # Mock directory listing for README check
            Mock Get-GitHubDirectoryContents {
                param($State, $Path, $Ref)
                return @(
                    [PSCustomObject]@{ Name = 'action.yaml'; Path = 'action.yaml'; Type = 'file'; Sha = 'abc123' }
                    [PSCustomObject]@{ Name = 'README.md'; Path = 'README.md'; Type = 'file'; Sha = 'def456' }
                    [PSCustomObject]@{ Name = 'lib'; Path = 'lib'; Type = 'dir'; Sha = 'ghi789' }
                )
            }
        }
        
        It "should detect action.yaml exists" {
            $state = [RepositoryState]::new()
            $state.RepoOwner = "test"
            $state.RepoName = "repo"
            
            $metadata = Get-ActionMarketplaceMetadata -State $state
            
            $metadata.ActionFileExists | Should -Be $true
            $metadata.ActionFilePath | Should -Be 'action.yaml'
        }
        
        It "should extract name property" {
            $state = [RepositoryState]::new()
            $state.RepoOwner = "test"
            $state.RepoName = "repo"
            
            $metadata = Get-ActionMarketplaceMetadata -State $state
            
            $metadata.HasName | Should -Be $true
            $metadata.Name | Should -Be 'Test Action'
        }
        
        It "should extract description property" {
            $state = [RepositoryState]::new()
            $state.RepoOwner = "test"
            $state.RepoName = "repo"
            
            $metadata = Get-ActionMarketplaceMetadata -State $state
            
            $metadata.HasDescription | Should -Be $true
            $metadata.Description | Should -Be 'A test action for unit testing'
        }
        
        It "should extract branding icon" {
            $state = [RepositoryState]::new()
            $state.RepoOwner = "test"
            $state.RepoName = "repo"
            
            $metadata = Get-ActionMarketplaceMetadata -State $state
            
            $metadata.HasBrandingIcon | Should -Be $true
            $metadata.BrandingIcon | Should -Be 'check-circle'
        }
        
        It "should extract branding color" {
            $state = [RepositoryState]::new()
            $state.RepoOwner = "test"
            $state.RepoName = "repo"
            
            $metadata = Get-ActionMarketplaceMetadata -State $state
            
            $metadata.HasBrandingColor | Should -Be $true
            $metadata.BrandingColor | Should -Be 'blue'
        }
        
        It "should detect README.md exists" {
            $state = [RepositoryState]::new()
            $state.RepoOwner = "test"
            $state.RepoName = "repo"
            
            $metadata = Get-ActionMarketplaceMetadata -State $state
            
            $metadata.ReadmeExists | Should -Be $true
        }
        
        It "should return valid metadata when all requirements are met" {
            $state = [RepositoryState]::new()
            $state.RepoOwner = "test"
            $state.RepoName = "repo"
            
            $metadata = Get-ActionMarketplaceMetadata -State $state
            
            $metadata.IsValid() | Should -Be $true
        }
    }
    
    Context "Missing action file" {
        BeforeAll {
            Mock Get-GitHubFileContents {
                param($State, $Path, $Ref)
                return $null  # File not found
            }
            
            Mock Test-GitHubFileExists {
                param($State, $Path, $Ref)
                return $false
            }
            
            # Mock empty directory listing
            Mock Get-GitHubDirectoryContents {
                param($State, $Path, $Ref)
                return @()
            }
        }
        
        It "should report action file missing" {
            $state = [RepositoryState]::new()
            $state.RepoOwner = "test"
            $state.RepoName = "repo"
            
            $metadata = Get-ActionMarketplaceMetadata -State $state
            
            $metadata.ActionFileExists | Should -Be $false
            $metadata.IsValid() | Should -Be $false
        }
    }
    
    Context "Partial metadata" {
        BeforeAll {
            Mock Get-GitHubFileContents {
                param($State, $Path, $Ref)
                
                if ($Path -eq 'action.yaml') {
                    return @"
name: 'Test Action'
# Missing description and branding
inputs:
  test-input:
    description: 'A test input'
"@
                }
                return $null
            }
            
            Mock Test-GitHubFileExists {
                param($State, $Path, $Ref)
                return $false  # No README
            }
            
            # Mock empty directory listing (no README)
            Mock Get-GitHubDirectoryContents {
                param($State, $Path, $Ref)
                return @(
                    [PSCustomObject]@{ Name = 'action.yaml'; Path = 'action.yaml'; Type = 'file'; Sha = 'abc123' }
                )
            }
        }
        
        It "should report missing fields" {
            $state = [RepositoryState]::new()
            $state.RepoOwner = "test"
            $state.RepoName = "repo"
            
            $metadata = Get-ActionMarketplaceMetadata -State $state
            
            $metadata.ActionFileExists | Should -Be $true
            $metadata.HasName | Should -Be $true
            $metadata.HasDescription | Should -Be $false
            $metadata.HasBrandingIcon | Should -Be $false
            $metadata.HasBrandingColor | Should -Be $false
            $metadata.ReadmeExists | Should -Be $false
            $metadata.IsValid() | Should -Be $false
        }
        
        It "should list missing requirements" {
            $state = [RepositoryState]::new()
            $state.RepoOwner = "test"
            $state.RepoName = "repo"
            
            $metadata = Get-ActionMarketplaceMetadata -State $state
            $missing = $metadata.GetMissingRequirements()
            
            $missing | Should -Contain "description property in action.yaml"
            $missing | Should -Contain "branding.icon property in action.yaml"
            $missing | Should -Contain "branding.color property in action.yaml"
            $missing | Should -Contain "README.md file in repository root"
        }
    }
    
    Context "action.yml fallback" {
        BeforeAll {
            Mock Get-GitHubFileContents {
                param($State, $Path, $Ref)
                
                if ($Path -eq 'action.yml') {
                    return @"
name: 'Test Action YML'
description: 'Found via yml fallback'
branding:
  icon: 'star'
  color: 'yellow'
"@
                }
                return $null  # action.yaml not found
            }
            
            Mock Test-GitHubFileExists {
                param($State, $Path, $Ref)
                return $Path -eq 'README.md'
            }
            
            # Mock directory listing with README (for action.yml fallback)
            Mock Get-GitHubDirectoryContents {
                param($State, $Path, $Ref)
                return @(
                    [PSCustomObject]@{ Name = 'action.yml'; Path = 'action.yml'; Type = 'file'; Sha = 'abc123' }
                    [PSCustomObject]@{ Name = 'README.md'; Path = 'README.md'; Type = 'file'; Sha = 'def456' }
                )
            }
        }
        
        It "should find action.yml when action.yaml doesn't exist" {
            $state = [RepositoryState]::new()
            $state.RepoOwner = "test"
            $state.RepoName = "repo"
            
            $metadata = Get-ActionMarketplaceMetadata -State $state
            
            $metadata.ActionFileExists | Should -Be $true
            $metadata.ActionFilePath | Should -Be 'action.yml'
            $metadata.Name | Should -Be 'Test Action YML'
        }
    }
}
