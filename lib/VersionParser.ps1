#############################################################################
# VersionParser.ps1 - Version Parsing Utilities
#############################################################################
# This module provides utilities for parsing and comparing version strings.
# Only 3-part semantic versions (major.minor.patch) are supported.
#############################################################################

function ConvertTo-Version
{
    <#
    .SYNOPSIS
    Converts a version string to a [Version] object with 3 parts (major.minor.patch).
    
    .DESCRIPTION
    Parses version strings and normalizes them to 3-part versions.
    Only supports versions with 0, 1, 2, or 3 numeric components.
    - "1" becomes 1.0.0
    - "1.2" becomes 1.2.0
    - "1.2.3" stays 1.2.3
    - Versions with 4+ components are truncated to first 3 parts
    
    .PARAMETER Value
    The version string to parse. Must contain only numeric components separated by dots.
    
    .OUTPUTS
    A [Version] object with major, minor, and build (patch) components.
    
    .EXAMPLE
    ConvertTo-Version "1.2.3"  # Returns [Version]1.2.3
    ConvertTo-Version "2.0"    # Returns [Version]2.0.0
    ConvertTo-Version "3"      # Returns [Version]3.0.0
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $Value
    )

    # Handle invalid input
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Version value cannot be null or empty"
    }

    $dots = $Value.Split(".").Count - 1

    switch ($dots)
    {
        0
        {
            return [Version]"$Value.0.0"
        }
        1
        {
            return [Version]"$Value.0"
        }
        2
        {
            return [Version]$Value
        }
        default
        {
            # For versions with more than 2 dots, truncate to first 3 parts
            $parts = $Value.Split(".") | Select-Object -First 3
            return [Version]($parts -join ".")
        }
    }
}

function Test-ValidVersionPattern
{
    <#
    .SYNOPSIS
    Validates that a version pattern is safe and well-formed.
    
    .DESCRIPTION
    Checks version patterns for:
    - Valid format (vX, vX.Y, vX.Y.Z, or wildcard patterns like v1.*)
    - ReDoS safety (prevents malicious patterns that could cause regex catastrophic backtracking)
    
    .PARAMETER Pattern
    The version pattern to validate.
    
    .OUTPUTS
    Returns $true if the pattern is valid and safe, $false otherwise.
    
    .EXAMPLE
    Test-ValidVersionPattern "v1.0.0"   # Returns $true
    Test-ValidVersionPattern "v1.*"     # Returns $true
    Test-ValidVersionPattern "v1.*.0"   # Returns $false (invalid)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Pattern
    )
    
    # Maximum length check to prevent DoS via extremely long patterns
    if ($Pattern.Length -gt 50) {
        return $false
    }
    
    # Only allow simple patterns: vX, vX.Y, vX.Y.Z, or wildcards like v1.*, v1.0.*
    # Uses possessive-style matching via atomic groups where possible
    if ($Pattern -match '^v\d{1,10}(\.\d{1,10}){0,2}(\.\*)?$' -or $Pattern -match '^v\d{1,10}\.\*$') {
        return $true
    }
    
    return $false
}

function Test-VersionIgnored {
    <#
    .SYNOPSIS
    Check if a version should be ignored based on the ignore-versions configuration.
    
    .PARAMETER Version
    The version string to check (e.g., "v1.0.0").
    
    .PARAMETER IgnoreVersions
    Array of version patterns to ignore.
    
    .OUTPUTS
    Returns $true if the version should be ignored, $false otherwise.
    #>
    param(
        [string]$Version,
        [string[]]$IgnoreVersions
    )
    
    if (-not $IgnoreVersions -or $IgnoreVersions.Count -eq 0) {
        return $false
    }
    
    foreach ($pattern in $IgnoreVersions) {
        # Exact match
        if ($Version -eq $pattern) {
            Write-Host "::debug::Ignoring version $Version (matches ignore pattern: $pattern)"
            return $true
        }
        
        # Support wildcard patterns (e.g., "v1.*" matches "v1.0.0", "v1.1.0", etc.)
        if ($pattern -match '\*') {
            $regexPattern = '^' + [regex]::Escape($pattern).Replace('\*', '.*') + '$'
            if ($Version -match $regexPattern) {
                Write-Host "::debug::Ignoring version $Version (matches wildcard pattern: $pattern)"
                return $true
            }
        }
    }
    
    return $false
}