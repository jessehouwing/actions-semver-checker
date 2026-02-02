#############################################################################
# MarketplaceRulesHelper.ps1 - Helper functions for marketplace validation rules
#############################################################################
# This module provides shared helper functions used by marketplace validation rules.
#############################################################################

<#
.SYNOPSIS
Converts an action name to a GitHub Marketplace URL slug.

.DESCRIPTION
GitHub Marketplace uses a URL-friendly slug derived from the action's name property.
The slug is lowercase with spaces replaced by hyphens and special characters removed.

.PARAMETER ActionName
The action name from action.yaml (e.g., "Actions SemVer Checker")

.OUTPUTS
The marketplace URL slug (e.g., "actions-semver-checker")
#>
function ConvertTo-MarketplaceSlug {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ActionName
    )
    
    # Convert to lowercase, replace spaces with hyphens, remove non-alphanumeric except hyphens
    $slug = $ActionName.ToLower() -replace '\s+', '-' -replace '[^a-z0-9\-]', ''
    # Remove consecutive hyphens and trim leading/trailing hyphens
    $slug = $slug -replace '-+', '-' -replace '^-|-$', ''
    
    return $slug
}

<#
.SYNOPSIS
Tests if a specific version of an action is published to GitHub Marketplace.

.DESCRIPTION
Queries the public GitHub Marketplace URL to check if a specific version
of an action has been published. The marketplace URL is:
https://github.com/marketplace/actions/{slug}?version={version}

When a version is published, the page shows "Use {version}" in the UI.
When a version is not published, it falls back to "Use latest version".

.PARAMETER ActionName
The action name from action.yaml (e.g., "Actions SemVer Checker")

.PARAMETER Version
The version tag to check (e.g., "v2.0.0")

