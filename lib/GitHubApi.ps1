#############################################################################
# GitHubApi.ps1 - GitHub REST API Interactions
#############################################################################
# This module provides functions for interacting with the GitHub REST API
# for releases, tags, branches, and other git references.
#############################################################################

function Get-ApiHeaders
{
    param(
        [string]$Token
    )
    
    $headers = @{
        'Accept' = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    
    if ($Token) {
        $headers['Authorization'] = "Bearer $Token"
    }
    
    return $headers
}

function Get-GitHubRepoInfo
{
    param()
    
    # Return the already-parsed repository info from script-level variables
    if ($script:repoOwner -and $script:repoName) {
        return @{
            Owner = $script:repoOwner
            Repo = $script:repoName
            Url = "$script:serverUrl/$script:repoOwner/$script:repoName"
        }
    }
    
    return $null
}

function Test-ReleaseImmutability
{
    param(
        [string]$Owner,
        [string]$Repo,
        [string]$Tag,
        [string]$Token,
        [string]$ApiUrl
    )
    
    try {
        # Use GitHub GraphQL API to check if release is immutable
        $headers = Get-ApiHeaders -Token $Token
        
        # Construct the GraphQL query
        $query = @"
query(`$owner: String!, `$name: String!, `$tag: String!) {
  repository(owner: `$owner, name: `$name) {
    release(tagName: `$tag) {
      tagName
      isDraft
      immutable
    }
  }
}
"@
        
        $variables = @{
            owner = $Owner
            name = $Repo
            tag = $Tag
        }
        
        $body = @{
            query = $query
            variables = $variables
        } | ConvertTo-Json -Depth 10
        
        # Determine GraphQL endpoint from API URL
        $graphqlUrl = $ApiUrl -replace '/api/v3$', '/api/graphql'
        if ($graphqlUrl -eq $ApiUrl) {
            # Default to public GitHub GraphQL endpoint
            $graphqlUrl = "https://api.github.com/graphql"
        }
        
        $response = Invoke-RestMethod -Uri $graphqlUrl -Headers $headers -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
        
        # Check if we got a valid response
        if ($response.data.repository.release) {
            $release = $response.data.repository.release
            # Release is immutable if the GitHub API reports it as immutable
            return $release.immutable -eq $true
        }
        
        # No release found for this tag
        return $false
    }
    catch {
        Write-Verbose "Failed to check release immutability: $_"
        # If API call fails, assume not immutable
        return $false
    }
}

function Get-GitHubReleases
{
    param()
    
    try {
        # Use the pre-obtained repo info
        if (-not $script:repoInfo) {
            return @()
        }
        
        # Use GitHub REST API to get releases
        $headers = Get-ApiHeaders -Token $script:token
        $allReleases = @()
        $url = "$script:apiUrl/repos/$($script:repoInfo.Owner)/$($script:repoInfo.Repo)/releases?per_page=100"
        
        do {
            # Use a wrapper to allow for test mocking
            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                $response = Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
            } else {
                $response = Invoke-WebRequest -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
            }
            $releases = $response.Content | ConvertFrom-Json
            
            if ($releases.Count -eq 0) {
                break
            }
            
            # Collect releases
            foreach ($release in $releases) {
                $allReleases += @{
                    id = $release.id
                    tagName = $release.tag_name
                    isPrerelease = $release.prerelease
                    isDraft = $release.draft
                }
            }
            
            # Check for Link header to get next page
            $linkHeader = $response.Headers['Link']
            $url = $null
            
            if ($linkHeader) {
                # Parse Link header: <url>; rel="next", <url>; rel="last"
                # RFC 8288 allows optional whitespace before semicolon
                $links = $linkHeader -split ','
                foreach ($link in $links) {
                    if ($link -match '<([^>]+)>\s*;\s*rel="next"') {
                        $url = $matches[1]
                        break
                    }
                }
            }
            
        } while ($url)
        
        return $allReleases
    }
    catch {
        # Silently fail if API is not accessible
        return @()
    }
}

function Remove-GitHubRelease
{
    param(
        [string]$TagName
    )
    
    try {
        # Use the pre-obtained repo info
        if (-not $script:repoInfo) {
            return $false
        }
        
        # First, get the release ID for this tag
        $headers = Get-ApiHeaders -Token $script:token
        $url = "$script:apiUrl/repos/$($script:repoInfo.Owner)/$($script:repoInfo.Repo)/releases/tags/$TagName"
        
        if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
            $response = Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
        } else {
            $response = Invoke-WebRequest -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
        }
        $release = $response.Content | ConvertFrom-Json
        
        # Now delete the release
        $deleteUrl = "$script:apiUrl/repos/$($script:repoInfo.Owner)/$($script:repoInfo.Repo)/releases/$($release.id)"
        
        if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
            $deleteResponse = Invoke-WebRequestWrapper -Uri $deleteUrl -Headers $headers -Method Delete -ErrorAction Stop -TimeoutSec 5
        } else {
            $deleteResponse = Invoke-WebRequest -Uri $deleteUrl -Headers $headers -Method Delete -ErrorAction Stop -TimeoutSec 5
        }
        
        return $true
    }
    catch {
        # Wrap exception message in stop-commands to prevent workflow command injection
        Write-SafeOutput -Message ([string]$_) -Prefix "::debug::Failed to delete release for $TagName : "
        return $false
    }
}

