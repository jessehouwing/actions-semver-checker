#############################################################################
# RuleSeverityValidation.Tests.ps1
# Integration tests to validate that all rules properly use error/warning
# severity levels based on configuration settings.
#############################################################################

BeforeAll {
    # Load required modules
    . "$PSScriptRoot/../../lib/StateModel.ps1"
    . "$PSScriptRoot/../../lib/ValidationRules.ps1"
    . "$PSScriptRoot/../../lib/RemediationActions.ps1"
    
    # Helper function to create a test state with common data
    function New-TestState {
        param(
            [switch]$WithPatchRelease,
            [switch]$WithDraftRelease,
            [switch]$WithMutableRelease,
            [switch]$WithMajorTag,
            [switch]$WithMinorTag,
            [switch]$WithFloatingRelease
        )
        
        $state = [RepositoryState]::new()
        $state.RepoOwner = "test"
        $state.RepoName = "test-repo"
        
        if ($WithPatchRelease) {
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 100
                draft = $false
                prerelease = $false
                html_url = "https://github.com/test/test-repo/releases/tag/v1.0.0"
                target_commitish = "abc123"
                immutable = $true
            }
            $state.Releases += [ReleaseInfo]::new($releaseData)
        }
        
        if ($WithDraftRelease) {
            $state.Tags += [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "def456", "tag")
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.1.0"
                id = 101
                draft = $true
                prerelease = $false
                html_url = "https://github.com/test/test-repo/releases/tag/v1.1.0"
                target_commitish = "def456"
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($releaseData)
        }
        
        if ($WithMutableRelease) {
            $state.Tags += [VersionRef]::new("v1.2.0", "refs/tags/v1.2.0", "ghi789", "tag")
            $releaseData = [PSCustomObject]@{
                tag_name = "v1.2.0"
                id = 102
                draft = $false
                prerelease = $false
                html_url = "https://github.com/test/test-repo/releases/tag/v1.2.0"
                target_commitish = "ghi789"
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($releaseData)
        }
        
        if ($WithMajorTag) {
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
        }
        
        if ($WithMinorTag) {
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
        }
        
        if ($WithFloatingRelease) {
            $releaseData = [PSCustomObject]@{
                tag_name = "v1"
                id = 200
                draft = $false
                prerelease = $false
                html_url = "https://github.com/test/test-repo/releases/tag/v1"
                target_commitish = "abc123"
                immutable = $true
            }
            $state.Releases += [ReleaseInfo]::new($releaseData)
        }
        
        return $state
    }
}

