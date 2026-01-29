$global:returnCode = 0

# Get GitHub context information first
$script:apiUrl = "https://api.github.com"
$script:serverUrl = "https://github.com"
$script:token = ""
$script:repoOwner = $null
$script:repoName = $null

if ($env:GITHUB_CONTEXT) {
    try {
        $githubContext = $env:GITHUB_CONTEXT | ConvertFrom-Json
        
        # Use specific fields from GitHub context
        $script:apiUrl = $githubContext.api_url ?? "https://api.github.com"
        $script:serverUrl = $githubContext.server_url ?? "https://github.com"
        $script:token = $githubContext.token ?? ""
        $script:repoOwner = $githubContext.repository_owner
        
        # Get repo name from repository field (format: owner/repo)
        if ($githubContext.repository) {
            $script:repoName = ($githubContext.repository -split "/")[1]
        }
    }
    catch {
        # Fall back to environment variables if JSON parsing fails
        $script:apiUrl = $env:GITHUB_API_URL ?? "https://api.github.com"
        $script:token = $env:GITHUB_TOKEN ?? ""
        
        if ($env:GITHUB_REPOSITORY -and $env:GITHUB_REPOSITORY -match "^([^/]+)/(.+)$") {
            $script:repoOwner = $matches[1]
            $script:repoName = $matches[2]
        }
    }
}
else {
    # Fall back to environment variables
    $script:apiUrl = $env:GITHUB_API_URL ?? "https://api.github.com"
    $script:token = $env:GITHUB_TOKEN ?? ""
    
    if ($env:GITHUB_REPOSITORY -and $env:GITHUB_REPOSITORY -match "^([^/]+)/(.+)$") {
        $script:repoOwner = $matches[1]
        $script:repoName = $matches[2]
    }
}

# If still not found, fall back to git remote
if (-not $script:repoOwner -or -not $script:repoName) {
    $remoteUrl = & git config --get remote.origin.url 2>$null
    if ($remoteUrl) {
        # Parse owner/repo from various Git URL formats
        # SSH: git@hostname:owner/repo.git
        # HTTPS: https://hostname/owner/repo.git
        # Handle both github.com and GitHub Enterprise Server
        if ($remoteUrl -match '(?:https?://|git@)([^/:]+)[:/]([^/]+)/([^/]+?)(\.git)?$') {
            $hostname = $matches[1]
            $script:repoOwner = $matches[2]
            $script:repoName = $matches[3]
            
            # Update server URL based on the parsed hostname
            if ($hostname -ne "github.com") {
                $script:serverUrl = "https://$hostname"
                # For GHE, API URL is typically https://hostname/api/v3
                if ($script:apiUrl -eq "https://api.github.com") {
                    $script:apiUrl = "https://$hostname/api/v3"
                }
            }
        }
    }
}

# Read inputs from JSON environment variable
if (-not $env:inputs) {
    Write-Host "::error::inputs environment variable is not set"
    exit 1
}

try {
    $inputs = $env:inputs | ConvertFrom-Json
    
    # Helper function to normalize check input values (accept boolean or string)
    function Normalize-CheckInput {
        param(
            [string]$value,
            [string]$default
        )
        
        $normalized = ($value ?? $default).Trim().ToLower()
        
        # Map boolean values to error/none
        if ($normalized -eq "true") {
            return "error"
        } elseif ($normalized -eq "false") {
            return "none"
        }
        
        return $normalized
    }
    
    # Parse inputs with defaults
    $script:token = $inputs.token ?? $script:token
    $checkMinorVersion = Normalize-CheckInput -value (($inputs.'check-minor-version' ?? "true") -as [string]) -default "error"
    $checkReleases = Normalize-CheckInput -value (($inputs.'check-releases' ?? "error") -as [string]) -default "error"
    $checkReleaseImmutability = Normalize-CheckInput -value (($inputs.'check-release-immutability' ?? "error") -as [string]) -default "error"
    $ignorePreviewReleases = (($inputs.'ignore-preview-releases' ?? "true") -as [string]).Trim() -eq "true"
    $floatingVersionsUse = (($inputs.'floating-versions-use' ?? "tags") -as [string]).Trim().ToLower()
    $autoFix = (($inputs.'auto-fix' ?? "false") -as [string]).Trim() -eq "true"
}
catch {
    Write-Host "::error::Failed to parse inputs JSON"
    exit 1
}

# Debug: Show parsed input values
Write-Host "::debug::=== Parsed Input Values ==="
Write-Host "::debug::auto-fix: $autoFix"
Write-Host "::debug::check-minor-version: $checkMinorVersion"
Write-Host "::debug::check-releases: $checkReleases"
Write-Host "::debug::check-release-immutability: $checkReleaseImmutability"
Write-Host "::debug::ignore-preview-releases: $ignorePreviewReleases"
Write-Host "::debug::floating-versions-use: $floatingVersionsUse"

# Validate inputs
if ($checkMinorVersion -notin @("error", "warning", "none")) {
    $errorMessage = "::error title=Invalid configuration::check-minor-version must be 'error', 'warning', 'none', 'true', or 'false', got '$checkMinorVersion'"
    Write-Output $errorMessage
    exit 1
}

if ($checkReleases -notin @("error", "warning", "none")) {
    $errorMessage = "::error title=Invalid configuration::check-releases must be 'error', 'warning', 'none', 'true', or 'false', got '$checkReleases'"
    Write-Output $errorMessage
    exit 1
}

if ($checkReleaseImmutability -notin @("error", "warning", "none")) {
    $errorMessage = "::error title=Invalid configuration::check-release-immutability must be 'error', 'warning', 'none', 'true', or 'false', got '$checkReleaseImmutability'"
    Write-Output $errorMessage
    exit 1
}

if ($floatingVersionsUse -notin @("tags", "branches")) {
    $errorMessage = "::error title=Invalid configuration::floating-versions-use must be either 'tags' or 'branches', got '$floatingVersionsUse'"
    Write-Output $errorMessage
    exit 1
}

$useBranches = $floatingVersionsUse -eq "branches"

# Debug output
Write-Host "::debug::Repository: $script:repoOwner/$script:repoName"
Write-Host "::debug::API URL: $script:apiUrl"
Write-Host "::debug::Server URL: $script:serverUrl"
Write-Host "::debug::Token available: $(if ($script:token) { 'Yes' } else { 'No' })"
Write-Host "::debug::Check releases: $checkReleases"
Write-Host "::debug::Check release immutability: $checkReleaseImmutability"
Write-Host "::debug::Floating versions use: $floatingVersionsUse"

# Validate git repository configuration
Write-Host "::debug::Validating repository configuration..."

# Check if repository is a shallow clone
if (Test-Path ".git/shallow") {
    $errorMessage = "::error title=Shallow clone detected::Repository is a shallow clone (fetch-depth: 1). This action requires full git history. Please configure your checkout action with 'fetch-depth: 0'.%0A%0AExample:%0A  - uses: actions/checkout@v4%0A    with:%0A      fetch-depth: 0%0A      fetch-tags: true"
    Write-Output $errorMessage
    $global:returnCode = 1
    exit 1
}

