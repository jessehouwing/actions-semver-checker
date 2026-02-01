#############################################################################
# ReleaseRulesHelper.ps1 - Shared helper functions for release rules
#############################################################################

<#
.SYNOPSIS
    Determines if a release should be marked as "latest" when created or published.

.DESCRIPTION
    Checks if the given version should become the "latest" release based on:
    1. It must be a valid patch version (vX.Y.Z)
    2. It must not be a prerelease (checked via ReleaseInfo if available)
    3. It must be the highest non-prerelease, non-ignored patch version

.PARAMETER State
    The RepositoryState object containing all releases and tags.

.PARAMETER Version
    The version string to check (e.g., "v1.0.0").

.PARAMETER ReleaseInfo
    Optional ReleaseInfo object for the release being created/published.
    Used to check prerelease status.

.OUTPUTS
    $true if the release should become latest, $false otherwise.
#>
function Test-ShouldBeLatestRelease {
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        [Parameter(Mandatory)]
        [string]$Version,
        [Parameter(Mandatory = $false)]
        [ReleaseInfo]$ReleaseInfo = $null
    )
    
    # Must be a valid patch version
    if ($Version -notmatch '^v(\d+)\.(\d+)\.(\d+)$') {
        return $false
    }
    
    $targetMajor = [int]$Matches[1]
    $targetMinor = [int]$Matches[2]
    $targetPatch = [int]$Matches[3]
    
    # If this release is a prerelease, it should NOT become latest
    if ($ReleaseInfo -and $ReleaseInfo.IsPrerelease) {
        return $false
    }
    
    # Find all existing published, non-prerelease, non-ignored patch releases
    $eligibleReleases = $State.Releases | Where-Object {
        -not $_.IsDraft -and
        -not $_.IsPrerelease -and
        -not $_.IsIgnored -and
        $_.TagName -match '^v(\d+)\.(\d+)\.(\d+)$'
    }
    
    # Parse versions and find the highest existing release
    $highestExisting = $null
    $highestMajor = -1
    $highestMinor = -1
    $highestPatch = -1
    
    foreach ($release in $eligibleReleases) {
        if ($release.TagName -match '^v(\d+)\.(\d+)\.(\d+)$') {
            $major = [int]$Matches[1]
            $minor = [int]$Matches[2]
            $patch = [int]$Matches[3]
            
            if ($major -gt $highestMajor -or
                ($major -eq $highestMajor -and $minor -gt $highestMinor) -or
                ($major -eq $highestMajor -and $minor -eq $highestMinor -and $patch -gt $highestPatch)) {
                $highestMajor = $major
                $highestMinor = $minor
                $highestPatch = $patch
                $highestExisting = $release
            }
        }
    }
    
    # Compare target version against highest existing
    # If target is higher, it should become latest
    if ($null -eq $highestExisting) {
        # No existing eligible releases, this should become latest
        return $true
    }
    
    if ($targetMajor -gt $highestMajor -or
        ($targetMajor -eq $highestMajor -and $targetMinor -gt $highestMinor) -or
        ($targetMajor -eq $highestMajor -and $targetMinor -eq $highestMinor -and $targetPatch -gt $highestPatch)) {
        # Target is higher than any existing release
        return $true
    }
    
    # Target is not the highest, should NOT become latest
    return $false
}

<#
.SYNOPSIS
    Gets the IDs of duplicate releases that should be deleted.

.DESCRIPTION
    Identifies duplicate releases (multiple releases for the same patch version tag)
    and returns the IDs of releases that should be deleted. The "best" release is kept
    based on these criteria (in order):
    1. Published releases are preferred over drafts
    2. Immutable releases are preferred over mutable
    3. Older releases (lower ID) are preferred over newer

.PARAMETER State
    The RepositoryState object containing all releases.

.OUTPUTS
    An array of release IDs that are duplicates and should be deleted.
#>
function Get-DuplicateReleaseId {
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State
    )
    
    $duplicateReleaseIds = @()
    
    # Get all patch releases (not ignored)
    $patchReleases = $State.Releases | Where-Object {
        -not $_.IsIgnored -and $_.TagName -match '^v\d+\.\d+\.\d+$'
    }
    
    # Group by tag name to find duplicates
    $releasesByTag = $patchReleases | Group-Object -Property TagName
    
    foreach ($group in $releasesByTag) {
        if ($group.Count -gt 1) {
            $releases = $group.Group
            
            # Sort to find which release to keep:
            # 1. Prefer published (non-draft) over draft
            # 2. Prefer immutable over mutable
            # 3. Keep the one with the lowest ID (oldest)
            $sortedReleases = $releases | Sort-Object -Property @(
                @{ Expression = { -not $_.IsDraft }; Descending = $true }
                @{ Expression = { $_.IsImmutable }; Descending = $true }
                @{ Expression = { $_.Id }; Ascending = $true }
            )
            
            # Mark all but the first as duplicates
            $duplicates = $sortedReleases | Select-Object -Skip 1
            $duplicateReleaseIds += $duplicates.Id
        }
    }
    
    return $duplicateReleaseIds
}

<#
.SYNOPSIS
    Gets duplicate draft releases that can be deleted.

.DESCRIPTION
    Returns the ReleaseInfo objects for duplicate draft releases that should be deleted.
    Only draft releases are returned since published/immutable releases cannot be deleted.

.PARAMETER State
    The RepositoryState object containing all releases.

.OUTPUTS
    An array of ReleaseInfo objects for duplicate drafts that should be deleted.
#>
function Get-DuplicateDraftRelease {
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State
    )
    
    $duplicatesToDelete = @()
    
    # Get all patch releases (not ignored)
    $patchReleases = $State.Releases | Where-Object {
        -not $_.IsIgnored -and $_.TagName -match '^v\d+\.\d+\.\d+$'
    }
    
    # Group by tag name to find duplicates
    $releasesByTag = $patchReleases | Group-Object -Property TagName
    
    foreach ($group in $releasesByTag) {
        if ($group.Count -gt 1) {
            $releases = $group.Group
            
            # Sort to find which release to keep
            $sortedReleases = $releases | Sort-Object -Property @(
                @{ Expression = { -not $_.IsDraft }; Descending = $true }
                @{ Expression = { $_.IsImmutable }; Descending = $true }
                @{ Expression = { $_.Id }; Ascending = $true }
            )
            
            # Get duplicates (all but the first), but only drafts can be deleted
            $duplicates = $sortedReleases | Select-Object -Skip 1 | Where-Object { $_.IsDraft }
            $duplicatesToDelete += $duplicates
        }
    }
    
    return $duplicatesToDelete
}
