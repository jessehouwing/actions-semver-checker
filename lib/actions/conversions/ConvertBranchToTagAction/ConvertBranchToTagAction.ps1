#############################################################################
# ConvertBranchToTagAction.ps1 - Convert a branch to a tag
#############################################################################

class ConvertBranchToTagAction : RemediationAction {
    [string]$Name
    [string]$Sha

    ConvertBranchToTagAction([string]$name, [string]$sha) : base("Convert branch to tag", $name) {
        $this.Name = $name
        $this.Sha = $sha
        $this.Priority = 25  # Run after deletes, before create/update
    }

    [bool] Execute([RepositoryState]$state) {
        $tagExists = $state.Tags | Where-Object { $_.Version -eq $this.Name } | Select-Object -First 1
        if ($tagExists) {
            Write-Host "Auto-fix: Delete branch $($this.Name) (tag already exists)"
            $deleteSuccess = Remove-GitHubRef -State $state -RefName "refs/heads/$($this.Name)"
            if ($deleteSuccess) {
                Write-Host "✓ Success: Removed branch $($this.Name)"
                return $true
            }

            Write-Host "✗ Failed: Delete branch $($this.Name)"
            return $false
        }

        Write-Host "Auto-fix: Convert branch $($this.Name) to tag"
        $createResult = New-GitHubRef -State $state -RefName "refs/tags/$($this.Name)" -Sha $this.Sha -Force $false

        if (-not $createResult.Success) {
            if ($createResult.RequiresManualFix) {
                Write-Host "✗ Manual fix required: Cannot create tag $($this.Name) - requires 'workflows' permission to modify workflow files"
                $issue = $state.Issues | Where-Object { $_.Version -eq $this.Name -and $_.RemediationAction -eq $this } | Select-Object -First 1
                if ($issue) {
                    $issue.Status = "manual_fix_required"
                    $issue.Message = "Version $($this.Name) cannot be converted to a tag by GitHub Actions because it contains workflow file changes and requires the 'workflows' permission. Please convert manually."
                }
            } else {
                Write-Host "✗ Failed: Create tag $($this.Name)"
            }
            return $false
        }

        $deleteSuccess = Remove-GitHubRef -State $state -RefName "refs/heads/$($this.Name)"
        if ($deleteSuccess) {
            Write-Host "✓ Success: Converted branch $($this.Name) to tag"
            return $true
        }

        Write-Host "✗ Failed: Delete branch $($this.Name) after creating tag"
        return $false
    }

    [string[]] GetManualCommands([RepositoryState]$state) {
        $tagExists = $state.Tags | Where-Object { $_.Version -eq $this.Name } | Select-Object -First 1
        if ($tagExists) {
            return @(
                "git push origin :refs/heads/$($this.Name)"
            )
        }

        return @(
            "git push origin $($this.Sha):refs/tags/$($this.Name)",
            "git push origin :refs/heads/$($this.Name)"
        )
    }
}
