#############################################################################
# InputValidation.ps1 - Input parsing and validation functions
#############################################################################
# This module contains functions for parsing and validating action inputs.
# It handles normalization, type conversion, and validation of all inputs
# passed to the action via the inputs environment variable.
#############################################################################

<#
.SYNOPSIS
Normalizes check input values to standard format (error/warning/none).

.DESCRIPTION
Accepts boolean or string values and normalizes them to the standard
check level format used throughout the action.

.PARAMETER Value
The input value to normalize (can be boolean string or level string).

.PARAMETER Default
The default value if the input is null or empty.

.OUTPUTS
String - One of: "error", "warning", "none"
#>
function ConvertTo-CheckLevel {
    param(
        [string]$Value,
        [string]$Default = "error"
    )
    
    $normalized = ($Value ?? $Default).Trim().ToLower()
    
    # Map boolean values to error/none
    if ($normalized -eq "true") {
        return "error"
    } elseif ($normalized -eq "false") {
        return "none"
    }
    
    return $normalized
}

<#
.SYNOPSIS
Parses the ignore-versions input into an array of version patterns.

.DESCRIPTION
Supports multiple input formats:
1. Comma-separated: "v1.0.0, v2.0.0"
2. Line-separated (newlines): "v1.0.0\nv2.0.0"
3. JSON array: ["v1.0.0", "v2.0.0"]

Each version pattern is validated using Test-ValidVersionPattern.

.PARAMETER RawInput
The raw input value from the action inputs.

.OUTPUTS
Array of validated version patterns.
#>
function ConvertTo-IgnoreVersionsList {
    param(
        $RawInput
    )
    
    $ignoreVersions = @()
    
    if (-not $RawInput) {
        return $ignoreVersions
    }
    
    $rawVersions = @()
    
    # Check if it's a JSON array (either already parsed or as string)
    if ($RawInput -is [array]) {
        # Already parsed as array by ConvertFrom-Json
        $rawVersions = $RawInput
    }
    elseif ($RawInput -is [string]) {
        $trimmedInput = $RawInput.Trim()
        
        # Check if it looks like a JSON array
        if ($trimmedInput.StartsWith('[') -and $trimmedInput.EndsWith(']')) {
            try {
                $parsed = $trimmedInput | ConvertFrom-Json
                if ($parsed -is [array]) {
                    $rawVersions = $parsed
                }
            }
            catch {
                Write-Host "::warning title=Invalid JSON in ignore-versions::Failed to parse JSON array. Treating as comma/newline-separated list."
                # Fall through to comma/newline parsing
            }
        }
        
        # If not parsed as JSON array, split by comma and newline
        if ($rawVersions.Count -eq 0 -and $trimmedInput) {
            $rawVersions = $trimmedInput -split '[,\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }
    }
    
    # Validate each version pattern using Test-ValidVersionPattern for ReDoS prevention
    foreach ($ver in $rawVersions) {
        $verTrimmed = "$ver".Trim()
        if (-not $verTrimmed) { continue }
        
        # Use safe validation function that prevents ReDoS attacks
        if (Test-ValidVersionPattern -Pattern $verTrimmed) {
            $ignoreVersions += $verTrimmed
        } else {
            Write-Host "::warning title=Invalid ignore-versions pattern::Pattern '$verTrimmed' does not match expected format (vX, vX.Y, vX.Y.Z, or wildcard like v1.*). Skipping."
        }
    }
    
    return $ignoreVersions
}

<#
.SYNOPSIS
Parses and validates all action inputs from JSON.

.DESCRIPTION
Reads the inputs JSON environment variable, parses all inputs with defaults,
validates them, and returns a hashtable with all parsed values.

.PARAMETER State
The RepositoryState object to update with configuration values.

.OUTPUTS
Hashtable with all parsed and validated input values.

.EXAMPLE
$config = Read-ActionInput -State $script:State
#>
function Read-ActionInput {
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State
    )
    
    # Read inputs from JSON environment variable
    if (-not $env:inputs) {
        Write-Host "::error::inputs environment variable is not set"
        return $null
    }
    
    try {
        $inputs = $env:inputs | ConvertFrom-Json
    }
    catch {
        Write-Host "::error::Failed to parse inputs JSON"
        return $null
    }
    
    # Parse token (treat empty/whitespace as not provided)
    $tokenInput = $inputs.token
    if ([string]::IsNullOrWhiteSpace($tokenInput)) {
        $token = $State.Token
    } else {
        $token = $tokenInput
    }
    
    # SECURITY: Mask the token if it was provided via input (may be different from env var)
    if (-not [string]::IsNullOrWhiteSpace($tokenInput) -and $tokenInput -ne $env:GITHUB_TOKEN) {
        Write-Host "::add-mask::$($tokenInput)"
    }
    
    # Parse check levels
    $checkMinorVersion = ConvertTo-CheckLevel -Value (($inputs.'check-minor-version' ?? "true") -as [string]) -Default "error"
    $checkReleases = ConvertTo-CheckLevel -Value (($inputs.'check-releases' ?? "error") -as [string]) -Default "error"
    $checkReleaseImmutability = ConvertTo-CheckLevel -Value (($inputs.'check-release-immutability' ?? "error") -as [string]) -Default "error"
    
    # Parse boolean inputs
    $ignorePreviewReleases = (($inputs.'ignore-preview-releases' ?? "true") -as [string]).Trim() -eq "true"
    $autoFix = (($inputs.'auto-fix' ?? "false") -as [string]).Trim() -eq "true"
    
    # Parse string inputs
    $floatingVersionsUse = (($inputs.'floating-versions-use' ?? "tags") -as [string]).Trim().ToLower()
    
    # Parse ignore-versions list
    $ignoreVersions = ConvertTo-IgnoreVersionsList -RawInput $inputs.'ignore-versions'
    
    if ($ignoreVersions.Count -gt 0) {
        Write-Host "::debug::Ignoring versions: $($ignoreVersions -join ', ')"
    }
    
    # Return parsed config
    return @{
        Token                    = $token
        CheckMinorVersion        = $checkMinorVersion
        CheckReleases            = $checkReleases
        CheckReleaseImmutability = $checkReleaseImmutability
        IgnorePreviewReleases    = $ignorePreviewReleases
        FloatingVersionsUse      = $floatingVersionsUse
        AutoFix                  = $autoFix
        IgnoreVersions           = $ignoreVersions
    }
}

