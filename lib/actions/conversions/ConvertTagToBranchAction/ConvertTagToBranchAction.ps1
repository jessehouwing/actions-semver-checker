#############################################################################
# ConvertTagToBranchAction.ps1 - Convert a tag to a branch
#############################################################################

class ConvertTagToBranchAction : RemediationAction {
    [string]$Name
    [string]$Sha

    ConvertTagToBranchAction([string]$name, [string]$sha) : base("Convert tag to branch", $name) {
        $this.Name = $name
        $this.Sha = $sha
        $this.Priority = 25  # Run after deletes, before create/update
    }

    [bool] Execute([RepositoryState]$state) {
        if ($state.RepoOwner -and $state.RepoName -and $state.Token) {
            try {
                $isImmutable = Test-ReleaseImmutability -Owner $state.RepoOwner -Repo $state.RepoName -Tag $this.Name -Token $state.Token -ApiUrl $state.ApiUrl
                if ($isImmutable) {
                    Write-Host "✗ Unfixable: Tag $($this.Name) is immutable and cannot be converted to a branch"
                    $issue = $state.Issues | Where-Object { $_.Version -eq $this.Name -and $_.RemediationAction -eq $this } | Select-Object -First 1
                    if ($issue) {
                        $issue.Status = "unfixable"
                        $issue.Message = "Tag $($this.Name) is immutable and cannot be converted to a branch. Consider keeping the tag or using ignore-versions."
                    }
                    return $false
                }
            } catch {
                Write-Host "::debug::Failed to check release immutability for tag $($this.Name): $($_.Exception.Message)"
            }
        }

        $branchExists = $state.Branches | Where-Object { $_.Version -eq $this.Name } | Select-Object -First 1
        if ($branchExists) {
            Write-Host "Auto-fix: Delete tag $($this.Name) (branch already exists)"
            $deleteSuccess = Remove-GitHubRef -State $state -RefName "refs/tags/$($this.Name)"
            if ($deleteSuccess) {
                Write-Host "✓ Success: Removed tag $($this.Name)"
                return $true
            }

            Write-Host "✗ Failed: Delete tag $($this.Name)"
            return $false
        }

        Write-Host "Auto-fix: Convert tag $($this.Name) to branch"
        $createResult = New-GitHubRef -State $state -RefName "refs/heads/$($this.Name)" -Sha $this.Sha -Force $false

        if (-not $createResult.Success) {
            if ($createResult.RequiresManualFix) {
                Write-Host "✗ Manual fix required: Cannot create branch $($this.Name) - requires 'workflows' permission to modify workflow files"
                $issue = $state.Issues | Where-Object { $_.Version -eq $this.Name -and $_.RemediationAction -eq $this } | Select-Object -First 1
                if ($issue) {
                    $issue.Status = "manual_fix_required"
                    $issue.Message = "Version $($this.Name) cannot be converted to a branch by GitHub Actions because it contains workflow file changes and requires the 'workflows' permission. Please convert manually."
                }
            } else {
                Write-Host "✗ Failed: Create branch $($this.Name)"
            }
            return $false
        }

        $deleteSuccess = Remove-GitHubRef -State $state -RefName "refs/tags/$($this.Name)"
        if ($deleteSuccess) {
            Write-Host "✓ Success: Converted tag $($this.Name) to branch"
            return $true
        }

        Write-Host "✗ Failed: Delete tag $($this.Name) after creating branch"
        return $false
    }

    [string[]] GetManualCommands([RepositoryState]$state) {
        $issue = $state.Issues | Where-Object { $_.Version -eq $this.Name -and $_.RemediationAction -eq $this } | Select-Object -First 1
        if ($issue -and $issue.Status -eq "unfixable") {
            return @()
        }

        $branchExists = $state.Branches | Where-Object { $_.Version -eq $this.Name } | Select-Object -First 1
        if ($branchExists) {
            return @(
                "git push origin :refs/tags/$($this.Name)"
            )
        }

        return @(
            "git push origin $($this.Sha):refs/heads/$($this.Name)",
            "git push origin :refs/tags/$($this.Name)"
        )
    }
}
