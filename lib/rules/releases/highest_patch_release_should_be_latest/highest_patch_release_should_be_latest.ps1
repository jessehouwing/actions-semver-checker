#############################################################################
# Rule: highest_patch_release_should_be_latest
# Category: releases
# Priority: 15
#############################################################################
# This rule ensures that the correct release is marked as "latest" in GitHub.
# The latest release should be the highest non-prerelease, non-draft patch version.
#############################################################################

$Rule_HighestPatchReleaseShouldBeLatest = [ValidationRule]@{
    Name = "highest_patch_release_should_be_latest"
    Description = "Ensures the correct release is marked as 'latest' (highest non-prerelease patch)"
    Priority = 15  # Run after other release rules
    Category = "releases"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when check-releases is enabled
        $checkReleases = $Config.'check-releases'
        if ($checkReleases -ne 'error' -and $checkReleases -ne 'warning') {
            return @()
        }
        
        # Find all published, non-prerelease, non-ignored patch releases
        $eligibleReleases = $State.Releases | Where-Object {
            -not $_.IsDraft -and
            -not $_.IsPrerelease -and
            -not $_.IsIgnored -and
            $_.TagName -match '^v(\d+)\.(\d+)\.(\d+)$'
        }
        
        if (-not $eligibleReleases -or $eligibleReleases.Count -eq 0) {
            return @()
        }
        
        # Parse versions and find the highest
        $releasesWithVersions = $eligibleReleases | ForEach-Object {
            $release = $_
            if ($release.TagName -match '^v(\d+)\.(\d+)\.(\d+)$') {
                [PSCustomObject]@{
                    Release = $release
                    Major = [int]$Matches[1]
                    Minor = [int]$Matches[2]
                    Patch = [int]$Matches[3]
                }
            }
        } | Where-Object { $_ }
        
        if (-not $releasesWithVersions -or $releasesWithVersions.Count -eq 0) {
            return @()
        }
        
        # Sort by version (descending) to find the highest
        $sortedReleases = $releasesWithVersions | Sort-Object -Property @(
            @{ Expression = { $_.Major }; Descending = $true }
            @{ Expression = { $_.Minor }; Descending = $true }
            @{ Expression = { $_.Patch }; Descending = $true }
        )
        
        $expectedLatestRelease = $sortedReleases[0].Release
        
        # Find the currently marked "latest" release
        $currentLatest = $State.Releases | Where-Object { $_.IsLatest } | Select-Object -First 1
        
        # Return a single object with both expected and current latest
        return @{
            ExpectedLatest = $expectedLatestRelease
            CurrentLatest = $currentLatest
        }
    }
    
    Check = { param($Item, [RepositoryState]$State, [hashtable]$Config)
        # Item is a hashtable with ExpectedLatest and CurrentLatest
        $expectedLatest = $Item.ExpectedLatest
        $currentLatest = $Item.CurrentLatest
        
        # Check if the expected latest is already marked as latest
        if ($currentLatest -and $expectedLatest.TagName -eq $currentLatest.TagName) {
            return $true
        }
        
        # Also check if the expected release has IsLatest set
        if ($expectedLatest.IsLatest) {
            return $true
        }
        
        return $false
    }
    
    CreateIssue = { param($Item, [RepositoryState]$State, [hashtable]$Config)
        $expectedLatest = $Item.ExpectedLatest
        $currentLatest = $Item.CurrentLatest
        $version = $expectedLatest.TagName
        
        $severity = if ($Config.'check-releases' -eq 'warning') { 'warning' } else { 'error' }
        
        # Create appropriate message
        if ($currentLatest) {
            $message = "Release $version should be marked as 'latest', but $($currentLatest.TagName) is currently marked as latest"
        } else {
            $message = "Release $version should be marked as 'latest', but no release is currently marked as latest"
        }
        
        $issue = [ValidationIssue]::new(
            "wrong_latest_release",
            $severity,
            $message
        )
        $issue.Version = $version
        
        # SetLatestReleaseAction constructor: tagName, releaseId
        $issue.RemediationAction = [SetLatestReleaseAction]::new($version, $expectedLatest.Id)
        
        return $issue
    }
}

# Export the rule
$Rule_HighestPatchReleaseShouldBeLatest
