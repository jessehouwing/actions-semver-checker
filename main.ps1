$global:returnCode = 0

$warnMinor = (${env:INPUT_CHECK-MINOR-VERSION} ?? "true").Trim() -eq "true"

$tags = & git tag -l v* | Where-Object{ return ($_ -match "v\d+(.\d+)*$") }

$branches = & git branch --list --quiet --remotes | Where-Object{ return ($_.Trim() -match "^origin/(v\d+(.\d+)*(-.*)?)$") } | ForEach-Object{ $_.Trim().Replace("origin/", "")}

$tagVersions = @()
$branchVersions = @()

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

foreach ($tag in $tags)
{
    $tagVersions += @{
        version = $tag
        ref = "refs/tags/$tag"
        sha = & git rev-list -n 1 $tag
        semver = ConvertTo-Version $tag.Substring(1)
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
    }
}

$allVersions = $branchVersions + $tagVersions

$majorVersions = $allVersions | 
    ForEach-Object{ ConvertTo-Version "$($_.semver.major)" } | 
    Select-Object -Unique

$minorVersions = $allVersions | 
    ForEach-Object{ ConvertTo-Version "$($_.semver.major).$($_.semver.minor)" } | 
    Select-Object -Unique

$patchVersions = $allVersions | 
    ForEach-Object{ ConvertTo-Version "$($_.semver.major).$($_.semver.minor).$($_.semver.build)" } | 
    Select-Object -Unique

foreach ($majorVersion in $majorVersions)
{
    $highestMinor = ($minorVersions | Where-Object{ $_.major -eq $majorVersion.major } | Measure-Object -Max).Maximum

    $majorSha = ($allVersions | 
        Where-Object{ $_.version -eq "v$($majorVersion.major)" } | 
        Select-Object -First 1).sha

    $minorSha = ($allVersions | 
        Where-Object{ $_.version -eq "v$($majorVersion.major).$($highestMinor.minor)" } | 
        Select-Object -First 1).sha

    if ($warnMinor)
    {
        if (-not $majorSha)
        {
            write-actions-error "::error title=Missing version::Version: v$($majorVersion.major) does not exist and must match: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha"
        }

        if ($warnMinor -and $minorSha -and ($majorSha -ne $minorSha))
        {
            write-actions-error "::error title=Incorrect version::Version: v$($majorVersion.major) ref $majorSha must match: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha"
        }
    }

    $highestPatch = ($patchVersions | 
        Where-Object{ $_.major -eq $highestMinor.major -and $_.minor -eq $highestMinor.minor } | 
        Measure-Object -Max).Maximum
    
    $majorSha = ($allVersions | 
        Where-Object{ $_.version -eq "v$($highestMinor.major)" } | 
        Select-Object -First 1).sha
    $minorSha = ($allVersions | 
        Where-Object{ $_.version -eq "v$($highestMinor.major).$($highestMinor.minor)" } | 
        Select-Object -First 1).sha
    $patchSha = ($allVersions | 
        Where-Object{ $_.version -eq "v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)" } | 
        Select-Object -First 1).sha
    
    if ($majorSha -and $patchSha -and ($majorSha -ne $patchSha))
    {
        write-actions-error "::error title=Incorrect version::Version: v$($highestMinor.major) ref $majorSha must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha"
    }

    if (-not $patchSha -and $majorSha)
    {
        write-actions-error "::error title=Missing version::Version: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) does not exist and must match: v$($highestPatch.major) ref $majorSha"
    }

    if (-not $majorSha)
    {
        write-actions-error "::error title=Missing version::Version: v$($majorVersion.major) does not exist and must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha"
    }

    if ($warnMinor -and -not $minorSha)
    {
        write-actions-error "::error title=Missing version::Version: v$($highestMinor.major).$($highestMinor.minor) does not exist must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha"
    }

    if ($minorSha -and ($minorSha -ne $patchSha))
    {
        write-actions-error "::error title=Incorrect version::Version: v$($highestMinor.major).$($highestMinor.minor) ref $minorSha must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $patchSha"
    }
}

$highestVersion = ($allVersions | 
    ForEach-Object{ ConvertTo-Version "$($_.semver.major).$($_.semver.minor).$($_.semver.build)" } | 
    Select-Object -Unique | 
    Measure-Object -Max).Maximum

$highestVersion = $allVersions | 
    Where-Object{ $_.version -eq "v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build)" } | 
    Select-Object -First 1 

if ($latest -and($latest.sha -ne $highestVersion.sha))
{
    write-actions-error "::error title=Incorrect version::Version: latest ref $($latest.sha) must match: v$($highestPatch.major).$($highestPatch.minor).$($highestPatch.build) ref $($highestVersion.sha)"
}

exit $global:returnCode
