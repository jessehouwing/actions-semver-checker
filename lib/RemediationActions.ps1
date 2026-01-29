#############################################################################
# RemediationActions.ps1 - Remediation Action Classes
#############################################################################
# This module provides classes for each type of remediation action.
# Each class encapsulates the logic for auto-fix and manual instructions.
#############################################################################

#############################################################################
# Base Remediation Action Class
#############################################################################

class RemediationAction {
    [string]$Description
    [string]$Version
    [int]$Priority  # Lower number = higher priority (for ordering)
    [bool]$IncludeCommentsInManualCommands = $false  # Control whether to include explanatory comments
    
    RemediationAction([string]$description, [string]$version) {
        $this.Description = $description
        $this.Version = $version
        $this.Priority = 50  # Default priority
    }
    
    # Execute the auto-fix action
    [bool] Execute([RepositoryState]$state) {
        throw "Execute must be implemented in derived class"
    }
    
    # Get manual fix command(s) - without comments by default
    [string[]] GetManualCommands([RepositoryState]$state) {
        throw "GetManualCommands must be implemented in derived class"
    }
    
    [string] ToString() {
        return "$($this.Description) for $($this.Version)"
    }
}

#############################################################################
# Release Actions
#############################################################################

class CreateReleaseAction : RemediationAction {
    [string]$TagName
    [bool]$AutoPublish = $false  # If true, create directly as published (non-draft)
    
    CreateReleaseAction([string]$tagName, [bool]$isDraft) : base("Create release", $tagName) {
        $this.TagName = $tagName
        # If isDraft is false, it means we want to publish, so set AutoPublish to true
        $this.AutoPublish = -not $isDraft
        $this.Priority = 30  # Create after tags
    }
    
    CreateReleaseAction([string]$tagName, [bool]$isDraft, [bool]$autoPublish) : base("Create release", $tagName) {
        $this.TagName = $tagName
        $this.AutoPublish = $autoPublish
        $this.Priority = 30  # Create after tags
    }
    
    [bool] Execute([RepositoryState]$state) {
        # If AutoPublish is enabled, create directly as published (non-draft)
        # This avoids the issue where a tag locked by a deleted immutable release
        # can't have a draft release published later
        $isDraft = -not $this.AutoPublish
        $actionDesc = if ($this.AutoPublish) { "Create and publish release" } else { "Create draft release" }
        
        Write-Host "Auto-fix: $actionDesc for $($this.TagName)"
        $result = New-GitHubRelease -State $state -TagName $this.TagName -Draft $isDraft
        
        if ($result.Success) {
            Write-Host "✓ Success: $actionDesc for $($this.TagName)"
            return $true
        } else {
            # Check if this is an unfixable error and mark it accordingly
            if ($result.Unfixable) {
                $this.MarkAsUnfixable($state, "Release $($this.TagName) cannot be created because this tag was previously used by an immutable release that was deleted. Consider adding this version to the ignore-versions list.")
            } else {
                Write-Host "✗ Failed: $actionDesc for $($this.TagName)"
            }
            return $false
        }
    }
    
    # Helper method to mark an issue as unfixable
    hidden [void] MarkAsUnfixable([RepositoryState]$state, [string]$message) {
        Write-Host "✗ Unfixable: Cannot create release for $($this.TagName) - tag was previously used by an immutable release"
        # Find this issue in the state and mark it as unfixable
        $issue = $state.Issues | Where-Object { $_.Version -eq $this.TagName -and $_.Type -eq "missing_release" } | Select-Object -First 1
        if ($issue) {
            $issue.Status = "unfixable"
            $issue.Message = $message
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        # Check if the issue is unfixable - if so, return empty array
        $issue = $state.Issues | Where-Object { $_.Version -eq $this.TagName -and $_.Type -eq "missing_release" } | Select-Object -First 1
        if ($issue -and $issue.Status -eq "unfixable") {
            return @()
        }
        
        if ($this.AutoPublish) {
            # Create and immediately publish
            return @(
                "gh release create $($this.TagName) --title `"$($this.TagName)`" --notes `"Release $($this.TagName)`""
            )
        } else {
            # Create as draft
            return @(
                "gh release create $($this.TagName) --draft --title `"$($this.TagName)`" --notes `"Release $($this.TagName)`""
            )
        }
    }
}

class PublishReleaseAction : RemediationAction {
    [string]$TagName
    [int]$ReleaseId
    
