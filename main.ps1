$global:returnCode = 0

# Read inputs
$script:token = ${env:INPUT_TOKEN} ?? $env:GITHUB_TOKEN ?? ""
$warnMinor = (${env:INPUT_CHECK-MINOR-VERSION} ?? "true").Trim() -eq "true"
$checkReleases = (${env:INPUT_CHECK-RELEASES} ?? "error").Trim().ToLower()
$checkReleaseImmutability = (${env:INPUT_CHECK-RELEASE-IMMUTABILITY} ?? "error").Trim().ToLower()
$ignorePreviewReleases = (${env:INPUT_IGNORE-PREVIEW-RELEASES} ?? "false").Trim() -eq "true"
$floatingVersionsUse = (${env:INPUT_FLOATING-VERSIONS-USE} ?? "tags").Trim().ToLower()
$autoFix = (${env:INPUT_AUTO-FIX} ?? "false").Trim() -eq "true"

# Validate inputs
if ($checkReleases -notin @("error", "warning", "none")) {
    write-output "::error title=Invalid configuration::check-releases must be 'error', 'warning', or 'none', got '$checkReleases'"
    exit 1
}

if ($checkReleaseImmutability -notin @("error", "warning", "none")) {
    write-output "::error title=Invalid configuration::check-release-immutability must be 'error', 'warning', or 'none', got '$checkReleaseImmutability'"
    exit 1
}

if ($floatingVersionsUse -notin @("tags", "branches")) {
    write-output "::error title=Invalid configuration::floating-versions-use must be either 'tags' or 'branches', got '$floatingVersionsUse'"
    exit 1
}

$useBranches = $floatingVersionsUse -eq "branches"

# Get GitHub context information
$script:apiUrl = "https://api.github.com"
$repository = $null
$script:repoOwner = $null
$script:repoName = $null

if ($env:GITHUB_CONTEXT) {
    try {
        $githubContext = $env:GITHUB_CONTEXT | ConvertFrom-Json
        $script:apiUrl = $githubContext.api_url ?? "https://api.github.com"
        $repository = $githubContext.repository
    }
    catch {
        # Fall back to environment variables if JSON parsing fails
        $script:apiUrl = $env:GITHUB_API_URL ?? "https://api.github.com"
        $repository = $env:GITHUB_REPOSITORY
    }
}
else {
    # Fall back to environment variables
    $script:apiUrl = $env:GITHUB_API_URL ?? "https://api.github.com"
    $repository = $env:GITHUB_REPOSITORY
}

# Parse repository owner and name
if ($repository -and $repository -match "^([^/]+)/(.+)$") {
    $script:repoOwner = $matches[1]
    $script:repoName = $matches[2]
}

$tags = & git tag -l v* | Where-Object{ return ($_ -match "v\d+(\.\d+)*$") }

$branches = & git branch --list --quiet --remotes | Where-Object{ return ($_.Trim() -match "^origin/(v\d+(\.\d+)*(-.*)?)$") } | ForEach-Object{ $_.Trim().Replace("origin/", "")}

$tagVersions = @()
$branchVersions = @()

$suggestedCommands = @()

function write-actions-error
{
    param(
        [string] $message
    )

    write-output $message
    $global:returnCode = 1
}

function write-actions-warning
{
    param(
        [string] $message
    )

    write-output $message
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
    
    try {
        # First try to use GitHub context (preferred)
        if ($script:repoOwner -and $script:repoName) {
            return @{
                Owner = $script:repoOwner
                Repo = $script:repoName
                Url = "https://github.com/$script:repoOwner/$script:repoName"
            }
        }
        
        # Fallback: Get the repository from git remote
        $remoteUrl = & git config --get remote.origin.url 2>$null
        if (-not $remoteUrl) {
            return $null
        }
        
        # Parse owner/repo from various Git URL formats
        # SSH: git@github.com:owner/repo.git
        # HTTPS: https://github.com/owner/repo.git
        # HTTPS without .git: https://github.com/owner/repo
        if ($remoteUrl -match 'github\.com[:/]([^/]+)/([^/]+?)(\.git)?$') {
            return @{
                Owner = $matches[1]
                Repo = $matches[2]
                Url = "https://github.com/$($matches[1])/$($matches[2])"
            }
        }
        
        return $null
    }
    catch {
        return $null
    }
}

