BeforeAll {
    . "$PSScriptRoot/../../StateModel.ps1"
    . "$PSScriptRoot/RemediationAction.ps1"
}

Describe "RemediationAction Base Class" {
    Context "Constructor" {
        It "Should set properties correctly" {
            $action = [RemediationAction]::new("Test action", "v1.0.0")
            
            $action.Description | Should -Be "Test action"
            $action.Version | Should -Be "v1.0.0"
            $action.Priority | Should -Be 50  # Default priority
        }
    }
    
    Context "ToString" {
        It "Should return formatted string" {
            $action = [RemediationAction]::new("Create tag", "v1.0.0")
            
            $action.ToString() | Should -Be "Create tag for v1.0.0"
        }
    }
    
    Context "Abstract Methods" {
        It "Execute should throw when not overridden" {
            $action = [RemediationAction]::new("Test action", "v1.0.0")
            $state = [RepositoryState]::new()
            
            { $action.Execute($state) } | Should -Throw "*must be implemented*"
        }
        
        It "GetManualCommands should throw when not overridden" {
            $action = [RemediationAction]::new("Test action", "v1.0.0")
            $state = [RepositoryState]::new()
            
            { $action.GetManualCommands($state) } | Should -Throw "*must be implemented*"
        }
    }
}
