#############################################################################
# Remediation.ps1 - Auto-fix and Remediation Functions
#############################################################################
# This module provides functions for auto-fixing validation issues and
# generating manual remediation commands.
#############################################################################

# NOTE: Get-ImmutableReleaseRemediationCommands was removed as it was unused.
# The functionality is now handled by RemediationAction classes in RemediationActions.ps1

function Get-ManualInstruction {
    <#
    .SYNOPSIS
    Prints manual remediation instructions for all issues that need manual intervention
    
    .DESCRIPTION
    Extracts and displays manual fix commands from RemediationAction objects for issues
    that are unfixable, failed, require manual fixes, or are still pending (not auto-fixed).
    Groups commands by action type for better readability.
    
    .PARAMETER State
    The RepositoryState object containing all validation issues
    
    .PARAMETER GroupByType
    If true, groups commands by remediation action type. Default is false.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        [bool]$GroupByType = $false
    )
    
    # Include pending issues (not yet fixed) as well as failed/unfixable ones
    # Sort by priority (lower number = higher priority), then by version for consistent ordering
    # Priority is taken from: 1) Issue.Priority if set, 2) RemediationAction.Priority, 3) default 100
    $issuesNeedingManualFix = $State.Issues | Where-Object { 
        $_.Status -eq "pending" -or $_.Status -eq "unfixable" -or $_.Status -eq "failed" -or $_.Status -eq "manual_fix_required"
    } | Sort-Object @(
        @{
            Expression = {
                # Use Issue.Priority if explicitly set (non-default)
                if ($_.Priority -and $_.Priority -ne 100) {
                    $_.Priority
                }
                # Otherwise use RemediationAction.Priority if available
                elseif ($_.RemediationAction -and ($_.RemediationAction -is [RemediationAction])) {
                    $_.RemediationAction.Priority
                } else {
                    100  # Default priority for issues without RemediationAction
                }
            }
            Ascending = $true
        },
        @{
            Expression = {
                # Parse version for proper sorting using .NET Version object
                $version = $_.Version
                if ($version -eq 'latest') {
                    # Sort 'latest' after all versioned items
                    return [Version]::new([int]::MaxValue, 0, 0)
                }
                if ($version -match '^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?') {
                    $major = [int]($Matches[1] ?? 0)
                    $minor = [int]($Matches[2] ?? 0)
                    $patch = [int]($Matches[3] ?? 0)
                    return [Version]::new($major, $minor, $patch)
                }
                # Non-parseable versions sort last
                return [Version]::new([int]::MaxValue, 0, 0)
            }
            Ascending = $true
        }
    )
    
    if ($issuesNeedingManualFix.Count -eq 0) {
        return
    }
    
    Write-Host "##[group]Manual Remediation Instructions"
    
    # Collect all manual commands first to determine if we need clone instructions
    $allCommands = @()
    foreach ($issue in $issuesNeedingManualFix) {
        if ($issue.RemediationAction -and ($issue.RemediationAction -is [RemediationAction])) {
            $commands = $issue.RemediationAction.GetManualCommands($State)
            if ($commands) {
                $allCommands += $commands
            }
        } elseif ($issue.ManualFixCommand) {
            $allCommands += $issue.ManualFixCommand
        }
    }
    
    # Stop workflow commands to prevent command injection in output
    $stopToken = [guid]::NewGuid().ToString()
    Write-Output "::stop-commands::$stopToken"
    
    # If we have manual commands and repo info is available, add clone instructions at the top
    if ($allCommands.Count -gt 0 -and $State.ServerUrl -and $State.RepoOwner -and $State.RepoName) {
        Write-Output "# Setup - Clone the repository and fetch all tags and branches:"
        Write-Output "git clone $($State.ServerUrl)/$($State.RepoOwner)/$($State.RepoName).git"
        Write-Output "cd $($State.RepoName)"
        Write-Output "git fetch --all --tags"
        Write-Output ""
        Write-Output "# Remediation Steps:"
    }
    
    if ($GroupByType) {
        # Group by action type
        $grouped = $issuesNeedingManualFix | Group-Object { 
            if ($_.RemediationAction) {
                $_.RemediationAction.GetType().Name
            } else {
                "Other"
            }
        }
        
        foreach ($group in $grouped) {
            Write-Output "#### $($group.Name) ($($group.Count) issue(s))"
            Write-Output ""
            
            foreach ($issue in $group.Group) {
                Write-Output "**$($issue.Version):** $($issue.Message)"
                
                if ($issue.RemediationAction -and ($issue.RemediationAction -is [RemediationAction])) {
                    $commands = $issue.RemediationAction.GetManualCommands($State)
                    foreach ($cmd in $commands) {
                        Write-Output "  ``````"
                        Write-Output "  $cmd"
                        Write-Output "  ``````"
                    }
                } elseif ($issue.ManualFixCommand) {
                    Write-Output "  ``````"
                    Write-Output "  $($issue.ManualFixCommand)"
                    Write-Output "  ``````"
                }
                Write-Output ""
            }
        }
    }
    else {
        # List all issues with their commands - clean format without emojis
        foreach ($issue in $issuesNeedingManualFix) {
            if ($issue.RemediationAction -and ($issue.RemediationAction -is [RemediationAction])) {
                $commands = $issue.RemediationAction.GetManualCommands($State)
                if ($commands) {
                    foreach ($cmd in $commands) {
                        Write-Output "$cmd"
                    }
                }
            } elseif ($issue.ManualFixCommand) {
                Write-Output "$($issue.ManualFixCommand)"
            }
        }
    }
    
    Write-Output "::$stopToken::"
    Write-Host "##[endgroup]"
}

