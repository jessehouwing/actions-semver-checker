#############################################################################
# ReleaseRemediationAction.ps1 - Base Class for Release Actions
#############################################################################
# This class provides common functionality for release-related actions.
# It includes helpers for handling unfixable errors and issue status.
#############################################################################

class ReleaseRemediationAction : RemediationAction {
    [string]$TagName
    
    ReleaseRemediationAction([string]$description, [string]$tagName) : base($description, $tagName) {
        $this.TagName = $tagName
    }
    
    # Helper method to check if an API result indicates unfixable error (422 - tag used by immutable release)
    hidden [bool] IsUnfixableError([hashtable]$result) {
        return $result.ContainsKey('Unfixable') -and $result.Unfixable -eq $true
    }
    
    # Helper method to build the suggested new ignore-versions value to paste back
    # into the input: the original configured list (preserving any wildcard
    # patterns such as "v1.*" exactly as configured) plus this action's TagName,
    # deduplicated and comma-separated.
    hidden [string] GetSuggestedIgnoreVersions([RepositoryState]$state) {
        $current = @()
        if ($state.IgnoreVersions) {
            $current = @($state.IgnoreVersions | Where-Object { $_ })
        }

        $updated = @($current + $this.TagName) | Select-Object -Unique

        return ($updated -join ",")
    }

    # Helper method to build a copy/pasteable YAML snippet showing the updated
    # ignore-versions input, ready to drop into the workflow file that calls
    # this action. Also switches ManualCommandsLanguage to "yaml" so the
    # snippet is rendered with a ```yaml fence instead of ```bash.
    hidden [string[]] GetIgnoreVersionsYamlSnippet([RepositoryState]$state) {
        $this.ManualCommandsLanguage = "yaml"
        $suggestedIgnoreVersions = $this.GetSuggestedIgnoreVersions($state)

        return @(
            "# Update your workflow step to skip this locked version:"
            "with:"
            "  ignore-versions: `"$suggestedIgnoreVersions`""
        )
    }

    # Helper method to mark an issue as unfixable
    hidden [void] MarkAsUnfixable([RepositoryState]$state, [string]$issueType, [string]$message) {
        Write-Host "✗ Unfixable: $message"
        # Find this issue in the state and mark it as unfixable
        $issue = $state.Issues | Where-Object { $_.Version -eq $this.TagName -and $_.Type -eq $issueType } | Select-Object -First 1
        if ($issue) {
            $issue.Status = "unfixable"
            $issue.Message = $message
        }
    }
    
    # Helper method to mark an issue as requiring manual intervention
    hidden [void] MarkAsManualFixRequired([RepositoryState]$state, [string]$issueType, [string]$message) {
        Write-Host "⚠ Manual fix required: $message"
        # Find this issue in the state and mark it as manual_fix_required
        $issue = $state.Issues | Where-Object { $_.Version -eq $this.TagName -and $_.Type -eq $issueType } | Select-Object -First 1
        if ($issue) {
            $issue.Status = "manual_fix_required"
            $issue.Message = $message
        }
    }
    
    # Helper method to check if issue is unfixable (for GetManualCommands)
    hidden [bool] IsIssueUnfixable([RepositoryState]$state, [string]$issueType) {
        $issue = $state.Issues | Where-Object { $_.Version -eq $this.TagName -and $_.Type -eq $issueType } | Select-Object -First 1
        return $issue -and $issue.Status -eq "unfixable"
    }
    
    # Helper method to check if issue requires manual fix (for GetManualCommands)
    hidden [bool] IsIssueManualFixRequired([RepositoryState]$state, [string]$issueType) {
        $issue = $state.Issues | Where-Object { $_.Version -eq $this.TagName -and $_.Type -eq $issueType } | Select-Object -First 1
        return $issue -and $issue.Status -eq "manual_fix_required"
    }
}
