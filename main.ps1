$global:returnCode = 0

$warnMinor = (${env:INPUT_CHECK-MINOR-VERSION} ?? "true").Trim() -eq "true"
$checkReleases = (${env:INPUT_CHECK-RELEASES} ?? "true").Trim() -eq "true"
$checkReleaseImmutability = (${env:INPUT_CHECK-RELEASE-IMMUTABILITY} ?? "true").Trim() -eq "true"
$ignorePreviewReleases = (${env:INPUT_IGNORE-PREVIEW-RELEASES} ?? "false").Trim() -eq "true"
$useBranches = (${env:INPUT_USE-BRANCHES} ?? "false").Trim() -eq "true"
$autoFix = (${env:INPUT_AUTO-FIX} ?? "false").Trim() -eq "true"

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

function Get-GitHubReleases
{
    param()
    
    try {
        # Check if gh CLI is available and we're in a GitHub repository
        $ghAvailable = (Get-Command gh -ErrorAction SilentlyContinue) -ne $null
        if (-not $ghAvailable) {
            return @()
        }
        
        # Get the repository from git remote
        $remoteUrl = & git config --get remote.origin.url 2>$null
        if (-not $remoteUrl) {
            return @()
        }
        
        # Try to get releases using gh CLI
        $releases = & gh release list --limit 1000 --json tagName,isPrerelease,isDraft 2>$null | ConvertFrom-Json
        
        if ($LASTEXITCODE -ne 0) {
            return @()
        }
        
        return $releases
    }
    catch {
        return @()
    }
}

# Get GitHub releases if check is enabled
$releases = @()
$releaseMap = @{}
if ($checkReleases -or $checkReleaseImmutability -or $ignorePreviewReleases)
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
if ($latest)
{
    $latest = @{
        version = "latest"
        ref = "refs/tags/latest"
        sha = & git rev-list -n 1 latest
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
if ($checkReleases -and $releases.Count -gt 0)
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
                write-actions-error "::error title=Missing release::Version $($tagVersion.version) does not have a GitHub Release"
                $suggestedCommands += "gh release create $($tagVersion.version) --draft --title `"$($tagVersion.version)`" --notes `"Release $($tagVersion.version)`""
                $suggestedCommands += "gh release edit $($tagVersion.version) --draft=false"
            }
        }
    }
}

# Check that releases are immutable (not draft, which allows tag changes)
if ($checkReleaseImmutability -and $releases.Count -gt 0)
{
    foreach ($release in $releases)
    {
        # Only check releases for patch versions (vX.Y.Z format)
        if ($release.tagName -match "^v\d+\.\d+\.\d+$")
        {
            if ($release.isDraft)
            {
                write-actions-error "::error title=Draft release::Release $($release.tagName) is still in draft status, making it mutable. Publish the release to make it immutable."
                $suggestedCommands += "gh release edit $($release.tagName) --draft=false"
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
            if ($useBranches)
            {
                $suggestedCommands += "git push origin $minorSha`:refs/heads/v$($majorVersion.major)"
            }
            else
            {
                $suggestedCommands += "git push origin $minorSha`:refs/tags/v$($majorVersion.major)"
            }
        }

        if ($majorSha -and $minorSha -and ($majorSha -ne $minorSha))
        {
            write-actions-error "::error title=Incorrect version::Version: v$($majorVersion.major) ref $majorSha must match: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha"
            if ($useBranches)
            {
                $suggestedCommands += "git push origin $minorSha`:refs/heads/v$($majorVersion.major) --force"
            }
            else
            {
                $suggestedCommands += "git push origin $minorSha`:refs/tags/v$($majorVersion.major) --force"
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
        write-actions-error "::error title=Incorrect version::Version: v$($highestMinor.major) ref $majorSha must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha"
        if ($useBranches)
        {
            $suggestedCommands += "git push origin $patchSha`:refs/heads/v$($majorVersion.major) --force"
        }
        else
        {
            $suggestedCommands += "git push origin $patchSha`:refs/tags/v$($majorVersion.major) --force"
        }
    }

    if (-not $patchSha -and $sourceShaForPatch)
    {
        write-actions-error "::error title=Missing version::Version: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) does not exist and must match: $sourceVersionForPatch ref $sourceShaForPatch"
        $suggestedCommands += "git push origin $sourceShaForPatch`:refs/tags/v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)"
    }

    if (-not $majorSha)
    {
        write-actions-error "::error title=Missing version::Version: v$($majorVersion.major) does not exist and must match: $sourceVersionForPatch ref $sourceShaForPatch"
        if ($useBranches)
        {
            $suggestedCommands += "git push origin $sourceShaForPatch`:refs/heads/v$($highestPatch.major)"
        }
        else
        {
            $suggestedCommands += "git push origin $sourceShaForPatch`:refs/tags/v$($highestPatch.major)"
        }
    }

    if ($warnMinor)
    {
        if (-not $minorSha -and $patchSha)
        {
            write-actions-error "::error title=Missing version::Version: v$($highestMinor.major).$($highestMinor.minor) does not exist and must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha"
            if ($useBranches)
            {
                $suggestedCommands += "git push origin $patchSha`:refs/heads/v$($highestMinor.major).$($highestMinor.minor)"
            }
            else
            {
                $suggestedCommands += "git push origin $patchSha`:refs/tags/v$($highestMinor.major).$($highestMinor.minor)"
            }
        }

        if ($minorSha -and $patchSha -and ($minorSha -ne $patchSha))
        {
            write-actions-error "::error title=Incorrect version::Version: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha"
            if ($useBranches)
            {
                $suggestedCommands += "git push origin $patchSha`:refs/heads/v$($highestMinor.major).$($highestMinor.minor) --force"
            }
            else
            {
                $suggestedCommands += "git push origin $patchSha`:refs/tags/v$($highestMinor.major).$($highestMinor.minor) --force"
            }
        }
    }
}

# For the "latest" tag, use the highest non-prerelease version globally
$globalHighestPatchVersion = ($versionsForCalculation | 
    ForEach-Object{ ConvertTo-Version "$($_.semver.major).$($_.semver.minor).$($_.semver.build)" } | 
    Select-Object -Unique | 
    Measure-Object -Max).Maximum

$highestVersion = $versionsForCalculation | 
    Where-Object{ $_.version -eq "v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build)" } | 
    Select-Object -First 1 

if ($latest -and ($latest.sha -ne $highestVersion.sha))
{
    write-actions-error "::error title=Incorrect version::Version: latest ref $($latest.sha) must match: v$($globalHighestPatchVersion.major).$($globalHighestPatchVersion.minor).$($globalHighestPatchVersion.build) ref $($highestVersion.sha)"
    $suggestedCommands += "git push origin $($highestVersion.sha):latest --force"
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
