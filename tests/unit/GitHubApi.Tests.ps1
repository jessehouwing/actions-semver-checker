BeforeAll {
    # Suppress progress reporting for folder cleanup operations (must be global scope)
    $global:ProgressPreference = 'SilentlyContinue'

    # Load dependent modules
    . "$PSScriptRoot/../../lib/StateModel.ps1"
    . "$PSScriptRoot/../../lib/Logging.ps1"
    . "$PSScriptRoot/../../lib/GitHubApi.ps1"
}

Describe "Test-ImmutableReleaseError" {
    Context "422 errors with immutable release message" {
        It "Should return true for structured 422 error with immutable release message" {
            # Create a mock error with proper structure
            $errorDetails = @{
                message = "Validation Failed"
                errors = @(
                    @{
                        resource = "Release"
                        code = "custom"
                        field = "tag_name"
                        message = "tag_name was used by an immutable release"
                    }
                )
            } | ConvertTo-Json
            
            $mockException = New-Object System.Exception "The remote server returned an error: (422)"
            $mockException | Add-Member -NotePropertyName "Response" -NotePropertyValue @{ StatusCode = @{ value__ = 422 } }
            
            $mockErrorRecord = @{
                Exception = $mockException
                ErrorDetails = @{ Message = $errorDetails }
            }
            
            $result = Test-ImmutableReleaseError -ErrorRecord $mockErrorRecord
            $result | Should -Be $true
        }
        
        It "Should return false for 422 error without immutable release message" {
            $errorDetails = @{
                message = "Validation Failed"
                errors = @(
                    @{
                        resource = "Release"
                        code = "custom"
                        field = "tag_name"
                        message = "some other error"
                    }
                )
            } | ConvertTo-Json
            
            $mockException = New-Object System.Exception "The remote server returned an error: (422)"
            $mockException | Add-Member -NotePropertyName "Response" -NotePropertyValue @{ StatusCode = @{ value__ = 422 } }
            
            $mockErrorRecord = @{
                Exception = $mockException
                ErrorDetails = @{ Message = $errorDetails }
            }
            
            $result = Test-ImmutableReleaseError -ErrorRecord $mockErrorRecord
            $result | Should -Be $false
        }
        
        It "Should return false for non-422 errors" -TestCases @(
            @{ StatusCode = 400 }
            @{ StatusCode = 403 }
            @{ StatusCode = 404 }
            @{ StatusCode = 500 }
        ) {
            param($StatusCode)
            
            $mockException = New-Object System.Exception "The remote server returned an error: ($StatusCode)"
            $mockException | Add-Member -NotePropertyName "Response" -NotePropertyValue @{ StatusCode = @{ value__ = $StatusCode } }
            
            $mockErrorRecord = @{
                Exception = $mockException
                ErrorDetails = $null
            }
            
            $result = Test-ImmutableReleaseError -ErrorRecord $mockErrorRecord
            $result | Should -Be $false
        }
    }
    
    Context "Fallback string matching" {
        It "Should match immutable release message in exception string when ErrorDetails unavailable" {
            $mockException = New-Object System.Exception "422 - tag_name was used by an immutable release"
            $mockException | Add-Member -NotePropertyName "Response" -NotePropertyValue $null
            
            $mockErrorRecord = @{
                Exception = $mockException
                ErrorDetails = $null
            }
            
            $result = Test-ImmutableReleaseError -ErrorRecord $mockErrorRecord
            $result | Should -Be $true
        }
    }
}

Describe "New-GitHubRef" {
    It "Should return manual fix required when REST API 403 and no git repo" {
        $state = [RepositoryState]::new()
        $state.RepoOwner = "test-owner"
        $state.RepoName = "test-repo"
        $state.ApiUrl = "https://api.github.com"
        $state.ServerUrl = "https://github.com"
        $state.Token = "test-token"

        Push-Location $TestDrive
        try {
            $throw403 = {
                $mockException = New-Object System.Exception "The remote server returned an error: (403)"
                $mockException | Add-Member -NotePropertyName "Response" -NotePropertyValue @{ StatusCode = @{ value__ = 403 } }
                throw $mockException
            }

            Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $throw403

            $result = New-GitHubRef -State $state -RefName "refs/tags/v1.0.0" -Sha "abc123" -Force $false

            $result.Success | Should -Be $false
            $result.RequiresManualFix | Should -Be $true
            $result.ErrorOutput | Should -Match "git fallback is disabled"
        }
        finally {
            if (Test-Path function:global:Invoke-WebRequestWrapper) {
                Remove-Item function:global:Invoke-WebRequestWrapper
            }
            Pop-Location
        }
    }
}

