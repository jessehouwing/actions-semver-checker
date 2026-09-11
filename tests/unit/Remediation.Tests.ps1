BeforeAll {
    # Suppress progress reporting for folder cleanup operations (must be global scope)
    $global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../lib/StateModel.ps1"
    . "$PSScriptRoot/../../lib/Logging.ps1"
    . "$PSScriptRoot/../../lib/GitHubApi.ps1"
    . "$PSScriptRoot/../../lib/RemediationActions.ps1"
    . "$PSScriptRoot/../../lib/Remediation.ps1"
}

Describe "Unfixable release remediation - ignore-versions YAML snippet" {
    BeforeEach {
        $script:state = [RepositoryState]::new()
        $script:state.RepoOwner = "test-owner"
        $script:state.RepoName = "test-repo"
        $script:state.ApiUrl = "https://api.github.com"
        $script:state.ServerUrl = "https://github.com"
        $script:state.Token = "test-token"
        $script:state.IgnoreVersions = @("v1.*")
    }

    Context "Scenario: latest patch release of a major version was deleted and cannot be recreated" {
        It "Marks the missing_release issue as unfixable and attaches a YAML manual-fix snippet with the suggested ignore-versions value" {
            # Simulate: v6.3.0 was the highest released patch for major v6, but its
            # immutable release was deleted. Recreating it now fails with HTTP 422.
            Mock New-GitHubRelease { return @{ Success = $false; Unfixable = $true } }

            $action = [CreateReleaseAction]::new("v6.3.0", $false)
            $issue = [ValidationIssue]::new("missing_release", "error", "Release required for patch version v6.3.0")
            $issue.Version = "v6.3.0"
            $issue.Status = "pending"
            $issue.RemediationAction = $action
            $script:state.Issues = @($issue)

            $action.Execute($script:state) | Should -Be $false

            $issue.Status | Should -Be "unfixable"
            $issue.Message | Should -Match "immutable release"

            $commands = $action.GetManualCommands($script:state)
            $action.ManualCommandsLanguage | Should -Be "yaml"
            ($commands -join "`n") | Should -Match 'ignore-versions:\s*"v1\.\*,v6\.3\.0"'
        }

        It 'Renders the snippet inside a fenced ```yaml block (not ```bash) in the GitHub Actions job summary' {
            Mock New-GitHubRelease { return @{ Success = $false; Unfixable = $true } }

            $action = [CreateReleaseAction]::new("v6.3.0", $false)
            $issue = [ValidationIssue]::new("missing_release", "error", "Release required for patch version v6.3.0")
            $issue.Version = "v6.3.0"
            $issue.Status = "pending"
            $issue.RemediationAction = $action
            $script:state.Issues = @($issue)

            $action.Execute($script:state) | Should -Be $false

            $summaryPath = Join-Path $TestDrive "step-summary.md"
            New-Item -Path $summaryPath -ItemType File -Force | Out-Null
            $originalSummaryEnv = $env:GITHUB_STEP_SUMMARY
            $env:GITHUB_STEP_SUMMARY = $summaryPath

            try {
                Write-ManualInstructionsToStepSummary -State $script:state
                $summaryContent = Get-Content -Path $summaryPath -Raw
            }
            finally {
                $env:GITHUB_STEP_SUMMARY = $originalSummaryEnv
            }

            $summaryContent | Should -Match '```yaml'
            $summaryContent | Should -Match 'ignore-versions:\s*"v1\.\*,v6\.3\.0"'
            # The ignore-versions snippet itself must be fenced as yaml, not bash
            $summaryContent | Should -Match '```yaml[\s\S]*?ignore-versions:\s*"v1\.\*,v6\.3\.0"[\s\S]*?```'
        }
    }
}