# Check if tags were fetched
$allTags = & git tag -l 2>$null
if (-not $allTags -or $allTags.Count -eq 0) {
    $warningMessage = "::warning title=No tags found::No git tags found in repository. This could mean:%0A  1. The repository has no tags yet (expected for new repositories)%0A  2. Tags were not fetched (fetch-tags: false)%0A%0AIf you expect tags to exist, please configure your checkout action with 'fetch-tags: true'.%0A%0AExample:%0A  - uses: actions/checkout@v4%0A    with:%0A      fetch-depth: 0%0A      fetch-tags: true"
    Write-Output $warningMessage
}

# Configure git credentials for auto-fix mode if needed
if ($autoFix) {
    Write-Host "::debug::Auto-fix mode enabled, configuring git credentials..."
    
    if (-not $script:token) {
        $errorMessage = "::error title=Auto-fix requires token::Auto-fix mode is enabled but no GitHub token is available. Please provide a token via the 'token' input or ensure GITHUB_TOKEN is available.%0A%0AExample:%0A  - uses: jessehouwing/actions-semver-checker@v2%0A    with:%0A      auto-fix: true%0A      token: `${{ secrets.GITHUB_TOKEN }}"
        Write-Output $errorMessage
        $global:returnCode = 1
        exit 1
    }
    
    # Configure git to use token for authentication
    # This handles cases where checkout action used persist-credentials: false
    try {
        # Configure credential helper to use the token
        & git config --local credential.helper "" 2>$null
        & git config --local credential.helper "!f() { echo username=x-access-token; echo password=$script:token; }; f" 2>$null
        
        # Configure git user identity for GitHub Actions bot
        & git config --local user.name "github-actions[bot]" 2>$null
        & git config --local user.email "github-actions[bot]@users.noreply.github.com" 2>$null
        
        # Also set up the URL rewrite to use HTTPS with token
        $remoteUrl = & git config --get remote.origin.url 2>$null
        if ($remoteUrl -and $remoteUrl -match '^https://') {
            Write-Host "::debug::Configured git credential helper for HTTPS authentication"
        }
        elseif ($remoteUrl -and $remoteUrl -match '^git@') {
            # Wrap remote URL in stop-commands to prevent workflow command injection
            Write-SafeOutput -Message "$remoteUrl). Auto-fix may fail if SSH credentials are not available. Consider using HTTPS remote with checkout action." -Prefix "::warning title=SSH remote detected::Remote URL uses SSH ("
        }
    }
    catch {
        # Wrap exception message in stop-commands to prevent workflow command injection
        Write-SafeOutput -Message ([string]$_) -Prefix "::warning title=Git configuration warning::Could not configure git credentials: "
    }
}

$tags = & git tag -l v* | Where-Object{ return ($_ -match "^v\d+(\.\d+){0,2}$") }
Write-Host "::debug::Found $($tags.Count) version tags: $($tags -join ', ')"

$branches = & git branch --list --quiet --remotes | Where-Object{ return ($_.Trim() -match "^origin/(v\d+(\.\d+){0,2}(-.*)?)$") } | ForEach-Object{ $_.Trim().Replace("origin/", "")}

$tagVersions = @()
$branchVersions = @()

$suggestedCommands = @()

# Auto-fix tracking
$script:fixedIssues = 0
$script:failedFixes = 0
$script:unfixableIssues = 0

function Write-SafeOutput
{
    param(
        [string]$Message,
        [string]$Prefix = ""
    )
    
    # Use stop-commands to prevent workflow command injection
    # https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#stopping-and-starting-workflow-commands
    # The prefix (containing workflow commands) is written BEFORE stop-commands
    # so GitHub Actions can interpret it, but the untrusted message is wrapped
    # in stop-commands to neutralize any malicious workflow commands it contains
    
    if ($Prefix) {
        Write-Host -NoNewline $Prefix
    }
    
    $stopMarker = New-Guid
    Write-Host "::stop-commands::$stopMarker"
    Write-Host $Message
    Write-Host "::$stopMarker::"
}

function Invoke-AutoFix
{
    param(
        [string]$Description,
        [string]$Command,
        [scriptblock]$ApiAction = $null
    )
    
    if (-not $autoFix)
    {
        return $false  # Not in auto-fix mode
    }
    
    Write-Host "Auto-fix: $Description"
    
    try
    {
        # If an API action is provided, use it instead of the command
        if ($ApiAction) {
            Write-Host "::debug::Executing via REST API"
            $success = & $ApiAction
            
            if ($success) {
                Write-Host "✓ Success: $Description"
                return $true
            }
            else {
                Write-Host "✗ Failed: $Description"
                Write-Host "::error::REST API call failed for: $Description"
                return $false
            }
        }
        else {
            # Fallback to executing the command (for non-git operations like gh CLI)
            Write-Host "Executing: $Command"
            
            # Reset LASTEXITCODE to ensure we're not seeing a stale value
            $global:LASTEXITCODE = 0
            
            # Execute the command and capture both stdout and stderr
            # The 2>&1 redirects stderr to stdout, ensuring we capture all output
            $commandOutput = Invoke-Expression $Command 2>&1
            
            if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -eq 0)
            {
                Write-Host "✓ Success: $Description"
                # Log command output as debug using GitHub Actions workflow command
                # Wrap output in stop-commands to prevent workflow command injection
                if ($commandOutput) {
                    Write-SafeOutput -Message ([string]$commandOutput) -Prefix "::debug::Command succeeded with output: "
                }
                return $true
            }
            else
            {
                Write-Host "✗ Failed: $Description (exit code: $LASTEXITCODE)"
                # Log error output prominently using GitHub Actions error command
                # Wrap output in stop-commands to prevent workflow command injection
                if ($commandOutput) {
                    Write-SafeOutput -Message ([string]$commandOutput) -Prefix "::error::Command failed: "
                }
                else {
                    # If no output captured, still log that the command failed
                    Write-Host "::error::Command failed with no output (exit code: $LASTEXITCODE)"
                }
                return $false
            }
        }
    }
    catch
    {
        Write-Host "✗ Failed: $Description"
        # Wrap exception message in stop-commands to prevent workflow command injection
        Write-SafeOutput -Message ([string]$_) -Prefix "::error::Exception: "
        return $false
    }
}

function write-actions-error
{
    param(
        [string] $message
    )

    Write-Output $message
    $global:returnCode = 1
}

function write-actions-warning
{
    param(
        [string] $message
    )

    Write-Output $message
}