Describe "Rule Severity Level Validation" {
    
    Context "Releases Rules - Config-Based Severity" {
        
        It "patch_release_required uses check-releases for severity" {
            # Load the rule
            . "$PSScriptRoot/../../lib/rules/releases/ReleaseRulesHelper.ps1"
            . "$PSScriptRoot/../../lib/rules/releases/patch_release_required/patch_release_required.ps1"
            
            $state = New-TestState
            $state.Tags += [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "xyz999", "tag")
            
            # Test error level
            $config = @{ 'check-releases' = 'error' }
            $items = & $Rule_PatchReleaseRequired.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_PatchReleaseRequired.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'error'
            }
            
            # Test warning level
            $config = @{ 'check-releases' = 'warning' }
            $items = & $Rule_PatchReleaseRequired.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_PatchReleaseRequired.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'warning'
            }
            
            # Test disabled
            $config = @{ 'check-releases' = 'none' }
            $items = & $Rule_PatchReleaseRequired.Condition $state $config
            $items.Count | Should -Be 0
        }
        
        It "release_should_be_published uses most-severe-wins logic for severity" {
            # Load the rule
            . "$PSScriptRoot/../../lib/rules/releases/ReleaseRulesHelper.ps1"
            . "$PSScriptRoot/../../lib/rules/releases/release_should_be_published/release_should_be_published.ps1"
            
            $state = New-TestState -WithDraftRelease
            
            # Both error → error
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'error'
            }
            $items = & $Rule_ReleaseShouldBePublished.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'error'
            }
            
            # One error + one warning → error (most severe wins)
            $config = @{ 
                'check-releases' = 'error'
                'check-release-immutability' = 'warning'
            }
            $items = & $Rule_ReleaseShouldBePublished.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'error'
            }
            
            # Other way around → error (most severe wins)
            $config = @{ 
                'check-releases' = 'warning'
                'check-release-immutability' = 'error'
            }
            $items = & $Rule_ReleaseShouldBePublished.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'error'
            }
            
            # Both warning → warning
            $config = @{ 
                'check-releases' = 'warning'
                'check-release-immutability' = 'warning'
            }
            $items = & $Rule_ReleaseShouldBePublished.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_ReleaseShouldBePublished.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'warning'
            }
        }
        
        It "release_should_be_immutable uses check-release-immutability for severity" {
            # Load the rule
            . "$PSScriptRoot/../../lib/rules/releases/ReleaseRulesHelper.ps1"
            . "$PSScriptRoot/../../lib/rules/releases/release_should_be_immutable/release_should_be_immutable.ps1"
            
            $state = New-TestState -WithMutableRelease
            
            # Test error level
            $config = @{ 'check-release-immutability' = 'error' }
            $items = & $Rule_ReleaseShouldBeImmutable.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_ReleaseShouldBeImmutable.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'error'
            }
            
            # Test warning level
            $config = @{ 'check-release-immutability' = 'warning' }
            $items = & $Rule_ReleaseShouldBeImmutable.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_ReleaseShouldBeImmutable.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'warning'
            }
            
            # Test disabled
            $config = @{ 'check-release-immutability' = 'none' }
            $items = & $Rule_ReleaseShouldBeImmutable.Condition $state $config
            $items.Count | Should -Be 0
        }
        
        It "floating_version_no_release uses config-based severity for mutable releases" {
            # Load the rule
            . "$PSScriptRoot/../../lib/rules/releases/floating_version_no_release/floating_version_no_release.ps1"
            
            # Test immutable floating release → always error (unfixable)
            $state = New-TestState -WithFloatingRelease
            $config = @{ 'check-releases' = 'error' }
            $items = & $Rule_FloatingVersionNoRelease.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_FloatingVersionNoRelease.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'error'
                $issue.Status | Should -Be 'unfixable'
            }
            
            # Test mutable floating release with error config → error
            $state = [RepositoryState]::new()
            $releaseData = [PSCustomObject]@{
                tag_name = "v2"
                id = 300
                draft = $true
                prerelease = $false
                html_url = "https://github.com/test/test-repo/releases/tag/v2"
                target_commitish = "xyz123"
                immutable = $false
            }
            $state.Releases += [ReleaseInfo]::new($releaseData)
            
            $config = @{ 'check-releases' = 'error'; 'check-release-immutability' = 'none' }
            $items = & $Rule_FloatingVersionNoRelease.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_FloatingVersionNoRelease.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'error'
            }
            
            # Test mutable floating release with warning config → warning
            $config = @{ 'check-releases' = 'warning'; 'check-release-immutability' = 'none' }
            $items = & $Rule_FloatingVersionNoRelease.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_FloatingVersionNoRelease.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'warning'
            }
            
            # Test mutable floating release with most-severe-wins (error + warning → error)
            $config = @{ 'check-releases' = 'error'; 'check-release-immutability' = 'warning' }
            $items = & $Rule_FloatingVersionNoRelease.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_FloatingVersionNoRelease.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'error'
            }
        }
    }
    
    Context "Version Tracking Rules - Config-Based Severity for Minor" {
        
        It "minor_tag_missing uses check-minor-version for severity" {
            # Load the rule
            . "$PSScriptRoot/../../lib/rules/version_tracking/minor_tag_missing/minor_tag_missing.ps1"
            
            $state = New-TestState -WithPatchRelease -WithMajorTag
            
            # Test error level
            $config = @{ 
                'check-minor-version' = 'error'
                'floating-versions-use' = 'tags'
                'ignore-preview-releases' = $false
            }
            $items = & $Rule_MinorTagMissing.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_MinorTagMissing.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'error'
            }
            
            # Test warning level
            $config = @{ 
                'check-minor-version' = 'warning'
                'floating-versions-use' = 'tags'
                'ignore-preview-releases' = $false
            }
            $items = & $Rule_MinorTagMissing.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_MinorTagMissing.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'warning'
            }
            
            # Test disabled
            $config = @{ 
                'check-minor-version' = 'none'
                'floating-versions-use' = 'tags'
            }
            $items = & $Rule_MinorTagMissing.Condition $state $config
            $items.Count | Should -Be 0
        }
        
        It "minor_tag_tracks_highest_patch uses check-minor-version for severity" {
            # Load the rule
            . "$PSScriptRoot/../../lib/rules/version_tracking/minor_tag_tracks_highest_patch/minor_tag_tracks_highest_patch.ps1"
            
            $state = New-TestState -WithPatchRelease -WithMinorTag
            # Add another patch that's higher
            $state.Tags += [VersionRef]::new("v1.0.1", "refs/tags/v1.0.1", "def456", "tag")
            
            # Test error level
            $config = @{ 
                'check-minor-version' = 'error'
                'floating-versions-use' = 'tags'
                'ignore-preview-releases' = $false
            }
            $items = & $Rule_MinorTagTracksHighestPatch.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_MinorTagTracksHighestPatch.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'error'
            }
            
            # Test warning level
            $config = @{ 
                'check-minor-version' = 'warning'
                'floating-versions-use' = 'tags'
                'ignore-preview-releases' = $false
            }
            $items = & $Rule_MinorTagTracksHighestPatch.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_MinorTagTracksHighestPatch.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'warning'
            }
        }
    }
    
    Context "Version Tracking Rules - Hardcoded Error for Major" {
        
        It "major_tag_tracks_highest_patch always uses error severity" {
            # Load the rule
            . "$PSScriptRoot/../../lib/rules/version_tracking/major_tag_tracks_highest_patch/major_tag_tracks_highest_patch.ps1"
            
            $state = New-TestState -WithPatchRelease -WithMajorTag
            # Add another patch that's higher
            $state.Tags += [VersionRef]::new("v1.0.1", "refs/tags/v1.0.1", "def456", "tag")
            
            # Always error regardless of config
            $config = @{ 
                'floating-versions-use' = 'tags'
                'ignore-preview-releases' = $false
            }
            $items = & $Rule_MajorTagTracksHighestPatch.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_MajorTagTracksHighestPatch.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'error'
            }
        }
    }
    
    Context "Ref Type Rules - Always Error" {
        
        It "tag_should_be_branch always uses error severity" {
            # Load the rule
            . "$PSScriptRoot/../../lib/rules/ref_type/tag_should_be_branch/tag_should_be_branch.ps1"
            
            $state = New-TestState -WithMajorTag
            
            $config = @{ 'floating-versions-use' = 'branches' }
            $items = & $Rule_TagShouldBeBranch.Condition $state $config
            if ($items.Count -gt 0) {
                $issue = & $Rule_TagShouldBeBranch.CreateIssue $items[0] $state $config
                $issue.Severity | Should -Be 'error'
            }
        }
    }
}

