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

Describe "Get-GitHubRelease GraphQL query validation" {
    It "Should include all required fields in GraphQL query" {
        # Read the GitHubApi.ps1 file to extract the GraphQL query
        $gitHubApiPath = "$PSScriptRoot/../../lib/GitHubApi.ps1"
        $gitHubApiContent = Get-Content -Path $gitHubApiPath -Raw

        # Extract the GraphQL query from the Get-GitHubRelease function
        # The query is between @" and "@ markers
        if ($gitHubApiContent -match 'query\(`\$owner[^@]*nodes\s*\{([^}]+)\}') {
            $queryFields = $Matches[1]

            # Required fields that must be present in the query
            $requiredFields = @(
                'databaseId',
                'tagName',
                'isPrerelease',
                'isDraft',
                'immutable',
                'isLatest'
            )

            # Check each required field is present
            foreach ($field in $requiredFields) {
                $queryFields | Should -Match $field -Because "GraphQL query must include '$field' field to populate ReleaseInfo correctly"
            }
        } else {
            throw "Could not find GraphQL query in Get-GitHubRelease function"
        }
    }

    It "Should map GraphQL response fields to ReleaseInfo correctly" {
        # Read the GitHubApi.ps1 file to find the response mapping code
        $gitHubApiPath = "$PSScriptRoot/../../lib/GitHubApi.ps1"
        $gitHubApiContent = Get-Content -Path $gitHubApiPath -Raw

        # Extract the releaseData creation code that maps GraphQL response to ReleaseInfo
        if ($gitHubApiContent -match '\$releaseData\s*=\s*\[PSCustomObject\]@\{([^}]+)\}') {
            $mappingCode = $Matches[1]

            # Required mappings that must be present for ReleaseInfo constructor
            $requiredMappings = @(
                'tag_name\s*=',
                'id\s*=',
                'draft\s*=',
                'prerelease\s*=',
                'immutable\s*=',
                'isLatest\s*='
            )

            # Check each required mapping is present
            foreach ($mapping in $requiredMappings) {
                $mappingCode | Should -Match $mapping -Because "Response mapping must include all fields required by ReleaseInfo constructor"
            }
        } else {
            throw "Could not find releaseData mapping code in Get-GitHubRelease function"
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

    It "Should throw when Get-GitHubTag encounters API failure" {
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

        { Get-GitHubTag -State $state -Pattern "^v\\d+" } | Should -Throw
    }

    It "Should return empty array when Get-GitHubTag receives 404 (no tags exist)" {
        # GitHub returns 404 for /git/refs/tags when a repository has zero tags
        # This is expected behavior and should not cause a failure
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

        # Should NOT throw - 404 means no tags, which is valid
        $result = Get-GitHubTag -State $state -Pattern "^v\\d+"

        # Result should be empty (null or empty array - PowerShell returns $null for @())
        @($result).Count | Should -Be 0
    }

    It "Should throw when Get-GitHubBranch encounters API failure" {
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

        { Get-GitHubBranch -State $state -Pattern "^v\\d+" } | Should -Throw
    }

    It "Should throw when Get-GitHubRelease encounters API failure" {
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

        { Get-GitHubRelease -State $state } | Should -Throw
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
