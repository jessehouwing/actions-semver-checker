BeforeAll {
    $global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../lib/StateModel.ps1"
    . "$PSScriptRoot/../../lib/ValidationRules.ps1"
}

Describe "Invoke-ValidationRules" {
    It "adds issues when check fails" {
        $state = [RepositoryState]::new()

        $rule = [ValidationRule]@{
            Name = "rule_adds_issue"
            Description = "fail rule"
            Category = "test"
            Priority = 10
            Condition = { param($State, $Config) @("item-1") }
            Check = { param($Item, $State, $Config) $false }
            CreateIssue = {
                param($Item, $State, $Config)
                $issue = [ValidationIssue]::new("test_issue", "error", "issue for $Item")
                $issue.Version = $Item
                return $issue
            }
        }

        $result = Invoke-ValidationRules -State $state -Config @{} -Rules @($rule)

        $state.Issues.Count | Should -Be 1
        $state.Issues[0].Version | Should -Be "item-1"
        $result.Count | Should -Be 1
    }

    It "skips issue creation when check passes" {
        $state = [RepositoryState]::new()

        $rule = [ValidationRule]@{
            Name = "rule_passes"
            Description = "pass rule"
            Category = "test"
            Priority = 5
            Condition = { param($State, $Config) @("item-2") }
            Check = { param($Item, $State, $Config) $true }
            CreateIssue = {
                throw "CreateIssue should not run when check passes"
            }
        }

        $result = Invoke-ValidationRules -State $state -Config @{} -Rules @($rule)

        $state.Issues.Count | Should -Be 0
        $result.Count | Should -Be 0
    }

    It "processes rules in ascending priority order" {
        $state = [RepositoryState]::new()
        $config = @{ ExecutionOrder = @() }

        $highPriority = [ValidationRule]@{
            Name = "high"
            Description = "high priority"
            Category = "test"
            Priority = 1
            Condition = { param($State, $Config) @("first") }
            Check = { param($Item, $State, $Config) $false }
            CreateIssue = {
                param($Item, $State, $Config)
                $Config.ExecutionOrder += "high"
                $issue = [ValidationIssue]::new("order_issue", "error", "high first")
                $issue.Version = $Item
                return $issue
            }
        }

        $lowPriority = [ValidationRule]@{
            Name = "low"
            Description = "low priority"
            Category = "test"
            Priority = 50
            Condition = { param($State, $Config) @("second") }
            Check = { param($Item, $State, $Config) $false }
            CreateIssue = {
                param($Item, $State, $Config)
                $Config.ExecutionOrder += "low"
                $issue = [ValidationIssue]::new("order_issue", "error", "low second")
                $issue.Version = $Item
                return $issue
            }
        }

        Invoke-ValidationRules -State $state -Config $config -Rules @($lowPriority, $highPriority)

        $config.ExecutionOrder | Should -Be @("high", "low")
    }

    It "throws when required scriptblocks are missing" {
        $state = [RepositoryState]::new()

        $rule = [ValidationRule]@{
            Name = "invalid"
            Description = "missing check"
            Category = "test"
            Priority = 1
            Condition = { param($State, $Config) @("item") }
            Check = $null
            CreateIssue = { param($Item, $State, $Config) $null }
        }

        { Invoke-ValidationRules -State $state -Config @{} -Rules @($rule) } | Should -Throw
    }

    It "handles null condition results" {
        $state = [RepositoryState]::new()

        $rule = [ValidationRule]@{
            Name = "null_condition"
            Description = "returns null"
            Category = "test"
            Priority = 2
            Condition = { param($State, $Config) $null }
            Check = { param($Item, $State, $Config) $false }
            CreateIssue = {
                param($Item, $State, $Config)
                [ValidationIssue]::new("should_not_run", "error", "should not run")
            }
        }

        $result = Invoke-ValidationRules -State $state -Config @{} -Rules @($rule)

        $state.Issues.Count | Should -Be 0
        $result.Count | Should -Be 0
    }
}

