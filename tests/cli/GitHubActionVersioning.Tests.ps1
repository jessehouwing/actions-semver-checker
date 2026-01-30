BeforeAll {
    # Suppress progress bars for cleaner test output (affects all operations in test session)
    $global:ProgressPreference = 'SilentlyContinue'

    # Import the module
    Import-Module "$PSScriptRoot/../../module/GitHubActionVersioning.psd1" -Force
}

AfterAll {
    # Clean up
    Remove-Module GitHubActionVersioning -ErrorAction SilentlyContinue
}

Describe "Test-GitHubActionVersioning" {
    Context "Parameter validation" {
        It "Should have Repository parameter" {
            $cmd = Get-Command Test-GitHubActionVersioning
            $cmd.Parameters.ContainsKey('Repository') | Should -Be $true
        }

        It "Should have Token parameter" {
            $cmd = Get-Command Test-GitHubActionVersioning
            $cmd.Parameters.ContainsKey('Token') | Should -Be $true
        }

        It "Should have CheckMinorVersion parameter with valid values" {
            $cmd = Get-Command Test-GitHubActionVersioning
            $param = $cmd.Parameters['CheckMinorVersion']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes.ValidValues | Should -Contain 'error'
            $param.Attributes.ValidValues | Should -Contain 'warning'
            $param.Attributes.ValidValues | Should -Contain 'none'
        }

        It "Should have CheckReleases parameter with valid values" {
            $cmd = Get-Command Test-GitHubActionVersioning
            $param = $cmd.Parameters['CheckReleases']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes.ValidValues | Should -Contain 'error'
            $param.Attributes.ValidValues | Should -Contain 'warning'
            $param.Attributes.ValidValues | Should -Contain 'none'
        }

        It "Should have CheckReleaseImmutability parameter with valid values" {
            $cmd = Get-Command Test-GitHubActionVersioning
            $param = $cmd.Parameters['CheckReleaseImmutability']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes.ValidValues | Should -Contain 'error'
            $param.Attributes.ValidValues | Should -Contain 'warning'
            $param.Attributes.ValidValues | Should -Contain 'none'
        }

        It "Should have FloatingVersionsUse parameter with valid values" {
            $cmd = Get-Command Test-GitHubActionVersioning
            $param = $cmd.Parameters['FloatingVersionsUse']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes.ValidValues | Should -Contain 'tags'
            $param.Attributes.ValidValues | Should -Contain 'branches'
        }

        It "Should have IgnorePreviewReleases parameter" {
            $cmd = Get-Command Test-GitHubActionVersioning
            $cmd.Parameters.ContainsKey('IgnorePreviewReleases') | Should -Be $true
        }

        It "Should have AutoFix switch parameter" {
            $cmd = Get-Command Test-GitHubActionVersioning
            $param = $cmd.Parameters['AutoFix']
            $param | Should -Not -BeNullOrEmpty
            $param.SwitchParameter | Should -Be $true
        }

        It "Should have IgnoreVersions parameter" {
            $cmd = Get-Command Test-GitHubActionVersioning
            $cmd.Parameters.ContainsKey('IgnoreVersions') | Should -Be $true
        }

        It "Should have Rules parameter" {
            $cmd = Get-Command Test-GitHubActionVersioning
            $cmd.Parameters.ContainsKey('Rules') | Should -Be $true
        }

        It "Should have PassThru switch parameter" {
            $cmd = Get-Command Test-GitHubActionVersioning
            $param = $cmd.Parameters['PassThru']
            $param | Should -Not -BeNullOrEmpty
            $param.SwitchParameter | Should -Be $true
        }

        It "Should have ApiUrl parameter" {
            $cmd = Get-Command Test-GitHubActionVersioning
            $cmd.Parameters.ContainsKey('ApiUrl') | Should -Be $true
        }

        It "Should have ServerUrl parameter" {
            $cmd = Get-Command Test-GitHubActionVersioning
            $cmd.Parameters.ContainsKey('ServerUrl') | Should -Be $true
        }
    }

    Context "Repository parameter handling" {
        It "Should return error when Repository is not provided and GITHUB_REPOSITORY is not set" {
            # Save current env var
            $oldRepo = $env:GITHUB_REPOSITORY
            try {
                $env:GITHUB_REPOSITORY = $null
                
                $result = Test-GitHubActionVersioning -PassThru
                
                $result.ReturnCode | Should -Be 1
            }
            finally {
                $env:GITHUB_REPOSITORY = $oldRepo
            }
        }

        It "Should use GITHUB_REPOSITORY environment variable when Repository not provided" {
            # Save current env var
            $oldRepo = $env:GITHUB_REPOSITORY
            try {
                $env:GITHUB_REPOSITORY = "test-owner/test-repo"
                
                # Mock API calls to prevent actual API requests
                Mock -ModuleName GitHubActionVersioning Get-GitHubTags { return @() }
                Mock -ModuleName GitHubActionVersioning Get-GitHubReleases { return @() }
                
                $result = Test-GitHubActionVersioning -PassThru
                
                # Should not fail on repository validation
                $result | Should -Not -BeNullOrEmpty
            }
            finally {
                $env:GITHUB_REPOSITORY = $oldRepo
            }
        }

        It "Should return error for invalid repository format" {
            $result = Test-GitHubActionVersioning -Repository "invalid-format" -PassThru
            
            $result.ReturnCode | Should -Be 1
        }
    }

    Context "Token resolution" {
        It "Should warn when no token is available" {
            # Save current env vars
            $oldToken = $env:GITHUB_TOKEN
            try {
                $env:GITHUB_TOKEN = $null
                
                # Mock gh command to fail
                Mock -ModuleName GitHubActionVersioning gh { throw "gh not found" }
                
                # Mock API calls
                Mock -ModuleName GitHubActionVersioning Get-GitHubTags { return @() }
                Mock -ModuleName GitHubActionVersioning Get-GitHubReleases { return @() }
                
                { Test-GitHubActionVersioning -Repository "owner/repo" -WarningVariable warnings } | Should -Not -Throw
            }
            finally {
                $env:GITHUB_TOKEN = $oldToken
            }
        }
    }

    Context "PassThru parameter" {
        It "Should return hashtable with expected properties when PassThru is used" {
            # Mock API calls
            Mock -ModuleName GitHubActionVersioning Get-GitHubTags { return @() }
            Mock -ModuleName GitHubActionVersioning Get-GitHubReleases { return @() }
            
            $result = Test-GitHubActionVersioning -Repository "owner/repo" -PassThru
            
            $result | Should -Not -BeNullOrEmpty
            $result.ContainsKey('Issues') | Should -Be $true
            $result.ContainsKey('FixedCount') | Should -Be $true
            $result.ContainsKey('FailedCount') | Should -Be $true
            $result.ContainsKey('UnfixableCount') | Should -Be $true
            $result.ContainsKey('ReturnCode') | Should -Be $true
        }
    }
}