function Write-ManualInstructionsToStepSummary
{
    <#
    .SYNOPSIS
    Writes manual remediation instructions to GitHub Actions step summary
    
    .DESCRIPTION
    Formats and writes manual fix commands to the GITHUB_STEP_SUMMARY file
    for easy viewing in the GitHub Actions UI.
    
    .PARAMETER State
    The RepositoryState object containing all validation issues
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State
    )
    
    if (-not $env:GITHUB_STEP_SUMMARY) {
        return
    }
    
    # Include pending issues (not yet fixed) as well as failed/unfixable ones
    # Sort by priority (lower number = higher priority), then by version for consistent ordering
    $issuesNeedingManualFix = $State.Issues | Where-Object { 
        $_.Status -eq "pending" -or $_.Status -eq "unfixable" -or $_.Status -eq "failed" -or $_.Status -eq "manual_fix_required"
    } | Sort-Object @(
        @{
            Expression = {
                # Use Issue.Priority if explicitly set (non-default)
                if ($_.Priority -and $_.Priority -ne 100) {
                    $_.Priority
                }
                # Otherwise use RemediationAction.Priority if available
                elseif ($_.RemediationAction -and ($_.RemediationAction -is [RemediationAction])) {
                    $_.RemediationAction.Priority
                } else {
                    100  # Default priority for issues without RemediationAction
                }
            }
            Ascending = $true
        },
        @{
            Expression = {
                # Parse version for proper sorting using .NET Version object
                $version = $_.Version
                if ($version -eq 'latest') {
                    # Sort 'latest' after all versioned items
                    return [Version]::new([int]::MaxValue, 0, 0)
                }
                if ($version -match '^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?') {
                    $major = [int]($Matches[1] ?? 0)
                    $minor = [int]($Matches[2] ?? 0)
                    $patch = [int]($Matches[3] ?? 0)
                    return [Version]::new($major, $minor, $patch)
                }
                # Non-parseable versions sort last
                return [Version]::new([int]::MaxValue, 0, 0)
            }
            Ascending = $true
        }
    )
    
    if ($issuesNeedingManualFix.Count -eq 0) {
        return
    }
    
    # Write to step summary
    "## Manual Remediation Required" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
    "" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
    
    # Collect all manual commands first to determine if we need clone instructions
    $allCommands = @()
    foreach ($issue in $issuesNeedingManualFix) {
        if ($issue.RemediationAction -and ($issue.RemediationAction -is [RemediationAction])) {
            $commands = $issue.RemediationAction.GetManualCommands($State)
            if ($commands) {
                $allCommands += $commands
            }
        } elseif ($issue.ManualFixCommand) {
            $allCommands += $issue.ManualFixCommand
        }
    }
    
    # If we have manual commands and repo info is available, add clone instructions at the top
    if ($allCommands.Count -gt 0 -and $State.ServerUrl -and $State.RepoOwner -and $State.RepoName) {
        "### Setup" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
        "Clone the repository and fetch all tags and branches:" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
        "``````bash" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
        "git clone $($State.ServerUrl)/$($State.RepoOwner)/$($State.RepoName).git" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
        "cd $($State.RepoName)" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
        "git fetch --all --tags" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
        "``````" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
        "" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
        "### Remediation Steps" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
        "" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
    }
    
    foreach ($issue in $issuesNeedingManualFix) {
        $statusEmoji = if ($issue.Status -eq "failed") { "❌" } else { "⚠️" }
        "$statusEmoji **$($issue.Version):** $($issue.Message)" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
        
        if ($issue.RemediationAction -and ($issue.RemediationAction -is [RemediationAction])) {
            $commands = $issue.RemediationAction.GetManualCommands($State)
            if ($commands) {
                "``````bash" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
                foreach ($cmd in $commands) {
                    $cmd | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
                }
                "``````" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
            }
        } elseif ($issue.ManualFixCommand) {
            "``````bash" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
            $issue.ManualFixCommand | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
            "``````" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
        }
        "" | Out-File -Append -FilePath $env:GITHUB_STEP_SUMMARY
    }
}

