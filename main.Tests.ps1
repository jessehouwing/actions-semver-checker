BeforeAll {
    # Create a temporary git repository for testing
    $script:testRepoPath = Join-Path $TestDrive "test-repo"
    $script:originalLocation = Get-Location
    
    function Initialize-TestRepo {
        param(
            [string]$Path
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
        
        # Create an initial commit
        "# Test Repo" | Out-File -FilePath "README.md"
        git add README.md
        git commit -m "Initial commit" 2>&1 | Out-Null
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
            # Arrange: Create v1.0.0, then v1.1.0, but leave v1 pointing to v1.0.0
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
}