.PARAMETER ServerUrl
The GitHub server URL (default: https://github.com). Used for GitHub Enterprise Server.

.OUTPUTS
Returns a PSCustomObject with:
- IsPublished: $true if the version is published to the marketplace
- MarketplaceUrl: The full marketplace URL for this version
- Error: Error message if the check failed, $null otherwise
#>
function Test-MarketplaceVersionPublished {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$ActionName,
        
        [Parameter(Mandatory)]
        [string]$Version,
        
        [string]$ServerUrl = "https://github.com"
    )
    
    $slug = ConvertTo-MarketplaceSlug -ActionName $ActionName
    $marketplaceUrl = "$ServerUrl/marketplace/actions/$slug"
    $versionUrl = "$marketplaceUrl`?version=$Version"
    
    try {
        # Use Invoke-WebRequestWrapper if available (for testability)
        $response = $null
        if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
            $response = Invoke-WebRequestWrapper -Uri $versionUrl -Method Get -ErrorAction Stop -TimeoutSec 10
        } else {
            $response = Invoke-WebRequest -Uri $versionUrl -Method Get -ErrorAction Stop -TimeoutSec 10
        }
        
        # Get content - handle both raw response and wrapped response
        $content = if ($response.Content) { $response.Content } else { $response }
        
        # Check if the page shows "Use {version}" which indicates the version is published
        # When not published, it shows "Use latest version" instead
        $escapedVersion = [regex]::Escape($Version)
        
        # Try multiple patterns to match different GitHub Marketplace UI formats
        $patterns = @(
            "data-version=[`"']$escapedVersion[`"']",     # data-version="v1.0.9" or data-version='v1.0.9'
            "value=[`"']$escapedVersion[`"']",            # value="v1.0.9"
            "version=[`"']$escapedVersion[`"']",          # version="v1.0.9"  
            "<option[^>]*>$escapedVersion</option>"       # <option>v1.0.9</option>
        )
        
        $isPublished = $false
        foreach ($pattern in $patterns) {
            if ($content -match $pattern) {
                $isPublished = $true
                break
            }
        }
        
        return [PSCustomObject]@{
            IsPublished = $isPublished
            MarketplaceUrl = $versionUrl
            Error = $null
        }
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        
        # If we get a 404, the action is not in the marketplace at all
        if ($statusCode -eq 404) {
            return [PSCustomObject]@{
                IsPublished = $false
                MarketplaceUrl = $marketplaceUrl
                Error = "Action is not published to the GitHub Marketplace"
            }
        }
        
        # For other errors, return with error message but don't fail
        return [PSCustomObject]@{
            IsPublished = $null  # Unknown
            MarketplaceUrl = $marketplaceUrl
            Error = "Failed to check marketplace: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Fetches and parses action.yaml/action.yml marketplace metadata from the repository.

.DESCRIPTION
Attempts to fetch action.yaml first, then falls back to action.yml.
Parses the YAML content to extract marketplace-required fields:
- name
- description
- branding.icon
- branding.color

Also checks for README.md existence.

.PARAMETER State
The RepositoryState object containing API configuration.

.PARAMETER Ref
Optional. The commit, branch, or tag to get the metadata from. Defaults to the default branch.

.OUTPUTS
Returns a MarketplaceMetadata object with the parsed information.
#>
function Get-ActionMarketplaceMetadata {
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        
        [string]$Ref
    )
    
    $metadata = [MarketplaceMetadata]::new()
    
    # Try to fetch action.yaml first, then action.yml
    $actionContent = $null
    $actionPath = $null
    
    foreach ($path in @('action.yaml', 'action.yml')) {
        Write-Host "::debug::Checking for $path..."
        $content = Get-GitHubFileContents -State $State -Path $path -Ref $Ref
        if ($content) {
            $actionContent = $content
            $actionPath = $path
            Write-Host "::debug::Found $path"
            break
        }
    }
    
    if ($actionContent -and $actionPath) {
        $metadata.ActionFileExists = $true
        $metadata.ActionFilePath = $actionPath
        
        # Parse YAML content to extract required fields
        # Note: Using simple regex-based parsing since PowerShell doesn't have built-in YAML support
        # This handles common YAML formats without requiring external modules
        
        # Extract 'name' property (top-level)
        if ($actionContent -match '(?m)^name:\s*[''"]?([^''"#\r\n]+)[''"]?') {
            $metadata.Name = $matches[1].Trim()
            $metadata.HasName = $metadata.Name.Length -gt 0
        } elseif ($actionContent -match '(?m)^name:\s*$') {
            # Empty name
            $metadata.HasName = $false
        }
        
        # Extract 'description' property (top-level)
        if ($actionContent -match '(?m)^description:\s*[''"]?([^''"#\r\n]+)[''"]?') {
            $metadata.Description = $matches[1].Trim()
            $metadata.HasDescription = $metadata.Description.Length -gt 0
        } elseif ($actionContent -match "(?m)^description:\s*['`"]\|") {
            # Multi-line description (folded or literal block)
            $metadata.HasDescription = $true
            $metadata.Description = "(multi-line)"
        }
        
        # Extract 'branding.icon' property
        # Split into lines and look for icon after branding section
        $lines = $actionContent -split '[\r\n]+'
        $inBranding = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*branding:\s*$') {
                $inBranding = $true
                continue
            }
            if ($inBranding) {
                # Check if we're still in branding section (indented lines)
                if ($lines[$i] -match '^\s{2,}icon:\s*[''"]?([^''"#]+)[''"]?\s*$') {
                    $metadata.BrandingIcon = $matches[1].Trim()
                    $metadata.HasBrandingIcon = $metadata.BrandingIcon.Length -gt 0
                }
                elseif ($lines[$i] -match '^\s{2,}color:\s*[''"]?([^''"#]+)[''"]?\s*$') {
                    $metadata.BrandingColor = $matches[1].Trim()
                    $metadata.HasBrandingColor = $metadata.BrandingColor.Length -gt 0
                }
                elseif ($lines[$i] -match '^\S' -and $lines[$i] -notmatch '^\s*$') {
                    # Non-indented non-empty line = end of branding section
                    break
                }
            }
        }
    }
    
    # Check for README.md using directory listing (single API call with case-insensitive local match)
    $rootContents = Get-GitHubDirectoryContents -State $State -Ref $Ref
    $readmeFile = $rootContents | Where-Object { $_.Type -eq 'file' -and $_.Name -match '^readme(\.md)?$' } | Select-Object -First 1
    if ($readmeFile) {
        $metadata.ReadmeExists = $true
    }
    
    return $metadata
}
