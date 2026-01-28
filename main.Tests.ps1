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
            [string]$CheckMinorVersion = "true"
        )
        
        ${env:INPUT_CHECK-MINOR-VERSION} = $CheckMinorVersion
        $global:returnCode = 0
        
        # Capture output
        $output = & "$PSScriptRoot/main.ps1" 2>&1 | Out-String
        
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
}
