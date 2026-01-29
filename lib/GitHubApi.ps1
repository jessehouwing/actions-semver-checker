#############################################################################
# GitHubApi.ps1 - GitHub REST API Interactions
#############################################################################
# This module provides functions for interacting with the GitHub REST API
# for releases, tags, branches, and other git references.
#############################################################################

#############################################################################
# Retry Helper Function
# Provides exponential backoff retry logic for API calls
#############################################################################

function Invoke-WithRetry
{
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [int]$MaxRetries = 3,
        [int]$InitialDelaySeconds = 1,
        [string]$OperationDescription = "operation"
    )
    
    $attempt = 0
    $delay = $InitialDelaySeconds
    
    while ($attempt -lt $MaxRetries) {
        $attempt++
        
        try {
            Write-Host "::debug::Attempt $attempt of $MaxRetries for $OperationDescription"
            return & $ScriptBlock
        }
        catch {
            $errorMessage = $_.Exception.Message
            
            # Check if this is a retryable error (network, timeout, rate limit)
            $isRetryable = $errorMessage -match '(timeout|connection|429|503|502|500)' -or
                          $_.Exception.GetType().Name -match '(WebException|HttpRequestException)'
            
            if ($attempt -ge $MaxRetries -or -not $isRetryable) {
                Write-Host "::debug::Non-retryable error or max retries reached for $OperationDescription"
                throw
            }
            
            Write-Host "::warning::$OperationDescription failed (attempt $attempt/$MaxRetries): $errorMessage. Retrying in $delay seconds..."
            Start-Sleep -Seconds $delay
            
            # Exponential backoff: double the delay each time
            $delay = $delay * 2
        }
    }
    
    # Safeguard: This should not be reached due to the throw on line 43, but add explicit error
    throw "Maximum retry attempts ($MaxRetries) reached for $OperationDescription without success or error"
}

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
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State
    )
    
    # Return the repository info from State
    if ($State.RepoOwner -and $State.RepoName) {
        return @{
            Owner = $State.RepoOwner
            Repo = $State.RepoName
            Url = "$($State.ServerUrl)/$($State.RepoOwner)/$($State.RepoName)"
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
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return @()
        }
        
        # Use GitHub REST API to get releases
        $headers = Get-ApiHeaders -Token $State.Token
        $allReleases = @()
        $url = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases?per_page=100"
        
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
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        [string]$TagName,
        [int]$ReleaseId = 0
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return $false
        }
        
        $headers = Get-ApiHeaders -Token $State.Token
        $releaseIdToDelete = $ReleaseId
        
        # If ReleaseId not provided, look it up by tag name
        # This handles both draft releases (which may not have tags yet) and regular releases
        if ($releaseIdToDelete -eq 0) {
            # Try to find the release ID from State.Releases first (more reliable for drafts)
            $releaseFromState = $State.Releases | Where-Object { $_.TagName -eq $TagName } | Select-Object -First 1
            if ($releaseFromState) {
                $releaseIdToDelete = $releaseFromState.Id
                Write-Host "::debug::Found release ID $releaseIdToDelete for $TagName from State"
            } else {
                # Fall back to API lookup by tag name (may fail for draft releases without tags)
                Write-Host "::debug::Looking up release by tag name: $TagName"
                $url = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases/tags/$TagName"
                
                if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                    $response = Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
                } else {
                    $response = Invoke-WebRequest -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
                }
                $release = $response.Content | ConvertFrom-Json
                $releaseIdToDelete = $release.id
            }
        }
        
        # Delete the release using the ID
        $deleteUrl = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases/$releaseIdToDelete"
        Write-Host "::debug::Deleting release ID $releaseIdToDelete for $TagName"
        
        if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
            $deleteResponse = Invoke-WebRequestWrapper -Uri $deleteUrl -Headers $headers -Method Delete -ErrorAction Stop -TimeoutSec 5
        } else {
            $deleteResponse = Invoke-WebRequest -Uri $deleteUrl -Headers $headers -Method Delete -ErrorAction Stop -TimeoutSec 5
        }
        
        return $true
    }
    catch {
        # Wrap exception message in stop-commands to prevent workflow command injection
        Write-SafeOutput -Message ([string]$_) -Prefix "::debug::Failed to delete release for $TagName (ID: $ReleaseId) : "
        return $false
    }
}

function New-GitHubDraftRelease
{
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        [string]$TagName
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return $null
        }
        
        # Create a draft release
        $headers = Get-ApiHeaders -Token $State.Token
        $url = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases"
        
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
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        [string]$TagName,
        [Parameter(Mandatory=$false)]
        [int]$ReleaseId
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return @{ Success = $false; Unfixable = $false }
        }
        
        $headers = Get-ApiHeaders -Token $State.Token
        
        # If ReleaseId is not provided, fetch it by tag name
        if (-not $ReleaseId) {
            $releasesUrl = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases/tags/$TagName"
            
            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                $releaseResponse = Invoke-WebRequestWrapper -Uri $releasesUrl -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
            } else {
                $releaseResponse = Invoke-RestMethod -Uri $releasesUrl -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
            }
            
            $ReleaseId = $releaseResponse.id
        }
        
        # Update the release to publish it (set draft to false)
        $updateUrl = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases/$ReleaseId"
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

