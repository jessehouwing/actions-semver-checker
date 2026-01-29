BeforeAll {
    # Import the state model first, then the validator module
    . "$PSScriptRoot/StateModel.ps1"
    . "$PSScriptRoot/Validator.ps1"
}

Describe "ValidatorBase" {
    It "Should throw when Validate is not implemented" {
        $validator = [ValidatorBase]::new("Test", "Test validator")
        $state = [RepositoryState]::new()
        $config = @{}
        
        { $validator.Validate($state, $config) } | Should -Throw "*must be implemented*"
    }
}

Describe "FloatingVersionValidator" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:config = @{
            checkReleases = "error"
            checkReleaseImmutability = "error"
        }
        $script:validator = [FloatingVersionValidator]::new()
    }
    
    It "Should create validator with correct name" {
        $script:validator.Name | Should -Be "FloatingVersion"
    }
    
    It "Should return empty issues for patch versions only" {
        # Add a patch version
        $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
        $script:state.Tags = @($tag)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
    
    It "Should validate major version with patch versions" {
        # Add major and patch versions
        $majorTag = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
        $patchTag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
        $script:state.Tags = @($majorTag, $patchTag)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
    
    It "Should validate minor version with patch versions" {
        # Add minor and patch versions
        $minorTag = [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
        $patchTag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
        $script:state.Tags = @($minorTag, $patchTag)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
}

Describe "ReleaseValidator" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:config = @{
            checkReleases = "error"
            checkReleaseImmutability = "error"
        }
        $script:validator = [ReleaseValidator]::new()
    }
    
    It "Should create validator with correct name" {
        $script:validator.Name | Should -Be "Release"
    }
    
    It "Should return no issues when check-releases is none" {
        $script:config.checkReleases = "none"
        
        $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
        $script:state.Tags = @($tag)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
    
    It "Should report missing release for patch version" {
        $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
        $script:state.Tags = @($tag)
        $script:state.Releases = @()
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 1
        $issues[0].Type | Should -Be "missing_release"
        $issues[0].Severity | Should -Be "error"
        $issues[0].Version | Should -Be "v1.0.0"
        $issues[0].ManualFixCommand | Should -Match "gh release create v1.0.0"
    }
    
    It "Should not report issue when release exists" {
        $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
        $script:state.Tags = @($tag)
        
        $releaseData = [PSCustomObject]@{
            tag_name = "v1.0.0"
            id = 12345
            draft = $false
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
    
    It "Should skip ignored versions" {
        $script:config.ignoreVersions = @("v1.0.0")
        
        $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
        $script:state.Tags = @($tag)
        $script:state.Releases = @()
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
    
    It "Should not check floating versions" {
        # Major version should not be checked for releases
        $tag = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
        $script:state.Tags = @($tag)
        $script:state.Releases = @()
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
    
    It "Should report with warning severity when configured" {
        $script:config.checkReleases = "warning"
        
        $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
        $script:state.Tags = @($tag)
        $script:state.Releases = @()
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 1
        $issues[0].Severity | Should -Be "warning"
    }
}

Describe "ReleaseImmutabilityValidator" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:config = @{
            checkReleases = "error"
            checkReleaseImmutability = "error"
        }
        $script:validator = [ReleaseImmutabilityValidator]::new()
    }
    
    It "Should create validator with correct name" {
        $script:validator.Name | Should -Be "ReleaseImmutability"
    }
    
    It "Should return no issues when check-release-immutability is none" {
        $script:config.checkReleaseImmutability = "none"
        
        $releaseData = [PSCustomObject]@{
            tag_name = "v1.0.0"
            id = 12345
            draft = $true
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
    
    It "Should report draft release for patch version" {
        $releaseData = [PSCustomObject]@{
            tag_name = "v1.0.0"
            id = 12345
            draft = $true
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 1
        $issues[0].Type | Should -Be "draft_release"
        $issues[0].Severity | Should -Be "error"
        $issues[0].Version | Should -Be "v1.0.0"
        $issues[0].ManualFixCommand | Should -Match "gh release edit v1.0.0"
    }
    
    It "Should not report issue for published release" {
        $releaseData = [PSCustomObject]@{
            tag_name = "v1.0.0"
            id = 12345
            draft = $false
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
    
    It "Should skip ignored versions" {
        $script:config.ignoreVersions = @("v1.0.0")
        
        $releaseData = [PSCustomObject]@{
            tag_name = "v1.0.0"
            id = 12345
            draft = $true
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
    
    It "Should not check floating version releases" {
        $releaseData = [PSCustomObject]@{
            tag_name = "v1"
            id = 12345
            draft = $true
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/v1"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
    
    It "Should report with warning severity when configured" {
        $script:config.checkReleaseImmutability = "warning"
        
        $releaseData = [PSCustomObject]@{
            tag_name = "v1.0.0"
            id = 12345
            draft = $true
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 1
        $issues[0].Severity | Should -Be "warning"
    }
}

Describe "FloatingVersionReleaseValidator" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:config = @{
            checkReleases = "error"
            checkReleaseImmutability = "error"
        }
        $script:validator = [FloatingVersionReleaseValidator]::new()
    }
    
    It "Should create validator with correct name" {
        $script:validator.Name | Should -Be "FloatingVersionRelease"
    }
    
    It "Should return no issues when checks are disabled" {
        $script:config.checkReleases = "none"
        $script:config.checkReleaseImmutability = "none"
        
        $releaseData = [PSCustomObject]@{
            tag_name = "v1"
            id = 12345
            draft = $false
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/v1"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
    
    It "Should report mutable release on floating version (major)" {
        $releaseData = [PSCustomObject]@{
            tag_name = "v1"
            id = 12345
            draft = $true  # Draft releases are mutable
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/v1"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 1
        $issues[0].Type | Should -Be "mutable_floating_release"
        $issues[0].Version | Should -Be "v1"
        $issues[0].ManualFixCommand | Should -Match "gh release delete v1"
    }
    
    It "Should report mutable release on floating version (minor)" {
        $releaseData = [PSCustomObject]@{
            tag_name = "v1.0"
            id = 12345
            draft = $true  # Draft releases are mutable
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/v1.0"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 1
        $issues[0].Type | Should -Be "mutable_floating_release"
        $issues[0].Version | Should -Be "v1.0"
    }
    
    It "Should report mutable release on 'latest'" {
        $releaseData = [PSCustomObject]@{
            tag_name = "latest"
            id = 12345
            draft = $false
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/latest"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 1
        $issues[0].Version | Should -Be "latest"
    }
    
    It "Should skip ignored versions" {
        $script:config.ignoreVersions = @("v1")
        
        $releaseData = [PSCustomObject]@{
            tag_name = "v1"
            id = 12345
            draft = $false
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/v1"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
    
    It "Should not report patch version releases" {
        $releaseData = [PSCustomObject]@{
            tag_name = "v1.0.0"
            id = 12345
            draft = $false
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        $issues = $script:validator.Validate($script:state, $script:config)
        
        $issues.Count | Should -Be 0
    }
}

Describe "ValidatorPipeline" {
    BeforeEach {
        $script:pipeline = [ValidatorPipeline]::new()
        $script:state = [RepositoryState]::new()
        $script:config = @{
            checkReleases = "error"
            checkReleaseImmutability = "error"
        }
    }
    
    It "Should create empty pipeline" {
        $script:pipeline.Validators.Count | Should -Be 0
    }
    
    It "Should add validators to pipeline" {
        $validator1 = [ReleaseValidator]::new()
        $validator2 = [ReleaseImmutabilityValidator]::new()
        
        $script:pipeline.AddValidator($validator1)
        $script:pipeline.AddValidator($validator2)
        
        $script:pipeline.Validators.Count | Should -Be 2
    }
    
    It "Should run all validators and collect issues" {
        # Add a tag without a release
        $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
        $script:state.Tags = @($tag)
        $script:state.Releases = @()
        
        # Add ReleaseValidator
        $script:pipeline.AddValidator([ReleaseValidator]::new())
        
        $issues = $script:pipeline.RunValidations($script:state, $script:config)
        
        $issues.Count | Should -BeGreaterThan 0
    }
    
    It "Should collect issues from multiple validators" {
        # Add a tag without a release
        $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
        $script:state.Tags = @($tag)
        
        # Add a draft release
        $releaseData = [PSCustomObject]@{
            tag_name = "v1.0.0"
            id = 12345
            draft = $true
            prerelease = $false
            html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
            target_commitish = "abc123"
        }
        $release = [ReleaseInfo]::new($releaseData)
        $script:state.Releases = @($release)
        
        # Add both validators
        $script:pipeline.AddValidator([ReleaseValidator]::new())
        $script:pipeline.AddValidator([ReleaseImmutabilityValidator]::new())
        
        $issues = $script:pipeline.RunValidations($script:state, $script:config)
        
        # Should find the draft release issue (not missing release since one exists)
        $issues.Count | Should -BeGreaterThan 0
    }
}

Describe "New-DefaultValidatorPipeline" {
    It "Should create pipeline with default validators" {
        $pipeline = New-DefaultValidatorPipeline
        
        $pipeline | Should -Not -BeNullOrEmpty
        $pipeline.Validators.Count | Should -BeGreaterThan 0
    }
    
    It "Should include ReleaseValidator" {
        $pipeline = New-DefaultValidatorPipeline
        
        $hasReleaseValidator = $false
        foreach ($validator in $pipeline.Validators) {
            if ($validator.Name -eq "Release") {
                $hasReleaseValidator = $true
                break
            }
        }
        
        $hasReleaseValidator | Should -Be $true
    }
    
    It "Should include ReleaseImmutabilityValidator" {
        $pipeline = New-DefaultValidatorPipeline
        
        $hasImmutabilityValidator = $false
        foreach ($validator in $pipeline.Validators) {
            if ($validator.Name -eq "ReleaseImmutability") {
                $hasImmutabilityValidator = $true
                break
            }
        }
        
        $hasImmutabilityValidator | Should -Be $true
    }
    
    It "Should include FloatingVersionReleaseValidator" {
        $pipeline = New-DefaultValidatorPipeline
        
        $hasFloatingValidator = $false
        foreach ($validator in $pipeline.Validators) {
            if ($validator.Name -eq "FloatingVersionRelease") {
                $hasFloatingValidator = $true
                break
            }
        }
        
        $hasFloatingValidator | Should -Be $true
    }
}
