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
