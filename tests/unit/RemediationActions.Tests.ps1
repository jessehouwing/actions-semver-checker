BeforeAll {
    # Suppress progress reporting for folder cleanup operations (must be global scope)
    $global:ProgressPreference = 'SilentlyContinue'

    # Import the remediation actions module
    . "$PSScriptRoot/../../lib/StateModel.ps1"
    . "$PSScriptRoot/../../lib/Logging.ps1"
    . "$PSScriptRoot/../../lib/GitHubApi.ps1"
    . "$PSScriptRoot/../../lib/RemediationActions.ps1"
}

Describe "RemediationAction Classes" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
    }
    
    Context "CreateTagAction" {
        It "Should create action with correct properties" {
            $action = [CreateTagAction]::new("v1.0.0", "abc123")
            
            $action.TagName | Should -Be "v1.0.0"
            $action.Sha | Should -Be "abc123"
            $action.Priority | Should -Be 20
            $action.Description | Should -Be "Create tag"
            $action.Version | Should -Be "v1.0.0"
        }
        
        It "Should generate correct manual commands" {
            $action = [CreateTagAction]::new("v1.0.0", "abc123")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "git push origin abc123:refs/tags/v1.0.0"
        }
    }
    
    Context "UpdateTagAction" {
        It "Should create action with force flag" {
            $action = [UpdateTagAction]::new("v1.0.0", "abc123", $true)
            
            $action.TagName | Should -Be "v1.0.0"
            $action.Sha | Should -Be "abc123"
            $action.Force | Should -Be $true
            $action.Priority | Should -Be 20
        }
        
        It "Should generate correct manual commands with force" {
            $action = [UpdateTagAction]::new("v1.0.0", "abc123", $true)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "--force"
        }
        
        It "Should generate correct manual commands without force" {
            $action = [UpdateTagAction]::new("v1.0.0", "abc123", $false)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Not -Match "--force"
        }
    }
    
    Context "DeleteTagAction" {
        It "Should have highest priority (delete first)" {
            $action = [DeleteTagAction]::new("v1.0.0")
            
            $action.Priority | Should -Be 10
        }
        
        It "Should generate correct manual commands" {
            $action = [DeleteTagAction]::new("v1.0.0")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 2
            $commands[0] | Should -Match "git tag -d v1.0.0"
            $commands[1] | Should -Match "git push origin :refs/tags/v1.0.0"
        }
    }
    
    Context "CreateReleaseAction" {
        It "Should create action for draft release" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true)
            
            $action.TagName | Should -Be "v1.0.0"
            $action.AutoPublish | Should -Be $false
            $action.Priority | Should -Be 30
        }
        
        It "Should create action with auto-publish" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true, $true)
            
            $action.TagName | Should -Be "v1.0.0"
            $action.AutoPublish | Should -Be $true
            $action.Priority | Should -Be 30
        }
        
        It "Should generate correct manual commands for draft" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true, $false)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "gh release create v1.0.0 --draft"
            $commands[0] | Should -Not -Match "^#"
        }
        
        It "Should generate correct manual commands for auto-publish" {
            $action = [CreateReleaseAction]::new("v1.0.0", $true, $true)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "gh release create v1.0.0"
            $commands[0] | Should -Not -Match "--draft"
            $commands[0] | Should -Not -Match "^#"
        }
    }
    
    Context "PublishReleaseAction" {
        It "Should create action with release ID" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            
            $action.TagName | Should -Be "v1.0.0"
            $action.ReleaseId | Should -Be 12345
            $action.Priority | Should -Be 40
        }
        
        It "Should generate correct manual commands" {
            $action = [PublishReleaseAction]::new("v1.0.0", 12345)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "gh release edit v1.0.0 --draft=false"
            $commands[0] | Should -Not -Match "^#"
            $commands[0] | Should -Not -Match "# Or edit at"
        }
    }
    
    Context "RepublishReleaseAction" {
        It "Should generate manual commands without latest flag by default" {
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 2
            $commands[0] | Should -Match "gh release edit v1.0.0 --draft=true"
            $commands[1] | Should -Match "gh release edit v1.0.0 --draft=false"
        }
    }
    
    Context "DeleteReleaseAction" {
        It "Should have high priority (delete early)" {
            $action = [DeleteReleaseAction]::new("v1.0.0", 12345)
            
            $action.Priority | Should -Be 10
        }
        
        It "Should generate correct manual commands" {
            $action = [DeleteReleaseAction]::new("v1.0.0", 12345)
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Match "gh release delete v1.0.0 --yes"
        }
    }
    
    Context "Priority Ordering" {
        It "Should order actions correctly by priority" {
            $actions = @(
                [CreateTagAction]::new("v1.0.0", "abc123"),           # Priority 20
                [PublishReleaseAction]::new("v1.0.0", 12345),        # Priority 40
                [DeleteTagAction]::new("v1.0.0"),                     # Priority 10
                [CreateReleaseAction]::new("v1.0.0", $true),         # Priority 30
                [UpdateTagAction]::new("v1.0.0", "def456", $true)    # Priority 20
            )
            
            $sorted = $actions | Sort-Object -Property Priority
            
            # First should be delete (priority 10)
            $sorted[0].GetType().Name | Should -Be "DeleteTagAction"
            # Then creates/updates (priority 20)
            $sorted[1].Priority | Should -Be 20
            $sorted[2].Priority | Should -Be 20
            # Then create release (priority 30)
            $sorted[3].GetType().Name | Should -Be "CreateReleaseAction"
            # Finally publish (priority 40)
            $sorted[4].GetType().Name | Should -Be "PublishReleaseAction"
        }
    }
    
    Context "Branch Actions" {
        It "Should create branch action" {
            $action = [CreateBranchAction]::new("v1", "abc123")
            
            $action.BranchName | Should -Be "v1"
            $action.Sha | Should -Be "abc123"
            $action.Priority | Should -Be 20
        }
        
        It "Should generate correct branch commands" {
            $action = [CreateBranchAction]::new("v1", "abc123")
            $commands = $action.GetManualCommands($script:state)
            
            $commands[0] | Should -Match "git push origin abc123:refs/heads/v1"
        }
        
        It "Should delete branch with high priority" {
            $action = [DeleteBranchAction]::new("v1")
            
            $action.Priority | Should -Be 10
        }
    }
    
    Context "Parameterized Priority Tests" {
        It "Action <ActionType> should have priority <ExpectedPriority>" -TestCases @(
            @{ ActionType = "DeleteTagAction"; Version = "v1.0.0"; Sha = $null; ReleaseId = 0; Force = $false; ExpectedPriority = 10 }
            @{ ActionType = "DeleteBranchAction"; Version = "v1"; Sha = $null; ReleaseId = 0; Force = $false; ExpectedPriority = 10 }
            @{ ActionType = "DeleteReleaseAction"; Version = "v1.0.0"; Sha = $null; ReleaseId = 123; Force = $false; ExpectedPriority = 10 }
            @{ ActionType = "CreateTagAction"; Version = "v1.0.0"; Sha = "abc123"; ReleaseId = 0; Force = $false; ExpectedPriority = 20 }
            @{ ActionType = "CreateBranchAction"; Version = "v1"; Sha = "abc123"; ReleaseId = 0; Force = $false; ExpectedPriority = 20 }
            @{ ActionType = "UpdateTagAction"; Version = "v1.0.0"; Sha = "abc123"; ReleaseId = 0; Force = $true; ExpectedPriority = 20 }
            @{ ActionType = "UpdateBranchAction"; Version = "v1"; Sha = "abc123"; ReleaseId = 0; Force = $true; ExpectedPriority = 20 }
            @{ ActionType = "CreateReleaseAction"; Version = "v1.0.0"; Sha = $null; ReleaseId = 0; Force = $false; ExpectedPriority = 30 }
            @{ ActionType = "PublishReleaseAction"; Version = "v1.0.0"; Sha = $null; ReleaseId = 123; Force = $false; ExpectedPriority = 40 }
            @{ ActionType = "RepublishReleaseAction"; Version = "v1.0.0"; Sha = $null; ReleaseId = 0; Force = $false; ExpectedPriority = 45 }
        ) {
            param($ActionType, $Version, $Sha, $ReleaseId, $Force, $ExpectedPriority)
            
            $action = switch ($ActionType) {
                "DeleteTagAction" { [DeleteTagAction]::new($Version) }
                "DeleteBranchAction" { [DeleteBranchAction]::new($Version) }
                "DeleteReleaseAction" { [DeleteReleaseAction]::new($Version, $ReleaseId) }
                "CreateTagAction" { [CreateTagAction]::new($Version, $Sha) }
                "CreateBranchAction" { [CreateBranchAction]::new($Version, $Sha) }
                "UpdateTagAction" { [UpdateTagAction]::new($Version, $Sha, $Force) }
                "UpdateBranchAction" { [UpdateBranchAction]::new($Version, $Sha, $Force) }
                "CreateReleaseAction" { [CreateReleaseAction]::new($Version, $true) }
                "PublishReleaseAction" { [PublishReleaseAction]::new($Version, $ReleaseId) }
                "RepublishReleaseAction" { [RepublishReleaseAction]::new($Version) }
            }
            
            $action.Priority | Should -Be $ExpectedPriority
        }
    }
    
    Context "Parameterized Manual Command Format Tests" {
        It "<ActionType> should generate command matching '<Pattern>'" -TestCases @(
            @{ ActionType = "DeleteTagAction"; Version = "v1.0.0"; Sha = $null; ReleaseId = 0; Pattern = "git tag -d v1.0.0" }
            @{ ActionType = "DeleteBranchAction"; Version = "v1"; Sha = $null; ReleaseId = 0; Pattern = "git branch -d v1" }
            @{ ActionType = "DeleteReleaseAction"; Version = "v1.0.0"; Sha = $null; ReleaseId = 123; Pattern = "gh release delete v1.0.0" }
            @{ ActionType = "CreateTagAction"; Version = "v1.0.0"; Sha = "abc123"; ReleaseId = 0; Pattern = "git push origin abc123:refs/tags/v1.0.0" }
            @{ ActionType = "CreateBranchAction"; Version = "v1"; Sha = "abc123"; ReleaseId = 0; Pattern = "git push origin abc123:refs/heads/v1" }
            @{ ActionType = "PublishReleaseAction"; Version = "v1.0.0"; Sha = $null; ReleaseId = 123; Pattern = "gh release edit v1.0.0 --draft=false" }
        ) {
            param($ActionType, $Version, $Sha, $ReleaseId, $Pattern)
            
            $action = switch ($ActionType) {
                "DeleteTagAction" { [DeleteTagAction]::new($Version) }
                "DeleteBranchAction" { [DeleteBranchAction]::new($Version) }
                "DeleteReleaseAction" { [DeleteReleaseAction]::new($Version, $ReleaseId) }
                "CreateTagAction" { [CreateTagAction]::new($Version, $Sha) }
                "CreateBranchAction" { [CreateBranchAction]::new($Version, $Sha) }
                "PublishReleaseAction" { [PublishReleaseAction]::new($Version, $ReleaseId) }
            }
            
            $commands = $action.GetManualCommands($script:state)
            $joinedCommands = $commands -join "`n"
            $escapedPattern = [regex]::Escape($Pattern)
            $joinedCommands | Should -Match $escapedPattern
        }
    }
    
    Context "ConvertTagToBranchAction" {
        It "Should create action with correct properties" {
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            
            $action.Name | Should -Be "v1"
            $action.Sha | Should -Be "abc123"
            $action.Priority | Should -Be 25
            $action.Description | Should -Be "Convert tag to branch"
            $action.Version | Should -Be "v1"
        }
        
        It "Should generate delete-only commands when branch already exists" {
            # Set up state with existing branch - VersionRef requires 4 params: (version, ref, sha, type)
            $branch = [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $script:state.Branches = @($branch)
            
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Be "git push origin :refs/tags/v1"
        }
        
        It "Should generate create-then-delete commands when branch does not exist" {
            # No branches in state
            $script:state.Branches = @()
            
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 2
            $commands[0] | Should -Be "git push origin abc123:refs/heads/v1"
            $commands[1] | Should -Be "git push origin :refs/tags/v1"
        }
        
        It "Should return empty commands when issue is unfixable" {
            # Create an issue marked as unfixable - ValidationIssue takes (type, severity, message)
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            $issue = [ValidationIssue]::new("wrong_ref_type", "error", "Tag has immutable release")
            $issue.Version = "v1"
            $issue.RemediationAction = $action
            $issue.Status = "unfixable"
            $script:state.Issues = @($issue)
            
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 0
        }
    }
    
    Context "ConvertBranchToTagAction" {
        It "Should create action with correct properties" {
            $action = [ConvertBranchToTagAction]::new("v1.0.0", "abc123")
            
            $action.Name | Should -Be "v1.0.0"
            $action.Sha | Should -Be "abc123"
            $action.Priority | Should -Be 25
            $action.Description | Should -Be "Convert branch to tag"
            $action.Version | Should -Be "v1.0.0"
        }
        
        It "Should generate delete-only commands when tag already exists" {
            # Set up state with existing tag - VersionRef requires 4 params: (version, ref, sha, type)
            $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $script:state.Tags = @($tag)
            
            $action = [ConvertBranchToTagAction]::new("v1.0.0", "abc123")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 1
            $commands[0] | Should -Be "git push origin :refs/heads/v1.0.0"
        }
        
        It "Should generate create-then-delete commands when tag does not exist" {
            # No tags in state
            $script:state.Tags = @()
            
            $action = [ConvertBranchToTagAction]::new("v1.0.0", "abc123")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 2
            $commands[0] | Should -Be "git push origin abc123:refs/tags/v1.0.0"
            $commands[1] | Should -Be "git push origin :refs/heads/v1.0.0"
        }
    }
    
    Context "ConvertTagToBranchAction Execution" {
        BeforeEach {
            # Mock the external functions
            Mock Test-ReleaseImmutability { return $false }
            Mock New-GitHubRef { return @{ Success = $true; RequiresManualFix = $false } }
            Mock Remove-GitHubRef { return $true }
        }
        
        It "Should mark issue unfixable when tag has immutable release" {
            # Mock immutability check to return true
            Mock Test-ReleaseImmutability { return $true }
            
            # Create issue for the action - ValidationIssue takes (type, severity, message)
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            $issue = [ValidationIssue]::new("wrong_ref_type", "error", "Tag should be branch")
            $issue.Version = "v1"
            $issue.RemediationAction = $action
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "unfixable"
            $issue.Message | Should -Match "immutable"
        }
        
        It "Should delete tag only when branch already exists" {
            # Set up state with existing branch - VersionRef requires 4 params
            $branch = [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $script:state.Branches = @($branch)
            
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
            # Should call Remove-GitHubRef for tag, not New-GitHubRef for branch
            Should -Invoke Remove-GitHubRef -Times 1 -ParameterFilter { $RefName -eq "refs/tags/v1" }
            Should -Not -Invoke New-GitHubRef
        }
        
        It "Should mark issue manual_fix_required when workflow permission error occurs" {
            Mock New-GitHubRef { return @{ Success = $false; RequiresManualFix = $true } }
            
            # Create issue for the action - ValidationIssue takes (type, severity, message)
            $action = [ConvertTagToBranchAction]::new("v1", "abc123")
            $issue = [ValidationIssue]::new("wrong_ref_type", "error", "Tag should be branch")
            $issue.Version = "v1"
            $issue.RemediationAction = $action
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            $script:state.Branches = @()  # No existing branch
            
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "manual_fix_required"
            $issue.Message | Should -Match "workflows.*permission"
        }
    }
    
    Context "ConvertBranchToTagAction Execution" {
        BeforeEach {
            Mock New-GitHubRef { return @{ Success = $true; RequiresManualFix = $false } }
            Mock Remove-GitHubRef { return $true }
        }
        
        It "Should delete branch only when tag already exists" {
            # Set up state with existing tag - VersionRef requires 4 params
            $tag = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $script:state.Tags = @($tag)
            
            $action = [ConvertBranchToTagAction]::new("v1.0.0", "abc123")
            $result = $action.Execute($script:state)
            
            $result | Should -Be $true
            # Should call Remove-GitHubRef for branch, not New-GitHubRef for tag
            Should -Invoke Remove-GitHubRef -Times 1 -ParameterFilter { $RefName -eq "refs/heads/v1.0.0" }
            Should -Not -Invoke New-GitHubRef
        }
        
        It "Should mark issue manual_fix_required when workflow permission error occurs" {
            Mock New-GitHubRef { return @{ Success = $false; RequiresManualFix = $true } }
            
            # Create issue for the action - ValidationIssue takes (type, severity, message)
            $action = [ConvertBranchToTagAction]::new("v1.0.0", "abc123")
            $issue = [ValidationIssue]::new("wrong_ref_type", "error", "Branch should be tag")
            $issue.Version = "v1.0.0"
            $issue.RemediationAction = $action
            $issue.Status = "pending"
            $script:state.Issues = @($issue)
            $script:state.Tags = @()  # No existing tag
            
            $result = $action.Execute($script:state)
            
            $result | Should -Be $false
            $issue.Status | Should -Be "manual_fix_required"
            $issue.Message | Should -Match "workflows.*permission"
        }
    }
}