Describe "Rule discovery" {
    It "loads rules from a custom path" {
        $state = [RepositoryState]::new()
        $rulesDir = Join-Path $TestDrive "rules"
        New-Item -ItemType Directory -Path $rulesDir | Out-Null

        $ruleFile = Join-Path $rulesDir "sample_rule.ps1"
        @'
$Rule_sample = [ValidationRule]@{
    Name = "sample_rule"
    Description = "sample"
    Category = "test"
    Priority = 3
    Condition = { param($State, $Config) @("item") }
    Check = { param($Item, $State, $Config) $false }
    CreateIssue = {
        param($Item, $State, $Config)
        $issue = [ValidationIssue]::new("discovered", "error", "from file")
        $issue.Version = $Item
        return $issue
    }
}
$Rule_sample
'@ | Set-Content -Path $ruleFile -Encoding ASCII

        $rules = Get-AllValidationRules -RulesPath $rulesDir

        $rules.Count | Should -Be 1
        $rules[0].Name | Should -Be "sample_rule"
    }
}

Describe "Helper functions" {
    Context "Get-HighestPatchForMajor" {
        It "returns highest patch across refs and skips prerelease when requested" {
            $state = [RepositoryState]::new()
            $tag100 = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "sha100", "tag")
            $branch120 = [VersionRef]::new("v1.2.0", "refs/heads/v1.2.0", "sha120", "branch")
            $pre130 = [VersionRef]::new("v1.3.0", "refs/tags/v1.3.0", "sha130", "tag")
            $pre130.IsPrerelease = $true

            $state.Tags = @($tag100, $pre130)
            $state.Branches = @($branch120)

            $result = Get-HighestPatchForMajor -State $state -Major 1 -ExcludePrereleases $true
            $result.Version | Should -Be "v1.2.0"

            $result = Get-HighestPatchForMajor -State $state -Major 1 -ExcludePrereleases $false
            $result.Version | Should -Be "v1.3.0"
        }

        It "returns null when no patches exist" {
            $state = [RepositoryState]::new()
            Get-HighestPatchForMajor -State $state -Major 9 | Should -Be $null
        }
    }

    Context "Get-HighestPatchForMinor" {
        It "returns highest patch for minor and ignores ignored refs" {
            $state = [RepositoryState]::new()
            $tag110 = [VersionRef]::new("v1.1.0", "refs/tags/v1.1.0", "sha110", "tag")
            $tag111 = [VersionRef]::new("v1.1.1", "refs/tags/v1.1.1", "sha111", "tag")
            $ignored = [VersionRef]::new("v1.1.5", "refs/tags/v1.1.5", "sha115", "tag")
            $ignored.IsIgnored = $true

            $state.Tags = @($tag110, $tag111, $ignored)

            $result = Get-HighestPatchForMinor -State $state -Major 1 -Minor 1 -ExcludePrereleases $false
            $result.Version | Should -Be "v1.1.1"
        }
    }

    Context "Get-HighestMinorForMajor" {
        It "returns highest minor using patches when available" {
            $state = [RepositoryState]::new()
            $v210 = [VersionRef]::new("v2.1.0", "refs/tags/v2.1.0", "sha210", "tag")
            $v230 = [VersionRef]::new("v2.3.0", "refs/heads/v2.3.0", "sha230", "branch")
            $v230.IsPrerelease = $true
            $v220 = [VersionRef]::new("v2.2.5", "refs/tags/v2.2.5", "sha225", "tag")

            $state.Tags = @($v210, $v220)
            $state.Branches = @($v230)

            $result = Get-HighestMinorForMajor -State $state -Major 2 -ExcludePrereleases $true
            $result.Version | Should -Be "v2.2.5"

            $result = Get-HighestMinorForMajor -State $state -Major 2 -ExcludePrereleases $false
            $result.Version | Should -Be "v2.3.0"
        }

        It "falls back to minor refs when no patches exist" {
            $state = [RepositoryState]::new()
            $minorBranch = [VersionRef]::new("v3.1", "refs/heads/v3.1", "sha31", "branch")
            $state.Branches = @($minorBranch)

            $result = Get-HighestMinorForMajor -State $state -Major 3 -ExcludePrereleases $false
            $result.Version | Should -Be "v3.1"
        }
    }
}