function Get-TagCommitSHA
{
    param(
        [string]$Owner,
        [string]$Repo,
        [string]$Tag,
        [string]$Token,
        [string]$ApiUrl
    )
    
    try {
        $headers = Get-ApiHeaders -Token $Token
        $url = "$ApiUrl/repos/$Owner/$Repo/git/ref/tags/$Tag"
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
        
        # The ref API returns an object with sha pointing to the tag object
        # We need to follow that to get the actual commit SHA
        if ($response.object.type -eq "tag") {
            # Annotated tag - need to fetch the tag object to get commit SHA
            $tagUrl = $response.object.url
            $tagResponse = Invoke-RestMethod -Uri $tagUrl -Headers $headers -Method Get -ErrorAction Stop
            return $tagResponse.object.sha
        } else {
            # Lightweight tag - directly points to commit
            return $response.object.sha
        }
    }
    catch {
        return $null
    }
}

function Test-ReleaseAttestation
{
    param(
        [string]$Owner,
        [string]$Repo,
        [string]$Tag,
        [string]$Token,
        [string]$ApiUrl
    )
    
    try {
        # Get the commit SHA for the tag
        $commitSHA = Get-TagCommitSHA -Owner $Owner -Repo $Repo -Tag $Tag -Token $Token -ApiUrl $ApiUrl
        if (-not $commitSHA) {
            return $false
        }
        
        # Format SHA as digest (sha256:...)
        $digest = "sha256:$commitSHA"
        
        # Check for attestations
        $headers = Get-ApiHeaders -Token $Token
        $url = "$ApiUrl/repos/$Owner/$Repo/attestations/$digest"
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
        
        # If we get a response with attestations, the release is attested
        if ($response.attestations -and $response.attestations.Count -gt 0) {
            return $true
        }
        
        return $false
    }
    catch {
        # If API call fails (404, etc.), assume no attestation
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

# Get repository info for URLs
$script:repoInfo = Get-GitHubRepoInfo

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
    
    $tagVersions += @{
        version = $tag
        ref = "refs/tags/$tag"
        sha = & git rev-list -n 1 $tag
        semver = ConvertTo-Version $tag.Substring(1)
        isPrerelease = $isPrerelease
    }
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
    $branchVersions += @{
        version = $branch
        ref = "refs/remotes/origin/$branch"
        sha = & git rev-parse refs/remotes/origin/$branch
        semver = ConvertTo-Version $branch.Substring(1)
        isPrerelease = $false  # Branches are not considered prereleases
    }
}

foreach ($tagVersion in $tagVersions)
{
    $branchVersion = $branchVersions | Where-Object{ $_.version -eq $tagVersion.version } | Select-Object -First 1

    if ($branchVersion)
    {
        $message = "title=Ambiguous version: $($tagVersion.version)::Exists as both tag ($($tagVersion.sha)) and branch ($($branchVersion.sha))"
        if ($branchVersion.sha -eq $tagVersion.sha)
        {
            
            write-actions-warning "::warning $message"
        }
        else
        {
            write-actions-error "::error $message"
        }

        $suggestedCommands += "git push origin :refs/heads/$($tagVersion.version)"
    }
}

# Check that every patch version (vX.Y.Z) has a corresponding release
if ($checkReleases -ne "none" -and $releases.Count -gt 0)
{
    $releaseTagNames = $releases | ForEach-Object { $_.tagName }
    
    foreach ($tagVersion in $tagVersions)
    {
        # Only check patch versions (vX.Y.Z format with 3 parts)
        if ($tagVersion.version -match "^v\d+\.\d+\.\d+$")
        {
            $hasRelease = $releaseTagNames -contains $tagVersion.version
            
            if (-not $hasRelease)
            {
                $messageType = if ($checkReleases -eq "error") { "error" } else { "warning" }
                $messageFunc = if ($checkReleases -eq "error") { "write-actions-error" } else { "write-actions-warning" }
                & $messageFunc "::$messageType title=Missing release::Version $($tagVersion.version) does not have a GitHub Release"
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

# Check that releases are immutable (not draft, which allows tag changes)
# Also optionally verify attestations for additional security
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
                if ($script:repoInfo) {
                    $suggestedCommands += "gh release edit $($release.tagName) --draft=false  # Or edit at: $($script:repoInfo.Url)/releases/edit/$($release.tagName)"
                } else {
                    $suggestedCommands += "gh release edit $($release.tagName) --draft=false"
                }
            }
            
            # Optionally check for attestations (provides cryptographic verification)
            # Only check if we have repo info and it's not a draft
            if ($repoInfo -and -not $release.isDraft) {
                $hasAttestation = Test-ReleaseAttestation -Owner $script:repoInfo.Owner -Repo $script:repoInfo.Repo -Tag $release.tagName -Token $script:token -ApiUrl $script:apiUrl
                if (-not $hasAttestation) {
                    # Note: This is informational only, not an error, as attestations are optional
                    write-actions-warning "::notice title=No attestation::Release $($release.tagName) does not have attestations. Consider using 'gh attestation' to cryptographically verify releases."
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
            write-actions-error "::error title=Version should be branch::Major version v$($majorVersion.major) is a tag but should be a branch when use-branches is enabled"
            $suggestedCommands += "git branch v$($majorVersion.major) $majorSha"
            $suggestedCommands += "git push origin v$($majorVersion.major):refs/heads/v$($majorVersion.major)"
            $suggestedCommands += "git push origin :refs/tags/v$($majorVersion.major)"
        }
        
        if ($minorVersion_obj -and $minorVersion_obj.ref -match "^refs/tags/")
        {
            write-actions-error "::error title=Version should be branch::Minor version v$($majorVersion.major).$($highestMinor.minor) is a tag but should be a branch when use-branches is enabled"
            $suggestedCommands += "git branch v$($majorVersion.major).$($highestMinor.minor) $minorSha"
            $suggestedCommands += "git push origin v$($majorVersion.major).$($highestMinor.minor):refs/heads/v$($majorVersion.major).$($highestMinor.minor)"
            $suggestedCommands += "git push origin :refs/tags/v$($majorVersion.major).$($highestMinor.minor)"
        }
    }

    if ($warnMinor)
    {
        if (-not $majorSha -and $minorSha)
        {
            write-actions-error "::error title=Missing version::Version: v$($majorVersion.major) does not exist and must match: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha"
            $suggestedCommands += "git push origin $minorSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($majorVersion.major)"
        }

        if ($majorSha -and $minorSha -and ($majorSha -ne $minorSha))
        {
            write-actions-error "::error title=Incorrect version::Version: v$($majorVersion.major) ref $majorSha must match: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha"
            $suggestedCommands += "git push origin $minorSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($majorVersion.major) --force"
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
        write-actions-error "::error title=Incorrect version::Version: v$($highestMinor.major) ref $majorSha must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha"
        $suggestedCommands += "git push origin $patchSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($highestMinor.major) --force"
    }

    if (-not $patchSha -and $sourceShaForPatch)
    {
        write-actions-error "::error title=Missing version::Version: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) does not exist and must match: $sourceVersionForPatch ref $sourceShaForPatch"
        $suggestedCommands += "git push origin $sourceShaForPatch`:refs/tags/v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)"
    }

    if (-not $majorSha)
    {
        write-actions-error "::error title=Missing version::Version: v$($majorVersion.major) does not exist and must match: $sourceVersionForPatch ref $sourceShaForPatch"
        $suggestedCommands += "git push origin $sourceShaForPatch`:refs/$($useBranches ? 'heads' : 'tags')/v$($highestPatch.major)"
    }

    if ($warnMinor)
    {
        if (-not $minorSha -and $patchSha)
        {
            write-actions-error "::error title=Missing version::Version: v$($highestMinor.major).$($highestMinor.minor) does not exist and must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha"
            $suggestedCommands += "git push origin $patchSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($highestMinor.major).$($highestMinor.minor)"
        }

        if ($minorSha -and $patchSha -and ($minorSha -ne $patchSha))
        {
            write-actions-error "::error title=Incorrect version::Version: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha"
            $suggestedCommands += "git push origin $patchSha`:refs/$($useBranches ? 'heads' : 'tags')/v$($highestMinor.major).$($highestMinor.minor) --force"
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
        write-actions-error "::error title=Incorrect version::Version: latest (branch) ref $($latestBranch.sha) must match: v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build) ref $($highestVersion.sha)"
        $suggestedCommands += "git push origin $($highestVersion.sha):refs/heads/latest --force"
    } elseif (-not $latestBranch -and $highestVersion) {
        write-actions-error "::error title=Missing version::Version: latest (branch) does not exist and must match: v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build) ref $($highestVersion.sha)"
        $suggestedCommands += "git push origin $($highestVersion.sha):refs/heads/latest"
    }
    
    # Warn if latest exists as a tag when we're using branches
    if ($latest) {
        write-actions-warning "::warning title=Latest should be branch::Version: latest exists as a tag but should be a branch when floating-versions-use is 'branches'"
        $suggestedCommands += "git push origin :refs/tags/latest"
    }
} else {
    # When using tags, check if latest tag exists and points to correct version
    if ($latest -and $highestVersion -and ($latest.sha -ne $highestVersion.sha)) {
        write-actions-error "::error title=Incorrect version::Version: latest ref $($latest.sha) must match: v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build) ref $($highestVersion.sha)"
        $suggestedCommands += "git push origin $($highestVersion.sha):refs/tags/latest --force"
    }
    
    # Warn if latest exists as a branch when we're using tags
    if ($latestBranch) {
        write-actions-warning "::warning title=Latest should be tag::Version: latest exists as a branch but should be a tag when floating-versions-use is 'tags'"
        $suggestedCommands += "git push origin :refs/heads/latest"
    }
}

if ($suggestedCommands -ne "")
{
    $suggestedCommands = $suggestedCommands | Select-Object -unique
    
    # Auto-fix if enabled
    if ($autoFix)
    {
        Write-Output "### Auto-fixing version tags/branches..."
        
        foreach ($command in $suggestedCommands)
        {
            # Only execute git commands that update tags/branches, skip gh release commands
            if ($command -match "^git push")
            {
                Write-Output "Executing: $command"
                try
                {
                    Invoke-Expression $command
                    if ($LASTEXITCODE -eq 0)
                    {
                        Write-Output "✓ Success"
                    }
                    else
                    {
                        Write-Output "✗ Failed with exit code $LASTEXITCODE"
                        $global:returnCode = 1
                    }
                }
                catch
                {
                    Write-Output "✗ Failed: $_"
                    $global:returnCode = 1
                }
            }
            elseif ($command -match "^gh release")
            {
                Write-Output "Skipping release command (manual execution required): $command"
            }
            else
            {
                Write-Output "Skipping non-push command: $command"
            }
        }
        
        write-output "### Auto-fix completed" >> $env:GITHUB_STEP_SUMMARY
    }
    else
    {
        Write-Output ($suggestedCommands -join "`n")
        write-output "### Suggested fix:`n```````n$($suggestedCommands -join "`n")`n``````" >> $env:GITHUB_STEP_SUMMARY
    }
}

exit $global:returnCode