function Invoke-AutoFix {
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
        # Not in auto-fix mode, mark all issues as manual_fix_required so manual instructions show
        foreach ($issue in $State.Issues) {
            if ($issue.Status -eq "pending") {
                $issue.Status = "manual_fix_required"
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
                    # Only set status to "failed" if the action didn't already mark it as something else
                    # (e.g., "unfixable" or "manual_fix_required")
                    if ($issue.Status -eq "pending") {
                        $issue.Status = "failed"
                    }
                }
            }
            catch {
                Write-Host "✗ Failed: $($action.Description)"
                Write-SafeOutput -Message ([string]$_) -Prefix "::debug::Exception during auto-fix: "
                # Only set status to "failed" if the action didn't already mark it as something else
                if ($issue.Status -eq "pending") {
                    $issue.Status = "failed"
                }
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

function Write-UnresolvedIssue {
    <#
    .SYNOPSIS
    Logs all unresolved issues (failed or unfixable) as errors or warnings
    
    .DESCRIPTION
    This function should be called at the end of validation, after all auto-fixes
    have been attempted. It logs all issues that remain unresolved based on their
    severity level.
    
    .PARAMETER State
    The RepositoryState object containing all validation issues
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State
    )
    
    # Get all unresolved issues (failed, manual_fix_required, unfixable, or pending)
    $unresolvedIssues = $State.Issues | Where-Object { 
        $_.Status -in @("failed", "manual_fix_required", "unfixable", "pending")
    }
    
    if ($unresolvedIssues.Count -eq 0) {
        return
    }
    
    # Log each unresolved issue based on its severity
    foreach ($issue in $unresolvedIssues) {
        $messageType = $issue.Severity
        $titlePrefix = if ($issue.Status -eq "unfixable") { "Unfixable" } elseif ($issue.Status -eq "manual_fix_required") { "Manual fix required" } elseif ($issue.Status -eq "failed") { "Failed to fix" } else { "Unresolved" }
        
        if ($messageType -eq "error") {
            Write-Output "::error title=$titlePrefix issue::$($issue.Message)"
        } elseif ($messageType -eq "warning") {
            Write-Output "::warning title=$titlePrefix issue::$($issue.Message)"
        }
    }
}
