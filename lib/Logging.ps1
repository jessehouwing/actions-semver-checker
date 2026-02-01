#############################################################################
# Logging.ps1 - Safe Output and GitHub Actions Commands
#############################################################################
# This module provides logging functions that handle workflow command
# injection protection for GitHub Actions.
#############################################################################

function Write-SafeOutput
{
    param(
        [string]$Message,
        [string]$Prefix = ""
    )
    
    # Use stop-commands to prevent workflow command injection
    # https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#stopping-and-starting-workflow-commands
    # The prefix (containing workflow commands) is written BEFORE stop-commands
    # so GitHub Actions can interpret it, but the untrusted message is wrapped
    # in stop-commands to neutralize any malicious workflow commands it contains
    
    if ($Prefix) {
        Write-Host -NoNewline $Prefix
    }
    
    $stopMarker = New-Guid
    Write-Host "::stop-commands::$stopMarker"
    Write-Host $Message
    Write-Host "::$stopMarker::"
}

function Write-ActionsError
{
    <#
    .SYNOPSIS
    Writes an error message in GitHub Actions workflow command format.
    
    .PARAMETER Message
    The error message to output.
    
    .PARAMETER State
    Optional RepositoryState object for tracking issues.
    #>
    param(
        [string] $Message,
        [RepositoryState] $State = $null
    )

    Write-Output $Message
    
    # If State is provided, add an error issue (for tracking)
    # This maintains backward compatibility when State is not passed
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
    Writes a warning message in GitHub Actions workflow command format.
    
    .PARAMETER Message
    The warning message to output.
    #>
    param(
        [string] $Message
    )

    Write-Output $Message
}

function Write-ActionsMessage
{
    <#
    .SYNOPSIS
    Writes a message in GitHub Actions workflow command format with configurable severity.
    
    .PARAMETER Message
    The message to output.
    
    .PARAMETER Severity
    The severity level: 'error', 'warning', or 'none'.
    
    .PARAMETER State
    Optional RepositoryState object for tracking issues.
    #>
    param(
        [string] $Message,
        [string] $Severity = "error",  # Can be "error", "warning", or "none"
        [RepositoryState] $State = $null
    )

    if ($Severity -eq "error") {
        Write-ActionsError -Message $Message -State $State
    } elseif ($Severity -eq "warning") {
        Write-ActionsWarning -Message $Message
    }
    # If "none", don't write anything
}
