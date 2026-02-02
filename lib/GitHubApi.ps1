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
    
    # Check if retries are disabled via environment variable (useful for faster test execution)
    # Set $env:GITHUB_API_DISABLE_RETRY = 'true' to skip retries and fail immediately
    if ($env:GITHUB_API_DISABLE_RETRY -eq 'true') {
        Write-Host "::debug::Retries disabled for $OperationDescription (GITHUB_API_DISABLE_RETRY=true)"
        return & $ScriptBlock
    }
    
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
            $isRetryable = $errorMessage -match '(timeout|connection|429|503|502|500)' -or `
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

function Get-ApiHeader {
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

function Throw-GitHubApiFailure
{
    param(
        [Parameter(Mandatory)]
        [string]$Operation,
        [Parameter(Mandatory)]
        $ErrorRecord
    )

    $detailMessage = $null
    $statusCode = $null

    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
        if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
            $detailMessage = $ErrorRecord.ErrorDetails.Message
        } elseif ($ErrorRecord.Exception -and $ErrorRecord.Exception.Message) {
            $detailMessage = $ErrorRecord.Exception.Message
        }

        if ($ErrorRecord.Exception -and $ErrorRecord.Exception.Response) {
            $statusCode = $ErrorRecord.Exception.Response.StatusCode.value__
        }
    }

    if (-not $detailMessage) {
        $detailMessage = [string]$ErrorRecord
    }

    $statusSuffix = if ($statusCode) { " (HTTP $statusCode)" } else { "" }
    Write-SafeOutput -Message $detailMessage -Prefix "::error::GitHub API request failed during $Operation$statusSuffix. "

    throw "GitHub API request failed during $Operation$statusSuffix"
}

function Test-VersionShouldBeIgnored {
    <#
    .SYNOPSIS
    Tests if a version should be ignored based on the ignore-versions patterns.
    
    .DESCRIPTION
    Checks if a version matches any of the ignore patterns. Supports both exact
    matches and wildcard patterns (using PowerShell's -like operator).
    
    .PARAMETER Version
    The version string to check (e.g., "v1.0.0", "v2.1")
    
    .PARAMETER IgnoreVersions
    Array of patterns to match against. Supports wildcards like "v1.*"
    
    .EXAMPLE
    Test-VersionShouldBeIgnored -Version "v1.0.0" -IgnoreVersions @("v1.*")
    # Returns $true
    
    .EXAMPLE
    Test-VersionShouldBeIgnored -Version "v2.0.0" -IgnoreVersions @("v1.0.0", "v1.1.0")
    # Returns $false
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version,
        
        [string[]]$IgnoreVersions = @()
    )
    
    if (-not $IgnoreVersions -or $IgnoreVersions.Count -eq 0) {
        return $false
    }
    
    foreach ($pattern in $IgnoreVersions) {
        # Use -like for wildcard pattern matching (supports *, ?)
        if ($Version -like $pattern) {
            return $true
        }
    }
    
    return $false
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
        $headers = Get-ApiHeader -Token $Token
        
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
        
        $response = Invoke-WithRetry -OperationDescription "Release immutability check for $Tag" -ScriptBlock {
            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                Invoke-WebRequestWrapper -Uri $graphqlUrl -Headers $headers -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
            } else {
                Invoke-RestMethod -Uri $graphqlUrl -Headers $headers -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
            }
        }

        if ($response -is [System.Collections.IDictionary] -and $response.ContainsKey('Content')) {
            $response = $response.Content | ConvertFrom-Json
        }
        
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
        Throw-GitHubApiFailure -Operation "release immutability check for $Tag" -ErrorRecord $_
    }
}

function Get-GitHubRelease {
    <#
    .SYNOPSIS
    Fetches all releases from a GitHub repository via the GraphQL API.
    
    .DESCRIPTION
    Uses the GitHub GraphQL API to fetch all releases with immutability and latest status.
    Returns ReleaseInfo objects directly, ready to add to RepositoryState.
    
    .PARAMETER State
    The RepositoryState object containing API configuration.
    
    .PARAMETER IgnoreVersions
    Optional array of version strings to mark as ignored.
    
    .OUTPUTS
    Returns an array of ReleaseInfo objects.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        
        [string[]]$IgnoreVersions = @()
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return @()
        }
        
        # Use GitHub GraphQL API to get releases with immutability status
        # This is more efficient than REST API + separate immutability checks
        $headers = Get-ApiHeader -Token $State.Token
        [ReleaseInfo[]]$allReleases = @()
        $cursor = $null
        
        # Determine GraphQL endpoint from API URL
        $graphqlUrl = $State.ApiUrl -replace '/api/v3$', '/api/graphql'
        if ($graphqlUrl -eq $State.ApiUrl) {
            # Default to public GitHub GraphQL endpoint
            $graphqlUrl = "https://api.github.com/graphql"
        }
        
        # Construct the GraphQL query
        $query = @"
query(`$owner: String!, `$name: String!, `$first: Int!, `$after: String) {
  repository(owner: `$owner, name: `$name) {
    releases(first: `$first, after: `$after, orderBy: {field: CREATED_AT, direction: DESC}) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        databaseId
        tagName
        isPrerelease
        isDraft
        immutable
        isLatest
      }
    }
  }
}
"@
        
        do {
            $variables = @{
                owner = $repoInfo.Owner
                name = $repoInfo.Repo
                first = 100
            }
            
            if ($cursor) {
                $variables['after'] = $cursor
            }
            
            $body = @{
                query = $query
                variables = $variables
            } | ConvertTo-Json -Depth 10
            
            # Use retry logic for transient failures
            $response = Invoke-WithRetry -OperationDescription "Get releases page" -ScriptBlock {
                # Use a wrapper to allow for test mocking
                if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                    Invoke-WebRequestWrapper -Uri $graphqlUrl -Headers $headers -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
                } else {
                    Invoke-RestMethod -Uri $graphqlUrl -Headers $headers -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
                }
            }
            
            # Handle response format (may be wrapped in Content property for Invoke-WebRequest)
            if ($response -is [System.Collections.IDictionary] -and $response.ContainsKey('Content')) {
                $response = $response.Content | ConvertFrom-Json
            }
            
            # Check for GraphQL errors
            if ($response.errors) {
                $errorMessages = ($response.errors | ForEach-Object { $_.message }) -join '; '
                throw "GraphQL errors: $errorMessages"
            }
            
            $releases = $response.data.repository.releases
            
            if (-not $releases -or -not $releases.nodes -or $releases.nodes.Count -eq 0) {
                break
            }
            
            # Collect releases - create ReleaseInfo objects directly
            foreach ($release in $releases.nodes) {
                # Build PSCustomObject in the format ReleaseInfo constructor expects
                $releaseData = [PSCustomObject]@{
                    tag_name = $release.tagName
                    id = $release.databaseId
                    draft = $release.isDraft
                    prerelease = $release.isPrerelease
                    html_url = $null  # Not available in GraphQL query
                    target_commitish = $null  # Not available in GraphQL query
                    immutable = $release.immutable
                    isLatest = $release.isLatest
                }
                
                $ri = [ReleaseInfo]::new($releaseData)
                
                # Check if this release's tag should be ignored (supports wildcards)
                $ri.IsIgnored = Test-VersionShouldBeIgnored -Version $ri.TagName -IgnoreVersions $IgnoreVersions
                
                $allReleases += $ri
            }
            
            # Check if there are more pages
            if ($releases.pageInfo.hasNextPage) {
                $cursor = $releases.pageInfo.endCursor
            } else {
                $cursor = $null
            }
            
        } while ($cursor)
        
        return $allReleases
    }
    catch {
        Throw-GitHubApiFailure -Operation "fetching releases" -ErrorRecord $_
    }
}

function Get-GitHubTag {
    <#
    .SYNOPSIS
    Fetches all tags from a GitHub repository via the REST API.
    
    .DESCRIPTION
    Uses the GitHub REST API to fetch all tags from the repository.
    This eliminates the need for a full clone with fetch-depth: 0 and fetch-tags: true.
    Returns VersionRef objects directly, ready to add to RepositoryState.
    
    .PARAMETER State
    The RepositoryState object containing API configuration.
    
    .PARAMETER Pattern
    Optional regex pattern to filter tags. If not specified, all tags are returned.
    
    .PARAMETER IgnoreVersions
    Optional array of version strings to mark as ignored.
    
    .OUTPUTS
    Returns an array of VersionRef objects.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        
        [string]$Pattern = $null,
        
        [string[]]$IgnoreVersions = @()
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            Write-Host "::debug::No repo info available for fetching tags"
            return @()
        }
        
        $headers = Get-ApiHeader -Token $State.Token
        $allTags = @()  # Untyped array for accumulating hashtables
        $url = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/git/refs/tags?per_page=100"
        
        do {
            $response = Invoke-WithRetry -OperationDescription "Get tags page" -ScriptBlock {
                if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                    Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
                } else {
                    Invoke-WebRequest -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
                }
            }
            
            $refs = $response.Content | ConvertFrom-Json
            
            # Handle case where response is a single object instead of array
            if ($refs -isnot [array]) {
                $refs = @($refs)
            }
            
            if ($refs.Count -eq 0) {
                break
            }
            
            foreach ($ref in $refs) {
                # refs/tags/v1.0.0 -> v1.0.0
                $tagName = $ref.ref -replace '^refs/tags/', ''
                
                # Apply pattern filter if specified
                if ($Pattern -and $tagName -notmatch $Pattern) {
                    continue
                }
                
                # Get the SHA - for annotated tags, we need to dereference
                $sha = $ref.object.sha
                
                # If this is an annotated tag (type = "tag"), we need to get the commit SHA
                if ($ref.object.type -eq "tag") {
                    try {
                        $tagResponse = Invoke-WithRetry -OperationDescription "Dereference tag $tagName" -ScriptBlock {
                            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                                Invoke-WebRequestWrapper -Uri $ref.object.url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
                            } else {
                                Invoke-WebRequest -Uri $ref.object.url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
                            }
                        }
                        $tagObj = $tagResponse.Content | ConvertFrom-Json
                        $sha = $tagObj.object.sha
                    }
                    catch {
                        Throw-GitHubApiFailure -Operation "dereferencing annotated tag $tagName" -ErrorRecord $_
                    }
                }
                
                $allTags += @{
                    name = $tagName
                    sha = $sha
                }
            }
            
            # Check for Link header to get next page
            $linkHeader = $response.Headers['Link']
            $url = $null
            
            if ($linkHeader) {
                $links = $linkHeader -split ','
                foreach ($link in $links) {
                    if ($link -match '<([^>]+)>\s*;\s*rel="next"') {
                        $url = $matches[1]
                        break
                    }
                }
            }
            
        } while ($url)
        
        # Convert hashtables to VersionRef objects
        [VersionRef[]]$result = @()
        foreach ($tag in $allTags) {
            $vr = [VersionRef]::new($tag.name, "refs/tags/$($tag.name)", $tag.sha, "tag")
            
            # Check if this version should be ignored (supports wildcards)
            $vr.IsIgnored = Test-VersionShouldBeIgnored -Version $tag.name -IgnoreVersions $IgnoreVersions
            
            $result += $vr
        }
        
        return $result
    }
    catch {
        Throw-GitHubApiFailure -Operation "fetching tags" -ErrorRecord $_
    }
}

function Get-GitHubBranch {
    <#
    .SYNOPSIS
    Fetches all branches from a GitHub repository via the REST API.
    
    .DESCRIPTION
    Uses the GitHub REST API to fetch all branches from the repository.
    This eliminates the need for a full clone.
    Returns VersionRef objects directly, ready to add to RepositoryState.
    
    .PARAMETER State
    The RepositoryState object containing API configuration.
    
    .PARAMETER Pattern
    Optional regex pattern to filter branches. If not specified, all branches are returned.
    
    .PARAMETER IgnoreVersions
    Optional array of version strings to mark as ignored.
    
    .OUTPUTS
    Returns an array of VersionRef objects.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        
        [string]$Pattern = $null,
        
        [string[]]$IgnoreVersions = @()
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            Write-Host "::debug::No repo info available for fetching branches"
            return @()
        }
        
        $headers = Get-ApiHeader -Token $State.Token
        $allBranches = @()
        $url = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/branches?per_page=100"
        
        do {
            $response = Invoke-WithRetry -OperationDescription "Get branches page" -ScriptBlock {
                if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                    Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
                } else {
                    Invoke-WebRequest -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
                }
            }
            
            $branches = $response.Content | ConvertFrom-Json
            
            if ($branches.Count -eq 0) {
                break
            }
            
            foreach ($branch in $branches) {
                # Apply pattern filter if specified
                if ($Pattern -and $branch.name -notmatch $Pattern) {
                    continue
                }
                
                $allBranches += @{
                    name = $branch.name
                    sha = $branch.commit.sha
                }
            }
            
            # Check for Link header to get next page
            $linkHeader = $response.Headers['Link']
            $url = $null
            
            if ($linkHeader) {
                $links = $linkHeader -split ','
                foreach ($link in $links) {
                    if ($link -match '<([^>]+)>\s*;\s*rel="next"') {
                        $url = $matches[1]
                        break
                    }
                }
            }
            
        } while ($url)
        
        # Convert hashtables to VersionRef objects
        [VersionRef[]]$result = @()
        foreach ($branch in $allBranches) {
            $vr = [VersionRef]::new($branch.name, "refs/heads/$($branch.name)", $branch.sha, "branch")
            
            # Check if this version should be ignored (supports wildcards)
            $vr.IsIgnored = Test-VersionShouldBeIgnored -Version $branch.name -IgnoreVersions $IgnoreVersions
            
            $result += $vr
        }
        
        return $result
    }
    catch {
        Throw-GitHubApiFailure -Operation "fetching branches" -ErrorRecord $_
    }
}

function Get-GitHubRef
{
    <#
    .SYNOPSIS
    Gets the SHA for a specific git reference (tag or branch) via the REST API.
    
    .DESCRIPTION
    Fetches the commit SHA for a specific reference. This is useful when you need
    the SHA for a single ref rather than fetching all refs.
    
    .PARAMETER State
    The RepositoryState object containing API configuration.
    
    .PARAMETER RefName
    The reference name (e.g., "v1.0.0" for a tag, "main" for a branch).
    
    .PARAMETER RefType
    The type of reference: "tags" or "heads" (for branches).
    
    .OUTPUTS
    Returns the commit SHA as a string, or $null if not found.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        
        [Parameter(Mandatory)]
        [string]$RefName,
        
        [Parameter(Mandatory)]
        [ValidateSet("tags", "heads")]
        [string]$RefType
    )
    
    try {
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return $null
        }
        
        $headers = Get-ApiHeader -Token $State.Token
        $url = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/git/refs/$RefType/$RefName"
        
        $response = Invoke-WithRetry -OperationDescription "Get ref $RefType/$RefName" -ScriptBlock {
            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
            } else {
                Invoke-WebRequest -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
            }
        }
        
        $ref = $response.Content | ConvertFrom-Json
        $sha = $ref.object.sha
        
        # If this is an annotated tag, dereference it
        if ($ref.object.type -eq "tag") {
            try {
                $tagResponse = Invoke-WithRetry -OperationDescription "Dereference ref $RefName" -ScriptBlock {
                    if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                        Invoke-WebRequestWrapper -Uri $ref.object.url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
                    } else {
                        Invoke-WebRequest -Uri $ref.object.url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
                    }
                }
                $tagObj = $tagResponse.Content | ConvertFrom-Json
                $sha = $tagObj.object.sha
            }
            catch {
                Throw-GitHubApiFailure -Operation "dereferencing annotated ref $RefName" -ErrorRecord $_
            }
        }
        
        return $sha
    }
    catch {
        $statusCode = $null
        if ($_.Exception -and $_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }

        if ($statusCode -eq 404) {
            Write-Host "::debug::Ref $RefType/$RefName not found"
            return $null
        }

        Throw-GitHubApiFailure -Operation "fetching ref $RefType/$RefName" -ErrorRecord $_
    }
}

function Test-ImmutableReleaseError
{
    <#
    .SYNOPSIS
    Check if an error is a 422 error indicating a tag was used by an immutable release.
    
    .DESCRIPTION
    When a release is deleted but was immutable, GitHub prevents creating/updating
    releases with the same tag. This function checks if an error matches this condition.
    
    .PARAMETER ErrorRecord
    The error record from a catch block ($_).
    
    .OUTPUTS
    Returns $true if this is an immutable release conflict error, $false otherwise.
    #>
    param(
        [Parameter(Mandatory)]
        $ErrorRecord
    )
    
    # Check status code
    $statusCode = $null
    if ($ErrorRecord.Exception.Response) {
        $statusCode = $ErrorRecord.Exception.Response.StatusCode.value__
    }
    
    # Must be a 422 error
    if ($statusCode -ne 422 -and $ErrorRecord.Exception.Message -notmatch "422") {
        return $false
    }
    
    # Try to parse the error details JSON
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        try {
            $errorData = $ErrorRecord.ErrorDetails.Message | ConvertFrom-Json
            
            # Check if errors array contains the immutable release message
            if ($errorData.errors) {
                foreach ($err in $errorData.errors) {
                    if ($err.field -eq "tag_name" -and $err.message -match "was used by an immutable release") {
                        return $true
                    }
                }
                # None of the structured errors matched, so this is not an immutable release error
                return $false
            }
        }
        catch {
            # If JSON parsing fails, fall back to string matching
            # This is intentional - we continue to the fallback check below
            $null = $null  # Suppress PSSA warning for empty catch
        }
    }
    
    # Fallback: check the exception message directly (only if ErrorDetails parsing failed or unavailable)
    return $ErrorRecord.Exception.Message -match "tag_name was used by an immutable release"
}

function Remove-GitHubRelease
{
    <#
    .SYNOPSIS
    Deletes a GitHub release via the REST API.
    
    .PARAMETER State
    The RepositoryState object containing API configuration.
    
    .PARAMETER TagName
    The tag name associated with the release.
    
    .PARAMETER ReleaseId
    Optional. The release ID. If not provided, will be looked up by tag name.
    
    .OUTPUTS
    Returns $true if deletion succeeded, $false otherwise.
    #>
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
        
        $headers = Get-ApiHeader -Token $State.Token
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
                
                $response = Invoke-WithRetry -OperationDescription "Get release $TagName" -ScriptBlock {
                    if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                        Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
                    } else {
                        Invoke-WebRequest -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 5
                    }
                }
                $release = $response.Content | ConvertFrom-Json
                $releaseIdToDelete = $release.id
            }
        }
        
        # Delete the release using the ID
        $deleteUrl = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases/$releaseIdToDelete"
        Write-Host "::debug::Deleting release ID $releaseIdToDelete for $TagName"
        
        Invoke-WithRetry -OperationDescription "Delete release $TagName" -ScriptBlock {
            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                $null = Invoke-WebRequestWrapper -Uri $deleteUrl -Headers $headers -Method Delete -ErrorAction Stop -TimeoutSec 5
            } else {
                $null = Invoke-WebRequest -Uri $deleteUrl -Headers $headers -Method Delete -ErrorAction Stop -TimeoutSec 5
            }
        }
        
        return $true
    }
    catch {
        # Wrap exception message in stop-commands to prevent workflow command injection
        Write-SafeOutput -Message ([string]$_) -Prefix "::debug::Failed to delete release for $TagName (ID: $ReleaseId) : "
        return $false
    }
}

function New-GitHubRelease
{
    <#
    .SYNOPSIS
    Create a GitHub release (draft or published).
    
    .DESCRIPTION
    Creates a GitHub release for the specified tag. Can create either a draft release
    or a published release based on the Draft parameter.
    
    .PARAMETER State
    The repository state object containing API configuration.
    
    .PARAMETER TagName
    The tag name for the release.
    
    .PARAMETER Draft
    If true, creates a draft release. If false, creates a published release. Defaults to true.
    
    .PARAMETER MakeLatest
    Controls whether this release should be marked as "latest".
    - $true: Force this release to be latest
    - $false: Prevent this release from becoming latest
    - $null: Let GitHub determine based on version (default behavior)
    
    .OUTPUTS
    A hashtable with Success (bool), ReleaseId (int or null), and Unfixable (bool) properties.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        [string]$TagName,
        [bool]$Draft = $true,
        [Parameter(Mandatory = $false)]
        $MakeLatest = $null
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return @{ Success = $false; ReleaseId = $null; Unfixable = $false }
        }
        
        # Create a release (draft or published based on parameter)
        $headers = Get-ApiHeader -Token $State.Token
        $url = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases"
        
        $bodyObj = @{
            tag_name = $TagName
            name = $TagName
            body = "Release $TagName"
            draft = $Draft
        }
        
        # Add make_latest if explicitly specified
        if ($null -ne $MakeLatest) {
            $bodyObj['make_latest'] = if ($MakeLatest) { 'true' } else { 'false' }
        }
        
        $body = $bodyObj | ConvertTo-Json
        
        if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
            $response = Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
            $releaseObj = $response.Content | ConvertFrom-Json
        } else {
            $releaseObj = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
        }
        
        # Return success with the release ID
        return @{ Success = $true; ReleaseId = $releaseObj.id; Unfixable = $false }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $isUnfixable = Test-ImmutableReleaseError -ErrorRecord $_
        
        if ($isUnfixable) {
            Write-SafeOutput -Message $errorMessage -Prefix "::debug::Unfixable error - tag used by immutable release for $TagName : "
        } else {
            Write-SafeOutput -Message $errorMessage -Prefix "::debug::Failed to create release for $TagName : "
        }
        
        return @{ Success = $false; ReleaseId = $null; Unfixable = $isUnfixable }
    }
}

function Publish-GitHubRelease {
    <#
    .SYNOPSIS
    Publish a draft GitHub release.
    
    .DESCRIPTION
    Publishes a draft release by setting draft to false. Optionally controls whether
    the release should be marked as "latest".
    
    .PARAMETER State
    The repository state object containing API configuration.
    
    .PARAMETER TagName
    The tag name for the release.
    
    .PARAMETER ReleaseId
    The release ID. If not provided, will be looked up by tag name.
    
    .PARAMETER MakeLatest
    Controls whether this release should be marked as "latest".
    - $true: Force this release to be latest
    - $false: Prevent this release from becoming latest
    - $null: Let GitHub determine based on version (default behavior)
    
    .OUTPUTS
    A hashtable with Success (bool) and Unfixable (bool) properties.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        [string]$TagName,
        [Parameter(Mandatory = $false)]
        [int]$ReleaseId,
        [Parameter(Mandatory = $false)]
        $MakeLatest = $null
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return @{ Success = $false; Unfixable = $false }
        }
        
        $headers = Get-ApiHeader -Token $State.Token
        
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
        $bodyObj = @{
            draft = $false
        }
        
        # Add make_latest if explicitly specified
        if ($null -ne $MakeLatest) {
            $bodyObj['make_latest'] = if ($MakeLatest) { 'true' } else { 'false' }
        }
        
        $body = $bodyObj | ConvertTo-Json
        
        # Use error variable to capture errors without writing to error stream
        if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
            $null = Invoke-WebRequestWrapper -Uri $updateUrl -Headers $headers -Method Patch -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
        } else {
            # Suppress PowerShell error output by using try/catch and error variable
            $null = Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method Patch -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
        }
        
        return @{ Success = $true; Unfixable = $false }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $isUnfixable = Test-ImmutableReleaseError -ErrorRecord $_
        
        if ($isUnfixable) {
            Write-SafeOutput -Message $errorMessage -Prefix "::debug::Unfixable error - tag used by immutable release for $TagName : "
        } else {
            Write-SafeOutput -Message $errorMessage -Prefix "::debug::Failed to publish release for $TagName : "
        }
        
        return @{ Success = $false; Unfixable = $isUnfixable }
    }
}

function Set-GitHubReleaseLatest
{
    <#
    .SYNOPSIS
    Set a release as the "latest" release in GitHub.
    
    .DESCRIPTION
    Updates a release to be marked as the "latest" release using the make_latest
    parameter. This is used when the wrong release is currently marked as latest.
    
    .PARAMETER State
    The repository state object containing API configuration.
    
    .PARAMETER TagName
    The tag name for the release.
    
    .PARAMETER ReleaseId
    The release ID.
    
    .OUTPUTS
    A hashtable with Success (bool) and Unfixable (bool) properties.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        [Parameter(Mandatory)]
        [string]$TagName,
        [Parameter(Mandatory)]
        [int]$ReleaseId
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return @{ Success = $false; Unfixable = $false }
        }
        
        $headers = Get-ApiHeader -Token $State.Token
        
        # Update the release to set it as latest
        $updateUrl = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/releases/$ReleaseId"
        $body = @{
            make_latest = 'true'
        } | ConvertTo-Json
        
        if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
            $null = Invoke-WebRequestWrapper -Uri $updateUrl -Headers $headers -Method Patch -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
        } else {
            $null = Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method Patch -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
        }
        
        return @{ Success = $true; Unfixable = $false }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $isUnfixable = Test-ImmutableReleaseError -ErrorRecord $_
        
        if ($isUnfixable) {
            Write-SafeOutput -Message $errorMessage -Prefix "::debug::Unfixable error when setting $TagName as latest: "
        } else {
            Write-SafeOutput -Message $errorMessage -Prefix "::debug::Failed to set release $TagName as latest: "
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
        [string]$TagName,
        [Parameter(Mandatory = $false)]
        $MakeLatest = $null
    )
    
    try {
        # Get repo info from State
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return @{ Success = $false; Reason = "No repo info available"; Unfixable = $false }
        }
        
        $headers = Get-ApiHeader -Token $State.Token
        
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
            return @{ Success = $true; Reason = "Already immutable"; Unfixable = $false }
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
        Write-Host "::debug::Publishing release $TagName to make it immutable (makeLatest=$MakeLatest)"
        $publishResult = Publish-GitHubRelease -State $State -TagName $TagName -ReleaseId $releaseId -MakeLatest $MakeLatest
        
        if ($publishResult.Success) {
            return @{ Success = $true; Reason = "Republished successfully"; Unfixable = $false }
        } else {
            # Propagate the unfixable status from Publish-GitHubRelease
            $isUnfixable = $publishResult.ContainsKey('Unfixable') -and $publishResult.Unfixable
            return @{ Success = $false; Reason = "Failed to publish"; Unfixable = $isUnfixable }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-SafeOutput -Message $errorMessage -Prefix "::debug::Failed to republish release for $TagName : "
        return @{ Success = $false; Reason = $errorMessage; Unfixable = $false }
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
            return @{ Success = $false; RequiresManualFix = $false; ErrorOutput = "No repo info available" }
        }
        
        $headers = Get-ApiHeader -Token $State.Token
        
        # Try to update the ref first (in case it exists)
        $updateUrl = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/git/$RefName"
        $body = @{
            sha = $Sha
            force = $Force
        } | ConvertTo-Json
        
        try {
            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                $null = Invoke-WebRequestWrapper -Uri $updateUrl -Headers $headers -Method Patch -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
            } else {
                $null = Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method Patch -Body $body -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
            }
            return @{ Success = $true; RequiresManualFix = $false }
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
                    $null = Invoke-WebRequestWrapper -Uri $createUrl -Headers $headers -Method Post -Body $createBody -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
                } else {
                    $null = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method Post -Body $createBody -ContentType "application/json" -ErrorAction Stop -TimeoutSec 10
                }
                return @{ Success = $true; RequiresManualFix = $false }
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
            $gitRoot = Join-Path (Get-Location) ".git"
            $gitAvailable = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
            $hasGitRepo = Test-Path $gitRoot

            if ($env:GITHUB_API_ALLOW_GIT_FALLBACK -ne 'true') {
                Write-Host "::debug::REST API returned 403 for $RefName, git fallback disabled"
                return @{ Success = $false; RequiresManualFix = $true; ErrorOutput = "REST API returned 403 for $RefName and git fallback is disabled." }
            }

            if (-not $gitAvailable -or -not $hasGitRepo) {
                Write-Host "::debug::REST API returned 403 for $RefName, git fallback unavailable"
                return @{ Success = $false; RequiresManualFix = $true; ErrorOutput = "REST API returned 403 for $RefName and git fallback is unavailable." }
            }

            Write-Host "::debug::REST API returned 403 for $RefName, falling back to git push"
            
            # Fall back to using git push since REST API doesn't have permission
            # Extract tag/branch name from RefName (e.g., "refs/tags/v1.0.0" -> "v1.0.0")
            
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
                    return @{ Success = $true; RequiresManualFix = $false }
                } else {
                    # Check if error is due to workflows permission
                    $outputStr = [string]$output
                    $requiresWorkflowsPermission = $outputStr -match "refusing to allow a GitHub App to create or update workflow" -and $outputStr -match "without `[`"'`]?workflows`[`"'`]? permission"
                    
                    Write-Host "::error::Git push failed for $RefName"
                    # Log the detailed error at debug level to avoid cluttering error output
                    Write-SafeOutput -Message $outputStr -Prefix "::debug::Git push error details: "
                    
                    return @{ 
                        Success = $false
                        RequiresManualFix = $requiresWorkflowsPermission
                        ErrorOutput = $outputStr
                    }
                }
            }
            catch {
                Write-Host "::error::Failed to push $RefName via git"
                Write-SafeOutput -Message ([string]$_) -Prefix "::debug::Git error details: "
                return @{ Success = $false; RequiresManualFix = $false; ErrorOutput = [string]$_ }
            }
        } else {
            Write-SafeOutput -Message $errorMessage -Prefix "::debug::Failed to create/update ref $RefName : "
        }
        
        return @{ Success = $false; RequiresManualFix = $false; ErrorOutput = $errorMessage }
    }
}