Describe "Rule Configuration Matrix - Complete Validation" {
    
    Context "All rules respect configuration settings" {
        
        It "loads all rules without errors" {
            $rules = Get-ValidationRule
            $rules.Count | Should -BeGreaterThan 20
            
            foreach ($rule in $rules) {
                $rule.Name | Should -Not -BeNullOrEmpty
                $rule.Description | Should -Not -BeNullOrEmpty
                $rule.Priority | Should -BeGreaterThan 0
                $rule.Category | Should -Not -BeNullOrEmpty
                $rule.Condition | Should -Not -BeNullOrEmpty
                $rule.Check | Should -Not -BeNullOrEmpty
                $rule.CreateIssue | Should -Not -BeNullOrEmpty
            }
        }
        
        It "config-based severity rules have consistent behavior" {
            # Rules that should respect check-minor-version
            $minorRules = @(
                'minor_tag_missing',
                'minor_tag_tracks_highest_patch',
                'minor_branch_missing',
                'minor_branch_tracks_highest_patch'
            )
            
            $rules = Get-ValidationRule
            foreach ($ruleName in $minorRules) {
                $rule = $rules | Where-Object { $_.Name -eq $ruleName }
                $rule | Should -Not -BeNullOrEmpty -Because "Rule $ruleName should exist"
                $rule.Description | Should -Not -BeNullOrEmpty
            }
        }
        
        It "all release rules respect check-releases or check-release-immutability" {
            $releaseRules = @(
                'patch_release_required',
                'release_should_be_published',
                'release_should_be_immutable',
                'highest_patch_release_should_be_latest',
                'duplicate_release'
            )
            
            $rules = Get-ValidationRule
            foreach ($ruleName in $releaseRules) {
                $rule = $rules | Where-Object { $_.Name -eq $ruleName }
                $rule | Should -Not -BeNullOrEmpty -Because "Rule $ruleName should exist"
                $rule.Category | Should -Be 'releases'
            }
        }
    }
}
