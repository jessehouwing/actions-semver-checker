#############################################################################
# VersionParser.ps1 - Version Parsing Utilities
#############################################################################
# This module provides utilities for parsing and comparing version strings.
#############################################################################

function ConvertTo-Version
{
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $value
    )

    # Handle invalid input
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Version value cannot be null or empty"
    }

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
        default
        {
            # For versions with more than 2 dots, truncate to first 3 parts
            $parts = $value.Split(".") | Select-Object -First 3
            return [Version]($parts -join ".")
        }
    }
}
