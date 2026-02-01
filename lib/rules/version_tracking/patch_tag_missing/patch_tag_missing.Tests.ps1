#############################################################################
# Tests for Rule: patch_tag_missing
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/patch_tag_missing.ps1"
}

Describe "patch_tag_missing" {
    Context "Condition - Only applies when check-releases is 'none'" {
        It "should return empty when check-releases is 'error'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            # No patch exists
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-releases' = 'error'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should return empty when check-releases is 'warning'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            # No patch exists
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-releases' = 'warning'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should apply when check-releases is 'none'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            # No patch exists
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-releases' = 'none'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            $result.Count | Should -Be 1
        }
    }
    
    Context "Condition - Major version tags without patches" {
        It "should detect missing patch for major tag" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            # No v1.0.0 exists
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-releases' = 'none'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].FloatingVersion.Version | Should -Be "v1"
            $result[0].ExpectedPatchVersion | Should -Be "v1.0.0"
        }
        
        It "should pass when patch exists for major version" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-releases' = 'none'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should handle major branch when floating-versions-use is branches" {
            $state = [RepositoryState]::new()
            $state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            # No v1.0.0 patch tag exists
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'branches'
                'check-releases' = 'none'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].ExpectedPatchVersion | Should -Be "v1.0.0"
        }
    }
    
    Context "Condition - Minor version tags without patches" {
        It "should detect missing patch for minor tag" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            # No v1.0.0 exists
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-releases' = 'none'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].FloatingVersion.Version | Should -Be "v1.0"
            $result[0].ExpectedPatchVersion | Should -Be "v1.0.0"
        }
        
        It "should pass when patch exists for minor version" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-releases' = 'none'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should handle different minor versions separately" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.1", "refs/tags/v1.1", "def456", "tag")
            # No patches exist for either
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-releases' = 'none'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            $result.Count | Should -Be 2
        }
    }
    
    Context "Condition - Latest tag without patches" {
        It "should detect missing patch for latest tag" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            # No patches exist
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-releases' = 'none'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].FloatingVersion.Version | Should -Be "latest"
            $result[0].ExpectedPatchVersion | Should -Be "v1.0.0"
        }
        
        It "should pass when at least one patch exists for latest" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("latest", "refs/tags/latest", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v2.5.7", "refs/tags/v2.5.7", "abc123", "tag")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-releases' = 'none'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
    }
    
    Context "Condition - Ignored versions" {
        It "should skip ignored floating versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $ignored.IsIgnored = $true
            $state.Tags += $ignored
            $state.IgnoreVersions = @("v1")
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-releases' = 'none'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            $result.Count | Should -Be 0
        }
        
        It "should skip ignored patch versions when checking if patches exist" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $ignoredPatch = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $ignoredPatch.IsIgnored = $true
            $state.Tags += $ignoredPatch
            $state.IgnoreVersions = @("v1.0.0")
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-releases' = 'none'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            # v1.0.0 is ignored, so v1 should be reported as missing patches
            $result.Count | Should -Be 1
        }
    }
    
    Context "Condition - Patches in branches" {
        It "should find patches that exist as branches" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Branches += [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "abc123", "branch")
            $state.IgnoreVersions = @()
            
            $config = @{ 
                'floating-versions-use' = 'tags'
                'check-releases' = 'none'
            }
            $result = & $Rule_PatchTagMissing.Condition $state $config
            
            # Patch exists (even as branch), so should pass
            $result.Count | Should -Be 0
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with correct details for major version" {
            $state = [RepositoryState]::new()
            $floatingTag = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            
            $item = [PSCustomObject]@{
                FloatingVersion = $floatingTag
                ExpectedPatchVersion = "v1.0.0"
            }
            $config = @{ 'check-releases' = 'none' }
            
            $issue = & $Rule_PatchTagMissing.CreateIssue $item $state $config
            
            $issue.Type | Should -Be "missing_patch_version"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1.0.0"
            $issue.Message | Should -Match "v1.*v1.0.0"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "CreateTagAction"
        }
        
        It "should configure CreateTagAction with floating version SHA" {
            $state = [RepositoryState]::new()
            $floatingTag = [VersionRef]::new("v2", "refs/tags/v2", "def456", "tag")
            
            $item = [PSCustomObject]@{
                FloatingVersion = $floatingTag
                ExpectedPatchVersion = "v2.0.0"
            }
            $config = @{ 'check-releases' = 'none' }
            
            $issue = & $Rule_PatchTagMissing.CreateIssue $item $state $config
            
            $issue.RemediationAction.TagName | Should -Be "v2.0.0"
            $issue.RemediationAction.Sha | Should -Be "def456"
        }
    }
}