    PublishReleaseAction([string]$tagName) : base("Publish release", $tagName) {
        $this.TagName = $tagName
        $this.ReleaseId = 0  # Will be looked up if needed
        $this.Priority = 40  # Publish after creation
    }
    
    PublishReleaseAction([string]$tagName, [int]$releaseId) : base("Publish release", $tagName) {
        $this.TagName = $tagName
        $this.ReleaseId = $releaseId
        $this.Priority = 40  # Publish after creation
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Publish draft release for $($this.TagName)"
        $result = Publish-GitHubRelease -State $state -TagName $this.TagName -ReleaseId $this.ReleaseId
        
        if ($result.Success) {
            Write-Host "✓ Success: Published release for $($this.TagName)"
            return $true
        } else {
            # Check if this is an unfixable error (422 - tag used by immutable release)
            if ($result.Unfixable) {
                Write-Host "✗ Unfixable: Cannot publish release for $($this.TagName) - tag was previously used by an immutable release"
                # Find this issue in the state and mark it as unfixable
                $issue = $state.Issues | Where-Object { $_.Version -eq $this.TagName -and $_.Type -eq "draft_release" } | Select-Object -First 1
                if ($issue) {
                    $issue.Status = "unfixable"
                    # Update message to be more helpful
                    $issue.Message = "Release $($this.TagName) cannot be published because this tag was previously used by an immutable release that was deleted. Consider adding this version to the ignore-versions list."
                }
            } else {
                Write-Host "✗ Failed: Publish release for $($this.TagName)"
            }
            
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        # Check if the issue is unfixable - if so, return empty array
        $issue = $state.Issues | Where-Object { $_.Version -eq $this.TagName -and $_.Type -eq "draft_release" } | Select-Object -First 1
        if ($issue -and $issue.Status -eq "unfixable") {
            return @()
        }
        return @("gh release edit $($this.TagName) --draft=false")
    }
}

class RepublishReleaseAction : RemediationAction {
    [string]$TagName
    
    RepublishReleaseAction([string]$tagName) : base("Republish release for immutability", $tagName) {
        $this.TagName = $tagName
        $this.Priority = 45  # Republish after other release operations
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Republish release $($this.TagName) to make it immutable"
        $result = Republish-GitHubRelease -State $state -TagName $this.TagName
        
        if ($result.Success) {
            Write-Host "✓ Success: Republished release for $($this.TagName)"
            return $true
        } else {
            Write-Host "✗ Failed: Republish release for $($this.TagName) - $($result.Reason)"
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        return @(
            "gh release edit $($this.TagName) --draft=true",
            "gh release edit $($this.TagName) --draft=false"
        )
    }
}

class DeleteReleaseAction : RemediationAction {
    [string]$TagName
    [int]$ReleaseId
    
    DeleteReleaseAction([string]$tagName, [int]$releaseId) : base("Delete release", $tagName) {
        $this.TagName = $tagName
        $this.ReleaseId = $releaseId
        $this.Priority = 10  # Delete first
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Remove release for $($this.TagName)"
        $success = Remove-GitHubRelease -State $state -TagName $this.TagName -ReleaseId $this.ReleaseId
        
        if ($success) {
            Write-Host "✓ Success: Removed release for $($this.TagName)"
            return $true
        } else {
            Write-Host "✗ Failed: Remove release for $($this.TagName)"
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        return @("gh release delete $($this.TagName) --yes")
    }
}

#############################################################################
# Tag Actions
#############################################################################

class CreateTagAction : RemediationAction {
    [string]$TagName
    [string]$Sha
    
