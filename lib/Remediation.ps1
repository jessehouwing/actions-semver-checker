#############################################################################
# Remediation.ps1 - Auto-fix and Remediation Functions
#############################################################################
# This module provides functions for auto-fixing validation issues and
# generating manual remediation commands.
#############################################################################

function Invoke-AutoFix
{
    param(
        [string]$Description,
        [string]$Command,
        [scriptblock]$ApiAction = $null,
        [bool]$AutoFix = $false
    )
    
    # Use parameter if provided, otherwise fall back to script-level variable
    $shouldAutoFix = if ($PSBoundParameters.ContainsKey('AutoFix')) { $AutoFix } else { $script:autoFix ?? $false }
    
    if (-not $shouldAutoFix)
    {
        return $false  # Not in auto-fix mode
    }
    
    Write-Host "Auto-fix: $Description"
    
    try
    {
        # If an API action is provided, use it instead of the command
        if ($ApiAction) {
            Write-Host "::debug::Executing via REST API"
            $success = & $ApiAction
            
            if ($success) {
                Write-Host "✓ Success: $Description"
                return $true
            }
            else {
                Write-Host "✗ Failed: $Description"
                Write-Host "::error::REST API call failed for: $Description"
                return $false
            }
        }
        else {
            # Fallback to executing the command (for non-git operations like gh CLI)
            Write-Host "Executing: $Command"
            
            # Reset LASTEXITCODE to ensure we're not seeing a stale value
            $global:LASTEXITCODE = 0
            
            # Execute the command and capture both stdout and stderr
            # The 2>&1 redirects stderr to stdout, ensuring we capture all output
            $commandOutput = Invoke-Expression $Command 2>&1
            
            if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -eq 0)
            {
                Write-Host "✓ Success: $Description"
                # Log command output as debug using GitHub Actions workflow command
                # Wrap output in stop-commands to prevent workflow command injection
                if ($commandOutput) {
                    Write-SafeOutput -Message ([string]$commandOutput) -Prefix "::debug::Command succeeded with output: "
                }
                return $true
            }
            else
            {
                Write-Host "✗ Failed: $Description (exit code: $LASTEXITCODE)"
                # Log error output prominently using GitHub Actions error command
                # Wrap output in stop-commands to prevent workflow command injection
                if ($commandOutput) {
                    Write-SafeOutput -Message ([string]$commandOutput) -Prefix "::error::Command failed: "
                }
                else {
                    # If no output captured, still log that the command failed
                    Write-Host "::error::Command failed with no output (exit code: $LASTEXITCODE)"
                }
                return $false
            }
        }
    }
    catch
    {
        Write-Host "✗ Failed: $Description"
        # Wrap exception message in stop-commands to prevent workflow command injection
        Write-SafeOutput -Message ([string]$_) -Prefix "::error::Exception: "
        return $false
    }
}

function Get-ImmutableReleaseRemediationCommands
{
    param(
        [string]$TagName
    )
    
    $commands = @()
    
    # The tag is already used by an immutable release
    # The only solution is to delete the release and create a new version
    # This function expects semantic version tags in the format vX.Y.Z
    if ($TagName -match "^v(\d+)\.(\d+)\.(\d+)$") {
        $major = $matches[1]
        $minor = $matches[2]
        $patch = [int]$matches[3] + 1
        $nextVersion = "v$major.$minor.$patch"
        
        $commands += "# Delete the immutable release (if possible) and create a new version:"
        $commands += "gh release delete $TagName --yes"
        $commands += "git tag -d $TagName"
        $commands += "git push origin :refs/tags/$TagName"
        $commands += "# Create new patch version $nextVersion with updated changes:"
        $commands += "git tag $nextVersion"
        $commands += "git push origin $nextVersion"
        $commands += "gh release create $nextVersion --draft --title `"$nextVersion`" --notes `"Release $nextVersion`""
        $commands += "gh release edit $nextVersion --draft=false"
    }
    else {
        # Tag doesn't match expected vX.Y.Z format
        $commands += "# Manual remediation required for tag: $TagName"
        $commands += "# The tag is used by an immutable release. You must delete the release and tag, then create a new version."
        $commands += "gh release delete $TagName --yes"
        $commands += "git tag -d $TagName"
        $commands += "git push origin :refs/tags/$TagName"
    }
    
    return $commands
}
