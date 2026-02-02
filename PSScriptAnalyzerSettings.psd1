# PSScriptAnalyzer Settings for Actions SemVer Checker
# https://github.com/PowerShell/PSScriptAnalyzer

@{
    # Severity levels to include
    Severity = @(
        'Error',
        'Warning',
        'Information'
    )

    # Rules to include
    IncludeRules = @(
        # Code quality rules
        'PSAvoidUsingCmdletAliases',
        'PSAvoidDefaultValueForMandatoryParameter',
        'PSAvoidDefaultValueSwitchParameter',
        'PSAvoidGlobalAliases',
        'PSAvoidGlobalFunctions',
        'PSAvoidGlobalVars',
        'PSAvoidInvokingEmptyMembers',
        'PSAvoidNullOrEmptyHelpMessageAttribute',
        'PSAvoidShouldContinueWithoutForce',
        'PSAvoidUsingComputerNameHardcoded',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSAvoidUsingDeprecatedManifestFields',
        'PSAvoidUsingEmptyCatchBlock',
        'PSAvoidUsingInvokeExpression',
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingPositionalParameters',
        'PSAvoidUsingUsernameAndPasswordParams',
        'PSAvoidUsingWMICmdlet',
        'PSAvoidUsingWriteHost',
        'PSMisleadingBacktick',
        'PSMissingModuleManifestField',
        'PSPossibleIncorrectComparisonWithNull',
        'PSPossibleIncorrectUsageOfAssignmentOperator',
        'PSPossibleIncorrectUsageOfRedirectionOperator',
        'PSProvideCommentHelp',
        'PSReservedCmdletChar',
        'PSReservedParams',
        'PSUseApprovedVerbs',
        'PSUseBOMForUnicodeEncodedFile',
        'PSUseCmdletCorrectly',
        'PSUseCompatibleCmdlets',
        'PSUseConsistentIndentation',
        'PSUseConsistentWhitespace',
        'PSUseCorrectCasing',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseLiteralInitializerForHashtable',
        'PSUseOutputTypeCorrectly',
        'PSUsePSCredentialType',
        'PSUseSingularNouns',
        'PSUseToExportFieldsInManifest',
        'PSUseUTF8EncodingForHelpFile'
    )

    # Rules to exclude
    ExcludeRules = @(
        # GitHub Actions scripts commonly use Write-Host for workflow commands
        'PSAvoidUsingWriteHost',
        
        # We use positional parameters in some places for brevity
        'PSAvoidUsingPositionalParameters',
        
        # We have some utility functions that don't follow verb-noun
        # (legacy compatibility, but these are now being renamed)
        'PSUseApprovedVerbs',
        
        # Comment-based help is not required for all internal functions
        'PSProvideCommentHelp',
        
        # Script variables are used for state management
        'PSAvoidGlobalVars',
        
        # Some functions are script-scoped for module access
        'PSAvoidGlobalFunctions',
        
        # Many function names intentionally use collective nouns (Contents, Metadata)
        # which PSScriptAnalyzer incorrectly flags as plural
        'PSUseSingularNouns',
        
        # OutputType checking has false positives with PSCustomObject[] returns
        'PSUseOutputTypeCorrectly'
        
        # Note: TypeNotFound parse errors cannot be excluded via this settings file.
        # They must be filtered at invocation time. See .github/workflows/powershell.yml
        # for the SARIF filtering implementation used in CI.
    )

    # Rule-specific settings
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

        # Compatible cmdlets for cross-platform
        PSUseCompatibleCmdlets = @{
            Enable = $true
            # Target PowerShell Core on Linux (GitHub Actions runner)
            Compatibility = @(
                'core-6.1.0-linux',
                'desktop-5.1.14393.206-windows'
            )
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
