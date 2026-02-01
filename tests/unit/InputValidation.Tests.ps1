BeforeAll {
    # Suppress progress reporting for folder cleanup operations (must be global scope)
    $global:ProgressPreference = 'SilentlyContinue'

    # Load dependencies
    . "$PSScriptRoot/../../lib/StateModel.ps1"
    . "$PSScriptRoot/../../lib/VersionParser.ps1"
    . "$PSScriptRoot/../../lib/InputValidation.ps1"
}

Describe "ConvertTo-CheckLevel" {
    Context "Boolean string conversions" {
        It "Should convert 'true' to 'error'" {
            ConvertTo-CheckLevel -Value "true" | Should -Be "error"
        }

        It "Should convert 'TRUE' to 'error' (case insensitive)" {
            ConvertTo-CheckLevel -Value "TRUE" | Should -Be "error"
        }

        It "Should convert 'false' to 'none'" {
            ConvertTo-CheckLevel -Value "false" | Should -Be "none"
        }

        It "Should convert 'FALSE' to 'none' (case insensitive)" {
            ConvertTo-CheckLevel -Value "FALSE" | Should -Be "none"
        }
    }

    Context "Direct level values" {
        It "Should pass through '<Value>' unchanged" -TestCases @(
            @{ Value = "error" }
            @{ Value = "warning" }
            @{ Value = "none" }
        ) {
            param($Value)
            ConvertTo-CheckLevel -Value $Value | Should -Be $Value
        }

        It "Should normalize '<InputValue>' to '<Expected>' (case insensitive)" -TestCases @(
            @{ InputValue = "ERROR"; Expected = "error" }
            @{ InputValue = "Warning"; Expected = "warning" }
            @{ InputValue = "NONE"; Expected = "none" }
        ) {
            param($InputValue, $Expected)
            ConvertTo-CheckLevel -Value $InputValue | Should -Be $Expected
        }
    }

    Context "Null coalesce behavior" {
        # Note: The function uses ($Value ?? $Default) which means empty string '' is NOT replaced by default
        # This tests the actual behavior of the function
        It "Should return empty string for empty string input (null coalesce does not trigger)" {
            # Empty string is not null, so ?? does not use Default
            ConvertTo-CheckLevel -Value "" | Should -Be ""
        }

        It "Should return empty string for null input (null coalesce with string parameter)" {
            # When null is passed to [string]$Value, PowerShell converts it to empty string before function executes
            ConvertTo-CheckLevel -Value $null | Should -Be ""
        }
    }

    Context "Default parameter value" {
        # Note: The -Default parameter only works when $Value is $null AND passed as $null
        # Due to PowerShell's [string] type coercion, $null becomes '' before ?? operator runs
        # The default is primarily useful when the caller uses an expression that can be truly $null
        It "Should have Default parameter defined" {
            # Verify the Default parameter exists and is a string type
            $cmd = Get-Command ConvertTo-CheckLevel
            $cmd.Parameters.ContainsKey('Default') | Should -Be $true
            $cmd.Parameters['Default'].ParameterType.Name | Should -Be 'String'
        }

        It "Should use default value 'error' in function definition" {
            # Verify the default is coded as expected by checking the script block
            $cmd = Get-Command ConvertTo-CheckLevel
            $cmd.ScriptBlock.ToString() | Should -BeLike '*$Default = "error"*'
        }
    }

    Context "Whitespace handling" {
        It "Should trim leading and trailing spaces from 'error'" {
            ConvertTo-CheckLevel -Value "  error  " | Should -Be "error"
        }

        It "Should trim whitespace from 'warning'" {
            ConvertTo-CheckLevel -Value "`twarning`t" | Should -Be "warning"
        }

        It "Should trim whitespace from 'true' and convert to 'error'" {
            ConvertTo-CheckLevel -Value " true " | Should -Be "error"
        }

        It "Should trim whitespace from 'false' and convert to 'none'" {
            ConvertTo-CheckLevel -Value " false " | Should -Be "none"
        }
    }
}

