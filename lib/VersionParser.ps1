#############################################################################
# VersionParser.ps1 - Version Parsing Utilities
#############################################################################
# This module provides utilities for parsing and comparing version strings.
#############################################################################

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