function New-GitHubDraftRelease
{
    param(
        [string]$TagName
    )
    
    try {
        # Use the pre-obtained repo info
        if (-not $script:repoInfo) {
            return $null
        }
        
        # Create a draft release
        $headers = Get-ApiHeaders -Token $script:token
        $url = "$script:apiUrl/repos/$($script:repoInfo.Owner)/$($script:repoInfo.Repo)/releases"
        
        $body = @{
            tag_name = $TagName
            name = $TagName
            body = "Release $TagName"
            draft = $true
        } | ConvertTo-Json
        
        if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
            $response = Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
        } else {
            $responseObj = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
            $response = $responseObj
        }
        
        # Return the release ID so it can be used for publishing
        return $response.id
    }
    catch {
        # Wrap exception message in stop-commands to prevent workflow command injection
        Write-SafeOutput -Message ([string]$_) -Prefix "::debug::Failed to create draft release for $TagName : "
        return $null
    }
}

function Publish-GitHubRelease
{
    param(
        [string]$TagName,
        [Parameter(Mandatory=$false)]
        [int]$ReleaseId
    )
    
    try {
        # Use the pre-obtained repo info
        if (-not $script:repoInfo) {
            return @{ Success = $false; Unfixable = $false }
        }
        
        $headers = Get-ApiHeaders -Token $script:token
        
        # If ReleaseId is not provided, fetch it by tag name
        if (-not $ReleaseId) {
            $releasesUrl = "$script:apiUrl/repos/$($script:repoInfo.Owner)/$($script:repoInfo.Repo)/releases/tags/$TagName"
            
            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                $releaseResponse = Invoke-WebRequestWrapper -Uri $releasesUrl -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
            } else {
                $releaseResponse = Invoke-RestMethod -Uri $releasesUrl -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
            }
            
            $ReleaseId = $releaseResponse.id
        }
        
        # Update the release to publish it (set draft to false)
        $updateUrl = "$script:apiUrl/repos/$($script:repoInfo.Owner)/$($script:repoInfo.Repo)/releases/$ReleaseId"
        $body = @{
            draft = $false
        } | ConvertTo-Json
        
        if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
            $response = Invoke-WebRequestWrapper -Uri $updateUrl -Headers $headers -Method Patch -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
        } else {
            $response = Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method Patch -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
        }
        
        return @{ Success = $true; Unfixable = $false }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $isUnfixable = $false
        
        # Check if this is a 422 error about tag_name being used by an immutable release
        # First check the HTTP status code if available
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        
        # Check for the specific error condition
        if (($statusCode -eq 422 -or $errorMessage -match "422") -and $errorMessage -match "tag_name was used by an immutable release") {
            $isUnfixable = $true
            Write-SafeOutput -Message $errorMessage -Prefix "::debug::Unfixable error - tag used by immutable release for $TagName : "
        } else {
            Write-SafeOutput -Message $errorMessage -Prefix "::debug::Failed to publish release for $TagName : "
        }
        
        return @{ Success = $false; Unfixable = $isUnfixable }
    }
}

function New-GitHubRef
{
    param(
        [string]$RefName,  # e.g., "refs/tags/v1.0.0" or "refs/heads/main"
        [string]$Sha,
        [bool]$Force = $true  # Force update if ref exists
    )
    
    try {
        # Use the pre-obtained repo info
        if (-not $script:repoInfo) {
            return $false
        }
        
        $headers = Get-ApiHeaders -Token $script:token
        
        # Try to update the ref first (in case it exists)
        $updateUrl = "$script:apiUrl/repos/$($script:repoInfo.Owner)/$($script:repoInfo.Repo)/git/$RefName"
        $body = @{
            sha = $Sha
            force = $Force
        } | ConvertTo-Json
        
        try {
            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                $response = Invoke-WebRequestWrapper -Uri $updateUrl -Headers $headers -Method Patch -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
            } else {
                $response = Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method Patch -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
            }
            return $true
        }
        catch {
            # Check if this is a 404 error (ref doesn't exist)
            $is404 = $false
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode.value__
                $is404 = ($statusCode -eq 404)
            }
            
            # Only try to create if the ref doesn't exist (404 error)
            if ($is404) {
                $createUrl = "$script:apiUrl/repos/$($script:repoInfo.Owner)/$($script:repoInfo.Repo)/git/refs"
                $createBody = @{
                    ref = $RefName
                    sha = $Sha
                } | ConvertTo-Json
                
                if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                    $createResponse = Invoke-WebRequestWrapper -Uri $createUrl -Headers $headers -Method Post -Body $createBody -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
                } else {
                    $createResponse = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method Post -Body $createBody -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
                }
                return $true
            }
            else {
                # Re-throw the error if it's not a 404
                throw
            }
        }
    }
    catch {
        Write-SafeOutput -Message ([string]$_) -Prefix "::debug::Failed to create/update ref $RefName : "
        return $false
    }
}

function Remove-GitHubRef
{
    param(
        [string]$RefName  # e.g., "refs/tags/v1.0.0" or "refs/heads/main"
    )
    
    try {
        # Use the pre-obtained repo info
        if (-not $script:repoInfo) {
            return $false
        }
        
        $headers = Get-ApiHeaders -Token $script:token
        $url = "$script:apiUrl/repos/$($script:repoInfo.Owner)/$($script:repoInfo.Repo)/git/$RefName"
        
        if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
            $response = Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Delete -ErrorAction Stop -TimeoutSec 10
        } else {
            $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Delete -ErrorAction Stop -TimeoutSec 10
        }
        
        return $true
    }
    catch {
        Write-SafeOutput -Message ([string]$_) -Prefix "::debug::Failed to delete ref $RefName : "
        return $false
    }
}