Describe "API failure handling" {
    BeforeEach {
        $env:GITHUB_API_DISABLE_RETRY = 'true'
    }

    AfterEach {
        if (Test-Path function:global:Invoke-WebRequestWrapper) {
            Remove-Item function:global:Invoke-WebRequestWrapper
        }
        if (Test-Path env:GITHUB_API_DISABLE_RETRY) {
            Remove-Item env:GITHUB_API_DISABLE_RETRY
        }
    }

    It "Should throw when Get-GitHubTags encounters API failure" {
        $state = [RepositoryState]::new()
        $state.RepoOwner = "test-owner"
        $state.RepoName = "test-repo"
        $state.ApiUrl = "https://api.github.com"
        $state.ServerUrl = "https://github.com"

        $throw500 = {
            $mockException = New-Object System.Exception "The remote server returned an error: (500)"
            $mockException | Add-Member -NotePropertyName "Response" -NotePropertyValue @{ StatusCode = @{ value__ = 500 } }
            throw $mockException
        }

        Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $throw500

        { Get-GitHubTags -State $state -Pattern "^v\\d+" } | Should -Throw
    }

    It "Should throw when Get-GitHubBranches encounters API failure" {
        $state = [RepositoryState]::new()
        $state.RepoOwner = "test-owner"
        $state.RepoName = "test-repo"
        $state.ApiUrl = "https://api.github.com"
        $state.ServerUrl = "https://github.com"

        $throw500 = {
            $mockException = New-Object System.Exception "The remote server returned an error: (500)"
            $mockException | Add-Member -NotePropertyName "Response" -NotePropertyValue @{ StatusCode = @{ value__ = 500 } }
            throw $mockException
        }

        Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $throw500

        { Get-GitHubBranches -State $state -Pattern "^v\\d+" } | Should -Throw
    }

    It "Should throw when Get-GitHubReleases encounters API failure" {
        $state = [RepositoryState]::new()
        $state.RepoOwner = "test-owner"
        $state.RepoName = "test-repo"
        $state.ApiUrl = "https://api.github.com"
        $state.ServerUrl = "https://github.com"

        $throw500 = {
            $mockException = New-Object System.Exception "The remote server returned an error: (500)"
            $mockException | Add-Member -NotePropertyName "Response" -NotePropertyValue @{ StatusCode = @{ value__ = 500 } }
            throw $mockException
        }

        Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $throw500

        { Get-GitHubReleases -State $state } | Should -Throw
    }

    It "Should return null when Get-GitHubRef receives 404" {
        $state = [RepositoryState]::new()
        $state.RepoOwner = "test-owner"
        $state.RepoName = "test-repo"
        $state.ApiUrl = "https://api.github.com"
        $state.ServerUrl = "https://github.com"

        $throw404 = {
            $mockException = New-Object System.Exception "The remote server returned an error: (404)"
            $mockException | Add-Member -NotePropertyName "Response" -NotePropertyValue @{ StatusCode = @{ value__ = 404 } }
            throw $mockException
        }

        Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $throw404

        $result = Get-GitHubRef -State $state -RefName "v1.0.0" -RefType "tags"
        $result | Should -Be $null
    }

    It "Should throw when Get-GitHubRef encounters non-404 error" {
        $state = [RepositoryState]::new()
        $state.RepoOwner = "test-owner"
        $state.RepoName = "test-repo"
        $state.ApiUrl = "https://api.github.com"
        $state.ServerUrl = "https://github.com"

        $throw500 = {
            $mockException = New-Object System.Exception "The remote server returned an error: (500)"
            $mockException | Add-Member -NotePropertyName "Response" -NotePropertyValue @{ StatusCode = @{ value__ = 500 } }
            throw $mockException
        }

        Set-Item -Path function:global:Invoke-WebRequestWrapper -Value $throw500

        { Get-GitHubRef -State $state -RefName "v1.0.0" -RefType "tags" } | Should -Throw
    }

    It "Should throw when Test-ReleaseImmutability encounters API failure" {
        $mockException = New-Object System.Exception "The remote server returned an error: (500)"
        $mockException | Add-Member -NotePropertyName "Response" -NotePropertyValue @{ StatusCode = @{ value__ = 500 } }

        Mock Invoke-RestMethod { throw $mockException }

        { Test-ReleaseImmutability -Owner "test-owner" -Repo "test-repo" -Tag "v1.0.0" -Token "" -ApiUrl "https://api.github.com" } | Should -Throw
    }
}
