BeforeAll {
    # Suppress progress reporting for folder cleanup operations (must be global scope)
    $global:ProgressPreference = 'SilentlyContinue'

    # Load the module under test
    . "$PSScriptRoot/../../lib/VersionParser.ps1"
}

Describe "ConvertTo-Version" {
    Context "3-part version number support" {
        It "Should convert '<VersionString>' to version <Expected>" -TestCases @(
            @{ VersionString = "1"; Expected = "1.0.0" }
            @{ VersionString = "2"; Expected = "2.0.0" }
            @{ VersionString = "10"; Expected = "10.0.0" }
            @{ VersionString = "1.0"; Expected = "1.0.0" }
            @{ VersionString = "1.1"; Expected = "1.1.0" }
            @{ VersionString = "2.5"; Expected = "2.5.0" }
            @{ VersionString = "1.0.0"; Expected = "1.0.0" }
            @{ VersionString = "1.2.3"; Expected = "1.2.3" }
            @{ VersionString = "10.20.30"; Expected = "10.20.30" }
            @{ VersionString = "0.0.1"; Expected = "0.0.1" }
        ) {
            param($VersionString, $Expected)
            
            $result = ConvertTo-Version -Value $VersionString
            $result.ToString() | Should -Be $Expected
        }
    }
    
    Context "Versions with more than 3 components are truncated" {
        It "Should truncate '<VersionString>' to '<Expected>'" -TestCases @(
            @{ VersionString = "1.2.3.4"; Expected = "1.2.3" }
            @{ VersionString = "1.0.0.0"; Expected = "1.0.0" }
            @{ VersionString = "10.20.30.40"; Expected = "10.20.30" }
        ) {
            param($VersionString, $Expected)
            
            $result = ConvertTo-Version -Value $VersionString
            $result.ToString() | Should -Be $Expected
        }
    }
    
    Context "Invalid inputs" {
        It "Should throw on null or empty input" {
            { ConvertTo-Version -Value $null } | Should -Throw
            { ConvertTo-Version -Value "" } | Should -Throw
            { ConvertTo-Version -Value "   " } | Should -Throw
        }
    }
    
    Context "Version object properties" {
        It "Should return correct major, minor, and build components" {
            $result = ConvertTo-Version -Value "1.2.3"
            $result.Major | Should -Be 1
            $result.Minor | Should -Be 2
            $result.Build | Should -Be 3
        }
        
        It "Should default minor and build to 0 for single component" {
            $result = ConvertTo-Version -Value "5"
            $result.Major | Should -Be 5
            $result.Minor | Should -Be 0
            $result.Build | Should -Be 0
        }
        
        It "Should default build to 0 for two components" {
            $result = ConvertTo-Version -Value "3.7"
            $result.Major | Should -Be 3
            $result.Minor | Should -Be 7
            $result.Build | Should -Be 0
        }
    }
}

Describe "Test-ValidVersionPattern" {
    Context "Valid version patterns" {
        It "Should accept '<Pattern>' as valid" -TestCases @(
            @{ Pattern = "v1" }
            @{ Pattern = "v2" }
            @{ Pattern = "v10" }
            @{ Pattern = "v1.0" }
            @{ Pattern = "v1.1" }
            @{ Pattern = "v10.20" }
            @{ Pattern = "v1.0.0" }
            @{ Pattern = "v1.2.3" }
            @{ Pattern = "v10.20.30" }
            @{ Pattern = "v1.*" }
            @{ Pattern = "v2.*" }
            @{ Pattern = "v1.0.*" }
            @{ Pattern = "v1.2.*" }
        ) {
            param($Pattern)
            
            Test-ValidVersionPattern -Pattern $Pattern | Should -Be $true
        }
    }
    
    Context "Invalid version patterns (ReDoS prevention)" {
        It "Should reject '<Pattern>' as invalid" -TestCases @(
            @{ Pattern = "v" }
            @{ Pattern = "v-1" }
            @{ Pattern = "v1.*.0" }
            @{ Pattern = "v*.0" }
            @{ Pattern = "v1.0.0-beta" }
            @{ Pattern = "v1.0.0+build" }
            @{ Pattern = "invalid" }
            @{ Pattern = "1.0.0" }  # Missing 'v' prefix
        ) {
            param($Pattern)
            
            Test-ValidVersionPattern -Pattern $Pattern | Should -Be $false
        }

        It "Should reject empty or whitespace-only patterns" {
            # Note: The function has [Mandatory=$true] so empty strings will throw
            # In actual use, empty patterns would be caught before reaching this function
            { Test-ValidVersionPattern -Pattern "" } | Should -Throw
            Test-ValidVersionPattern -Pattern "   " | Should -Be $false
        }
    }
    
    Context "Pattern length limits (DoS prevention)" {
        It "Should reject patterns longer than 50 characters" {
            $longPattern = "v" + ("1" * 60)
            Test-ValidVersionPattern -Pattern $longPattern | Should -Be $false
        }
        
        It "Should accept patterns at the limit" {
            $validPattern = "v" + ("1" * 10) + "." + ("2" * 10) + "." + ("3" * 10)
            # This is 33 characters, should be valid
            Test-ValidVersionPattern -Pattern $validPattern | Should -Be $true
        }
    }
}