function write-actions-message
{
    param(
        [string] $message,
        [string] $severity = "error"  # Can be "error", "warning", or "none"
    )

    if ($severity -eq "error") {
        write-actions-error $message
    } elseif ($severity -eq "warning") {
        write-actions-warning $message
    }
    # If "none", don't write anything
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

function ConvertTo-Version
{
    param(
        [string] $value
    )

    $dots = $value.Split(".").Count - 1

    switch ($dots)
    {
        0
        {
            return [Version]"$value.0.0"
        }
        1
        {
            return [Version]"$value.0"
        }
        2
        {
            return [Version]$value
        }
    }
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

function Get-ImmutableReleaseRemediationCommands
{
    param(
        [string]$TagName
    )
    
    $commands = @()
    
    # The tag is already used by an immutable release
    # The only solution is to delete the release and create a new version
    # This function expects semantic version tags in the format vX.Y.Z
    if ($TagName -match "^v(\d+)\.(\d+)\.(\d+)$") {
        $major = $matches[1]
        $minor = $matches[2]
        $patch = [int]$matches[3] + 1
        $nextVersion = "v$major.$minor.$patch"
        
        $commands += "# Delete the immutable release (if possible) and create a new version:"
        $commands += "gh release delete $TagName --yes"
        $commands += "git tag -d $TagName"
        $commands += "git push origin :refs/tags/$TagName"
        $commands += "# Create new patch version $nextVersion with updated changes:"
        $commands += "git tag $nextVersion"
        $commands += "git push origin $nextVersion"
        $commands += "gh release create $nextVersion --draft --title `"$nextVersion`" --notes `"Release $nextVersion`""
        $commands += "gh release edit $nextVersion --draft=false"
    }
    else {
        # Tag doesn't match expected vX.Y.Z format
        $commands += "# Manual remediation required for tag: $TagName"
        $commands += "# The tag is used by an immutable release. You must delete the release and tag, then create a new version."
        $commands += "gh release delete $TagName --yes"
        $commands += "git tag -d $TagName"
        $commands += "git push origin :refs/tags/$TagName"
    }
    
    return $commands
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

# Get repository info for URLs
$script:repoInfo = Get-GitHubRepoInfo

# Check permissions if auto-fix is enabled
if ($autoFix -and $script:repoInfo) {
    Write-Host "::debug::Checking GitHub token permissions..."
    
    # For token permission checks, we need to check if the token has appropriate scopes
    # GitHub Actions tokens typically have contents: write by default when permissions are not explicitly set
    # However, actions: write requires explicit permission in the workflow
    
    # Check if GITHUB_TOKEN has necessary permissions by examining the context
    # The GITHUB_TOKEN permissions are set at the workflow/job level
    # We'll provide a helpful error message if auto-fix operations fail
    
    # Note: GitHub API doesn't expose token permissions directly via a simple endpoint
    # The permissions are workflow-level configuration, not token-level metadata
    # We'll validate this at the workflow configuration level in documentation
    # and provide clear error messages when operations fail due to insufficient permissions
    
    Write-Host "::debug::Auto-fix is enabled. Ensure your workflow has 'contents: write' permission."
    Write-Host "::debug::If pushing changes to workflow files, 'actions: write' permission is also required."
    Write-Host "::debug::Example workflow permissions:"
    Write-Host "::debug::  permissions:"
    Write-Host "::debug::    contents: write"
    Write-Host "::debug::    actions: write"
}

# Get GitHub releases if check is enabled
$releases = @()
$releaseMap = @{}
if (($checkReleases -ne "none" -or $checkReleaseImmutability -ne "none" -or $ignorePreviewReleases) -and $script:repoInfo)
{
    $releases = Get-GitHubReleases
    # Create a map for quick lookup
    foreach ($release in $releases)
    {
        $releaseMap[$release.tagName] = $release
    }
}

foreach ($tag in $tags)
{
    $isPrerelease = $false
    if ($ignorePreviewReleases -and $releaseMap.ContainsKey($tag))
    {
        $isPrerelease = $releaseMap[$tag].isPrerelease
    }
    
    # Determine if this is a patch version (vX.Y.Z) or a floating version (vX or vX.Y)
    # Strip any prerelease suffix (e.g., -beta) before counting parts
    $versionWithoutPrefix = $tag.Substring(1)
    $versionCore = $versionWithoutPrefix -split '-' | Select-Object -First 1
    $versionParts = $versionCore -split '\.'
    $isPatchVersion = $versionParts.Count -eq 3
    $isMinorVersion = $versionParts.Count -eq 2
    $isMajorVersion = $versionParts.Count -eq 1
    
    $tagVersions += @{
        version = $tag
        ref = "refs/tags/$tag"
        sha = & git rev-list -n 1 $tag
        semver = ConvertTo-Version $tag.Substring(1)
        isPrerelease = $isPrerelease
        isPatchVersion = $isPatchVersion
        isMinorVersion = $isMinorVersion
        isMajorVersion = $isMajorVersion
    }
    
    Write-Host "::debug::Parsed tag $tag - isPatch:$isPatchVersion isMinor:$isMinorVersion isMajor:$isMajorVersion parts:$($versionParts.Count)"
}

$latest = & git tag -l latest
$latestBranch = $null
if ($latest)
{
    $latest = @{
        version = "latest"
        ref = "refs/tags/latest"
        sha = & git rev-list -n 1 latest
        semver = $null
    }
}

# Also check for latest branch (regardless of floating-versions-use setting)
# This allows us to warn when latest exists as wrong type
$latestBranchExists = & git branch --list --quiet --remotes origin/latest
if ($latestBranchExists) {
    $latestBranch = @{
        version = "latest"
        ref = "refs/remotes/origin/latest"
        sha = & git rev-parse refs/remotes/origin/latest
        semver = $null
    }
}

foreach ($branch in $branches)
{
    # Determine if this is a patch version (vX.Y.Z) or a floating version (vX or vX.Y)
    # Strip any prerelease suffix (e.g., -beta) before counting parts
    $versionWithoutPrefix = $branch.Substring(1)
    $versionCore = $versionWithoutPrefix -split '-' | Select-Object -First 1
    $versionParts = $versionCore -split '\.'
    $isPatchVersion = $versionParts.Count -eq 3
    $isMinorVersion = $versionParts.Count -eq 2
    $isMajorVersion = $versionParts.Count -eq 1
    
    $branchVersions += @{
        version = $branch
        ref = "refs/remotes/origin/$branch"
        sha = & git rev-parse refs/remotes/origin/$branch
        semver = ConvertTo-Version $branch.Substring(1)
        isPrerelease = $false  # Branches are not considered prereleases
        isPatchVersion = $isPatchVersion
        isMinorVersion = $isMinorVersion
        isMajorVersion = $isMajorVersion
    }
}

foreach ($tagVersion in $tagVersions)
{
    $branchVersion = $branchVersions | Where-Object{ $_.version -eq $tagVersion.version } | Select-Object -First 1

    if ($branchVersion)
    {
        $message = "title=Ambiguous version: $($tagVersion.version)::Exists as both tag ($($tagVersion.sha)) and branch ($($branchVersion.sha))"
        
        # Determine which reference to keep based on floating-versions-use setting
        $keepBranch = ($useBranches -eq $true)
        
        if ($branchVersion.sha -eq $tagVersion.sha)
        {
            # Same SHA - can auto-fix by removing the non-preferred reference
            if ($keepBranch)
            {
                # Keep branch, remove tag
                $fixCmd = "git push origin :refs/tags/$($tagVersion.version)"
                $fixDescription = "Remove ambiguous tag for $($tagVersion.version) (keeping branch)"
                $apiAction = { Remove-GitHubRef -RefName "refs/tags/$($tagVersion.version)" }
            }
            else
            {
                # Keep tag, remove branch (default)
                $fixCmd = "git push origin :refs/heads/$($tagVersion.version)"
                $fixDescription = "Remove ambiguous branch for $($tagVersion.version) (keeping tag)"
                $apiAction = { Remove-GitHubRef -RefName "refs/heads/$($tagVersion.version)" }
            }
            
            $fixed = Invoke-AutoFix -Description $fixDescription -Command $fixCmd -ApiAction $apiAction
            
            if ($fixed)
            {
                $script:fixedIssues++
            }
            else
            {
                if ($autoFix) { $script:failedFixes++ }
                write-actions-warning "::warning $message"
                $suggestedCommands += $fixCmd
            }
        }
        else
        {
            # Different SHAs - can auto-fix by removing the non-preferred reference
            if ($keepBranch)
            {
                # Keep branch, remove tag
                $fixCmd = "git push origin :refs/tags/$($tagVersion.version)"
                $fixDescription = "Remove ambiguous tag for $($tagVersion.version) (keeping branch at $($branchVersion.sha))"
                $apiAction = { Remove-GitHubRef -RefName "refs/tags/$($tagVersion.version)" }
            }
            else
            {
                # Keep tag, remove branch (default)
                $fixCmd = "git push origin :refs/heads/$($tagVersion.version)"
                $fixDescription = "Remove ambiguous branch for $($tagVersion.version) (keeping tag at $($tagVersion.sha))"
                $apiAction = { Remove-GitHubRef -RefName "refs/heads/$($tagVersion.version)" }
            }
            
            $fixed = Invoke-AutoFix -Description $fixDescription -Command $fixCmd -ApiAction $apiAction
            
            if ($fixed)
            {
                $script:fixedIssues++
            }
            else
            {
                if ($autoFix) { $script:failedFixes++ }
                write-actions-error "::error $message"
                $suggestedCommands += $fixCmd
            }
        }
    }
}

# Validate that floating versions (vX or vX.Y) have corresponding patch versions
$allVersions = $tagVersions + $branchVersions
Write-Host "::debug::Validating floating versions. Total versions: $($allVersions.Count) (tags: $($tagVersions.Count), branches: $($branchVersions.Count))"

foreach ($version in $allVersions)
{
    Write-Host "::debug::Checking version $($version.version) - isMajor:$($version.isMajorVersion) isMinor:$($version.isMinorVersion) isPatch:$($version.isPatchVersion)"
    
    if ($version.isMajorVersion)
    {
        # Check if any patch versions exist for this major version
        $patchVersionsExist = $allVersions | Where-Object { 
            $_.isPatchVersion -and $_.semver.major -eq $version.semver.major 
        }
        
        Write-Host "::debug::Major version $($version.version) - found $($patchVersionsExist.Count) patch versions"
        
        # Note: Missing patch versions will be detected and auto-fixed in the version consistency checks below
        # We don't need to report errors here to avoid redundant error messages
    }
    elseif ($version.isMinorVersion)
    {
        # Check if any patch versions exist for this minor version
        $patchVersionsExist = $allVersions | Where-Object { 
            $_.isPatchVersion -and 
            $_.semver.major -eq $version.semver.major -and 
            $_.semver.minor -eq $version.semver.minor 
        }
        
        Write-Host "::debug::Minor version $($version.version) - found $($patchVersionsExist.Count) patch versions"
        
        # Note: Missing patch versions will be detected and auto-fixed in the version consistency checks below
        # We don't need to report errors here to avoid redundant error messages
    }
}

# Check that every patch version (vX.Y.Z) has a corresponding release
if ($checkReleases -ne "none")
{
    $releaseTagNames = $releases | ForEach-Object { $_.tagName }
    
    foreach ($tagVersion in $tagVersions)
    {
        # Only check patch versions (vX.Y.Z format with 3 parts) - floating versions don't need releases
        if ($tagVersion.isPatchVersion)
        {
            $hasRelease = $releaseTagNames -contains $tagVersion.version
            
            if (-not $hasRelease)
            {
                $messageType = if ($checkReleases -eq "error") { "error" } else { "warning" }
                $messageFunc = if ($checkReleases -eq "error") { "write-actions-error" } else { "write-actions-warning" }
                & $messageFunc "::$messageType title=Missing release::Version $($tagVersion.version) does not have a GitHub Release"
                
                # Try to auto-fix by creating a draft release
                if ($autoFix)
                {
                    $fixDescription = "Create draft release for $($tagVersion.version)"
                    Write-Host "Auto-fix: $fixDescription"
                    $releaseId = New-GitHubDraftRelease -TagName $tagVersion.version
                    
                    if ($releaseId)
                    {
                        Write-Host "✓ Success: $fixDescription"
                        $script:fixedIssues++
                        
                        # Now try to publish the draft release
                        $publishDescription = "Publish draft release for $($tagVersion.version)"
                        Write-Host "Auto-fix: $publishDescription"
                        $publishResult = Publish-GitHubRelease -TagName $tagVersion.version -ReleaseId $releaseId
                        
                        if ($publishResult.Success)
                        {
                            Write-Host "✓ Success: $publishDescription"
                            $script:fixedIssues++
                        }
                        elseif ($publishResult.Unfixable)
                        {
                            Write-Host "✗ Unfixable: $publishDescription (tag used by immutable release)"
                            $script:unfixableIssues++
                            
                            # Use helper function to get remediation commands
                            $remediationCommands = Get-ImmutableReleaseRemediationCommands -TagName $tagVersion.version
                            $suggestedCommands += $remediationCommands
                        }
                        else
                        {
                            Write-Host "✗ Failed: $publishDescription"
                            $script:failedFixes++
                            
                            # Log message about manual publishing requirement
                            $editUrl = "$($script:repoInfo.Url)/releases/edit/$($tagVersion.version)"
                            Write-Host "::warning title=Manual action required::The draft release $($tagVersion.version) must be published manually. Edit and publish at: $editUrl"
                            
                            if ($script:repoInfo) {
                                $suggestedCommands += "gh release edit $($tagVersion.version) --draft=false  # Or edit at: $($script:repoInfo.Url)/releases/edit/$($tagVersion.version)"
                            } else {
                                $suggestedCommands += "gh release edit $($tagVersion.version) --draft=false"
                            }
                        }
                    }
                    else
                    {
                        Write-Host "✗ Failed: $fixDescription"
                        $script:failedFixes++
                        $suggestedCommands += "gh release create $($tagVersion.version) --draft --title `"$($tagVersion.version)`" --notes `"Release $($tagVersion.version)`""
                        if ($script:repoInfo) {
                            $suggestedCommands += "gh release edit $($tagVersion.version) --draft=false  # Or edit at: $($script:repoInfo.Url)/releases/edit/$($tagVersion.version)"
                        } else {
                            $suggestedCommands += "gh release edit $($tagVersion.version) --draft=false"
                        }
                    }
                }
                else
                {
                    $script:unfixableIssues++
                    $suggestedCommands += "gh release create $($tagVersion.version) --draft --title `"$($tagVersion.version)`" --notes `"Release $($tagVersion.version)`""
                    if ($script:repoInfo) {
                        $suggestedCommands += "gh release edit $($tagVersion.version) --draft=false  # Or edit at: $($script:repoInfo.Url)/releases/edit/$($tagVersion.version)"
                    } else {
                        $suggestedCommands += "gh release edit $($tagVersion.version) --draft=false"
                    }
                }
            }
        }
    }
}

# Check that releases are immutable (not draft, which allows tag changes)
# Use GitHub's immutable field to check if a release is truly immutable
if ($checkReleaseImmutability -ne "none" -and $releases.Count -gt 0)
{
    foreach ($release in $releases)
    {
        # Only check releases for patch versions (vX.Y.Z format)
        if ($release.tagName -match "^v\d+\.\d+\.\d+$")
        {
            if ($release.isDraft)
            {
                $messageType = if ($checkReleaseImmutability -eq "error") { "error" } else { "warning" }
                $messageFunc = if ($checkReleaseImmutability -eq "error") { "write-actions-error" } else { "write-actions-warning" }
                & $messageFunc "::$messageType title=Draft release::Release $($release.tagName) is still in draft status, making it mutable. Publish the release to make it immutable."
                
                # Try to auto-fix by publishing the draft release
                if ($autoFix)
                {
                    $publishDescription = "Publish draft release for $($release.tagName)"
                    Write-Host "Auto-fix: $publishDescription"
                    $publishResult = Publish-GitHubRelease -TagName $release.tagName -ReleaseId $release.id
                    
                    if ($publishResult.Success)
                    {
                        Write-Host "✓ Success: $publishDescription"
                        $script:fixedIssues++
                    }
                    elseif ($publishResult.Unfixable)
                    {
                        Write-Host "✗ Unfixable: $publishDescription (tag used by immutable release)"
                        $script:unfixableIssues++
                        
                        # Use helper function to get remediation commands
                        $remediationCommands = Get-ImmutableReleaseRemediationCommands -TagName $release.tagName
                        $suggestedCommands += $remediationCommands
                    }
                    else
                    {
                        Write-Host "✗ Failed: $publishDescription"
                        $script:failedFixes++
                        
                        if ($script:repoInfo) {
                            $suggestedCommands += "gh release edit $($release.tagName) --draft=false  # Or edit at: $($script:repoInfo.Url)/releases/edit/$($release.tagName)"
                        } else {
                            $suggestedCommands += "gh release edit $($release.tagName) --draft=false"
                        }
                    }
                }
                else
                {
                    $script:unfixableIssues++
                    if ($script:repoInfo) {
                        $suggestedCommands += "gh release edit $($release.tagName) --draft=false  # Or edit at: $($script:repoInfo.Url)/releases/edit/$($release.tagName)"
                    } else {
                        $suggestedCommands += "gh release edit $($release.tagName) --draft=false"
                    }
                }
            }
            else
            {
                # Check if the release is truly immutable using GraphQL
                # Only check if we have repo info
                if ($script:repoInfo) {
                    $isImmutable = Test-ReleaseImmutability -Owner $script:repoInfo.Owner -Repo $script:repoInfo.Repo -Tag $release.tagName -Token $script:token -ApiUrl $script:apiUrl
                    if (-not $isImmutable) {
                        # Non-draft release that is not immutable can still be force-pushed
                        write-actions-warning "::warning title=Mutable release::Release $($release.tagName) is published but is not immutable, making it mutable via force-push. Consider using 'gh attestation' to make it truly immutable."
                    }
                }
            }
        }
    }
}

# Check that floating versions (major/minor/latest) DO NOT have GitHub releases
# Floating versions should not have releases as they are mutable by design
# This check runs when either check-releases or check-release-immutability is enabled
if (($checkReleases -ne "none" -or $checkReleaseImmutability -ne "none") -and $releases.Count -gt 0)
{
    foreach ($release in $releases)
    {
        # Check if this is a floating version (vX, vX.Y, or "latest")
        $isFloatingVersion = $release.tagName -match "^v\d+$" -or $release.tagName -match "^v\d+\.\d+$" -or $release.tagName -eq "latest"
        
        if ($isFloatingVersion)
        {
            # Check if the release is truly immutable using GraphQL
            $isImmutable = $false
            if (-not $release.isDraft -and $script:repoInfo)
            {
                # Check immutability via GitHub's GraphQL API
                $isImmutable = Test-ReleaseImmutability -Owner $script:repoInfo.Owner -Repo $script:repoInfo.Repo -Tag $release.tagName -Token $script:token -ApiUrl $script:apiUrl
            }
            
            if ($isImmutable)
            {
                # Immutable release on a floating version - this is unfixable
                $script:unfixableIssues++
                $messageType = if ($checkReleaseImmutability -eq "error" -or $checkReleases -eq "error") { "error" } else { "warning" }
                $messageFunc = if ($checkReleaseImmutability -eq "error" -or $checkReleases -eq "error") { "write-actions-error" } else { "write-actions-warning" }
                & $messageFunc "::$messageType title=Release on floating version::Floating version $($release.tagName) has an immutable release, which conflicts with its mutable nature. This cannot be auto-fixed."
                $suggestedCommands += "# WARNING: Cannot delete immutable release for $($release.tagName). Floating versions should not have releases."
            }
            else
            {
                # Mutable release (draft or not immutable) on a floating version - can be auto-fixed by deleting it
                $fixCmd = "gh release delete $($release.tagName) --yes"
                $fixDescription = "Remove mutable release for floating version $($release.tagName)"
                
                # Try to auto-fix if enabled
                if ($autoFix)
                {
                    Write-Host "Auto-fix: $fixDescription"
                    $deleteSuccess = Remove-GitHubRelease -TagName $release.tagName
                    
                    if ($deleteSuccess)
                    {
                        Write-Host "✓ Success: $fixDescription"
                        $script:fixedIssues++
                    }
                    else
                    {
                        Write-Host "✗ Failed: $fixDescription"
                        $script:failedFixes++
                        $messageType = if ($checkReleaseImmutability -eq "error" -or $checkReleases -eq "error") { "error" } else { "warning" }
                        $messageFunc = if ($checkReleaseImmutability -eq "error" -or $checkReleases -eq "error") { "write-actions-error" } else { "write-actions-warning" }
                        & $messageFunc "::$messageType title=Release on floating version::Floating version $($release.tagName) has a mutable release, which should be removed."
                        $suggestedCommands += $fixCmd
                    }
                }
                else
                {
                    $messageType = if ($checkReleaseImmutability -eq "error" -or $checkReleases -eq "error") { "error" } else { "warning" }
                    $messageFunc = if ($checkReleaseImmutability -eq "error" -or $checkReleases -eq "error") { "write-actions-error" } else { "write-actions-warning" }
                    & $messageFunc "::$messageType title=Release on floating version::Floating version $($release.tagName) has a mutable release, which should be removed."
                    $suggestedCommands += $fixCmd
                }
            }
        }
    }
}

$allVersions = $branchVersions + $tagVersions

# Filter out preview releases if requested
$versionsForCalculation = $allVersions
if ($ignorePreviewReleases)
{
    $versionsForCalculation = $allVersions | Where-Object{ -not $_.isPrerelease }
}

# If all versions are filtered out (e.g., all are prereleases), use all versions
if ($versionsForCalculation.Count -eq 0)
{
    $versionsForCalculation = $allVersions
}

$majorVersions = $versionsForCalculation | 
    ForEach-Object{ ConvertTo-Version "$($_.semver.major)" } | 
    Select-Object -Unique

$minorVersions = $versionsForCalculation | 
    ForEach-Object{ ConvertTo-Version "$($_.semver.major).$($_.semver.minor)" } | 
    Select-Object -Unique

$patchVersions = $versionsForCalculation | 
    ForEach-Object{ ConvertTo-Version "$($_.semver.major).$($_.semver.minor).$($_.semver.build)" } | 
    Select-Object -Unique

foreach ($majorVersion in $majorVersions)
{
    $highestMinor = ($minorVersions | Where-Object{ $_.major -eq $majorVersion.major } | Measure-Object -Max).Maximum

    # Check if major/minor versions exist (look in all versions)
    $majorVersion_obj = $allVersions | 
        Where-Object{ $_.version -eq "v$($majorVersion.major)" } | 
        Select-Object -First 1
    $majorSha = $majorVersion_obj.sha
    
    # If no minor versions exist for this major version, we need to create v{major}.0.0 and v{major}.0
    if (-not $highestMinor)
    {
        Write-Host "::debug::No minor versions found for major version v$($majorVersion.major), will create v$($majorVersion.major).0.0 and v$($majorVersion.major).0"
        
        # Create v{major}.0.0 using the major version's SHA
        if ($majorSha)
        {
            $fixCmd = "git push origin $majorSha`:refs/tags/v$($majorVersion.major).0.0"
            $apiAction = { New-GitHubRef -RefName "refs/tags/v$($majorVersion.major).0.0" -Sha $majorSha -Force $false }
            $fixed = Invoke-AutoFix -Description "Create missing patch version v$($majorVersion.major).0.0" -Command $fixCmd -ApiAction $apiAction
            
            if ($fixed) {
                $script:fixedIssues++
                # Update our tracking to include the new version
                $newPatchVersion = ConvertTo-Version "$($majorVersion.major).0.0"
                $patchVersions += $newPatchVersion
            } else {
                if ($autoFix) { $script:failedFixes++ }
                write-actions-error "::error title=Missing version::Version: v$($majorVersion.major).0.0 does not exist and must match: v$($majorVersion.major) ref $majorSha"
                $suggestedCommands += $fixCmd
            }
            
            # Create v{major}.0 if check-minor-version is enabled
            if ($checkMinorVersion -ne "none")
            {
                $fixCmd = "git push origin $majorSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($majorVersion.major).0"
                $refType = $useBranches ? 'heads' : 'tags'
                $apiAction = { New-GitHubRef -RefName "refs/$refType/v$($majorVersion.major).0" -Sha $majorSha -Force $false }
                $fixed = Invoke-AutoFix -Description "Create missing minor version v$($majorVersion.major).0" -Command $fixCmd -ApiAction $apiAction
                
                if ($fixed) {
                    $script:fixedIssues++
                    # Update our tracking to include the new version
                    $newMinorVersion = ConvertTo-Version "$($majorVersion.major).0"
                    $minorVersions += $newMinorVersion
                    $highestMinor = $newMinorVersion
                } else {
                    if ($autoFix) { $script:failedFixes++ }
                    write-actions-message "::$($checkMinorVersion) title=Missing version::Version: v$($majorVersion.major).0 does not exist and must match: v$($majorVersion.major) ref $majorSha" -severity $checkMinorVersion
                    $suggestedCommands += $fixCmd
                }
            }
            else
            {
                # Even if check-minor-version is none, we still need $highestMinor set for the rest of the logic
                $highestMinor = ConvertTo-Version "$($majorVersion.major).0"
            }
        }
        
        # If we still don't have highestMinor, skip this major version
        if (-not $highestMinor)
        {
            continue
        }
    }

    # Determine what they should point to (look in non-prerelease versions)
    $minorVersion_obj = $versionsForCalculation | 
        Where-Object{ $_.version -eq "v$($majorVersion.major).$($highestMinor.minor)" } | 
        Select-Object -First 1
    $minorSha = $minorVersion_obj.sha
    
    # Check if major/minor versions use branches when use-branches is enabled
    if ($useBranches)
    {
        if ($majorVersion_obj -and $majorVersion_obj.ref -match "^refs/tags/")
        {
            $fixCmd = "git branch v$($majorVersion.major) $majorSha && git push origin v$($majorVersion.major):refs/heads/v$($majorVersion.major) && git push origin :refs/tags/v$($majorVersion.major)"
            $apiAction = { 
                $createBranch = New-GitHubRef -RefName "refs/heads/v$($majorVersion.major)" -Sha $majorSha -Force $false
                $deleteTag = Remove-GitHubRef -RefName "refs/tags/v$($majorVersion.major)"
                return ($createBranch -and $deleteTag)
            }
            $fixed = Invoke-AutoFix -Description "Convert major version v$($majorVersion.major) from tag to branch" -Command $fixCmd -ApiAction $apiAction
            
            if ($fixed) {
                $script:fixedIssues++
            } else {
                if ($autoFix) { $script:failedFixes++ }
                write-actions-error "::error title=Version should be branch::Major version v$($majorVersion.major) is a tag but should be a branch when use-branches is enabled"
                $suggestedCommands += "git branch v$($majorVersion.major) $majorSha"
                $suggestedCommands += "git push origin v$($majorVersion.major):refs/heads/v$($majorVersion.major)"
                $suggestedCommands += "git push origin :refs/tags/v$($majorVersion.major)"
            }
        }
        
        if ($minorVersion_obj -and $minorVersion_obj.ref -match "^refs/tags/")
        {
            $fixCmd = "git branch v$($majorVersion.major).$($highestMinor.minor) $minorSha && git push origin v$($majorVersion.major).$($highestMinor.minor):refs/heads/v$($majorVersion.major).$($highestMinor.minor) && git push origin :refs/tags/v$($majorVersion.major).$($highestMinor.minor)"
            $apiAction = {
                $createBranch = New-GitHubRef -RefName "refs/heads/v$($majorVersion.major).$($highestMinor.minor)" -Sha $minorSha -Force $false
                $deleteTag = Remove-GitHubRef -RefName "refs/tags/v$($majorVersion.major).$($highestMinor.minor)"
                return ($createBranch -and $deleteTag)
            }
            $fixed = Invoke-AutoFix -Description "Convert minor version v$($majorVersion.major).$($highestMinor.minor) from tag to branch" -Command $fixCmd -ApiAction $apiAction
            
            if ($fixed) {
                $script:fixedIssues++
            } else {
                if ($autoFix) { $script:failedFixes++ }
                write-actions-error "::error title=Version should be branch::Minor version v$($majorVersion.major).$($highestMinor.minor) is a tag but should be a branch when use-branches is enabled"
                $suggestedCommands += "git branch v$($majorVersion.major).$($highestMinor.minor) $minorSha"
                $suggestedCommands += "git push origin v$($majorVersion.major).$($highestMinor.minor):refs/heads/v$($majorVersion.major).$($highestMinor.minor)"
                $suggestedCommands += "git push origin :refs/tags/v$($majorVersion.major).$($highestMinor.minor)"
            }
        }
    }

    if ($checkMinorVersion -ne "none")
    {
        if (-not $majorSha -and $minorSha)
        {
            $fixCmd = "git push origin $minorSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($majorVersion.major)"
            $refType = $useBranches ? 'heads' : 'tags'
            $apiAction = { New-GitHubRef -RefName "refs/$refType/v$($majorVersion.major)" -Sha $minorSha -Force $false }
            $fixed = Invoke-AutoFix -Description "Create missing major version v$($majorVersion.major) pointing to minor version" -Command $fixCmd -ApiAction $apiAction
            
            if ($fixed) {
                $script:fixedIssues++
            } else {
                if ($autoFix) { $script:failedFixes++ }
                write-actions-message "::$($checkMinorVersion) title=Missing version::Version: v$($majorVersion.major) does not exist and must match: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha" -severity $checkMinorVersion
                $suggestedCommands += $fixCmd
            }
        }

        if ($majorSha -and $minorSha -and ($majorSha -ne $minorSha))
        {
            $fixCmd = "git push origin $minorSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($majorVersion.major) --force"
            $refType = $useBranches ? 'heads' : 'tags'
            $apiAction = { New-GitHubRef -RefName "refs/$refType/v$($majorVersion.major)" -Sha $minorSha -Force $true }
            $fixed = Invoke-AutoFix -Description "Update major version v$($majorVersion.major) to match minor version" -Command $fixCmd -ApiAction $apiAction
            
            if ($fixed) {
                $script:fixedIssues++
            } else {
                if ($autoFix) { $script:failedFixes++ }
                write-actions-message "::$($checkMinorVersion) title=Incorrect version::Version: v$($majorVersion.major) ref $majorSha must match: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha" -severity $checkMinorVersion
                $suggestedCommands += $fixCmd
            }
        }
    }

    $highestPatch = ($patchVersions | 
        Where-Object{ $_.major -eq $highestMinor.major -and $_.minor -eq $highestMinor.minor } | 
        Measure-Object -Max).Maximum
    
    # Check if major/minor/patch versions exist (look in all versions)
    $majorSha = ($allVersions | 
        Where-Object{ $_.version -eq "v$($highestMinor.major)" } | 
        Select-Object -First 1).sha
    $minorSha = ($allVersions | 
        Where-Object{ $_.version -eq "v$($highestMinor.major).$($highestMinor.minor)" } | 
        Select-Object -First 1).sha
    
    # Determine what they should point to (look in non-prerelease versions)
    $patchSha = ($versionsForCalculation | 
        Where-Object{ $_.version -eq "v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)" } | 
        Select-Object -First 1).sha
    
    # Determine the source SHA for the patch version
    # If patchSha doesn't exist, use minorSha if available, otherwise majorSha
    $sourceShaForPatch = $patchSha
    $sourceVersionForPatch = "v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)"
    if (-not $sourceShaForPatch) {
        $sourceShaForPatch = $minorSha
        $sourceVersionForPatch = "v$($highestMinor.major).$($highestMinor.minor)"
    }
    if (-not $sourceShaForPatch) {
        $sourceShaForPatch = $majorSha
        $sourceVersionForPatch = "v$($highestMinor.major)"
    }
    
    if ($majorSha -and $patchSha -and ($majorSha -ne $patchSha))
    {
        $fixCmd = "git push origin $patchSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($highestMinor.major) --force"
        $refType = $useBranches ? 'heads' : 'tags'
        $apiAction = { New-GitHubRef -RefName "refs/$refType/v$($highestMinor.major)" -Sha $patchSha -Force $true }
        $fixed = Invoke-AutoFix -Description "Update major version v$($highestMinor.major) to match patch version" -Command $fixCmd -ApiAction $apiAction
        
        if ($fixed) {
            $script:fixedIssues++
        } else {
            if ($autoFix) { $script:failedFixes++ }
            write-actions-error "::error title=Incorrect version::Version: v$($highestMinor.major) ref $majorSha must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha"
            $suggestedCommands += $fixCmd
        }
    }

    if (-not $patchSha -and $sourceShaForPatch)
    {
        $fixCmd = "git push origin $sourceShaForPatch`:refs/tags/v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)"
        $apiAction = { New-GitHubRef -RefName "refs/tags/v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)" -Sha $sourceShaForPatch -Force $false }
        $fixed = Invoke-AutoFix -Description "Create missing patch version v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)" -Command $fixCmd -ApiAction $apiAction
        
        if ($fixed) {
            $script:fixedIssues++
        } else {
            if ($autoFix) { $script:failedFixes++ }
            write-actions-error "::error title=Missing version::Version: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) does not exist and must match: $sourceVersionForPatch ref $sourceShaForPatch"
            $suggestedCommands += $fixCmd
        }
    }

    if (-not $majorSha)
    {
        $fixCmd = "git push origin $sourceShaForPatch`:refs/$($useBranches ? 'heads' : 'tags')/v$($highestPatch.major)"
        $refType = $useBranches ? 'heads' : 'tags'
        $apiAction = { New-GitHubRef -RefName "refs/$refType/v$($highestPatch.major)" -Sha $sourceShaForPatch -Force $false }
        $fixed = Invoke-AutoFix -Description "Create missing major version v$($highestPatch.major)" -Command $fixCmd -ApiAction $apiAction
        
        if ($fixed) {
            $script:fixedIssues++
        } else {
            if ($autoFix) { $script:failedFixes++ }
            write-actions-error "::error title=Missing version::Version: v$($majorVersion.major) does not exist and must match: $sourceVersionForPatch ref $sourceShaForPatch"
            $suggestedCommands += $fixCmd
        }
    }

    if ($checkMinorVersion -ne "none")
    {
        if (-not $minorSha)
        {
            # Determine source for minor version: prefer patch, fall back to major
            $sourceShaForMinor = $patchSha
            $sourceVersionForMinor = "v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)"
            if (-not $sourceShaForMinor) {
                $sourceShaForMinor = $majorSha
                $sourceVersionForMinor = "v$($highestMinor.major)"
            }
            
            if ($sourceShaForMinor) {
                $fixCmd = "git push origin $sourceShaForMinor`:refs/$($useBranches ? 'heads' : 'tags')/v$($highestMinor.major).$($highestMinor.minor)"
                $refType = $useBranches ? 'heads' : 'tags'
                $apiAction = { New-GitHubRef -RefName "refs/$refType/v$($highestMinor.major).$($highestMinor.minor)" -Sha $sourceShaForMinor -Force $false }
                $fixed = Invoke-AutoFix -Description "Create missing minor version v$($highestMinor.major).$($highestMinor.minor)" -Command $fixCmd -ApiAction $apiAction
                
                if ($fixed) {
                    $script:fixedIssues++
                } else {
                    if ($autoFix) { $script:failedFixes++ }
                    write-actions-message "::$($checkMinorVersion) title=Missing version::Version: v$($highestMinor.major).$($highestMinor.minor) does not exist and must match: $sourceVersionForMinor ref $sourceShaForMinor" -severity $checkMinorVersion
                    $suggestedCommands += $fixCmd
                }
            }
        }

        if ($minorSha -and $patchSha -and ($minorSha -ne $patchSha))
        {
            $fixCmd = "git push origin $patchSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($highestMinor.major).$($highestMinor.minor) --force"
            $refType = $useBranches ? 'heads' : 'tags'
            $apiAction = { New-GitHubRef -RefName "refs/$refType/v$($highestMinor.major).$($highestMinor.minor)" -Sha $patchSha -Force $true }
            $fixed = Invoke-AutoFix -Description "Update minor version v$($highestMinor.major).$($highestMinor.minor) to match patch version" -Command $fixCmd -ApiAction $apiAction
            
            if ($fixed) {
                $script:fixedIssues++
            } else {
                if ($autoFix) { $script:failedFixes++ }
                write-actions-message "::$($checkMinorVersion) title=Incorrect version::Version: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha" -severity $checkMinorVersion
                $suggestedCommands += $fixCmd
            }
        }
    }
}

# For the "latest" version, use the highest non-prerelease version globally
$globalHighestPatchVersion = ($versionsForCalculation | 
    ForEach-Object{ ConvertTo-Version "$($_.semver.major).$($_.semver.minor).$($_.semver.build)" } | 
    Select-Object -Unique | 
    Measure-Object -Max).Maximum

$highestVersion = $versionsForCalculation | 
    Where-Object{ $_.version -eq "v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build)" } | 
    Select-Object -First 1 

# Check latest based on whether we're using branches or tags
if ($useBranches) {
    # When using branches, check if latest branch exists and points to correct version
    if ($latestBranch -and ($latestBranch.sha -ne $highestVersion.sha)) {
        $fixCmd = "git push origin $($highestVersion.sha):refs/heads/latest --force"
        $apiAction = { New-GitHubRef -RefName "refs/heads/latest" -Sha $highestVersion.sha -Force $true }
        $fixed = Invoke-AutoFix -Description "Update latest branch to match highest version" -Command $fixCmd -ApiAction $apiAction
        
        if ($fixed) {
            $script:fixedIssues++
        } else {
            if ($autoFix) { $script:failedFixes++ }
            write-actions-error "::error title=Incorrect version::Version: latest (branch) ref $($latestBranch.sha) must match: v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build) ref $($highestVersion.sha)"
            $suggestedCommands += $fixCmd
        }
    } elseif (-not $latestBranch -and $highestVersion) {
        $fixCmd = "git push origin $($highestVersion.sha):refs/heads/latest"
        $apiAction = { New-GitHubRef -RefName "refs/heads/latest" -Sha $highestVersion.sha -Force $false }
        $fixed = Invoke-AutoFix -Description "Create missing latest branch" -Command $fixCmd -ApiAction $apiAction
        
        if ($fixed) {
            $script:fixedIssues++
        } else {
            if ($autoFix) { $script:failedFixes++ }
            write-actions-error "::error title=Missing version::Version: latest (branch) does not exist and must match: v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build) ref $($highestVersion.sha)"
            $suggestedCommands += $fixCmd
        }
    }
    
    # Warn if latest exists as a tag when we're using branches
    if ($latest) {
        write-actions-warning "::warning title=Latest should be branch::Version: latest exists as a tag but should be a branch when floating-versions-use is 'branches'"
        $suggestedCommands += "git push origin :refs/tags/latest"
    }
} else {
    # When using tags, check if latest tag exists and points to correct version
    if ($latest -and $highestVersion -and ($latest.sha -ne $highestVersion.sha)) {
        $fixCmd = "git push origin $($highestVersion.sha):refs/tags/latest --force"
        $apiAction = { New-GitHubRef -RefName "refs/tags/latest" -Sha $highestVersion.sha -Force $true }
        $fixed = Invoke-AutoFix -Description "Update latest tag to match highest version" -Command $fixCmd -ApiAction $apiAction
        
        if ($fixed) {
            $script:fixedIssues++
        } else {
            if ($autoFix) { $script:failedFixes++ }
            write-actions-error "::error title=Incorrect version::Version: latest ref $($latest.sha) must match: v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build) ref $($highestVersion.sha)"
            $suggestedCommands += $fixCmd
        }
    }
    
    # Warn if latest exists as a branch when we're using tags
    if ($latestBranch) {
        write-actions-warning "::warning title=Latest should be tag::Version: latest exists as a branch but should be a tag when floating-versions-use is 'tags'"
        $suggestedCommands += "git push origin :refs/heads/latest"
    }
}

# Display summary based on auto-fix mode
if ($autoFix)
{
    Write-Output ""
    Write-Output "### Auto-fix Summary"
    Write-Output "✓ Fixed issues: $script:fixedIssues"
    Write-Output "✗ Failed fixes: $script:failedFixes"
    Write-Output "⚠ Unfixable issues: $script:unfixableIssues"
    
    # Only fail if there are failed fixes or unfixable issues
    if ($script:failedFixes -gt 0 -or $script:unfixableIssues -gt 0)
    {
        $global:returnCode = 1
        Write-Output ""
        if ($script:failedFixes -gt 0) {
            Write-Output "::error::Some fixes failed. Please review the errors above and fix manually."
        }
        if ($script:unfixableIssues -gt 0) {
            Write-Output "::error::Some issues cannot be auto-fixed (draft releases must be published manually, or immutable releases on floating versions). Please fix manually."
        }
    }
    elseif ($script:fixedIssues -gt 0)
    {
        # Issues were found and all were fixed successfully
        $global:returnCode = 0
        Write-Output ""
        Write-Output "::notice::All issues were successfully fixed!"
    }
    else
    {
        # No issues were found
        $global:returnCode = 0
        Write-Output ""
        Write-Output "::notice::No issues found!"
    }
    
    # Show suggested commands for unfixable issues or failed fixes
    if ($suggestedCommands -ne "")
    {
        $suggestedCommands = $suggestedCommands | Select-Object -unique
        Write-Output ""
        Write-Output "### Manual fixes required for unfixable or failed issues:"
        Write-Output ($suggestedCommands -join "`n")
        write-output "### Manual fixes required:`n```````n$($suggestedCommands -join "`n")`n``````" >> $env:GITHUB_STEP_SUMMARY
    }
}
else
{
    # Not in auto-fix mode, just show suggested commands if any
    if ($suggestedCommands -ne "")
    {
        $suggestedCommands = $suggestedCommands | Select-Object -unique
        Write-Output ($suggestedCommands -join "`n")
        write-output "### Suggested fix:`n```````n$($suggestedCommands -join "`n")`n``````" >> $env:GITHUB_STEP_SUMMARY
    }
}

exit $global:returnCode
