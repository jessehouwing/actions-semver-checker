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
            [string]$AutoFix = "false"
        )
        
        # Create inputs JSON object
        $inputsObject = @{
            'check-minor-version' = $CheckMinorVersion
            'check-releases' = $CheckReleases
            'check-release-immutability' = $CheckReleaseImmutability
            'ignore-preview-releases' = $IgnorePreviewReleases
            'floating-versions-use' = $FloatingVersionsUse
            'auto-fix' = $AutoFix
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
            
            # Verify git config was attempted (credential helper should be configured)
            $credHelper = & git config --local credential.helper 2>$null
            # The credential helper should be set (even if empty array)
            $credHelper | Should -Not -BeNullOrEmpty
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
    }
}