Describe "CliLogging functions" {
    BeforeAll {
        # Test CliLogging functions directly since they are internal helper functions
        # not exported from the module. These functions are used internally by
        # Test-GitHubActionVersioning but are tested separately here.
        . "$PSScriptRoot/../../module/CliLogging.ps1"
        . "$PSScriptRoot/../../lib/StateModel.ps1"
    }

    Context "Write-ActionsError" {
        It "Should write error message" {
            { Write-ActionsError -Message "Test error" } | Should -Not -Throw
        }

        It "Should add error to State when provided" {
            $state = [RepositoryState]::new()
            Write-ActionsError -Message "Test error" -State $state
            
            $state.Issues.Count | Should -Be 1
            $state.Issues[0].Severity | Should -Be "error"
        }
    }

    Context "Write-ActionsWarning" {
        It "Should write warning message" {
            { Write-ActionsWarning -Message "Test warning" } | Should -Not -Throw
        }
    }

    Context "Write-ActionsMessage" {
        It "Should call Write-ActionsError for error severity" {
            { Write-ActionsMessage -Message "Test" -Severity "error" } | Should -Not -Throw
        }

        It "Should call Write-ActionsWarning for warning severity" {
            { Write-ActionsMessage -Message "Test" -Severity "warning" } | Should -Not -Throw
        }

        It "Should not write anything for none severity" {
            { Write-ActionsMessage -Message "Test" -Severity "none" } | Should -Not -Throw
        }
    }

    Context "Write-SafeOutput" {
        It "Should write output without workflow commands" {
            { Write-SafeOutput -Message "Test message" } | Should -Not -Throw
        }

        It "Should handle prefix" {
            { Write-SafeOutput -Message "Test message" -Prefix "PREFIX: " } | Should -Not -Throw
        }
    }
}
