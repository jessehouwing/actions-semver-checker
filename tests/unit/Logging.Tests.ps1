BeforeAll {
    # Suppress progress reporting for folder cleanup operations
    $ProgressPreference = 'SilentlyContinue'

    # Load the module under test
    . "$PSScriptRoot/../../lib/StateModel.ps1"
    . "$PSScriptRoot/../../lib/Logging.ps1"
}

Describe "Write-SafeOutput" {
    It "Should write message with stop-commands wrapper" {
        # Capture output
        $output = & {
            Write-SafeOutput -Message "Test message"
        } 6>&1 | Out-String
        
        # Should contain stop-commands pattern
        $output | Should -Match "::stop-commands::"
        $output | Should -Match "Test message"
    }
    
    It "Should include prefix before stop-commands" {
        $output = & {
            Write-SafeOutput -Message "Details here" -Prefix "::error title=Test::"
        } 6>&1 | Out-String
        
        # Prefix should appear before stop-commands
        $output | Should -Match "::error title=Test::"
        $output | Should -Match "Details here"
    }
    
    It "Should neutralize workflow commands in message" {
        $output = & {
            Write-SafeOutput -Message "::set-env name=MALICIOUS::value"
        } 6>&1 | Out-String
        
        # The message should be wrapped in stop-commands
        $output | Should -Match "::stop-commands::"
        $output | Should -Match "::set-env"
    }
}

Describe "Write-ActionsError" {
    It "Should output the error message" {
        $output = & {
            Write-ActionsError -Message "::error::Test error"
        } | Out-String
        
        $output | Should -Match "::error::Test error"
    }
    
    It "Should track issue in State when provided" {
        $state = [RepositoryState]::new()
        
        Write-ActionsError -Message "Test error" -State $state
        
        $state.Issues.Count | Should -Be 1
        $state.Issues[0].Severity | Should -Be "error"
    }
    
    It "Should set global returnCode when State not provided" {
        $global:returnCode = 0
        
        Write-ActionsError -Message "Test error"
        
        $global:returnCode | Should -Be 1
    }
}

Describe "Write-ActionsWarning" {
    It "Should output the warning message" {
        $output = & {
            Write-ActionsWarning -Message "::warning::Test warning"
        } | Out-String
        
        $output | Should -Match "::warning::Test warning"
    }
}

Describe "Write-ActionsMessage" {
    It "Should call Write-ActionsError for severity 'error'" {
        $global:returnCode = 0
        
        Write-ActionsMessage -Message "Test" -Severity "error"
        
        $global:returnCode | Should -Be 1
    }
    
    It "Should call Write-ActionsWarning for severity 'warning'" {
        $output = & {
            Write-ActionsMessage -Message "::warning::Test" -Severity "warning"
        } | Out-String
        
        $output | Should -Match "::warning::Test"
    }
    
    It "Should not output anything for severity 'none'" {
        $output = & {
            Write-ActionsMessage -Message "Should not appear" -Severity "none"
        } | Out-String
        
        $output | Should -BeNullOrEmpty
    }
    
    It "Should accept State parameter and track issues" {
        $state = [RepositoryState]::new()
        
        Write-ActionsMessage -Message "Test" -Severity "error" -State $state
        
        $state.Issues.Count | Should -Be 1
    }
}
