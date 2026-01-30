#############################################################################
# CliLogging.ps1 - CLI Logging Functions (No GitHub Actions Commands)
#############################################################################
# This module provides logging functions for CLI usage without emitting
# GitHub Actions workflow commands.
#############################################################################

function Write-SafeOutput
{
    param(
        [string]$Message,
        [string]$Prefix = ""
    )
    
    # In CLI mode, just write the message normally without workflow command protection
    if ($Prefix) {
        Write-Host -NoNewline $Prefix
    }
    Write-Host $Message
}

function Write-ActionsError
{
    <#
    .SYNOPSIS
    Writes an error message in CLI format.
    
    .PARAMETER Message
    The error message to output.
    
    .PARAMETER State
    Optional RepositoryState object for tracking issues.
    #>
    param(
        [string] $Message,
        [RepositoryState] $State = $null
    )

    # Write to error stream with color if supported
    if ($Host.UI.SupportsVirtualTerminal) {
        Write-Host "ERROR: $Message" -ForegroundColor Red
    }
    else {
        Write-Host "ERROR: $Message"
    }
    
    # If State is provided, add an error issue (for tracking)
    if ($State) {
        $issue = [ValidationIssue]::new("error", "error", $Message)
        $State.AddIssue($issue)
    }
    else {
        # Fallback for test harness compatibility
        $global:returnCode = 1
    }
}

function Write-ActionsWarning
{
    <#
    .SYNOPSIS
    Writes a warning message in CLI format.
    
    .PARAMETER Message
    The warning message to output.
    #>
    param(
        [string] $Message
    )

    # Write to warning stream with color if supported
    if ($Host.UI.SupportsVirtualTerminal) {
        Write-Host "WARNING: $Message" -ForegroundColor Yellow
    }
    else {
        Write-Host "WARNING: $Message"
    }
}

function Write-ActionsMessage
{
    <#
    .SYNOPSIS
    Writes a message in CLI format with configurable severity.
    
    .PARAMETER Message
    The message to output.
    
    .PARAMETER Severity
    The severity level: 'error', 'warning', or 'none'.
    
    .PARAMETER State
    Optional RepositoryState object for tracking issues.
    #>
    param(
        [string] $Message,
        [string] $Severity = "error",
        [RepositoryState] $State = $null
    )

    if ($Severity -eq "error") {
        Write-ActionsError -Message $Message -State $State
    } elseif ($Severity -eq "warning") {
        Write-ActionsWarning -Message $Message
    }
    # If "none", don't write anything
}