function Get-GitHubFileContents {
    <#
    .SYNOPSIS
    Fetches the contents of a file from a GitHub repository.
    
    .PARAMETER State
    The RepositoryState object containing API configuration.
    
    .PARAMETER Path
    The path to the file in the repository (e.g., "action.yaml" or "README.md").
    
    .PARAMETER Ref
    Optional. The commit, branch, or tag to get the file from. Defaults to the default branch.
    
    .OUTPUTS
    Returns the file content as a string, or $null if the file doesn't exist.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        
        [Parameter(Mandatory)]
        [string]$Path,
        
        [string]$Ref
    )
    
    try {
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return $null
        }
        
        $headers = Get-ApiHeader -Token $State.Token
        $url = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/contents/$Path"
        
        if ($Ref) {
            $url += "?ref=$Ref"
        }
        
        $response = Invoke-WithRetry -OperationDescription "Fetch file $Path" -ScriptBlock {
            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
            } else {
                Invoke-WebRequest -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
            }
        }
        
        $content = $response.Content | ConvertFrom-Json
        
        # GitHub returns base64-encoded content for files
        if ($content.encoding -eq 'base64' -and $content.content) {
            $decodedContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($content.content))
            return $decodedContent
        }
        
        return $null
    }
    catch {
        $statusCode = $null
        if ($_.Exception -and $_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        
        if ($statusCode -eq 404) {
            Write-Host "::debug::File $Path not found in repository"
            return $null
        }
        
        Throw-GitHubApiFailure -Operation "fetching file $Path" -ErrorRecord $_
    }
}

