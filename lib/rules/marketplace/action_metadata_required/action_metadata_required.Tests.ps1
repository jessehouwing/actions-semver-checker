#############################################################################
# Tests for action_metadata_required rule
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../MarketplaceRulesHelper.ps1"
    . "$PSScriptRoot/action_metadata_required.ps1"
}

Describe "action_metadata_required" {
    Context "Rule Properties" {
        It "should have correct name" {
            $Rule_ActionMetadataRequired.Name | Should -Be "action_metadata_required"
        }
        
        It "should have correct category" {
            $Rule_ActionMetadataRequired.Category | Should -Be "marketplace"
        }
        
        It "should have low priority (runs early)" {
            $Rule_ActionMetadataRequired.Priority | Should -BeLessOrEqual 10
        }
    }
    
    Context "Condition" {
        It "should return empty when check-marketplace is none" {
            $state = [RepositoryState]::new()
            $config = @{ 'check-marketplace' = 'none' }
            
            $result = & $Rule_ActionMetadataRequired.Condition $state $config
            
            $result | Should -BeNullOrEmpty
        }
        
        It "should return empty when check-marketplace is disabled" {
            $state = [RepositoryState]::new()
            $config = @{ 'check-marketplace' = $null }
            
            $result = & $Rule_ActionMetadataRequired.Condition $state $config
            
            $result | Should -BeNullOrEmpty
        }
        
        It "should return item when marketplace metadata is missing and check-marketplace is error" {
            $state = [RepositoryState]::new()
            $state.MarketplaceMetadata = [MarketplaceMetadata]::new()  # All defaults to false
            $config = @{ 'check-marketplace' = 'error' }
            
            $result = & $Rule_ActionMetadataRequired.Condition $state $config
            
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
        }
        
        It "should return item when marketplace metadata is missing and check-marketplace is warning" {
            $state = [RepositoryState]::new()
            $state.MarketplaceMetadata = [MarketplaceMetadata]::new()
            $config = @{ 'check-marketplace' = 'warning' }
            
            $result = & $Rule_ActionMetadataRequired.Condition $state $config
            
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "should return empty when all marketplace metadata is valid" {
            $state = [RepositoryState]::new()
            $metadata = [MarketplaceMetadata]::new()
            $metadata.ActionFileExists = $true
            $metadata.HasName = $true
            $metadata.HasDescription = $true
            $metadata.HasBrandingIcon = $true
            $metadata.HasBrandingColor = $true
            $metadata.ReadmeExists = $true
            $state.MarketplaceMetadata = $metadata
            $config = @{ 'check-marketplace' = 'error' }
            
            $result = & $Rule_ActionMetadataRequired.Condition $state $config
            
            $result | Should -BeNullOrEmpty
        }
    }
    
    Context "CreateIssue" {
        It "should create error issue when check-marketplace is error" {
            $state = [RepositoryState]::new()
            $state.MarketplaceMetadata = [MarketplaceMetadata]::new()
            $item = [PSCustomObject]@{ Type = 'metadata_check' }
            $config = @{ 'check-marketplace' = 'error' }
            
            $issue = & $Rule_ActionMetadataRequired.CreateIssue $item $state $config
            
            $issue | Should -Not -BeNullOrEmpty
            $issue.Type | Should -Be "missing_marketplace_metadata"
            $issue.Severity | Should -Be "error"
            $issue.Status | Should -Be "manual_fix_required"
        }
        
        It "should create warning issue when check-marketplace is warning" {
            $state = [RepositoryState]::new()
            $state.MarketplaceMetadata = [MarketplaceMetadata]::new()
            $item = [PSCustomObject]@{ Type = 'metadata_check' }
            $config = @{ 'check-marketplace' = 'warning' }
            
            $issue = & $Rule_ActionMetadataRequired.CreateIssue $item $state $config
            
            $issue.Severity | Should -Be "warning"
        }
        
        It "should include all missing requirements in message" {
            $state = [RepositoryState]::new()
            $metadata = [MarketplaceMetadata]::new()
            # All fields missing
            $state.MarketplaceMetadata = $metadata
            $item = [PSCustomObject]@{ Type = 'metadata_check' }
            $config = @{ 'check-marketplace' = 'error' }
            
            $issue = & $Rule_ActionMetadataRequired.CreateIssue $item $state $config
            
            $issue.Message | Should -Match "action.yaml"
            $issue.Message | Should -Match "README.md"
        }
        
        It "should not be auto-fixable" {
            $state = [RepositoryState]::new()
            $state.MarketplaceMetadata = [MarketplaceMetadata]::new()
            $item = [PSCustomObject]@{ Type = 'metadata_check' }
            $config = @{ 'check-marketplace' = 'error' }
            
            $issue = & $Rule_ActionMetadataRequired.CreateIssue $item $state $config
            
            $issue.IsAutoFixable | Should -Be $false
            $issue.RemediationAction | Should -BeNullOrEmpty
        }
        
        It "should provide manual fix instructions" {
            $state = [RepositoryState]::new()
            $metadata = [MarketplaceMetadata]::new()
            $metadata.ActionFileExists = $true
            $metadata.ActionFilePath = "action.yaml"
            $state.MarketplaceMetadata = $metadata
            $item = [PSCustomObject]@{ Type = 'metadata_check' }
            $config = @{ 'check-marketplace' = 'error' }
            
            $issue = & $Rule_ActionMetadataRequired.CreateIssue $item $state $config
            
            $issue.ManualFixCommand | Should -Not -BeNullOrEmpty
            $issue.ManualFixCommand | Should -Match "action.yaml"
        }
    }
}

Describe "MarketplaceMetadata" {
    Context "IsValid" {
        It "should return true when all requirements are met" {
            $metadata = [MarketplaceMetadata]::new()
            $metadata.ActionFileExists = $true
            $metadata.HasName = $true
            $metadata.HasDescription = $true
            $metadata.HasBrandingIcon = $true
            $metadata.HasBrandingColor = $true
            $metadata.ReadmeExists = $true
            
            $metadata.IsValid() | Should -Be $true
        }
        
        It "should return false when action file is missing" {
            $metadata = [MarketplaceMetadata]::new()
            $metadata.ActionFileExists = $false
            $metadata.HasName = $true
            $metadata.HasDescription = $true
            $metadata.HasBrandingIcon = $true
            $metadata.HasBrandingColor = $true
            $metadata.ReadmeExists = $true
            
            $metadata.IsValid() | Should -Be $false
        }
        
        It "should return false when name is missing" {
            $metadata = [MarketplaceMetadata]::new()
            $metadata.ActionFileExists = $true
            $metadata.HasName = $false
            $metadata.HasDescription = $true
            $metadata.HasBrandingIcon = $true
            $metadata.HasBrandingColor = $true
            $metadata.ReadmeExists = $true
            
            $metadata.IsValid() | Should -Be $false
        }
        
        It "should return false when README is missing" {
            $metadata = [MarketplaceMetadata]::new()
            $metadata.ActionFileExists = $true
            $metadata.HasName = $true
            $metadata.HasDescription = $true
            $metadata.HasBrandingIcon = $true
            $metadata.HasBrandingColor = $true
            $metadata.ReadmeExists = $false
            
            $metadata.IsValid() | Should -Be $false
        }
    }
    
    Context "GetMissingRequirements" {
        It "should return all missing requirements" {
            $metadata = [MarketplaceMetadata]::new()
            
            $missing = $metadata.GetMissingRequirements()
            
            $missing.Count | Should -Be 5
            $missing | Should -Contain "README.md file in repository root"
        }
        
        It "should return empty array when all requirements are met" {
            $metadata = [MarketplaceMetadata]::new()
            $metadata.ActionFileExists = $true
            $metadata.HasName = $true
            $metadata.HasDescription = $true
            $metadata.HasBrandingIcon = $true
            $metadata.HasBrandingColor = $true
            $metadata.ReadmeExists = $true
            
            $missing = $metadata.GetMissingRequirements()
            
            $missing.Count | Should -Be 0
        }
    }
}
