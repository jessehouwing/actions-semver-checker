#############################################################################
# Rule: major_tag_missing
# Category: version_tracking
# Priority: 21
#############################################################################

$Rule_MajorTagMissing = [ValidationRule]@{
    Name = "major_tag_missing"
    Description = "Major version tags should exist for all major versions that have patches"
    Priority = 21
    Category = "version_tracking"

    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when using tags for floating versions (default)
        $floatingVersionsUse = $Config.'floating-versions-use'
        if ($floatingVersionsUse -eq 'branches') {
            return @()
        }

        # Get all unique major numbers from patch versions
        # Filter out prereleases if ignore-preview-releases is enabled
        $allRefs = $State.Tags + $State.Branches
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $patchVersions = $allRefs | Where-Object {
            $_.IsPatch -and
            -not $_.IsIgnored -and
            (-not $ignorePreviewReleases -or -not (Test-IsPrerelease -State $State -VersionRef $_))
        }

        if ($patchVersions.Count -eq 0) {
            return @()
        }

        $majorNumbers = $patchVersions | ForEach-Object { $_.Major } | Select-Object -Unique | Sort-Object

        # Find which major versions don't have a major tag
        $missingMajors = @()
        foreach ($major in $majorNumbers) {
            $majorRef = ($State.Tags + $State.Branches) | Where-Object {
                $_.Version -eq "v$major" -and -not $_.IsIgnored
            } | Select-Object -First 1
            if ($null -eq $majorRef) {
                # Create a synthetic object representing the missing major version
                $missingMajors += [PSCustomObject]@{
                    Major = $major
                }
            }
        }

        return $missingMajors
    }

    Check = { param([PSCustomObject]$Item, [RepositoryState]$State, [hashtable]$Config)
        # If we got here from Condition, the major tag is missing
        return $false
    }

    CreateIssue = { param([PSCustomObject]$Item, [RepositoryState]$State, [hashtable]$Config)
        $major = $Item.Major
        $version = "v$major"

        # Get the highest patch for this major version
        $ignorePreviewReleases = $Config.'ignore-preview-releases'
        $highestPatch = Get-HighestPatchForMajor -State $State -Major $major -ExcludePrereleases $ignorePreviewReleases

        $issue = [ValidationIssue]::new(
            "missing_major_version",
            "error",
            "$version does not exist. It should point to $($highestPatch.Version) at $($highestPatch.Sha)"
        )
        $issue.Version = $version
        $issue.ExpectedSha = $highestPatch.Sha

        # CreateTagAction constructor: tagName, sha
        $issue.RemediationAction = [CreateTagAction]::new($version, $highestPatch.Sha)

        return $issue
    }
}

# Export the rule
$Rule_MajorTagMissing