function Test-GitHubFileExists {
    <#
    .SYNOPSIS
    Checks if a file exists in a GitHub repository without fetching its contents.
    
    .PARAMETER State
    The RepositoryState object containing API configuration.
    
    .PARAMETER Path
    The path to the file in the repository.
    
    .PARAMETER Ref
    Optional. The commit, branch, or tag to check. Defaults to the default branch.
    
    .OUTPUTS
    Returns $true if the file exists, $false otherwise.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        
        [Parameter(Mandatory)]
        [string]$Path,
        
        [string]$Ref
    )
    
    try {
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return $false
        }
        
        $headers = Get-ApiHeader -Token $State.Token
        $url = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/contents/$Path"
        
        if ($Ref) {
            $url += "?ref=$Ref"
        }
        
        # Use HEAD request to check existence without fetching content
        $response = Invoke-WithRetry -OperationDescription "Check file $Path exists" -ScriptBlock {
            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Head -ErrorAction Stop -TimeoutSec 10
            } else {
                Invoke-WebRequest -Uri $url -Headers $headers -Method Head -ErrorAction Stop -TimeoutSec 10
            }
        }
        
        return $response.StatusCode -eq 200
    }
    catch {
        $statusCode = $null
        if ($_.Exception -and $_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        
        if ($statusCode -eq 404) {
            return $false
        }
        
        Write-Host "::debug::Error checking file $Path exists: $_"
        return $false
    }
}