    CreateTagAction([string]$tagName, [string]$sha) : base("Create tag", $tagName) {
        $this.TagName = $tagName
        $this.Sha = $sha
        $this.Priority = 20  # Create after deletes
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Create tag $($this.TagName)"
        $result = New-GitHubRef -State $state -RefName "refs/tags/$($this.TagName)" -Sha $this.Sha -Force $false
        
        if ($result.Success) {
            Write-Host "✓ Success: Created tag $($this.TagName)"
            return $true
        } else {
            # Check if this requires manual fix due to workflows permission
            if ($result.RequiresManualFix) {
                Write-Host "✗ Manual fix required: Cannot create tag $($this.TagName) - requires 'workflows' permission to modify workflow files"
                # Find this issue in the state and mark it as requiring manual fix
                $issue = $state.Issues | Where-Object { $_.Version -eq $this.TagName -and $_.RemediationAction -eq $this } | Select-Object -First 1
                if ($issue) {
                    $issue.Status = "manual_fix_required"
                    # Update message to be more helpful
                    $issue.Message = "Version $($this.TagName) cannot be created by GitHub Actions because it contains workflow file changes and requires the 'workflows' permission. Please create manually."
                }
            } else {
                Write-Host "✗ Failed: Create tag $($this.TagName)"
            }
            
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        return @("git push origin $($this.Sha):refs/tags/$($this.TagName)")
    }
}

class UpdateTagAction : RemediationAction {
    [string]$TagName
    [string]$Sha
    [bool]$Force
    
    UpdateTagAction([string]$tagName, [string]$sha, [bool]$force) : base("Update tag", $tagName) {
        $this.TagName = $tagName
        $this.Sha = $sha
        $this.Force = $force
        $this.Priority = 20  # Same as create
    }
    
    [bool] Execute([RepositoryState]$state) {
        $forceStr = if ($this.Force) { " (force)" } else { "" }
        Write-Host "Auto-fix: Update tag $($this.TagName)$forceStr"
        $result = New-GitHubRef -State $state -RefName "refs/tags/$($this.TagName)" -Sha $this.Sha -Force $this.Force
        
        if ($result.Success) {
            Write-Host "✓ Success: Updated tag $($this.TagName)"
            return $true
        } else {
            # Check if this requires manual fix due to workflows permission
            if ($result.RequiresManualFix) {
                Write-Host "✗ Manual fix required: Cannot update tag $($this.TagName) - requires 'workflows' permission to modify workflow files"
                $issue = $state.Issues | Where-Object { $_.Version -eq $this.TagName -and $_.RemediationAction -eq $this } | Select-Object -First 1
                if ($issue) {
                    $issue.Status = "manual_fix_required"
                    # Update message to be more helpful
                    $issue.Message = "Version $($this.TagName) cannot be updated by GitHub Actions because it contains workflow file changes and requires the 'workflows' permission. Please update manually."
                }
            } else {
                Write-Host "✗ Failed: Update tag $($this.TagName)"
            }
            
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        $forceFlag = if ($this.Force) { " --force" } else { "" }
        return @("git push origin $($this.Sha):refs/tags/$($this.TagName)$forceFlag")
    }
}

class DeleteTagAction : RemediationAction {
    [string]$TagName
    
    DeleteTagAction([string]$tagName) : base("Delete tag", $tagName) {
        $this.TagName = $tagName
        $this.Priority = 10  # Delete first
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Delete tag $($this.TagName)"
        $success = Remove-GitHubRef -State $state -RefName "refs/tags/$($this.TagName)"
        
        if ($success) {
            Write-Host "✓ Success: Deleted tag $($this.TagName)"
            return $true
        } else {
            Write-Host "✗ Failed: Delete tag $($this.TagName)"
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        return @(
            "git tag -d $($this.TagName)",
            "git push origin :refs/tags/$($this.TagName)"
        )
    }
}

#############################################################################
# Branch Actions
#############################################################################

class CreateBranchAction : RemediationAction {
    [string]$BranchName
    [string]$Sha
    
