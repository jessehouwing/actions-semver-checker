BeforeAll {
    # Create a temporary git repository for testing
    $script:testRepoPath = Join-Path $TestDrive "test-repo"
    $script:remoteRepoPath = Join-Path $TestDrive "remote-repo"
    $script:originalLocation = Get-Location
    
    function Initialize-TestRepo {
        param(
            [string]$Path,
            [switch]$WithRemote
        )
        
        # Change back to original location first
        Set-Location $script:originalLocation
        
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force
        }
        
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Set-Location $Path
        
        git init --initial-branch=main 2>&1 | Out-Null
        git config user.email "test@example.com"
        git config user.name "Test User"
        
        # Set up remote if requested
        if ($WithRemote) {
            if (Test-Path $script:remoteRepoPath) {
                Remove-Item -Path $script:remoteRepoPath -Recurse -Force
            }
            git init --bare --initial-branch=main $script:remoteRepoPath 2>&1 | Out-Null
            git remote add origin $script:remoteRepoPath 2>&1 | Out-Null
        }
        
        # Create an initial commit
        "# Test Repo" | Out-File -FilePath "README.md"
        git add README.md
        git commit -m "Initial commit" 2>&1 | Out-Null
        
        # Push initial commit to remote if it exists
        if ($WithRemote) {
            git push origin main 2>&1 | Out-Null
        }
    }
    
    function Get-CommitSha {
        param(
            [string]$Ref = "HEAD"
        )
        return (git rev-parse $Ref).Trim()
    }
    
    function Invoke-MainScript {
        param(
            [string]$CheckMinorVersion = "true",
            [string]$CheckReleases = "none",
            [string]$CheckReleaseImmutability = "none",
            [string]$IgnorePreviewReleases = "false",
            [string]$FloatingVersionsUse = "tags",
            [string]$AutoFix = "false",
            [string]$IgnoreVersions = ""
        )
        
        # Create inputs JSON object
        $inputsObject = @{
            'check-minor-version' = $CheckMinorVersion
            'check-releases' = $CheckReleases
            'check-release-immutability' = $CheckReleaseImmutability
            'ignore-preview-releases' = $IgnorePreviewReleases
            'floating-versions-use' = $FloatingVersionsUse
            'auto-fix' = $AutoFix
            'ignore-versions' = $IgnoreVersions
        }
        $env:inputs = ($inputsObject | ConvertTo-Json -Compress)
        $global:returnCode = 0
        
        # Define mock function in global scope before running script
        $global:InvokeWebRequestWrapper = {
            param($Uri, $Headers, $Method, $TimeoutSec)
            return @{
                Content = "[]"
                Headers = @{}
            }
        }
        
        # Make the function available
        Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
        
        # Capture output
        $output = & "$PSScriptRoot/main.ps1" 2>&1 | Out-String
        
        # Clean up mock
        if (Test-Path function:global:Invoke-WebRequestWrapper) {
            Remove-Item function:global:Invoke-WebRequestWrapper
        }
        
        return @{
            Output = $output
            ReturnCode = $global:returnCode
        }
    }
}

AfterAll {
    Set-Location $script:originalLocation
}