function Get-GitHubDirectoryContents {
    <#
    .SYNOPSIS
    Lists the contents of a directory in a GitHub repository.
    
    .DESCRIPTION
    Uses the GitHub Contents API to list files and subdirectories in a given path.
    This is more efficient than checking individual files when you need to find
    one of several possible filenames (e.g., README.md with different cases).
    
    .PARAMETER State
    The RepositoryState object containing API configuration.
    
    .PARAMETER Path
    The directory path in the repository. Use empty string or "/" for root.
    
    .PARAMETER Ref
    Optional. The commit, branch, or tag to list from. Defaults to the default branch.
    
    .OUTPUTS
    Returns an array of objects with Name, Path, Type (file/dir), and Sha properties.
    Returns empty array if the directory doesn't exist.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        
        [string]$Path = "",
        
        [string]$Ref
    )
    
    try {
        $repoInfo = Get-GitHubRepoInfo -State $State
        if (-not $repoInfo) {
            return @()
        }
        
        $headers = Get-ApiHeader -Token $State.Token
        $url = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/contents"
        
        if ($Path -and $Path -ne "/" -and $Path -ne ".") {
            $url += "/$Path"
        }
        
        if ($Ref) {
            $url += "?ref=$Ref"
        }
        
        $response = Invoke-WithRetry -OperationDescription "List directory $Path" -ScriptBlock {
            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
            } else {
                Invoke-WebRequest -Uri $url -Headers $headers -Method Get -ErrorAction Stop -TimeoutSec 10
            }
        }
        
        $content = $response.Content | ConvertFrom-Json
        
        # Ensure we have an array (single file returns object, directory returns array)
        if ($content -isnot [array]) {
            # Single item returned - might be a file, not a directory
            if ($content.type -eq 'file') {
                Write-Host "::debug::Path $Path is a file, not a directory"
                return @()
            }
            $content = @($content)
        }
        
        # Map to simplified objects
        $results = $content | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.name
                Path = $_.path
                Type = $_.type
                Sha  = $_.sha
            }
        }
        
        return $results
    }
    catch {
        $statusCode = $null
        if ($_.Exception -and $_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        
        if ($statusCode -eq 404) {
            Write-Host "::debug::Directory $Path not found in repository"
            return @()
        }
        
        Write-Host "::debug::Error listing directory $Path : $_"
        return @()
    }
}

function Remove-GitHubRef
{
    <#
    .SYNOPSIS
    Deletes a git reference (tag or branch) via the GitHub REST API.
    
    .PARAMETER State
    The RepositoryState object containing API configuration.
    
    .PARAMETER RefName
    The full reference name (e.g., "refs/tags/v1.0.0" or "refs/heads/main").
    
    .OUTPUTS
    Returns $true if deletion succeeded, $false otherwise.
    #>
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
        
        $headers = Get-ApiHeader -Token $State.Token
        $url = "$($State.ApiUrl)/repos/$($repoInfo.Owner)/$($repoInfo.Repo)/git/$RefName"
        
        Invoke-WithRetry -OperationDescription "Delete ref $RefName" -ScriptBlock {
            if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
                $null = Invoke-WebRequestWrapper -Uri $url -Headers $headers -Method Delete -ErrorAction Stop -TimeoutSec 10
            } else {
                $null = Invoke-RestMethod -Uri $url -Headers $headers -Method Delete -ErrorAction Stop -TimeoutSec 10
            }
        }
        
        return $true
    }
    catch {
        Write-SafeOutput -Message ([string]$_) -Prefix "::debug::Failed to delete ref $RefName : "
        return $false
    }
}