function Republish-GitHubRelease
{
    <#
    .SYNOPSIS
    Republish a release to make it immutable.
    
    .DESCRIPTION
    When immutable releases are enabled for a repository, existing releases
    are not automatically made immutable. This function converts a mutable
    release to immutable by temporarily making it a draft, then publishing it again.
    
    This only works for patch versions (vX.Y.Z) and will fail if the release
    is already immutable.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        [Parameter(Mandatory)]
        [string]$TagName
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return @{ Success = $false; Reason = "No repo info available" }
        }
        
        $headers = Get-ApiHeaders -Token $State.Token
        
        # Step 1: Get the release by tag name
        $releasesUrl = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases/tags/$TagName"
        
        $releaseResponse = Invoke-WithRetry -OperationDescription "Get release $TagName" -ScriptBlock {
            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                Invoke-WebRequestWrapper -Uri $releasesUrl -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
            } else {
                Invoke-RestMethod -Uri $releasesUrl -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
            }
        }
        
        $releaseId = $releaseResponse.id
        $isDraft = $releaseResponse.draft
        
        # Step 2: Check if already immutable
        $isImmutable = Test-ReleaseImmutability -Owner $repoInfo.Owner -Repo $repoInfo.Repo -Tag $TagName -Token $State.Token -ApiUrl $State.ApiUrl
        
        if ($isImmutable) {
            Write-Host "::debug::Release $TagName is already immutable, skipping"
            return @{ Success = $true; Reason = "Already immutable" }
        }
        
        # If not already in draft, make it a draft first
        if (-not $isDraft) {
            Write-Host "::debug::Converting release $TagName to draft"
            $updateUrl = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases/$releaseId"
            $draftBody = @{
                draft = $true
            } | ConvertTo-Json
            
            Invoke-WithRetry -OperationDescription "Convert release $TagName to draft" -ScriptBlock {
                if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                    Invoke-WebRequestWrapper -Uri $updateUrl -Headers $headers -Method Patch -Body $draftBody -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
                } else {
                    Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method Patch -Body $draftBody -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
                }
            }
        }
        
        # Step 3: Publish the release to make it immutable
        Write-Host "::debug::Publishing release $TagName to make it immutable"
        $publishResult = Publish-GitHubRelease -State $State -TagName $TagName -ReleaseId $releaseId
        
        if ($publishResult.Success) {
            return @{ Success = $true; Reason = "Republished successfully" }
        } else {
            return @{ Success = $false; Reason = "Failed to publish" }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-SafeOutput -Message $errorMessage -Prefix "::debug::Failed to republish release for $TagName : "
        return @{ Success = $false; Reason = $errorMessage }
    }
}

function New-GitHubRef
{
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        [string]$RefName,  # e.g., "refs/tags/v1.0.0" or "refs/heads/main"
        [string]$Sha,
        [bool]$Force = $true  # Force update if ref exists
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return $false
        }
        
        $headers = Get-ApiHeaders -Token $State.Token
        
        # Try to update the ref first (in case it exists)
        $updateUrl = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/git/$RefName"
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
                $createUrl = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/git/refs"
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
        # Extract detailed error information
        $errorMessage = $_.Exception.Message
        $statusCode = 0
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        
        # Check for permission errors (403 Forbidden)
        if ($statusCode -eq 403) {
            Write-Host "::debug::REST API returned 403 for $RefName, falling back to git push"
            
            # Fall back to using git push since REST API doesn't have permission
            # Extract tag/branch name from RefName (e.g., "refs/tags/v1.0.0" -> "v1.0.0")
            $refParts = $RefName -split '/'
            $refShortName = $refParts[-1]
            
            try {
                # Use git push to create/update the ref
                if ($Force) {
                    $gitCmd = "git push origin $Sha`:$RefName --force"
                } else {
                    $gitCmd = "git push origin $Sha`:$RefName"
                }
                
                Write-Host "::debug::Executing fallback: $gitCmd"
                
                # Execute git push
                $output = & git push origin "$Sha`:$RefName" $(if ($Force) { '--force' }) 2>&1
                $exitCode = $LASTEXITCODE
                
                if ($exitCode -eq 0) {
                    Write-Host "::debug::Successfully created/updated $RefName via git push"
                    return $true
                } else {
                    Write-Host "::error::Git push failed for $RefName"
                    Write-SafeOutput -Message ([string]$output) -Prefix "::error::Git push error: "
                    return $false
                }
            }
            catch {
                Write-Host "::error::Failed to push $RefName via git"
                Write-SafeOutput -Message ([string]$_) -Prefix "::error::Git error: "
                return $false
            }
        } else {
            Write-SafeOutput -Message $errorMessage -Prefix "::debug::Failed to create/update ref $RefName : "
        }
        
        return $false
    }
}

function Remove-GitHubRef
{
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        [string]$RefName  # e.g., "refs/tags/v1.0.0" or "refs/heads/main"
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return $false
        }
        
        $headers = Get-ApiHeaders -Token $State.Token
        $url = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/git/$RefName"
        
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
