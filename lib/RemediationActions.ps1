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
    
    RemediationAction([string]$description, [string]$version) {
        $this.Description = $description
        $this.Version = $version
        $this.Priority = 50  # Default priority
    }
    
    # Execute the auto-fix action
    [bool] Execute([RepositoryState]$state) {
        throw "Execute must be implemented in derived class"
    }
    
    # Get manual fix command(s)
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
    [bool]$IsDraft
    
    CreateReleaseAction([string]$tagName, [bool]$isDraft) : base("Create release", $tagName) {
        $this.TagName = $tagName
        $this.IsDraft = $isDraft
        $this.Priority = 30  # Create after tags
    }
    
    [bool] Execute([RepositoryState]$state) {
        Write-Host "Auto-fix: Create draft release for $($this.TagName)"
        $releaseId = New-GitHubDraftRelease -State $state -TagName $this.TagName
        
        if ($releaseId) {
            Write-Host "✓ Success: Created draft release for $($this.TagName)"
            return $true
        } else {
            Write-Host "✗ Failed: Create draft release for $($this.TagName)"
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        return @(
            "gh release create $($this.TagName) --draft --title `"$($this.TagName)`" --notes `"Release $($this.TagName)`""
        )
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
            Write-Host "✗ Failed: Publish release for $($this.TagName)"
            return $false
        }
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        $repoInfo = Get-GitHubRepoInfo -State $state
        $commands = @("gh release edit $($this.TagName) --draft=false")
        
        if ($repoInfo) {
            $commands[0] += "  # Or edit at: $($repoInfo.Url)/releases/edit/$($this.TagName)"
        }
        
        return $commands
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
            "# Manually republish release $($this.TagName) to make it immutable",
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
        $success = New-GitHubRef -State $state -RefName "refs/tags/$($this.TagName)" -Sha $this.Sha -Force $false
        
        if ($success) {
            Write-Host "✓ Success: Created tag $($this.TagName)"
            return $true
        } else {
            Write-Host "✗ Failed: Create tag $($this.TagName)"
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
        $success = New-GitHubRef -State $state -RefName "refs/tags/$($this.TagName)" -Sha $this.Sha -Force $this.Force
        
        if ($success) {
            Write-Host "✓ Success: Updated tag $($this.TagName)"
            return $true
        } else {
            Write-Host "✗ Failed: Update tag $($this.TagName)"
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
        $success = New-GitHubRef -State $state -RefName "refs/heads/$($this.BranchName)" -Sha $this.Sha -Force $false
        
        if ($success) {
            Write-Host "✓ Success: Created branch $($this.BranchName)"
            return $true
        } else {
            Write-Host "✗ Failed: Create branch $($this.BranchName)"
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
        $success = New-GitHubRef -State $state -RefName "refs/heads/$($this.BranchName)" -Sha $this.Sha -Force $this.Force
        
        if ($success) {
            Write-Host "✓ Success: Updated branch $($this.BranchName)"
            return $true
        } else {
            Write-Host "✗ Failed: Update branch $($this.BranchName)"
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
