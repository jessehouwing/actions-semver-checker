# PSScriptAnalyzer Settings for Actions SemVer Checker
# https://github.com/PowerShell/PSScriptAnalyzer
#
# Policy: denylist model.
#   All rules shipped by PSScriptAnalyzer (current and future) are enabled by default.
#   Rules are only added to ExcludeRules when they are demonstrably noisy or
#   incompatible with this project. Every exclusion below has a justification.
#   When PSScriptAnalyzer ships a new rule, it will be picked up automatically;
#   if it is noisy for this codebase, add it here with a justification comment.

@{
    # Severity levels to include
    Severity = @(
        'Error',
        'Warning',
        'Information'
    )

    # NOTE: We intentionally do NOT set IncludeRules. Setting IncludeRules turns
    # the configuration into an allowlist and silently drops any rule (including
    # future new rules) not explicitly listed. Rely on ExcludeRules instead.

    # Rules to exclude, with justification.
    ExcludeRules = @(
        # GitHub Actions scripts commonly use Write-Host for workflow commands
        # (::error::, ::warning::, ::add-mask::, ##[group], etc.).
        'PSAvoidUsingWriteHost',

        # Positional parameters are used intentionally in some Pester assertions
        # and short helper calls for readability.
        'PSAvoidUsingPositionalParameters',

        # Some legacy utility function names do not use approved verbs; kept for
        # backwards compatibility until they are renamed.
        'PSUseApprovedVerbs',

        # Comment-based help is not required for internal helper functions.
        'PSProvideCommentHelp',

        # Script/global variables are used deliberately for state management
        # ($script:State) and for Pester mocking patterns.
        'PSAvoidGlobalVars',

        # Some functions are script-scoped/global to support the Pester mocking
        # pattern used across the test suite.
        'PSAvoidGlobalFunctions',

        # Many function names intentionally use collective nouns (Contents,
        # Metadata, ...) which PSScriptAnalyzer incorrectly flags as plural.
        'PSUseSingularNouns',

        # OutputType checking has false positives with PSCustomObject[] returns
        # used by our GitHub API wrappers.
        'PSUseOutputTypeCorrectly',

        # This project targets PowerShell 7.x which is the default on all
        # modern GitHub-hosted runners. The compatibility profile data files
        # for older PowerShell versions (core-6.1.0-linux,
        # desktop-5.1.14393.206-windows) have previously caused
        # "Get-Command is not recognized" errors on hosted runners.
        'PSUseCompatibleCmdlets',

        # Almost all reports are false positives caused by our rule-engine
        # scriptblock invocation pattern (parameters consumed inside
        # `& $Rule.Check $item $state $config` scriptblocks and by `param()`
        # blocks in Pester mock scriptblocks). PSScriptAnalyzer cannot see
        # through scriptblock invocation.
        'PSReviewUnusedParameter',

        # Flags thin GitHub API wrappers (New-GitHubRelease, Remove-GitHubRef,
        # ...) and test helpers (New-GitBasedApiMock, New-TestState,
        # New-ErrorResult). These intentionally do not implement -WhatIf /
        # -Confirm.
        # TODO: consider adding [CmdletBinding(SupportsShouldProcess)] to the
        # real state-changing helpers in lib/GitHubApi.ps1 in a follow-up PR,
        # then remove this exclusion.
        'PSUseShouldProcessForStateChangingFunctions',

        # Repository-wide whitespace hygiene issue (thousands of hits across
        # tests and modules). Not a defect.
        # TODO: run a dedicated trailing-whitespace cleanup PR across lib/,
        # tests/, and *.psm1, then remove this exclusion so regressions are
        # caught.
        'PSAvoidTrailingWhitespace'

        # Note: TypeNotFound parse errors cannot be excluded via this settings
        # file. They must be filtered at invocation time. See
        # .github/workflows/powershell.yml for the SARIF filtering
        # implementation used in CI.
    )

    # Rule-specific settings. These take effect because we no longer use an
    # IncludeRules allowlist.
    Rules = @{
        # Consistent indentation settings
        PSUseConsistentIndentation = @{
            Enable = $true
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind = 'space'
        }

        # Consistent whitespace settings
        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckPipeForRedundantWhitespace = $false
            CheckSeparator = $true
            CheckParameter = $false
            IgnoreAssignmentOperatorInsideHashTable = $true
        }

        # Correct casing
        PSUseCorrectCasing = @{
            Enable = $true
        }

        # Avoid aliases
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
            # Allowed aliases (none by default)
            allowlist = @()
        }

        # Align assignment statements
        PSAlignAssignmentStatement = @{
            Enable = $false
            CheckHashtable = $false
        }

        # Place open brace on same line
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            NewLineAfter = $true
            IgnoreOneLineBlock = $true
        }

        # Place close brace
        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore = $false
        }
    }
}
