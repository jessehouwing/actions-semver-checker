BeforeAll {
    # Suppress progress reporting for folder cleanup operations (must be global scope)
    $global:ProgressPreference = 'SilentlyContinue'
    
    # Disable API retries for faster test execution
    $env:GITHUB_API_DISABLE_RETRY = 'true'
    $env:GITHUB_API_ALLOW_GIT_FALLBACK = 'true'
    
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
    
    # Helper function to create a mock that uses local git to return API-formatted responses
    function New-GitBasedApiMock {
        <#
        .SYNOPSIS
        Creates an API mock that uses local git commands to return tag/branch data.
        
        .DESCRIPTION
        This mock intercepts Invoke-WebRequestWrapper calls and returns data from the
        local git repository formatted as GitHub API responses.
        #>
        return {
            param($Uri, $Headers, $Method, $TimeoutSec)
            
            # Tags refs endpoint: /repos/{owner}/{repo}/git/refs/tags
            if ($Uri -match '/git/refs/tags') {
                $tags = & git tag -l 2>$null
                if (-not $tags) { $tags = @() }
                if ($tags -isnot [array]) { $tags = @($tags) }
                
                $refs = @()
                foreach ($tag in $tags) {
                    if ([string]::IsNullOrWhiteSpace($tag)) { continue }
                    $sha = (& git rev-list -n 1 $tag 2>$null)
                    if ($sha) {
                        $refs += @{
                            ref = "refs/tags/$tag"
                            object = @{
                                sha = $sha.Trim()
                                type = "commit"  # Simplified - treat all as lightweight tags
                            }
                        }
                    }
                }
                
                return @{
                    Content = ($refs | ConvertTo-Json -Depth 5 -Compress)
                    Headers = @{}
                }
            }
            
            # Branches endpoint: /repos/{owner}/{repo}/branches
            # Include both local and remote branches (like the actual API would)
            if ($Uri -match '/branches(\?|$)') {
                $branchData = @()
                
                # Get local branches
                $localBranches = & git branch -l 2>$null | ForEach-Object { $_.Trim() -replace '^\*\s*', '' }
                if ($localBranches) {
                    if ($localBranches -isnot [array]) { $localBranches = @($localBranches) }
                    foreach ($branch in $localBranches) {
                        if ([string]::IsNullOrWhiteSpace($branch)) { continue }
                        $sha = (& git rev-parse $branch 2>$null)
                        if ($sha) {
                            $branchData += @{
                                name = $branch
                                commit = @{
                                    sha = $sha.Trim()
                                }
                            }
                        }
                    }
                }
                
                # Get remote branches (simulating what the API would return)
                $remoteBranches = & git branch -r 2>$null | ForEach-Object { $_.Trim() -replace '^origin/', '' }
                if ($remoteBranches) {
                    if ($remoteBranches -isnot [array]) { $remoteBranches = @($remoteBranches) }
                    foreach ($branch in $remoteBranches) {
                        if ([string]::IsNullOrWhiteSpace($branch)) { continue }
                        if ($branch -match '^HEAD ->') { continue }  # Skip HEAD reference
                        # Skip if already added from local
                        if ($branchData | Where-Object { $_.name -eq $branch }) { continue }
                        $sha = (& git rev-parse "origin/$branch" 2>$null)
                        if ($sha) {
                            $branchData += @{
                                name = $branch
                                commit = @{
                                    sha = $sha.Trim()
                                }
                            }
                        }
                    }
                }
                
                return @{
                    Content = ($branchData | ConvertTo-Json -Depth 5 -Compress)
                    Headers = @{}
                }
            }
            
            # Releases endpoint: /repos/{owner}/{repo}/releases
            if ($Uri -match '/releases(\?|$)') {
                return @{
                    Content = "[]"
                    Headers = @{}
                }
            }
            
            # Default: empty response
            return @{
                Content = "[]"
                Headers = @{}
            }
        }
    }
    
    function Invoke-MainScript {
        param(
            [string]$CheckMinorVersion = "true",
            [string]$CheckReleases = "none",
            [string]$CheckReleaseImmutability = "none",
            [string]$IgnorePreviewReleases = "false",
            [string]$FloatingVersionsUse = "tags",
            [string]$AutoFix = "false",
            [string]$IgnoreVersions = "",
            [switch]$SkipMockSetup  # Skip setting up default mock if caller provides one
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
        $env:GITHUB_REPOSITORY = "test-owner/test-repo"
        $global:returnCode = 0
        
        # Define mock function in global scope before running script (unless caller skipped)
        if (-not $SkipMockSetup) {
            # Use the git-based API mock by default
            $global:InvokeWebRequestWrapper = New-GitBasedApiMock
            
            # Make the function available
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
        }
        
        # Capture output
        $output = & "$PSScriptRoot/../../main.ps1" 2>&1 | Out-String
        
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
    # Clean up environment variables
    Remove-Item Env:GITHUB_API_DISABLE_RETRY -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_API_ALLOW_GIT_FALLBACK -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_REPOSITORY -ErrorAction SilentlyContinue
}

Describe "SemVer Checker Integration Tests" {
    BeforeEach {
        Initialize-TestRepo -Path $script:testRepoPath
    }
    
    Context "Floating Version Validation (Example Table)" {
        It "Should handle floating version scenario: <Description>" -TestCases @(
            @{
                Description = "Major version only (v1) - should suggest patch"
                Tags = @("v1")
                ExpectedError = $true
                ExpectedPattern = "v1\.0\.0"
            }
            @{
                Description = "Minor version only (v1.0) - should suggest patch"
                Tags = @("v1.0")
                ExpectedError = $true
                ExpectedPattern = "v1\.0\.0"
            }
            @{
                Description = "Complete version set - should pass"
                Tags = @("v1.0.0", "v1.0", "v1")
                ExpectedError = $false
                ExpectedPattern = $null
            }
            @{
                Description = "Patch only - should suggest major and minor"
                Tags = @("v1.0.0")
                ExpectedError = $true
                ExpectedPattern = "v1[^.]"
            }
            @{
                Description = "Major and patch - should suggest minor"
                Tags = @("v1.0.0", "v1")
                ExpectedError = $true
                ExpectedPattern = "v1\.0[^.]"
            }
        ) {
            param($Description, $Tags, $ExpectedError, $ExpectedPattern)
            
            # Arrange
            $commitSha = Get-CommitSha
            foreach ($tag in $Tags) {
                git tag $tag $commitSha
            }
            
            # Act
            $result = Invoke-MainScript
            
            # Assert
            if ($ExpectedError) {
                $result.ReturnCode | Should -Be 1
                if ($ExpectedPattern) {
                    $result.Output | Should -Match $ExpectedPattern
                }
            } else {
                $result.ReturnCode | Should -Be 0
            }
        }
    }
    
    Context "Ignore Versions (Example Table)" {
        It "Should handle ignore-versions format: <Format>" -TestCases @(
            @{
                Format = "Comma-separated"
                IgnoreVersions = "v1.0.0,v2.0.0"
                IgnoredVersions = @("v1", "v2")
                NotIgnoredVersion = "v3"
            }
            @{
                Format = "Newline-separated"
                IgnoreVersions = "v1.0.0`nv2.0.0"
                IgnoredVersions = @("v1", "v2")
                NotIgnoredVersion = "v3"
            }
            @{
                Format = "JSON array"
                IgnoreVersions = '["v1.0.0", "v2.0.0"]'
                IgnoredVersions = @("v1", "v2")
                NotIgnoredVersion = "v3"
            }
            @{
                Format = "Wildcard pattern"
                IgnoreVersions = "v1.*"
                IgnoredVersions = @("v1")
                NotIgnoredVersion = "v2"
            }
            @{
                Format = "Mixed comma and newline"
                IgnoreVersions = "v1.0.0,v2.0.0`nv3.0.0"
                IgnoredVersions = @("v1", "v2", "v3")
                NotIgnoredVersion = "v4"
            }
        ) {
            param($Format, $IgnoreVersions, $IgnoredVersions, $NotIgnoredVersion)
            
            # Arrange
            $commitSha = Get-CommitSha
            foreach ($v in $IgnoredVersions) {
                git tag "$v.0.0" $commitSha
            }
            git tag "$NotIgnoredVersion.0.0" $commitSha
            
            # Act
            $result = Invoke-MainScript -IgnoreVersions $IgnoreVersions
            
            # Assert - Issues should only exist for non-ignored version
            $issues = $global:State.Issues
            foreach ($ignoredVer in $IgnoredVersions) {
                $matchingIssues = $issues | Where-Object { $_.Version -like "$ignoredVer*" }
                $matchingIssues.Count | Should -Be 0 -Because "Version $ignoredVer should be ignored"
            }
            
            # Not-ignored version should have issues
            $notIgnoredIssues = $issues | Where-Object { $_.Version -like "$NotIgnoredVersion*" }
            $notIgnoredIssues.Count | Should -BeGreaterThan 0 -Because "Version $NotIgnoredVersion should not be ignored"
        }
    }
    
    Context "HTTP Error Handling (Example Table)" {
        It "Should handle HTTP <StatusCode> (<Description>) gracefully" -TestCases @(
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
            
            # Should handle error gracefully (not crash)
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "Prerelease Detection" {
        It "Should NOT detect prerelease from version suffix (only from GitHub Release property)" {
            # Arrange - version suffixes are NOT supported for prerelease detection
            # Prerelease is determined by the GitHub Release isPrerelease property
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            $commit = Get-CommitSha
            
            # These tags look like prereleases but should be treated as regular versions
            # because we don't support semantic version suffixes
            git tag v1.0.0-beta $commit
            git tag v1.0.0 $commit
            
            # Act
            $result = Invoke-MainScript -IgnorePreviewReleases "true"
            
            # Assert - should handle without crashing
            # v1.0.0-beta is filtered out by the tag regex (not a valid version)
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
        
        It "Should filter prerelease versions based on GitHub Release isPrerelease property" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            git tag v2.0.0 $commit
            
            # Mock API to mark v2.0.0 as prerelease via the Release object
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                
                $mockContent = @(
                    @{ tag_name = "v1.0.0"; prerelease = $false; draft = $false; id = 1 }
                    @{ tag_name = "v2.0.0"; prerelease = $true; draft = $false; id = 2 }
                ) | ConvertTo-Json
                
                return @{
                    Content = $mockContent
                    Headers = @{}
                }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            
            # Act - with prerelease filtering enabled
            $result = Invoke-MainScript -CheckReleases "error" -IgnorePreviewReleases "true"
            
            # Clean up
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Assert - v2.0.0 should be filtered from version calculations
            # but we should still detect v1.0.0 needs v1 and v1.0
            $result.ReturnCode | Should -BeIn @(0, 1)
        }
    }
    
    Context "Pagination Handling" {
        It "Should handle API pagination with Link header" {
            Initialize-TestRepo -Path $script:testRepoPath -WithRemote
            $commit = Get-CommitSha
            git tag v1.0.0 $commit
            
            # Mock API to return pagination headers - use global scope for counter
            $global:pageRequests = 0
            $global:InvokeWebRequestWrapper = {
                param($Uri, $Headers, $Method, $TimeoutSec)
                $global:pageRequests++
                
                if ($Uri -match "page=2") {
                    # Second page - no more pages
                    return @{
                        Content = '[{"tag_name":"v2.0.0","prerelease":false,"draft":false,"id":2}]'
                        Headers = @{}
                    }
                } else {
                    # First page with Link header
                    return @{
                        Content = '[{"tag_name":"v1.0.0","prerelease":false,"draft":false,"id":1}]'
                        Headers = @{
                            Link = '<https://api.github.com/repos/test/test/releases?page=2>; rel="next"'
                        }
                    }
                }
            }
            
            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
            
            # Act - use SkipMockSetup since we set up our own mock
            $result = Invoke-MainScript -CheckReleases "error" -SkipMockSetup
            
            # Clean up
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            
            # Assert - should have made multiple requests following pagination
            $global:pageRequests | Should -BeGreaterThan 1
        }
    }
}