Describe "ConvertTo-IgnoreVersionsList" {
    Context "Empty and null input handling" {
        It "Should return empty array for null input" {
            $result = ConvertTo-IgnoreVersionsList -RawInput $null
            $result | Should -BeNullOrEmpty
            $result.Count | Should -Be 0
        }

        It "Should return empty array for empty string" {
            $result = ConvertTo-IgnoreVersionsList -RawInput ""
            $result | Should -BeNullOrEmpty
        }

        It "Should return empty array for whitespace-only string" {
            $result = ConvertTo-IgnoreVersionsList -RawInput "   "
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Comma-separated list parsing" {
        It "Should parse single version" {
            $result = ConvertTo-IgnoreVersionsList -RawInput "v1.0.0"
            $result | Should -Be @("v1.0.0")
        }

        It "Should parse comma-separated versions" {
            $result = ConvertTo-IgnoreVersionsList -RawInput "v1.0.0, v2.0.0, v3.0.0"
            $result.Count | Should -Be 3
            $result | Should -Contain "v1.0.0"
            $result | Should -Contain "v2.0.0"
            $result | Should -Contain "v3.0.0"
        }

        It "Should trim whitespace around versions" {
            $result = ConvertTo-IgnoreVersionsList -RawInput "  v1.0.0  ,  v2.0.0  "
            $result | Should -Be @("v1.0.0", "v2.0.0")
        }

        It "Should handle commas without spaces" {
            $result = ConvertTo-IgnoreVersionsList -RawInput "v1.0.0,v2.0.0,v3.0.0"
            $result.Count | Should -Be 3
        }
    }

    Context "Newline-separated list parsing" {
        It "Should parse newline-separated versions" {
            $result = ConvertTo-IgnoreVersionsList -RawInput "v1.0.0`nv2.0.0`nv3.0.0"
            $result.Count | Should -Be 3
            $result | Should -Contain "v1.0.0"
            $result | Should -Contain "v2.0.0"
            $result | Should -Contain "v3.0.0"
        }

        It "Should handle Windows-style line endings (CRLF)" {
            $result = ConvertTo-IgnoreVersionsList -RawInput "v1.0.0`r`nv2.0.0`r`nv3.0.0"
            $result.Count | Should -Be 3
        }

        It "Should handle mixed newlines and commas" {
            $result = ConvertTo-IgnoreVersionsList -RawInput "v1.0.0,v2.0.0`nv3.0.0"
            $result.Count | Should -Be 3
        }
    }

    Context "JSON array parsing" {
        It "Should parse JSON array string" {
            $result = ConvertTo-IgnoreVersionsList -RawInput '["v1.0.0", "v2.0.0"]'
            $result.Count | Should -Be 2
            $result | Should -Contain "v1.0.0"
            $result | Should -Contain "v2.0.0"
        }

        It "Should handle pre-parsed array" {
            $inputArray = @("v1.0.0", "v2.0.0", "v3.0.0")
            $result = ConvertTo-IgnoreVersionsList -RawInput $inputArray
            $result.Count | Should -Be 3
        }

        It "Should handle empty JSON array" {
            $result = ConvertTo-IgnoreVersionsList -RawInput '[]'
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Version pattern validation" {
        It "Should accept valid version patterns" -TestCases @(
            @{ Pattern = "v1" }
            @{ Pattern = "v1.0" }
            @{ Pattern = "v1.0.0" }
            @{ Pattern = "v1.*" }
            @{ Pattern = "v1.0.*" }
        ) {
            param($Pattern)
            $result = ConvertTo-IgnoreVersionsList -RawInput $Pattern
            $result | Should -Contain $Pattern
        }

        It "Should skip invalid version patterns" {
            # These are invalid patterns that should be filtered out
            $result = ConvertTo-IgnoreVersionsList -RawInput "invalid, v1.0.0, badpattern"
            $result.Count | Should -Be 1
            $result | Should -Contain "v1.0.0"
            $result | Should -Not -Contain "invalid"
            $result | Should -Not -Contain "badpattern"
        }

        It "Should skip versions without 'v' prefix" {
            $result = ConvertTo-IgnoreVersionsList -RawInput "1.0.0, v2.0.0"
            $result | Should -Be @("v2.0.0")
        }

        It "Should handle empty entries in lists" {
            $result = ConvertTo-IgnoreVersionsList -RawInput "v1.0.0, , , v2.0.0"
            $result.Count | Should -Be 2
        }
    }

    Context "Edge cases" {
        It "Should handle JSON-like string that is not valid JSON" {
            # Invalid JSON should fall back to comma/newline parsing
            $result = ConvertTo-IgnoreVersionsList -RawInput '[v1.0.0, v2.0.0]'
            # This should emit a warning and treat as comma-separated
            # Since items inside brackets aren't quoted, JSON parse fails
            $result | Should -BeNullOrEmpty  # Both fall through but fail validation
        }

        It "Should handle consecutive delimiters" {
            $result = ConvertTo-IgnoreVersionsList -RawInput "v1.0.0,,,v2.0.0"
            $result.Count | Should -Be 2
        }
    }
}

Describe "Test-ActionInput" {
    Context "Valid configurations" {
        It "Should return no errors for valid configuration" {
            $config = @{
                CheckMinorVersion        = "error"
                CheckReleases            = "warning"
                CheckReleaseImmutability = "none"
                FloatingVersionsUse      = "tags"
            }
            # Force array context to handle PowerShell's scalar unboxing
            $errors = @(Test-ActionInput -Config $config)
            $errors.Count | Should -Be 0
        }

        It "Should accept all valid check-minor-version values" -TestCases @(
            @{ Value = "error" }
            @{ Value = "warning" }
            @{ Value = "none" }
        ) {
            param($Value)
            $config = @{
                CheckMinorVersion        = $Value
                CheckReleases            = "error"
                CheckReleaseImmutability = "error"
                FloatingVersionsUse      = "tags"
            }
            # Force array context to handle PowerShell's scalar unboxing
            $errors = @(Test-ActionInput -Config $config)
            $errors.Count | Should -Be 0
        }

        It "Should accept 'tags' for floating-versions-use" {
            $config = @{
                CheckMinorVersion        = "error"
                CheckReleases            = "error"
                CheckReleaseImmutability = "error"
                FloatingVersionsUse      = "tags"
            }
            # Force array context to handle PowerShell's scalar unboxing
            $errors = @(Test-ActionInput -Config $config)
            $errors.Count | Should -Be 0
        }

        It "Should accept 'branches' for floating-versions-use" {
            $config = @{
                CheckMinorVersion        = "error"
                CheckReleases            = "error"
                CheckReleaseImmutability = "error"
                FloatingVersionsUse      = "branches"
            }
            # Force array context to handle PowerShell's scalar unboxing
            $errors = @(Test-ActionInput -Config $config)
            $errors.Count | Should -Be 0
        }
    }

    Context "Invalid check-minor-version values" {
        It "Should return error for invalid check-minor-version value" {
            $config = @{
                CheckMinorVersion        = "invalid"
                CheckReleases            = "error"
                CheckReleaseImmutability = "error"
                FloatingVersionsUse      = "tags"
            }
            # Force array context to handle PowerShell's scalar unboxing
            $errors = @(Test-ActionInput -Config $config)
            $errors.Count | Should -Be 1
            $errors[0] | Should -BeLike "*check-minor-version*"
        }
    }

    Context "Invalid check-releases values" {
        It "Should return error for invalid check-releases value" {
            $config = @{
                CheckMinorVersion        = "error"
                CheckReleases            = "bad"
                CheckReleaseImmutability = "error"
                FloatingVersionsUse      = "tags"
            }
            # Force array context to handle PowerShell's scalar unboxing
            $errors = @(Test-ActionInput -Config $config)
            $errors.Count | Should -Be 1
            $errors[0] | Should -BeLike "*check-releases*"
        }
    }

    Context "Invalid check-release-immutability values" {
        It "Should return error for invalid check-release-immutability value" {
            $config = @{
                CheckMinorVersion        = "error"
                CheckReleases            = "error"
                CheckReleaseImmutability = "invalid"
                FloatingVersionsUse      = "tags"
            }
            # Force array context to handle PowerShell's scalar unboxing
            $errors = @(Test-ActionInput -Config $config)
            $errors.Count | Should -Be 1
            $errors[0] | Should -BeLike "*check-release-immutability*"
        }
    }

    Context "Invalid floating-versions-use values" {
        It "Should return error for invalid floating-versions-use value" {
            $config = @{
                CheckMinorVersion        = "error"
                CheckReleases            = "error"
                CheckReleaseImmutability = "error"
                FloatingVersionsUse      = "invalid"
            }
            # Force array context to handle PowerShell's scalar unboxing
            $errors = @(Test-ActionInput -Config $config)
            $errors.Count | Should -Be 1
            $errors[0] | Should -BeLike "*floating-versions-use*"
        }
    }

    Context "Multiple validation errors" {
        It "Should return all errors when multiple inputs are invalid" {
            $config = @{
                CheckMinorVersion        = "bad1"
                CheckReleases            = "bad2"
                CheckReleaseImmutability = "bad3"
                FloatingVersionsUse      = "bad4"
            }
            # Force array context to handle PowerShell's scalar unboxing
            $errors = @(Test-ActionInput -Config $config)
            $errors.Count | Should -Be 4
        }
    }
}

Describe "Read-ActionInput" {
    BeforeEach {
        # Save original environment variables
        $script:originalInputs = $env:inputs
        $script:originalToken = $env:GITHUB_TOKEN
    }

    AfterEach {
        # Restore original environment variables
        $env:inputs = $script:originalInputs
        $env:GITHUB_TOKEN = $script:originalToken
    }

    Context "Missing inputs environment variable" {
        It "Should return null when inputs env var is not set" {
            $env:inputs = $null
            $state = [RepositoryState]::new()
            
            $result = Read-ActionInput -State $state
            
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Invalid JSON in inputs" {
        It "Should return null for invalid JSON" {
            $env:inputs = "not valid json"
            $state = [RepositoryState]::new()
            
            $result = Read-ActionInput -State $state
            
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Default values" {
        It "Should use default values when inputs are empty" {
            $env:inputs = '{}'
            $env:GITHUB_TOKEN = "test-token"
            $state = [RepositoryState]::new()
            $state.Token = "test-token"
            
            $result = Read-ActionInput -State $state
            
            $result | Should -Not -BeNullOrEmpty
            $result.CheckMinorVersion | Should -Be "error"  # default from "true"
            $result.CheckReleases | Should -Be "error"
            $result.CheckReleaseImmutability | Should -Be "error"
            $result.IgnorePreviewReleases | Should -Be $true
            $result.FloatingVersionsUse | Should -Be "tags"
            $result.AutoFix | Should -Be $false
            $result.IgnoreVersions.Count | Should -Be 0
        }
    }

    Context "Custom input values" {
        It "Should parse custom check levels" {
            $env:inputs = @{
                'check-minor-version'        = 'warning'
                'check-releases'             = 'none'
                'check-release-immutability' = 'warning'
            } | ConvertTo-Json
            $state = [RepositoryState]::new()
            $state.Token = "test-token"
            
            $result = Read-ActionInput -State $state
            
            $result.CheckMinorVersion | Should -Be "warning"
            $result.CheckReleases | Should -Be "none"
            $result.CheckReleaseImmutability | Should -Be "warning"
        }

        It "Should parse boolean inputs" {
            $env:inputs = @{
                'ignore-preview-releases' = 'false'
                'auto-fix'                = 'true'
            } | ConvertTo-Json
            $state = [RepositoryState]::new()
            $state.Token = "test-token"
            
            $result = Read-ActionInput -State $state
            
            $result.IgnorePreviewReleases | Should -Be $false
            $result.AutoFix | Should -Be $true
        }

        It "Should parse floating-versions-use" {
            $env:inputs = @{
                'floating-versions-use' = 'branches'
            } | ConvertTo-Json
            $state = [RepositoryState]::new()
            $state.Token = "test-token"
            
            $result = Read-ActionInput -State $state
            
            $result.FloatingVersionsUse | Should -Be "branches"
        }

        It "Should parse ignore-versions list" {
            $env:inputs = @{
                'ignore-versions' = 'v1.0.0, v2.0.0'
            } | ConvertTo-Json
            $state = [RepositoryState]::new()
            $state.Token = "test-token"
            
            $result = Read-ActionInput -State $state
            
            $result.IgnoreVersions.Count | Should -Be 2
            $result.IgnoreVersions | Should -Contain "v1.0.0"
            $result.IgnoreVersions | Should -Contain "v2.0.0"
        }

        It "Should use token from inputs when provided" {
            $env:inputs = @{
                'token' = 'custom-token'
            } | ConvertTo-Json
            $env:GITHUB_TOKEN = "env-token"
            $state = [RepositoryState]::new()
            $state.Token = "state-token"
            
            $result = Read-ActionInput -State $state
            
            $result.Token | Should -Be "custom-token"
        }

        It "Should fall back to state token when input token is empty" {
            $env:inputs = @{
                'token' = ''
            } | ConvertTo-Json
            $state = [RepositoryState]::new()
            $state.Token = "state-token"
            
            $result = Read-ActionInput -State $state
            
            $result.Token | Should -Be "state-token"
        }

        It "Should fall back to state token when input token is not specified" {
            $env:inputs = '{}'
            $state = [RepositoryState]::new()
            $state.Token = "state-token"
            
            $result = Read-ActionInput -State $state
            
            $result.Token | Should -Be "state-token"
        }
    }

    Context "Boolean conversion from string" {
        It "Should convert string 'true' to check level 'error'" {
            $env:inputs = @{
                'check-minor-version' = 'true'
            } | ConvertTo-Json
            $state = [RepositoryState]::new()
            $state.Token = "test-token"
            
            $result = Read-ActionInput -State $state
            
            $result.CheckMinorVersion | Should -Be "error"
        }

        It "Should convert string 'false' to check level 'none'" {
            $env:inputs = @{
                'check-minor-version' = 'false'
            } | ConvertTo-Json
            $state = [RepositoryState]::new()
            $state.Token = "test-token"
            
            $result = Read-ActionInput -State $state
            
            $result.CheckMinorVersion | Should -Be "none"
        }
    }
}

Describe "Test-AutoFixRequirement" {
    Context "Auto-fix disabled" {
        It "Should return true when auto-fix is disabled" {
            $state = [RepositoryState]::new()
            $state.Token = $null
            
            $result = Test-AutoFixRequirement -State $state -AutoFix $false
            
            $result | Should -Be $true
        }

        It "Should return true when auto-fix is disabled even with token" {
            $state = [RepositoryState]::new()
            $state.Token = "some-token"
            
            $result = Test-AutoFixRequirement -State $state -AutoFix $false
            
            $result | Should -Be $true
        }
    }

    Context "Auto-fix enabled" {
        It "Should return true when auto-fix is enabled with token" {
            $state = [RepositoryState]::new()
            $state.Token = "valid-token"
            
            $result = Test-AutoFixRequirement -State $state -AutoFix $true
            
            $result | Should -Be $true
        }

        It "Should return false when auto-fix is enabled without token" {
            $state = [RepositoryState]::new()
            $state.Token = $null
            
            # Function returns $false directly (error message goes to Write-Host)
            $result = Test-AutoFixRequirement -State $state -AutoFix $true
            
            $result | Should -Be $false
        }

        It "Should return false when auto-fix is enabled with empty token" {
            $state = [RepositoryState]::new()
            $state.Token = ""
            
            # Function returns $false directly (error message goes to Write-Host)
            $result = Test-AutoFixRequirement -State $state -AutoFix $true
            
            $result | Should -Be $false
        }
    }
}

Describe "Write-InputDebugInfo" {
    It "Should not throw when called with valid config" {
        $config = @{
            AutoFix                  = $true
            CheckMinorVersion        = "error"
            CheckReleases            = "warning"
            CheckReleaseImmutability = "none"
            IgnorePreviewReleases    = $false
            FloatingVersionsUse      = "branches"
            IgnoreVersions           = @("v1.0.0", "v2.0.0")
        }
        
        { Write-InputDebugInfo -Config $config } | Should -Not -Throw
    }

    It "Should handle empty ignore-versions array" {
        $config = @{
            AutoFix                  = $false
            CheckMinorVersion        = "error"
            CheckReleases            = "error"
            CheckReleaseImmutability = "error"
            IgnorePreviewReleases    = $true
            FloatingVersionsUse      = "tags"
            IgnoreVersions           = @()
        }
        
        { Write-InputDebugInfo -Config $config } | Should -Not -Throw
    }
}

Describe "Write-RepositoryDebugInfo" {
    It "Should not throw when called with valid state and config" {
        $state = [RepositoryState]::new()
        $state.RepoOwner = "test-owner"
        $state.RepoName = "test-repo"
        $state.ApiUrl = "https://api.github.com"
        $state.ServerUrl = "https://github.com"
        $state.Token = "test-token"
        
        $config = @{
            CheckReleases            = "error"
            CheckReleaseImmutability = "warning"
            FloatingVersionsUse      = "tags"
        }
        
        { Write-RepositoryDebugInfo -State $state -Config $config } | Should -Not -Throw
    }

    It "Should handle missing token gracefully" {
        $state = [RepositoryState]::new()
        $state.RepoOwner = "test-owner"
        $state.RepoName = "test-repo"
        $state.ApiUrl = "https://api.github.com"
        $state.ServerUrl = "https://github.com"
        $state.Token = $null
        
        $config = @{
            CheckReleases            = "none"
            CheckReleaseImmutability = "none"
            FloatingVersionsUse      = "branches"
        }
        
        { Write-RepositoryDebugInfo -State $state -Config $config } | Should -Not -Throw
    }
}
