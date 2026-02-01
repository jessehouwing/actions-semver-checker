#############################################################################
# ReleaseRulesHelper.ps1 - Shared helper functions for release rules
#############################################################################

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
function Get-DuplicateReleaseIds {
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
function Get-DuplicateDraftReleases {
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
