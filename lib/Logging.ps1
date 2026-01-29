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

function write-actions-error
{
    param(
        [string] $message
    )

    Write-Output $message
    $global:returnCode = 1
}

function write-actions-warning
{
    param(
        [string] $message
    )

    Write-Output $message
}

function write-actions-message
{
    param(
        [string] $message,
        [string] $severity = "error"  # Can be "error", "warning", or "none"
    )

    if ($severity -eq "error") {
        write-actions-error $message
    } elseif ($severity -eq "warning") {
        write-actions-warning $message
    }
    # If "none", don't write anything
}
