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

function Get-ManualFixCommands
{
    <#
    .SYNOPSIS
    Extracts manual fix commands from all issues that need manual intervention
    
    .DESCRIPTION
    Gets manual fix commands from issues that are unfixable or failed.
    Supports both RemediationAction objects and legacy ManualFixCommand strings.
    
    .PARAMETER State
    The RepositoryState object containing all validation issues
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State
    )
    
    $commands = @()
    
    foreach ($issue in $State.Issues) {
        # Only include unfixable or failed issues
        if ($issue.Status -ne "unfixable" -and $issue.Status -ne "failed") {
            continue
        }
        
        # Try to get commands from RemediationAction first
        if ($issue.RemediationAction -and ($issue.RemediationAction -is [RemediationAction])) {
            $actionCommands = $issue.RemediationAction.GetManualCommands($State)
            if ($actionCommands) {
                $commands += $actionCommands
            }
        }
        # Fall back to ManualFixCommand string
        elseif ($issue.ManualFixCommand) {
            $commands += $issue.ManualFixCommand
        }
    }
    
    return $commands | Select-Object -Unique
}

function Invoke-AllAutoFixes
{
    <#
    .SYNOPSIS
    Executes all auto-fix actions for pending issues in the State
    
    .DESCRIPTION
    This function processes all ValidationIssues in the State that have RemediationAction objects
    defined. It executes the actions in priority order and updates the issue statuses accordingly. 
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
    
    # Separate issues by whether they have RemediationAction objects
    $issuesWithActions = $State.Issues | Where-Object { 
        $_.Status -eq "pending" -and $_.RemediationAction
    }
    
    # Sort issues by priority (RemediationAction.Priority, lower = higher priority)
    # This ensures: Delete (10) → Create/Update (20) → Release operations (30-40)
    $sortedIssues = $issuesWithActions | Sort-Object { 
        if ($_.RemediationAction -and ($_.RemediationAction -is [RemediationAction])) {
            $_.RemediationAction.Priority
        } else {
            50  # Default priority for scriptblock-based actions
        }
    }
    
    # Process all issues in priority order
    foreach ($issue in $sortedIssues) {
        # RemediationAction object handling
        if ($issue.RemediationAction -and ($issue.RemediationAction -is [RemediationAction])) {
            $action = $issue.RemediationAction
            
            try {
                $result = $action.Execute($State)
                
                if ($result) {
                    $issue.Status = "fixed"
                } else {
                    $issue.Status = "failed"
                }
            }
            catch {
                Write-Host "✗ Failed: $($action.Description)"
                Write-SafeOutput -Message ([string]$_) -Prefix "::error::Exception during auto-fix: "
                $issue.Status = "failed"
            }
        }
        else {
            # No auto-fix action available, mark as unfixable
            $issue.Status = "unfixable"
        }
    }
    
    # Mark any remaining pending issues as unfixable
    foreach ($issue in $State.Issues) {
        if ($issue.Status -eq "pending") {
            $issue.Status = "unfixable"
        }
    }
}