<#
.SYNOPSIS
Validates parsed input values and returns errors if invalid.

.DESCRIPTION
Checks that all input values are within their allowed ranges/values.
Returns an array of error messages, or empty array if all valid.

.PARAMETER Config
Hashtable of parsed input values from Read-ActionInput.

.OUTPUTS
Array of error message strings. Empty if all inputs are valid.
#>
function Test-ActionInput {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    
    $errors = @()
    
    if ($Config.CheckMinorVersion -notin @("error", "warning", "none")) {
        $errors += "::error title=Invalid configuration::check-minor-version must be 'error', 'warning', 'none', 'true', or 'false', got '$($Config.CheckMinorVersion)'"
    }
    
    if ($Config.CheckReleases -notin @("error", "warning", "none")) {
        $errors += "::error title=Invalid configuration::check-releases must be 'error', 'warning', 'none', 'true', or 'false', got '$($Config.CheckReleases)'"
    }
    
    if ($Config.CheckReleaseImmutability -notin @("error", "warning", "none")) {
        $errors += "::error title=Invalid configuration::check-release-immutability must be 'error', 'warning', 'none', 'true', or 'false', got '$($Config.CheckReleaseImmutability)'"
    }
    
    if ($Config.FloatingVersionsUse -notin @("tags", "branches")) {
        $errors += "::error title=Invalid configuration::floating-versions-use must be either 'tags' or 'branches', got '$($Config.FloatingVersionsUse)'"
    }
    
    return $errors
}

<#
.SYNOPSIS
Writes debug output showing all parsed input values.

.PARAMETER Config
Hashtable of parsed input values.
#>
function Write-InputDebugInfo {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    
    Write-Host "::debug::=== Parsed Input Values ==="
    Write-Host "::debug::auto-fix: $($Config.AutoFix)"
    Write-Host "::debug::check-minor-version: $($Config.CheckMinorVersion)"
    Write-Host "::debug::check-releases: $($Config.CheckReleases)"
    Write-Host "::debug::check-release-immutability: $($Config.CheckReleaseImmutability)"
    Write-Host "::debug::ignore-preview-releases: $($Config.IgnorePreviewReleases)"
    Write-Host "::debug::floating-versions-use: $($Config.FloatingVersionsUse)"
    Write-Host "::debug::ignore-versions: $($Config.IgnoreVersions -join ', ')"
}

<#
.SYNOPSIS
Writes debug output showing repository configuration.

.PARAMETER State
The RepositoryState object.

.PARAMETER Config
Hashtable of parsed input values.
#>
function Write-RepositoryDebugInfo {
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    
    Write-Host "::debug::Repository: $($State.RepoOwner)/$($State.RepoName)"
    Write-Host "::debug::API URL: $($State.ApiUrl)"
    Write-Host "::debug::Server URL: $($State.ServerUrl)"
    Write-Host "::debug::Token available: $(if ($State.Token) { 'Yes' } else { 'No' })"
    Write-Host "::debug::Check releases: $($Config.CheckReleases)"
    Write-Host "::debug::Check release immutability: $($Config.CheckReleaseImmutability)"
    Write-Host "::debug::Floating versions use: $($Config.FloatingVersionsUse)"
}

<#
.SYNOPSIS
Validates that auto-fix mode has required token.

.PARAMETER State
The RepositoryState object.

.PARAMETER AutoFix
Whether auto-fix mode is enabled.

.OUTPUTS
Boolean - True if valid, False if auto-fix enabled without token.
#>
function Test-AutoFixRequirement {
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        
        [Parameter(Mandatory)]
        [bool]$AutoFix
    )
    
    if ($AutoFix) {
        if (-not $State.Token) {
            # Use Write-Host for GitHub Actions error annotation (visible in Actions UI)
            Write-Host "::error title=Auto-fix requires token::Auto-fix mode is enabled but no GitHub token is available. Please provide a token via the 'token' input or ensure GITHUB_TOKEN is available.%0A%0AExample:%0A  - uses: jessehouwing/actions-semver-checker@v2%0A    with:%0A      auto-fix: true%0A      token: `${{ secrets.GITHUB_TOKEN }}"
            return $false
        }
        Write-Host "::debug::Auto-fix mode enabled with token"
    }
    
    return $true
}
