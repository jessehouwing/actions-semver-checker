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
    
    if (-not $AutoFix)
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
        [string]$TagName,
        [RepositoryState]$State = $null
    )
    
    $commands = @()
    
    # The tag is already used by an immutable release
    # The only solution is to delete the release and create a new version
    # This function expects semantic version tags in the format vX.Y.Z
    if ($TagName -match "^v(\d+)\.(\d+)\.(\d+)$") {
        $major = $matches[1]
        $minor = $matches[2]
        $currentPatch = [int]$matches[3]
        
        # Calculate next available version by checking existing tags
        $nextPatch = $currentPatch + 1
        if ($State) {
            # Find the highest patch version for this major.minor combination
            $existingVersions = $State.Tags | Where-Object { 
                $_.Version -match "^v$major\.$minor\.(\d+)$" 
            } | ForEach-Object {
                if ($_.Version -match "^v$major\.$minor\.(\d+)$") {
                    [int]$matches[1]
                }
            } | Sort-Object -Descending
            
            if ($existingVersions) {
                $highestPatch = $existingVersions[0]
                $nextPatch = $highestPatch + 1
            }
        }
        
        $nextVersion = "v$major.$minor.$nextPatch"
        
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

function Invoke-AllAutoFixes
{
    <#
    .SYNOPSIS
    Executes all auto-fix actions for pending issues in the State
    
    .DESCRIPTION
    This function processes all ValidationIssues in the State that have AutoFixAction scriptblocks defined.
    It executes the actions and updates the issue statuses accordingly.
    This should be called AFTER displaying the planned changes to the user.
    
    .PARAMETER State
    The RepositoryState object containing all validation issues
    
    .PARAMETER AutoFix
    Boolean indicating if auto-fix mode is enabled
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        [bool]$AutoFix = $false
    )
    
    if (-not $AutoFix) {
        # Not in auto-fix mode, mark all issues as unfixable
        foreach ($issue in $State.Issues) {
            if ($issue.Status -eq "pending") {
                $issue.Status = "unfixable"
            }
        }
        return
    }
    
    # Process all issues that have auto-fix actions
    foreach ($issue in $State.Issues) {
        if ($issue.Status -ne "pending") {
            continue  # Skip issues that have already been processed
        }
        
        if (-not $issue.AutoFixAction) {
            # No auto-fix action available, mark as unfixable
            $issue.Status = "unfixable"
            continue
        }
        
        # Execute the auto-fix action
        $description = "Fix $($issue.Type) for $($issue.Version)"
        Write-Host "Auto-fix: $description"
        
        try {
            $result = & $issue.AutoFixAction
            
            if ($result) {
                Write-Host "✓ Success: $description"
                $issue.Status = "fixed"
            } else {
                Write-Host "✗ Failed: $description"
                $issue.Status = "failed"
            }
        }
        catch {
            Write-Host "✗ Failed: $description"
            Write-SafeOutput -Message ([string]$_) -Prefix "::error::Exception during auto-fix: "
            $issue.Status = "failed"
        }
    }
}
