#############################################################################
# TestHelpers.psm1 - Shared test helper functions
#############################################################################
# This module provides common test utilities used across all test files.
# Import this module in BeforeAll blocks to access these functions.
#############################################################################

function Initialize-TestRepo {
    <#
    .SYNOPSIS
    Initializes a temporary git repository for testing.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$RemotePath,
        [switch]$WithRemote
    )
    
    # Get original location
    $originalLocation = Get-Location
    
    if (Test-Path $Path) {
        Remove-Item -Path $Path -Recurse -Force
    }
    
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location $Path
    
    git init --initial-branch=main 2>&1 | Out-Null
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    # Set up remote if requested
    if ($WithRemote -and $RemotePath) {
        if (Test-Path $RemotePath) {
            Remove-Item -Path $RemotePath -Recurse -Force
        }
        git init --bare --initial-branch=main $RemotePath 2>&1 | Out-Null
        git remote add origin $RemotePath 2>&1 | Out-Null
    }
    
    # Create an initial commit
    "# Test Repo" | Out-File -FilePath "README.md"
    git add README.md
    git commit -m "Initial commit" 2>&1 | Out-Null
    
    # Push initial commit to remote if it exists
    if ($WithRemote -and $RemotePath) {
        git push origin main 2>&1 | Out-Null
    }
    
    return $originalLocation
}

function Get-CommitSha {
    <#
    .SYNOPSIS
    Gets the SHA of a git reference.
    #>
    param(
        [string]$Ref = "HEAD"
    )
    return (git rev-parse $Ref).Trim()
}

function New-GitBasedApiMock {
    <#
    .SYNOPSIS
    Creates an API mock that uses local git commands to return tag/branch data.
    
    .DESCRIPTION
    This mock intercepts Invoke-WebRequestWrapper calls and returns data from the
    local git repository formatted as GitHub API responses. This allows testing
    the main script without requiring actual GitHub API access.
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
    <#
    .SYNOPSIS
    Invokes the main.ps1 script with specified parameters.
    
    .DESCRIPTION
    Sets up the environment, mocks, and runs main.ps1 with the given configuration.
    Returns an object with Output and ReturnCode properties.
    #>
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
    $global:returnCode = 0
    
    # Define mock function in global scope before running script (unless caller skipped)
    if (-not $SkipMockSetup) {
        # Use the git-based API mock by default
        $global:InvokeWebRequestWrapper = New-GitBasedApiMock
        
        # Make the function available
        Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $global:InvokeWebRequestWrapper
    }
    
    # Determine main.ps1 path - look for it relative to the module location
    $mainScriptPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "main.ps1"
    if (-not (Test-Path $mainScriptPath)) {
        # Fallback: try current directory structure
        $mainScriptPath = Join-Path $PSScriptRoot "../../main.ps1"
    }
    
    # Capture output
    $output = & $mainScriptPath 2>&1 | Out-String
    
    # Clean up mock
    if (Test-Path function:global:Invoke-WebRequestWrapper) {
        Remove-Item function:global:Invoke-WebRequestWrapper
    }
    
    return @{
        Output = $output
        ReturnCode = $global:returnCode
    }
}

Export-ModuleMember -Function Initialize-TestRepo, Get-CommitSha, New-GitBasedApiMock, Invoke-MainScript
