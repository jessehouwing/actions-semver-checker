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
