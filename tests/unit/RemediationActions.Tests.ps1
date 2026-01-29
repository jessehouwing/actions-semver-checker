BeforeAll {
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
        It "Should generate manual commands without comments" {
            $action = [RepublishReleaseAction]::new("v1.0.0")
            $commands = $action.GetManualCommands($script:state)
            
            $commands.Count | Should -Be 2
            $commands[0] | Should -Match "gh release edit v1.0.0 --draft=true"
            $commands[1] | Should -Match "gh release edit v1.0.0 --draft=false"
            
            # Verify no comment lines
            foreach ($cmd in $commands) {
                $cmd | Should -Not -Match "^#"
            }
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
}