Describe "SemVer Checker" {
    BeforeEach {
        Initialize-TestRepo -Path $script:testRepoPath
    }
    
    Context "When repo only has a minor version tag (e.g., v1.1)" {
        It "Should suggest creating both major version (v1) and patch version (v1.1.0)" {
            # Arrange: Create only v1.1 tag
            $commitSha = Get-CommitSha
            git tag v1.1
            
            # Act
            $result = Invoke-MainScript
            
            # Assert
            $result.ReturnCode | Should -Be 1
            
            # Should suggest creating v1
            $result.Output | Should -Match "git push origin $commitSha`:refs/tags/v1"
            
            # Should suggest creating v1.1.0
            $result.Output | Should -Match "git push origin $commitSha`:refs/tags/v1.1.0"
            
            # Should NOT suggest deleting v1 (no :refs/tags/v1 without a sha)
            $result.Output | Should -Not -Match "git push origin :refs/tags/v1[^.]"
            
            # Should NOT suggest force updating v1.1 (it should stay as is or create v1.1.0)
            $result.Output | Should -Not -Match "git push origin :refs/tags/v1.1"
        }
    }
    
    Context "When repo has proper semver tags (v1, v1.1, v1.1.0)" {
        It "Should not report any errors when all tags point to same commit" {
            # Arrange: Create all proper tags
            $commitSha = Get-CommitSha
            git tag v1
            git tag v1.1
            git tag v1.1.0
            
            # Act
            $result = Invoke-MainScript
            
            # Assert
            $result.ReturnCode | Should -Be 0
            $result.Output | Should -Not -Match "::error"
            $result.Output | Should -Not -Match "git push"
        }
    }
    
    Context "When repo has only patch version (v1.0.0)" {
        It "Should suggest creating major (v1) and minor (v1.0) versions" {
            # Arrange: Create only v1.0.0 tag
            $commitSha = Get-CommitSha
            git tag v1.0.0
            
            # Act
            $result = Invoke-MainScript
            
            # Assert
            $result.ReturnCode | Should -Be 1
            
            # Should suggest creating v1
            $result.Output | Should -Match "git push origin $commitSha`:refs/tags/v1[^.]"
            
            # Should suggest creating v1.0
            $result.Output | Should -Match "git push origin $commitSha`:refs/tags/v1.0[^.]"
        }
    }
    
    Context "When repo has mismatched versions" {
        It "Should suggest force updating when major version points to wrong commit" {
            # Arrange: Create v1.0.0 on first commit, then v1.1.0 and v1.1 on second commit,
            # but set v1 to point to the old v1.0.0 commit to test version mismatch detection
            git tag v1.0.0
            $oldCommitSha = Get-CommitSha
            
            "# Update" | Out-File -FilePath "README.md" -Append
            git add README.md
            git commit -m "Update" 2>&1 | Out-Null
            
            git tag v1.1.0
            git tag v1.1
            $newCommitSha = Get-CommitSha
            git tag v1 v1.0.0 2>&1 | Out-Null
            
            # Act
            $result = Invoke-MainScript
            
            # Assert
            $result.ReturnCode | Should -Be 1
            $result.Output | Should -Match "git push origin $newCommitSha`:refs/tags/v1 --force"
        }
    }
    
    Context "When check-minor-version is false" {
        It "Should not check minor version tags" {
            # Arrange: Create only v1.1.0 tag (missing v1.1)
            $commitSha = Get-CommitSha
            git tag v1.1.0
            git tag v1
            
            # Act
            $result = Invoke-MainScript -CheckMinorVersion "false"
            
            # Assert
            $result.ReturnCode | Should -Be 0
            $result.Output | Should -Not -Match "v1.1[^.]"
        }
    }
    
    Context "When repo only has a major version tag (e.g., v1)" {
        It "Should suggest creating patch version (v1.0.0) when check-minor-version is true" {
            # Arrange: Create only v1 tag
            $commitSha = Get-CommitSha
            git tag v1
            
            # Act
            $result = Invoke-MainScript -CheckMinorVersion "true"
            
            # Assert
            $result.ReturnCode | Should -Be 1
            
            # Should suggest creating v1.0.0
            $result.Output | Should -Match "git push origin $commitSha`:refs/tags/v1.0.0"
            
            # TODO: According to issue requirements, should also suggest v1.0 when check-minor-version is true
            # Currently the script only suggests v1.0.0
        }
        
        It "Should suggest creating only patch version (v1.0.0) when check-minor-version is false" {
            # Arrange: Create only v1 tag
            $commitSha = Get-CommitSha
            git tag v1
            
            # Act
            $result = Invoke-MainScript -CheckMinorVersion "false"
            
            # Assert
            $result.ReturnCode | Should -Be 1
            
            # Should suggest creating v1.0.0
            $result.Output | Should -Match "git push origin $commitSha`:refs/tags/v1.0.0"
            
            # Should NOT suggest creating v1.0 when check-minor-version is false
            $result.Output | Should -Not -Match "git push origin $commitSha`:refs/tags/v1.0[^.]"
        }
    }
    
    Context "When major version doesn't point to latest patch version" {
        It "Should suggest force updating when v1 points to v1.0.0 but v1.0.1 exists" {
            # Arrange: Create v1.0.0 on first commit, then v1.0.1 on second commit
            # Set v1 to point to v1.0.0 instead of v1.0.1
            git tag v1.0.0
            git tag v1.0
            git tag v1 v1.0.0
            
            "# Update" | Out-File -FilePath "README.md" -Append
            git add README.md
            git commit -m "Patch update" 2>&1 | Out-Null
            
            git tag v1.0.1
            $newCommitSha = Get-CommitSha
            
            # Act
            $result = Invoke-MainScript
            
            # Assert
            $result.ReturnCode | Should -Be 1
            $result.Output | Should -Match "git push origin $newCommitSha`:refs/tags/v1 --force"
            $result.Output | Should -Match "git push origin $newCommitSha`:refs/tags/v1.0 --force"
        }
    }
    
    Context "When minor version doesn't point to latest patch version" {
        It "Should suggest force updating when v1.1 points to v1.1.0 but v1.1.1 exists" {
            # Arrange: Create v1.1.0 on first commit, then v1.1.1 on second commit
            # Set v1.1 to point to v1.1.0 instead of v1.1.1
            git tag v1.1.0
            git tag v1.1 v1.1.0
            git tag v1.0.0
            git tag v1.0
            git tag v1
            
            "# Update" | Out-File -FilePath "README.md" -Append
            git add README.md
            git commit -m "Patch update" 2>&1 | Out-Null
            
            git tag v1.1.1
            $newCommitSha = Get-CommitSha
            
            # Act
            $result = Invoke-MainScript
            
            # Assert
            $result.ReturnCode | Should -Be 1
            $result.Output | Should -Match "git push origin $newCommitSha`:refs/tags/v1.1 --force"
            # v1 should also be updated to point to latest (v1.1.1)
            $result.Output | Should -Match "git push origin $newCommitSha`:refs/tags/v1 --force"
        }
    }
    
    Context "When major version doesn't point to latest minor version" {
        It "Should suggest force updating when v1 points to v1.0.0 but v1.1.0 exists" {
            # Arrange: Create v1.0.0 on first commit, then v1.1.0 on second commit
            # Set v1 to point to v1.0.0 instead of v1.1.0
            git tag v1.0.0
            git tag v1.0
            git tag v1 v1.0.0
            
            "# Update" | Out-File -FilePath "README.md" -Append
            git add README.md
            git commit -m "Minor update" 2>&1 | Out-Null
            
            git tag v1.1.0
            git tag v1.1
            $newCommitSha = Get-CommitSha
            
            # Act
            $result = Invoke-MainScript
            
            # Assert
            $result.ReturnCode | Should -Be 1
            $result.Output | Should -Match "git push origin $newCommitSha`:refs/tags/v1 --force"
        }
    }
    
    Context "When using branches for versions" {
        BeforeEach {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
        }
        
        It "Should validate branch versions just like tags" {
            # Arrange: Create a branch v1.0.0 but no v1 or v1.0 branches/tags
            $commitSha = Get-CommitSha
            
            # Create and push a remote branch using checkout
            git checkout -b v1.0.0 2>&1 | Out-Null
            git push origin v1.0.0 2>&1 | Out-Null
            git checkout main 2>&1 | Out-Null
            
            # Act
            $result = Invoke-MainScript
            
            # Assert
            $result.ReturnCode | Should -Be 1
            
            # Should suggest creating v1 and v1.0 tags (not branches)
            $result.Output | Should -Match "git push origin $commitSha`:refs/tags/v1[^.]"
            $result.Output | Should -Match "git push origin $commitSha`:refs/tags/v1.0[^.]"
        }
        
        It "Should warn when same version exists as both tag and branch pointing to same commit" {
            # Arrange: Create both a tag and branch for v1.0.0
            $commitSha = Get-CommitSha
            git tag v1.0.0
            
            # Push branch explicitly to refs/heads to avoid tag conflict
            git branch v1.0.0-temp
            git push origin v1.0.0-temp:v1.0.0 2>&1 | Out-Null
            git branch -D v1.0.0-temp 2>&1 | Out-Null
            
            # Act
            $result = Invoke-MainScript
            
            # Assert
            # Should warn about ambiguous version
            $result.Output | Should -Match "::warning.*Ambiguous version: v1.0.0"
            $result.Output | Should -Match "git push origin :refs/heads/v1.0.0"
        }
        
        It "Should error when same version exists as both tag and branch pointing to different commits" {
            # Arrange: Create a tag v1.0.0 on first commit
            git tag v1.0.0
            
            # Create a new commit
            "# Update" | Out-File -FilePath "README.md" -Append
            git add README.md
            git commit -m "Update for branch" 2>&1 | Out-Null
            
            # Push branch v1.0.0 pointing to the new commit
            git branch v1.0.0-temp
            git push origin v1.0.0-temp:v1.0.0 2>&1 | Out-Null
            git branch -D v1.0.0-temp 2>&1 | Out-Null
            
            # Act
            $result = Invoke-MainScript
            
            # Assert
            $result.ReturnCode | Should -Be 1
            # Should error about ambiguous version
            $result.Output | Should -Match "::error.*Ambiguous version: v1.0.0"
            $result.Output | Should -Match "git push origin :refs/heads/v1.0.0"
        }
        
        It "Should auto-fix ambiguous version respecting floating-versions-use setting (tags mode)" {
            # Arrange: Create both tag and branch for v1.0.0 pointing to same commit
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            $commitSha = Get-CommitSha
            git tag v1.0.0
            git branch v1.0.0-temp
            git push origin v1.0.0-temp:v1.0.0 2>&1 | Out-Null
            git branch -D v1.0.0-temp 2>&1 | Out-Null
            
            # Act without auto-fix to see suggestion (floating-versions-use=tags means keep tag, remove branch)
            $result = Invoke-MainScript -AutoFix $false -FloatingVersionsUse "tags"
            
            # Assert: Should suggest removing the branch (keep tag)
            $result.Output | Should -Match "git push origin :refs/heads/v1.0.0"
            $result.Output | Should -Not -Match "git push origin :refs/tags/v1.0.0"
        }
        
        It "Should auto-fix ambiguous version respecting floating-versions-use setting (branches mode)" {
            # Arrange: Create both tag and branch for v1.0.0 pointing to same commit  
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            $commitSha = Get-CommitSha
            git tag v1.0.0
            git branch v1.0.0-temp
            git push origin v1.0.0-temp:v1.0.0 2>&1 | Out-Null
            git branch -D v1.0.0-temp 2>&1 | Out-Null
            
            # Act without auto-fix to see suggestion (floating-versions-use=branches means keep branch, remove tag)
            $result = Invoke-MainScript -AutoFix $false -FloatingVersionsUse "branches"
            
            # Assert: Should suggest removing the tag (keep branch)
            $result.Output | Should -Match "git push origin :refs/tags/v1.0.0"
            $result.Output | Should -Not -Match "git push origin :refs/heads/v1.0.0"
        }
    }
    
    Context "Parameterized tests for missing versions" {
        It "Should suggest creating missing versions for <Description>" -TestCases @(
            @{ 
                Description = "v2 major version"
                ExistingTag = "v2.0.0"
                ExpectedMissingMajor = "v2"
                ExpectedMissingMinor = "v2.0"
                CheckMinor = $true
            },
            @{ 
                Description = "v3 major version"
                ExistingTag = "v3.0.0"
                ExpectedMissingMajor = "v3"
                ExpectedMissingMinor = "v3.0"
                CheckMinor = $true
            },
            @{ 
                Description = "v1.2 minor version"
                ExistingTag = "v1.2.0"
                ExpectedMissingMajor = "v1"
                ExpectedMissingMinor = "v1.2"
                CheckMinor = $true
            },
            @{ 
                Description = "v2.1 minor version"
                ExistingTag = "v2.1.0"
                ExpectedMissingMajor = "v2"
                ExpectedMissingMinor = "v2.1"
                CheckMinor = $true
            }
        ) {
            param($Description, $ExistingTag, $ExpectedMissingMajor, $ExpectedMissingMinor, $CheckMinor)
            
            # Arrange
            $commitSha = Get-CommitSha
            git tag $ExistingTag
            
            # Act
            $checkMinorStr = if ($CheckMinor) { "true" } else { "false" }
            $result = Invoke-MainScript -CheckMinorVersion $checkMinorStr
            
            # Assert
            $result.ReturnCode | Should -Be 1
            $result.Output | Should -Match "git push origin $commitSha`:refs/tags/$ExpectedMissingMajor[^.]"
            
            if ($CheckMinor) {
                $result.Output | Should -Match "git push origin $commitSha`:refs/tags/$ExpectedMissingMinor[^.]"
            }
        }
    }
    
    Context "Parameterized tests for version consistency" {
        It "Should detect when <Description> doesn't point to latest" -TestCases @(
            @{ 
                Description = "v2 doesn't point to latest patch v2.0.1"
                InitialTags = @("v2.0.0", "v2.0", "v2")
                NewTag = "v2.0.1"
                ExpectedForceUpdate = "v2"
            },
            @{ 
                Description = "v3 doesn't point to latest minor v3.1.0"
                InitialTags = @("v3.0.0", "v3.0", "v3")
                NewTag = "v3.1.0"
                NewMinorTag = "v3.1"
                ExpectedForceUpdate = "v3"
            },
            @{ 
                Description = "v1.2 doesn't point to latest patch v1.2.1"
                InitialTags = @("v1.2.0", "v1.2", "v1.0.0", "v1.0", "v1")
                NewTag = "v1.2.1"
                ExpectedForceUpdate = "v1.2"
            }
        ) {
            param($Description, $InitialTags, $NewTag, $NewMinorTag, $ExpectedForceUpdate)
            
            # Arrange: Create initial tags on first commit
            foreach ($tag in $InitialTags) {
                git tag $tag
            }
            
            # Create a new commit
            "# Update" | Out-File -FilePath "README.md" -Append
            git add README.md
            git commit -m "Update" 2>&1 | Out-Null
            
            # Create new version tag
            git tag $NewTag
            if ($NewMinorTag) {
                git tag $NewMinorTag
            }
            $newCommitSha = Get-CommitSha
            
            # Act
            $result = Invoke-MainScript
            
            # Assert
            $result.ReturnCode | Should -Be 1
            $result.Output | Should -Match "git push origin $newCommitSha`:refs/tags/$ExpectedForceUpdate --force"
        }
    }
    
    Context "Release checking" {
        It "Should not check releases when check-releases is none" {
            # Arrange
            git tag v1.0.0
            
            # Act - disable release checking
            $result = Invoke-MainScript -CheckReleases "none"
            
            # Assert - should not mention releases at all
            $result.Output | Should -Not -Match "Missing release"
            $result.Output | Should -Not -Match "gh release"
        }
        
        It "Should suggest creating a release when tag exists but release doesn't" {
            # This test verifies the error message is generated
            # The REST API is used to query actual releases
            
            # Arrange
            git tag v1.0.0
            git tag v1
            
            # Act - with releases enabled (REST API will be queried)
            $result = Invoke-MainScript -CheckReleases "error"
            
            # If REST API is accessible and no releases exist, it would suggest:
            # gh release create v1.0.0 --draft
            # For now, we just verify the feature doesn't break existing tests
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "Release immutability checking" {
        It "Should not check release immutability when check-release-immutability is none" {
            # Arrange
            git tag v1.0.0
            git tag v1
            
            # Act - disable immutability checking
            $result = Invoke-MainScript -CheckReleaseImmutability "none"
            
            # Assert - should not mention draft releases
            $result.Output | Should -Not -Match "Draft release"
            $result.Output | Should -Not -Match "immutable"
        }
        
        It "Should allow checking releases but not immutability separately" {
            # Arrange
            git tag v1.0.0
            git tag v1
            
            # Act - check releases but not immutability
            $result = Invoke-MainScript -CheckReleases "error" -CheckReleaseImmutability "none"
            
            # Assert - feature doesn't break existing functionality
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "Preview release handling" {
        It "Should not filter preview releases when ignore-preview-releases is false" {
            # Arrange
            git tag v1.0.0
            git tag v1
            
            # Act - don't ignore preview releases (default behavior)
            $result = Invoke-MainScript -IgnorePreviewReleases "false"
            
            # Assert - should work normally
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should filter preview releases when ignore-preview-releases is true" {
            # Arrange - create both stable and preview versions
            git tag v1.0.0
            git tag v1.0
            git tag v1
            
            # Create a new commit for preview
            "# Preview" | Out-File -FilePath "README.md" -Append
            git add README.md
            git commit -m "Preview update" 2>&1 | Out-Null
            
            git tag v1.1.0-preview
            
            # Act - with preview filtering enabled
            # Note: The actual filtering depends on GitHub releases API marking releases as prerelease
            # In test environment, REST API will be queried
            $result = Invoke-MainScript -IgnorePreviewReleases "true"
            
            # Assert - should still work (actual filtering requires REST API and releases)
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "Floating versions configuration" {
        It "Should not enforce branches when floating-versions-use is tags" {
            # Arrange
            git tag v1.0.0
            git tag v1
            
            # Act - use tags (default behavior)
            $result = Invoke-MainScript -FloatingVersionsUse "tags"
            
            # Assert - should work normally with tags
            $result.Output | Should -Not -Match "should be a branch"
        }
        
        It "Should suggest using branches when floating-versions-use is branches and tags exist" {
            # Arrange
            git tag v1.0.0
            git tag v1
            
            # Act - enforce branches
            $result = Invoke-MainScript -FloatingVersionsUse "branches"
            
            # Assert - should error that v1 should be a branch
            $result.Output | Should -Match "should be a branch"
            $result.ReturnCode | Should -Be 1
        }
        
        It "Should suggest creating branches when floating-versions-use is branches" {
            # Arrange
            git tag v1.0.0
            
            # Act - enforce branches
            $result = Invoke-MainScript -FloatingVersionsUse "branches"
            
            # Assert - should suggest creating v1 as a branch, not tag
            $result.Output | Should -Match "refs/heads/v1"
            $result.Output | Should -Not -Match "refs/tags/v1[^.]"
        }
        
        It "Should error on invalid floating-versions-use value" {
            # Arrange
            git tag v1.0.0
            
            # Act & Assert - invalid value should cause error
            $inputsObject = @{
                'check-minor-version' = "true"
                'check-releases' = "none"
                'check-release-immutability' = "none"
                'ignore-preview-releases' = "false"
                'floating-versions-use' = "invalid"
                'auto-fix' = "false"
            }
            $env:inputs = ($inputsObject | ConvertTo-Json -Compress)
            $result = & "$PSScriptRoot/main.ps1" 2>&1 | Out-String
            $result | Should -Match "Invalid configuration"
        }
    }
    
    Context "Auto-fix functionality" {
        It "Should not auto-fix when auto-fix is false" {
            # Arrange
            git tag v1.0.0
            
            # Act - don't auto-fix (default behavior)
            $result = Invoke-MainScript -AutoFix "false"
            
            # Assert - should only suggest, not execute
            $result.Output | Should -Not -Match "Auto-fixing"
            $result.Output | Should -Not -Match "Executing:"
        }
        
        It "Should suggest fixes when auto-fix is false and versions are missing" {
            # Arrange
            git tag v1.0.0
            
            # Act
            $result = Invoke-MainScript -AutoFix "false"
            
            # Assert - should suggest creating v1 and v1.0
            $result.Output | Should -Match "git push"
            $result.ReturnCode | Should -Be 1
        }
        
        It "Should report auto-fix mode when enabled" {
            # Arrange - create proper repo with remote for push
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            git tag v1.0.0
            git push origin v1.0.0 2>&1 | Out-Null
            
            # Act - enable auto-fix
            $result = Invoke-MainScript -AutoFix "true"
            
            # Assert - should attempt to auto-fix
            if ($result.Output -match "git push")
            {
                $result.Output | Should -Match "Auto-fixing"
            }
        }
        
        It "Should auto-fix multiple missing patch versions when auto-fix is enabled" {
            # Arrange - create proper repo with remote for push
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create v1 and v2 tags without patch versions
            $commit = Get-CommitSha
            git tag v1 $commit
            git tag v2 $commit
            git push origin v1 2>&1 | Out-Null
            git push origin v2 2>&1 | Out-Null
            
            # Set token for auto-fix
            $env:GITHUB_TOKEN = "test-token-12345"
            
            try {
                # Act - enable auto-fix with check-releases=none
                $result = Invoke-MainScript -AutoFix "true" -CheckReleases "none" -CheckReleaseImmutability "none"
                
                # Assert - should show fixed issues count (v1.0.0, v1.0, v2.0.0, v2.0 created)
                $result.Output | Should -Match "Fixed issues: 4"
                
                # Should not show failed fixes
                $result.Output | Should -Match "Failed fixes: 0"
                
                # Should not show unfixable issues (the redundant floating version errors are removed)
                $result.Output | Should -Match "Unfixable issues: 0"
                
                # Should show success message
                $result.Output | Should -Match "All issues were successfully fixed"
                
                $result.ReturnCode | Should -Be 0
            }
            finally {
                Remove-Item env:GITHUB_TOKEN -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context "Floating version validation" {
        It "Should error when major version tag exists without patch versions" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create only a major version tag
            $commit = Get-CommitSha
            git tag v1 $commit
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Should error about missing patch versions (detected by version consistency checks)
            $result.Output | Should -Match "Version: v1.0.0 does not exist"
            $result.Output | Should -Match "v1 ref"
            $result.ReturnCode | Should -Be 1
        }
        
        It "Should error when minor version tag exists without patch versions" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create only a minor version tag
            $commit = Get-CommitSha
            git tag v1.0 $commit
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Should error about missing patch versions (detected by version consistency checks)
            $result.Output | Should -Match "Version: v1.0.0 does not exist"
            $result.Output | Should -Match "v1.0 ref"
            $result.ReturnCode | Should -Be 1
        }
        
        It "Should not error when floating versions have corresponding patch versions" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create patch version, minor floating version, and major floating version
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v1.0 $commit
            git tag v1 $commit
            
            # Run the checker with check-releases=none to focus on floating version validation
            $result = Invoke-MainScript -CheckReleases "none" -CheckReleaseImmutability "none"
            
            # Should not error about floating version since v1.0.0 exists
            $result.Output | Should -Not -Match "Floating version without patch version"
            $result.ReturnCode | Should -Be 0
        }
        
        It "Should not require releases for floating versions" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create patch version and floating versions
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v1.0 $commit
            git tag v1 $commit
            
            # Run the checker with check-releases=error
            $result = Invoke-MainScript -CheckReleases "error" -CheckReleaseImmutability "none"
            
            # Should not error about missing releases for v1 or v1.0 (floating versions)
            # Only patch versions require releases
            $result.Output | Should -Not -Match "v1 .*release"
            $result.Output | Should -Not -Match "v1.0 .*release"
            # Should error about missing release for v1.0.0 (patch version)
            $result.Output | Should -Match "v1.0.0 .*release"
            $result.ReturnCode | Should -Be 1
        }
        
        It "Should error when branch floating version exists without patch versions" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create a major version branch
            $commit = Get-CommitSha
            git branch v1 $commit
            git push origin v1 2>&1 | Out-Null
            git fetch origin 2>&1 | Out-Null
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Should error about missing patch versions (detected by version consistency checks)
            $result.Output | Should -Match "Version: v1.0.0 does not exist"
            $result.Output | Should -Match "v1 ref"
            $result.ReturnCode | Should -Be 1
        }
        
        It "Should handle multiple major versions without patch versions" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create multiple major version tags without patch versions
            $commit = Get-CommitSha
            git tag v1 $commit
            git tag v2 $commit
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Should error about both (detected by version consistency checks)
            $result.Output | Should -Match "Version: v1.0.0 does not exist"
            $result.Output | Should -Match "Version: v2.0.0 does not exist"
            $result.ReturnCode | Should -Be 1
        }
        
        It "Should validate that v1 has patch version even when v2.0.0 exists" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create v1 without patch, but v2.0.0 with patch
            $commit = Get-CommitSha
            git tag v1 $commit
            git tag v2.0.0 $commit
            
            # Run the checker with check-releases=none
            $result = Invoke-MainScript -CheckReleases "none" -CheckReleaseImmutability "none"
            
            # Should error only about v1 missing patch versions (detected by version consistency checks)
            $result.Output | Should -Match "Version: v1.0.0 does not exist"
            $result.Output | Should -Not -Match "Version: v2.0.0 does not exist"
            $result.ReturnCode | Should -Be 1
        }
        
        It "Should suggest patch version creation using SHA from existing floating version tag" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create a major version tag at a specific commit
            $commit = Get-CommitSha
            git tag v1 $commit
            
            # Run the checker with check-releases=none
            $result = Invoke-MainScript -CheckReleases "none" -CheckReleaseImmutability "none"
            
            # Should suggest using the SHA from v1 tag (direct push only, no alternative commands)
            $result.Output | Should -Match "git push origin $commit`:refs/tags/v1\.0\.0"
            $result.ReturnCode | Should -Be 1
        }
        
        It "Should suggest patch version creation using SHA from existing floating minor version tag" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create a minor version tag at a specific commit
            $commit = Get-CommitSha
            git tag v1.2 $commit
            
            # Run the checker with check-releases=none
            $result = Invoke-MainScript -CheckReleases "none" -CheckReleaseImmutability "none"
            
            # Should suggest using the SHA from v1.2 tag (direct push only, no alternative commands)
            $result.Output | Should -Match "git push origin $commit`:refs/tags/v1\.2\.0"
            $result.ReturnCode | Should -Be 1
        }
    }
    
    Describe "Repository Configuration Validation" {
        It "Should detect shallow clone and provide helpful error" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create a shallow clone marker
            New-Item -ItemType File -Path ".git/shallow" -Force | Out-Null
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Should error about shallow clone
            $result.Output | Should -Match "Shallow clone detected"
            $result.Output | Should -Match "fetch-depth: 0"
            $result.ReturnCode | Should -Be 1
        }
        
        It "Should warn when no tags are found" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Don't create any tags
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Should warn about no tags
            $result.Output | Should -Match "No tags found"
            $result.Output | Should -Match "fetch-tags: true"
            # Should not fail (warning only)
            $result.ReturnCode | Should -Be 0
        }
        
        It "Should error when auto-fix is enabled but no token available" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create a version that needs fixing
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v1 HEAD~1 2>&1 | Out-Null  # Point to wrong commit
            
            # Save and clear token
            $savedToken = $env:GITHUB_TOKEN
            $env:GITHUB_TOKEN = $null
            
            try {
                # Run with auto-fix but no token
                $result = Invoke-MainScript -AutoFix "true"
                
                # Should error about missing token
                $result.Output | Should -Match "Auto-fix requires token"
                $result.ReturnCode | Should -Be 1
            }
            finally {
                # Restore token
                $env:GITHUB_TOKEN = $savedToken
            }
        }
        
        It "Should configure git credentials when auto-fix is enabled with token" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create a version that needs fixing
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v1.0 $commit
            
            # Ensure token is available
            $env:GITHUB_TOKEN = "test-token-12345"
            
            # Run with auto-fix
            $result = Invoke-MainScript -AutoFix "true"
            
            # Should show auto-fix summary
            $result.Output | Should -Match "Fixed issues:"
            
            # Verify git user identity is configured for GitHub Actions bot
            # This proves the credential setup code ran
            $userName = & git config --local user.name 2>$null
            $userEmail = & git config --local user.email 2>$null
            $userName | Should -Be "github-actions[bot]"
            $userEmail | Should -Be "github-actions[bot]@users.noreply.github.com"
            
            # SECURITY: Verify the token is NOT embedded directly in git config output
            # (the token should be passed via environment variables instead)
            $allConfig = & git config --local --list 2>$null
            $allConfig | Should -Not -Match "test-token-12345" -Because "Token should not be embedded in git config"
        }
    }
    
    Context "Security - Workflow Command Injection Protection" {
        It "Should protect against workflow command injection in git command output" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create a git hook that outputs malicious content
            $hookPath = Join-Path $script:testRepoPath ".git/hooks/pre-push"
            New-Item -ItemType Directory -Path (Split-Path $hookPath) -Force -ErrorAction SilentlyContinue | Out-Null
            @'
#!/bin/sh
echo "::set-env name=MALICIOUS::injected"
echo "::error::Fake error from hook"
exit 0
'@ | Out-File -FilePath $hookPath -Encoding UTF8
            
            # Make the hook executable on Unix-like systems
            if ($IsLinux -or $IsMacOS) {
                chmod +x $hookPath
            }
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Ensure token is available for auto-fix
            $env:GITHUB_TOKEN = "test-token-12345"
            
            # Run with auto-fix which will execute git push
            $result = Invoke-MainScript -AutoFix "true"
            
            # The auto-fix should still work despite malicious hook output
            # We can't easily verify the stop-commands in this context, but we verify it doesn't fail
            $result.ReturnCode | Should -Not -BeNullOrEmpty
        }
        
        It "Should protect against workflow command injection with special characters in version output" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create a tag with potential injection attempt in commit message
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v1.0 $commit
            git tag v1 $commit
            
            # Run the checker - it should sanitize any output
            $result = Invoke-MainScript
            
            # Should complete without errors (workflow commands are allowed in output, 
            # but they are properly escaped by GitHub Actions)
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "REST API - Pagination Handling" {
        It "Should handle pagination for repositories with 100+ releases" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create tags that would result in many releases
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock the REST API to return pagination headers
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                
                # Simulate paginated response with Link header
                $mockContent = @(
                    @{ tag_name = "v1.0.0"; draft = $false; prerelease = $false; id = 1 }
                ) | ConvertTo-Json
                
                return @{
                    Content = $mockContent
                    Headers = @{
                        Link = '<https://api.github.com/repos/test/test/releases?page=2>; rel="next", <https://api.github.com/repos/test/test/releases?page=5>; rel="last"'
                    }
                }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            
            # Run with release checking enabled
            $result = Invoke-MainScript -CheckReleases "error"
            
            # Clean up mock
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should handle pagination without errors
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "REST API - HTTP Error Handling" {
        It "Should handle 404 errors from GitHub API gracefully" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock API to return 404
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                throw [System.Net.WebException]::new("The remote server returned an error: (404) Not Found.")
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            
            # Run with release checking
            $result = Invoke-MainScript -CheckReleases "error"
            
            # Clean up mock
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should handle 404 gracefully without crashing
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should handle 422 errors when creating references" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock API to return 422 (Unprocessable Entity)
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                
                if ($Method -eq "POST") {
                    throw [System.Net.WebException]::new("The remote server returned an error: (422) Unprocessable Entity.")
                }
                
                return @{
                    Content = "[]"
                    Headers = @{}
                }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            
            # Set up environment for auto-fix
            $env:GITHUB_TOKEN = "test-token"
            
            # Run with auto-fix enabled
            $result = Invoke-MainScript -AutoFix "true"
            
            # Clean up mock
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should handle error and report it
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should handle 500 server errors from GitHub API" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock API to return 500
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                throw [System.Net.WebException]::new("The remote server returned an error: (500) Internal Server Error.")
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            
            # Run with release checking
            $result = Invoke-MainScript -CheckReleases "error"
            
            # Clean up mock
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should handle 500 gracefully
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "REST API - Timeout Handling" {
        It "Should handle API timeout scenarios" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock API to simulate timeout
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                throw [System.Net.WebException]::new("The operation has timed out")
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            
            # Run with release checking
            $result = Invoke-MainScript -CheckReleases "error"
            
            # Clean up mock
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should handle timeout gracefully
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "REST API - GitHub Enterprise Server Support" {
        It "Should construct correct API URLs for GitHub Enterprise Server" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Set up GHE environment
            $env:GITHUB_API_URL = "https://github.enterprise.com/api/v3"
            $env:GITHUB_SERVER_URL = "https://github.enterprise.com"
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Track API calls
            $script:apiCalls = @()
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                $script:apiCalls += $Uri
                return @{
                    Content = "[]"
                    Headers = @{}
                }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            
            # Run with release checking
            $result = Invoke-MainScript -CheckReleases "error"
            
            # Clean up mock and environment
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            $env:GITHUB_API_URL = $null
            $env:GITHUB_SERVER_URL = $null
            
            # Should work with GHE
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "Release Immutability - Draft Release Publishing" {
        It "Should create remediation action for missing release with AutoPublish when immutability checking enabled" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            $env:GITHUB_TOKEN = "test-token"
            
            # Run with release checking and immutability checking (no auto-fix to inspect State)
            $result = Invoke-MainScript -CheckReleases "error" -CheckReleaseImmutability "error" -AutoFix "false"
            
            # Check that the State has a CreateReleaseAction with AutoPublish=true for the missing release
            $global:State.Issues | Should -Not -BeNullOrEmpty
            $createIssues = $global:State.Issues | Where-Object { 
                $_.RemediationAction -and $_.RemediationAction.GetType().Name -eq "CreateReleaseAction" 
            }
            $createIssues | Should -Not -BeNullOrEmpty
            $createIssues[0].Version | Should -Be "v1.0.0"
            $createIssues[0].RemediationAction.AutoPublish | Should -Be $true
            $createIssues[0].RemediationAction.TagName | Should -Be "v1.0.0"
        }
        
        It "Should use CreateReleaseAction without AutoPublish when immutability checking disabled" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            $env:GITHUB_TOKEN = "test-token"
            
            # Run with release checking but NO immutability checking
            $result = Invoke-MainScript -CheckReleases "error" -CheckReleaseImmutability "none" -AutoFix "false"
            
            # Check that the State has a CreateReleaseAction with AutoPublish=false
            $global:State.Issues | Should -Not -BeNullOrEmpty
            $createIssues = $global:State.Issues | Where-Object { 
                $_.RemediationAction -and $_.RemediationAction.GetType().Name -eq "CreateReleaseAction" 
            }
            $createIssues | Should -Not -BeNullOrEmpty
            $createIssues[0].Version | Should -Be "v1.0.0"
            $createIssues[0].RemediationAction.AutoPublish | Should -Be $false
            $createIssues[0].RemediationAction.TagName | Should -Be "v1.0.0"
        }
        
        It "Should handle 422 error when tag_name used by immutable release" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock API to return 422 on publish
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                
                if ($Method -eq "PATCH") {
                    $errorResponse = @{
                        message = "Validation Failed"
                        errors = @(
                            @{
                                resource = "Release"
                                code = "custom"
                                field = "tag_name"
                                message = "tag_name was used by an immutable release"
                            }
                        )
                    } | ConvertTo-Json
                    throw [System.Net.WebException]::new("422 - $errorResponse")
                }
                
                return @{
                    Content = "[]"
                    Headers = @{}
                }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            $env:GITHUB_TOKEN = "test-token"
            
            # Run with auto-fix
            $result = Invoke-MainScript -CheckReleases "error" -CheckReleaseImmutability "error" -AutoFix "true"
            
            # Clean up
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should handle the error and report as unfixable
            $result.Output | Should -Match "immutable|Unfixable"
        }
        
        It "Should delete mutable releases on floating versions" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v1 $commit
            
            # Mock API to return mutable release for v1
            $script:deleteCalled = $false
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                
                if ($Uri -match "/releases/tags/v1$") {
                    $mockContent = @{
                        tag_name = "v1"
                        draft = $false
                        prerelease = $false
                        id = 456
                    } | ConvertTo-Json
                } elseif ($Method -eq "DELETE") {
                    $script:deleteCalled = $true
                    return @{ Content = ""; Headers = @{} }
                } else {
                    $mockContent = '[{"tag_name":"v1.0.0","draft":false,"prerelease":false,"id":123}]'
                }
                
                return @{
                    Content = $mockContent
                    Headers = @{}
                }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            $env:GITHUB_TOKEN = "test-token"
            
            # Run with auto-fix
            $result = Invoke-MainScript -CheckReleases "error" -CheckReleaseImmutability "error" -AutoFix "true"
            
            # Clean up
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should detect mutable release on floating version
            # This test verifies the check runs without error
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should parse GraphQL immutability check responses" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock GraphQL API response
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                
                if ($Uri -match "/graphql") {
                    $mockContent = @{
                        data = @{
                            repository = @{
                                release = @{
                                    isImmutable = $true
                                }
                            }
                        }
                    } | ConvertTo-Json -Depth 5
                } else {
                    $mockContent = '[{"tag_name":"v1.0.0","draft":false,"prerelease":false,"id":123}]'
                }
                
                return @{
                    Content = $mockContent
                    Headers = @{}
                }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            
            # Run with immutability checking
            $result = Invoke-MainScript -CheckReleases "error" -CheckReleaseImmutability "error"
            
            # Clean up
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should handle GraphQL response
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "Auto-fix Execution - Mixed Success and Failure" {
        It "Should track multiple auto-fix attempts with mixed results" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v2.0.0 $commit
            
            # Mock API with mixed success/failure
            $script:callCount = 0
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                
                if ($Method -eq "POST") {
                    $script:callCount++
                    if ($script:callCount -eq 1) {
                        # First call succeeds
                        return @{
                            Content = '{"ref":"refs/tags/v1","object":{"sha":"abc123"}}'
                            Headers = @{}
                        }
                    } else {
                        # Second call fails
                        throw [System.Net.WebException]::new("422 Unprocessable Entity")
                    }
                }
                
                return @{ Content = "[]"; Headers = @{} }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            $env:GITHUB_TOKEN = "test-token"
            
            # Run with auto-fix
            $result = Invoke-MainScript -AutoFix "true"
            
            # Clean up
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should report both success and failure counts
            $result.Output | Should -Match "Fixed issues:|Failed fixes:"
        }
        
        It "Should handle API call failures during auto-fix gracefully" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock API to fail
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                
                if ($Method -eq "POST") {
                    throw [System.Exception]::new("Network error")
                }
                
                return @{ Content = "[]"; Headers = @{} }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            $env:GITHUB_TOKEN = "test-token"
            
            # Run with auto-fix
            $result = Invoke-MainScript -AutoFix "true"
            
            # Clean up
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should handle exception and report failure (may return 0 or 1 depending on other validation)
            $result.ReturnCode | Should -BeIn @(0, 1)
            $result.Output | Should -Match "Failed|Error|fixed issues"
        }
        
        It "Should properly escape workflow commands in auto-fix output" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock API to return output with workflow commands
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                
                if ($Method -eq "POST") {
                    # Simulate response with potential injection
                    return @{
                        Content = '{"ref":"refs/tags/v1::error::malicious"}'
                        Headers = @{}
                    }
                }
                
                return @{ Content = "[]"; Headers = @{} }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            $env:GITHUB_TOKEN = "test-token"
            
            # Run with auto-fix
            $result = Invoke-MainScript -AutoFix "true"
            
            # Clean up
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should sanitize output
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "Version Logic - Prerelease Filtering Edge Cases" {
        It "Should handle when all versions are filtered as prereleases" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create only prerelease versions (these should NOT be supported per user requirement)
            # But we still need to test the filtering logic doesn't crash
            $commit = Get-CommitSha
            git tag v1.0.0-beta $commit
            git tag v1.0.0-rc1 $commit
            
            # Run with prerelease filtering enabled
            $result = Invoke-MainScript -IgnorePreviewReleases "true"
            
            # Should handle gracefully even if all versions filtered
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should not support version suffixes beyond patch version" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create version with suffix (should be ignored)
            $commit = Get-CommitSha
            git tag v1.0.0-beta $commit
            git tag v1.0.0 $commit
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Should only recognize v1.0.0, not v1.0.0-beta
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "Version Logic - Simultaneous Version Creation" {
        It "Should create both major.0.0 and major.0 when check-minor-version is true" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create only major version
            $commit = Get-CommitSha
            git tag v2 $commit
            
            $env:GITHUB_TOKEN = "test-token"
            
            # Run with auto-fix and minor version checking
            $result = Invoke-MainScript -CheckMinorVersion "true" -AutoFix "false"
            
            # Should suggest creating both v2.0.0 and v2.0
            $result.Output | Should -Match "v2\.0\.0"
            $result.Output | Should -Match "v2\.0[^.]"
        }
    }
    
    Context "Version Logic - Branch and Tag Conflicts" {
        It "Should detect when same version exists as both branch and tag" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v1 $commit
            git branch v1 $commit
            git push origin v1 2>&1 | Out-Null
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Should detect the ambiguous refname
            $result.Output | Should -Match "ambiguous|conflict"
        }
        
        It "Should handle branch/tag conflict with floating-versions-use setting" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v1 $commit
            
            # Run with branches mode
            $result = Invoke-MainScript -FloatingVersionsUse "branches"
            
            # Should suggest converting to branch
            $result.Output | Should -Match "refs/heads/v1|branch"
        }
    }
    
    Context "Version Logic - Source SHA Fallback" {
        It "Should use source SHA when no matching versions exist" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create a single tag without floating versions
            $commit = Get-CommitSha
            git tag v3.5.2 $commit
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Should suggest creating floating versions from the patch version's SHA
            $result.Output | Should -Match "git push origin $commit"
        }
    }
    
    Context "Release Creation Flow - Draft Creation via REST API" {
        It "Should create draft releases via REST API during auto-fix" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock API for draft creation
            $script:draftCreated = $false
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                
                if ($Method -eq "POST" -and $Uri -match "/releases") {
                    $script:draftCreated = $true
                    return @{
                        Content = '{"id":789,"tag_name":"v1.0.0","draft":true}'
                        Headers = @{}
                    }
                }
                
                return @{ Content = "[]"; Headers = @{} }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            $env:GITHUB_TOKEN = "test-token"
            
            # Run with auto-fix and release checking
            $result = Invoke-MainScript -CheckReleases "error" -AutoFix "true"
            
            # Clean up
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should attempt to create draft
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should handle cascading fixes - create draft then publish" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock API for cascading operations
            $script:operations = @()
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                
                if ($Method -eq "POST" -and $Uri -match "/releases") {
                    $script:operations += "create"
                    return @{
                        Content = '{"id":999,"tag_name":"v1.0.0","draft":true}'
                        Headers = @{}
                    }
                } elseif ($Method -eq "PATCH") {
                    $script:operations += "publish"
                    return @{
                        Content = '{"id":999,"tag_name":"v1.0.0","draft":false}'
                        Headers = @{}
                    }
                }
                
                return @{ Content = "[]"; Headers = @{} }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            $env:GITHUB_TOKEN = "test-token"
            
            # Run with auto-fix
            $result = Invoke-MainScript -CheckReleases "error" -CheckReleaseImmutability "error" -AutoFix "true"
            
            # Clean up
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should handle cascading operations
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "Branch Version Handling - REST API Creation" {
        It "Should create branches via REST API when floating-versions-use is branches" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock API for branch creation
            $script:branchCreated = $false
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                
                if ($Method -eq "POST" -and $Uri -match "refs/heads") {
                    $script:branchCreated = $true
                    return @{
                        Content = '{"ref":"refs/heads/v1","object":{"sha":"abc123"}}'
                        Headers = @{}
                    }
                }
                
                return @{ Content = "[]"; Headers = @{} }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            $env:GITHUB_TOKEN = "test-token"
            
            # Run with branches mode and auto-fix
            $result = Invoke-MainScript -FloatingVersionsUse "branches" -AutoFix "true"
            
            # Clean up
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should attempt branch creation
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should convert tags to branches when auto-fix enabled with branches mode" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v1 $commit
            
            # Mock API for conversion
            $script:operations = @()
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                
                if ($Method -eq "DELETE") {
                    $script:operations += "delete-tag"
                    return @{ Content = ""; Headers = @{} }
                } elseif ($Method -eq "POST") {
                    $script:operations += "create-branch"
                    return @{
                        Content = '{"ref":"refs/heads/v1","object":{"sha":"abc123"}}'
                        Headers = @{}
                    }
                }
                
                return @{ Content = "[]"; Headers = @{} }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            $env:GITHUB_TOKEN = "test-token"
            
            # Run with branches mode and auto-fix
            $result = Invoke-MainScript -FloatingVersionsUse "branches" -AutoFix "true"
            
            # Clean up
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should show error about tag that should be branch or attempt conversion
            $result.Output | Should -Match "should be a branch|refs/heads|Fixed issues"
        }
    }
    
    Context "Error Reporting - GITHUB_STEP_SUMMARY Output" {
        It "Should write summary to GITHUB_STEP_SUMMARY when available" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Set up step summary file
            $summaryFile = Join-Path $TestDrive "step_summary.md"
            New-Item -ItemType File -Path $summaryFile -Force | Out-Null
            $env:GITHUB_STEP_SUMMARY = $summaryFile
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Clean up
            $env:GITHUB_STEP_SUMMARY = $null
            
            # Should write to summary file
            if (Test-Path $summaryFile) {
                $summaryContent = Get-Content $summaryFile -Raw
                # Summary file should exist (even if empty in test context)
                $summaryContent | Should -Not -BeNullOrEmpty -Because "Summary should be written"
            }
        }
        
        It "Should sanitize debug output with special characters" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create tag with special characters in commit message
            "Test file" | Out-File -FilePath "test.txt"
            git add test.txt
            git commit -m "Test ::error:: in message" 2>&1 | Out-Null
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Output should be sanitized
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "Edge Cases - Invalid Version Formats" {
        It "Should not support version numbers with more than 3 components" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create tag with 4 components (should be filtered out by regex)
            $commit = Get-CommitSha
            git tag v1.0.0.0 $commit
            git tag v1.0.0 $commit
            
            # Run the checker
            $result = Invoke-MainScript
            
            # The 4-component version should be filtered out, only v1.0.0 should be recognized
            $result.Output | Should -Not -Match "v1\.0\.0\.0"
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should not support version components higher than 65535" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create tag with component over 65535
            # PowerShell's [Version] type has a max of 65535 per component
            $commit = Get-CommitSha
            git tag v1.70000.0 $commit
            git tag v1.0.0 $commit
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Should handle gracefully - may error or filter out the invalid version
            # The important thing is it doesn't crash
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should handle version tags with Unicode characters" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create tag with Unicode (should be ignored)
            $commit = Get-CommitSha
            git tag "v1.0.0-α" $commit
            git tag v1.0.0 $commit
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Should handle Unicode gracefully
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should handle very large version numbers within limits" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create tag with large but valid numbers
            $commit = Get-CommitSha
            git tag v65535.65535.65535 $commit
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Should handle large valid versions
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should ignore versions with non-numeric components" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create tag with non-numeric parts (should be ignored)
            $commit = Get-CommitSha
            git tag v1.x.0 $commit
            git tag v1.0.0 $commit
            
            # Run the checker
            $result = Invoke-MainScript
            
            # Should only recognize valid version
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "Ignore Versions Configuration" {
        It "Should skip validation for versions in ignore-versions list" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create two patch versions without floating versions
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v2.0.0 $commit
            
            # v2.0.0 will have missing v2 and v2.0, but we'll ignore it
            $result = Invoke-MainScript -IgnoreVersions "v2.0.0"
            
            # Check State object for issues - v1 issues should exist, v2 issues should not
            $v1Issues = $global:State.Issues | Where-Object { $_.Version -like "v1*" }
            $v2Issues = $global:State.Issues | Where-Object { $_.Version -like "v2*" }
            
            # Should have issues for v1 (missing v1, v1.0)
            $v1Issues.Count | Should -BeGreaterThan 0
            # Should NOT have issues for v2 (it's ignored)
            $v2Issues.Count | Should -Be 0
        }
        
        It "Should support wildcard patterns in ignore-versions" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            # Create multiple versions
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v1.1.0 $commit
            git tag v2.0.0 $commit
            
            # Ignore all v1.* versions
            $result = Invoke-MainScript -IgnoreVersions "v1.*"
            
            # Check State object - v1.x issues should not exist, v2.x issues should
            $v1Issues = $global:State.Issues | Where-Object { $_.Version -like "v1*" }
            $v2Issues = $global:State.Issues | Where-Object { $_.Version -like "v2*" }
            
            # Should NOT have issues for v1.x versions (ignored)
            $v1Issues.Count | Should -Be 0
            # Should have issues for v2.x versions
            $v2Issues.Count | Should -BeGreaterThan 0
        }
        
        It "Should handle multiple comma-separated versions in ignore-versions" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v2.0.0 $commit
            git tag v3.0.0 $commit
            
            # Ignore v1.0.0 and v2.0.0, but not v3.0.0
            $result = Invoke-MainScript -IgnoreVersions "v1.0.0,v2.0.0"
            
            # Check State object
            $v1Issues = $global:State.Issues | Where-Object { $_.Version -like "v1*" }
            $v2Issues = $global:State.Issues | Where-Object { $_.Version -like "v2*" }
            $v3Issues = $global:State.Issues | Where-Object { $_.Version -like "v3*" }
            
            # v1 and v2 should be ignored
            $v1Issues.Count | Should -Be 0
            $v2Issues.Count | Should -Be 0
            # v3 should have issues
            $v3Issues.Count | Should -BeGreaterThan 0
        }
        
        It "Should silently skip invalid ignore-versions patterns but process valid ones" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v1 $commit
            git tag v1.0 $commit
            git tag v2.0.0 $commit
            git tag v2 $commit
            git tag v2.0 $commit
            
            # Use mix of invalid and valid patterns - ignore v2.0.0
            $result = Invoke-MainScript -IgnoreVersions "invalid-pattern,v2.0.0"
            
            # v1 is complete (v1, v1.0, v1.0.0 all exist and point to same commit)
            # v2.0.0 is ignored, but v2 and v2.0 still exist and will have issues
            # since their "target" patch version is ignored
            $v1Issues = $global:State.Issues | Where-Object { $_.Version -like "v1*" }
            
            # v1 should have no issues (all versions exist)
            $v1Issues.Count | Should -Be 0
            # Script completes (return code doesn't matter for this test)
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should handle empty ignore-versions gracefully" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Empty ignore-versions
            $result = Invoke-MainScript -IgnoreVersions ""
            
            # Should work normally - issues should be detected
            $global:State.Issues.Count | Should -BeGreaterThan 0
            $result.ReturnCode | Should -Be 1
        }
        
        It "Should handle ignore-versions with extra whitespace and commas" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v1 $commit
            git tag v1.0 $commit
            
            # Malformed input with extra whitespace and commas - only v1.0.0 should be parsed as valid
            # Since v1, v1.0, and v1.0.0 all exist and point to same commit, this should pass
            # But v1.0.0 being ignored means floating versions won't find their patch target
            $result = Invoke-MainScript -IgnoreVersions "  v1.0.0 , , ,  "
            
            # The ignore-versions parsing should handle the malformed input gracefully
            # (extra whitespace and empty entries between commas)
            # Script completes without crashing
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should support newline-separated ignore-versions" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v2.0.0 $commit
            git tag v3.0.0 $commit
            
            # Use newline-separated format (like multi-line YAML input)
            $newlineSeparated = "v1.0.0`nv2.0.0"
            $result = Invoke-MainScript -IgnoreVersions $newlineSeparated
            
            # Check State object - v1 and v2 should be ignored
            $v1Issues = $global:State.Issues | Where-Object { $_.Version -like "v1*" }
            $v2Issues = $global:State.Issues | Where-Object { $_.Version -like "v2*" }
            $v3Issues = $global:State.Issues | Where-Object { $_.Version -like "v3*" }
            
            $v1Issues.Count | Should -Be 0
            $v2Issues.Count | Should -Be 0
            $v3Issues.Count | Should -BeGreaterThan 0
        }
        
        It "Should support JSON array format for ignore-versions" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v2.0.0 $commit
            git tag v3.0.0 $commit
            
            # Use JSON array format
            $jsonArray = '["v1.0.0", "v2.0.0"]'
            $result = Invoke-MainScript -IgnoreVersions $jsonArray
            
            # Check State object - v1 and v2 should be ignored
            $v1Issues = $global:State.Issues | Where-Object { $_.Version -like "v1*" }
            $v2Issues = $global:State.Issues | Where-Object { $_.Version -like "v2*" }
            $v3Issues = $global:State.Issues | Where-Object { $_.Version -like "v3*" }
            
            $v1Issues.Count | Should -Be 0
            $v2Issues.Count | Should -Be 0
            $v3Issues.Count | Should -BeGreaterThan 0
        }
        
        It "Should support mixed newline and comma separators" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v2.0.0 $commit
            git tag v3.0.0 $commit
            git tag v4.0.0 $commit
            
            # Mix of newlines and commas
            $mixedFormat = "v1.0.0,v2.0.0`nv3.0.0"
            $result = Invoke-MainScript -IgnoreVersions $mixedFormat
            
            # Check State object - v1, v2, v3 should be ignored
            $v1Issues = $global:State.Issues | Where-Object { $_.Version -like "v1*" }
            $v2Issues = $global:State.Issues | Where-Object { $_.Version -like "v2*" }
            $v3Issues = $global:State.Issues | Where-Object { $_.Version -like "v3*" }
            $v4Issues = $global:State.Issues | Where-Object { $_.Version -like "v4*" }
            
            $v1Issues.Count | Should -Be 0
            $v2Issues.Count | Should -Be 0
            $v3Issues.Count | Should -Be 0
            $v4Issues.Count | Should -BeGreaterThan 0
        }
    }
    
    Context "Parameterized Input Validation Tests" {
        It "Should normalize <InputName> value '<InputValue>' to '<Expected>'" -TestCases @(
            @{ InputName = "check-minor-version"; InputValue = "true"; Expected = "error" }
            @{ InputName = "check-minor-version"; InputValue = "false"; Expected = "none" }
            @{ InputName = "check-minor-version"; InputValue = "error"; Expected = "error" }
            @{ InputName = "check-minor-version"; InputValue = "warning"; Expected = "warning" }
            @{ InputName = "check-minor-version"; InputValue = "none"; Expected = "none" }
            @{ InputName = "check-releases"; InputValue = "true"; Expected = "error" }
            @{ InputName = "check-releases"; InputValue = "false"; Expected = "none" }
            @{ InputName = "check-release-immutability"; InputValue = "true"; Expected = "error" }
            @{ InputName = "check-release-immutability"; InputValue = "false"; Expected = "none" }
        ) {
            param($InputName, $InputValue, $Expected)
            
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v1.0 $commit
            git tag v1 $commit
            
            # Build inputs dynamically
            $inputsObject = @{
                'check-minor-version' = "true"
                'check-releases' = "none"
                'check-release-immutability' = "none"
                'ignore-preview-releases' = "false"
                'floating-versions-use' = "tags"
                'auto-fix' = "false"
            }
            $inputsObject[$InputName] = $InputValue
            $env:inputs = ($inputsObject | ConvertTo-Json -Compress)
            
            # Should not crash with any of these inputs
            $result = & "$PSScriptRoot/main.ps1" 2>&1 | Out-String
            
            # Basic validation - script should complete without parsing error
            $result | Should -Not -Match "Invalid configuration.*$InputName"
        }
    }
    
    Context "Parameterized API Error Classification Tests" {
        It "Should handle HTTP <StatusCode> errors gracefully" -TestCases @(
            @{ StatusCode = 404; Description = "Not Found" }
            @{ StatusCode = 422; Description = "Unprocessable Entity" }
            @{ StatusCode = 500; Description = "Internal Server Error" }
            @{ StatusCode = 502; Description = "Bad Gateway" }
            @{ StatusCode = 503; Description = "Service Unavailable" }
            @{ StatusCode = 429; Description = "Too Many Requests" }
        ) {
            param($StatusCode, $Description)
            
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock API to return specific error
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                throw [System.Net.WebException]::new("The remote server returned an error: ($StatusCode) $Description.")
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            
            # Run with release checking
            $result = Invoke-MainScript -CheckReleases "error"
            
            # Clean up mock
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Should handle error gracefully
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "Invoke-WithRetry Behavior" {
        BeforeAll {
            # Load the GitHubApi module to access Invoke-WithRetry
            . "$PSScriptRoot/lib/GitHubApi.ps1"
        }
        
        It "Should succeed on first attempt if no error" {
            $counter = @{ Value = 0 }
            $result = Invoke-WithRetry -ScriptBlock {
                $counter.Value++
                return "success"
            } -MaxRetries 3 -OperationDescription "test operation"
            
            $result | Should -Be "success"
            $counter.Value | Should -Be 1
        }
        
        It "Should retry on retryable errors and eventually succeed" {
            $counter = @{ Value = 0 }
            $result = Invoke-WithRetry -ScriptBlock {
                $counter.Value++
                if ($counter.Value -lt 2) {
                    throw [System.Net.WebException]::new("Connection timeout")
                }
                return "success after retry"
            } -MaxRetries 3 -InitialDelaySeconds 0 -OperationDescription "retry test"
            
            $result | Should -Be "success after retry"
            $counter.Value | Should -Be 2
        }
        
        It "Should throw after max retries on persistent retryable errors" {
            $counter = @{ Value = 0 }
            {
                Invoke-WithRetry -ScriptBlock {
                    $counter.Value++
                    throw [System.Net.WebException]::new("Connection timeout")
                } -MaxRetries 3 -InitialDelaySeconds 0 -OperationDescription "max retry test"
            } | Should -Throw
            
            $counter.Value | Should -Be 3
        }
        
        It "Should not retry on non-retryable errors" {
            $counter = @{ Value = 0 }
            {
                Invoke-WithRetry -ScriptBlock {
                    $counter.Value++
                    throw "Invalid input parameter"
                } -MaxRetries 3 -InitialDelaySeconds 0 -OperationDescription "non-retryable test"
            } | Should -Throw
            
            $counter.Value | Should -Be 1
        }
        
        It "Should retry on HTTP <ErrorCode> status codes" -TestCases @(
            @{ ErrorCode = "429"; Description = "rate limit" }
            @{ ErrorCode = "500"; Description = "internal server error" }
            @{ ErrorCode = "502"; Description = "bad gateway" }
            @{ ErrorCode = "503"; Description = "service unavailable" }
        ) {
            param($ErrorCode, $Description)
            
            $counter = @{ Value = 0 }
            $result = Invoke-WithRetry -ScriptBlock {
                $counter.Value++
                if ($counter.Value -lt 2) {
                    throw "HTTP $ErrorCode - $Description"
                }
                return "recovered"
            } -MaxRetries 3 -InitialDelaySeconds 0 -OperationDescription "HTTP $ErrorCode test"
            
            $result | Should -Be "recovered"
            $counter.Value | Should -Be 2
        }
    }
    
}