    CreateBranchAction([string]$branchName, [string]$sha) : base("Create branch", $branchName) {
        $this.BranchName = $branchName
        $this.Sha = $sha
        $this.Priority = 20  # Create after deletes
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Create branch $($this.BranchName)"
        $result = New-GitHubRef -State $state -RefName "refs/heads/$($this.BranchName)" -Sha $this.Sha -Force $false
        
        if ($result.Success) {
            Write-Host "✓ Success: Created branch $($this.BranchName)"
            return $true
        } else {
            # Check if this requires manual fix due to workflows permission
            if ($result.RequiresManualFix) {
                Write-Host "✗ Manual fix required: Cannot create branch $($this.BranchName) - requires 'workflows' permission to modify workflow files"
                $issue = $state.Issues | Where-Object { $_.Version -eq $this.BranchName -and $_.RemediationAction -eq $this } | Select-Object -First 1
                if ($issue) {
                    $issue.Status = "manual_fix_required"
                    # Update message to be more helpful
                    $issue.Message = "Version $($this.BranchName) cannot be created by GitHub Actions because it contains workflow file changes and requires the 'workflows' permission. Please create manually."
                }
            } else {
                Write-Host "✗ Failed: Create branch $($this.BranchName)"
            }
            
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        return @("git push origin $($this.Sha):refs/heads/$($this.BranchName)")
    }
}

class UpdateBranchAction : RemediationAction {
    [string]$BranchName
    [string]$Sha
    [bool]$Force
    
    UpdateBranchAction([string]$branchName, [string]$sha, [bool]$force) : base("Update branch", $branchName) {
        $this.BranchName = $branchName
        $this.Sha = $sha
        $this.Force = $force
        $this.Priority = 20  # Same as create
    }
    
    [bool] Execute([RepositoryState]$state) {
        $forceStr = if ($this.Force) { " (force)" } else { "" }
        Write-Host "Auto-fix: Update branch $($this.BranchName)$forceStr"
        $result = New-GitHubRef -State $state -RefName "refs/heads/$($this.BranchName)" -Sha $this.Sha -Force $this.Force
        
        if ($result.Success) {
            Write-Host "✓ Success: Updated branch $($this.BranchName)"
            return $true
        } else {
            # Check if this requires manual fix due to workflows permission
            if ($result.RequiresManualFix) {
                Write-Host "✗ Manual fix required: Cannot update branch $($this.BranchName) - requires 'workflows' permission to modify workflow files"
                $issue = $state.Issues | Where-Object { $_.Version -eq $this.BranchName -and $_.RemediationAction -eq $this } | Select-Object -First 1
                if ($issue) {
                    $issue.Status = "manual_fix_required"
                    # Update message to be more helpful
                    $issue.Message = "Version $($this.BranchName) cannot be updated by GitHub Actions because it contains workflow file changes and requires the 'workflows' permission. Please update manually."
                }
            } else {
                Write-Host "✗ Failed: Update branch $($this.BranchName)"
            }
            
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        $forceFlag = if ($this.Force) { " --force" } else { "" }
        return @("git push origin $($this.Sha):refs/heads/$($this.BranchName)$forceFlag")
    }
}

class DeleteBranchAction : RemediationAction {
    [string]$BranchName
    
    DeleteBranchAction([string]$branchName) : base("Delete branch", $branchName) {
        $this.BranchName = $branchName
        $this.Priority = 10  # Delete first
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Delete branch $($this.BranchName)"
        $success = Remove-GitHubRef -State $state -RefName "refs/heads/$($this.BranchName)"
        
        if ($success) {
            Write-Host "✓ Success: Deleted branch $($this.BranchName)"
            return $true
        } else {
            Write-Host "✗ Failed: Delete branch $($this.BranchName)"
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        return @(
            "git branch -d $($this.BranchName)",
            "git push origin :refs/heads/$($this.BranchName)"
        )
    }
}
