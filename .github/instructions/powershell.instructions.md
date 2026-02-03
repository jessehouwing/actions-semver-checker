---
applyTo: '**/*.ps1'
name: Development guidance for powershell files
description: This file provides guidance for writing powershell files.
---

# PowerShell linting & repo guidance

- TypeNotFound warnings from PSScriptAnalyzer are expected in this repo (classes are loaded across files). The repo includes `PSScriptAnalyzerSettings.psd1` to disable `TypeNotFound`.
- After editing PowerShell classes, always start a fresh PowerShell terminal to avoid class reloading/type comparison issues.
- Use `Write-SafeOutput` / `Write-SafeHost` from `lib/Logging.ps1` for any output containing untrusted data to prevent workflow command injection.
- Use `Invoke-WithRetry` wrapper for all GitHub API calls.
- Do not call `git` directly for fetching tags/branches in validation — use `Get-GitHubTag` / `Get-GitHubBranch`.
- When adding/modifying GraphQL queries, add/update unit tests that validate required fields are present.
- If other PSScriptAnalyzer rules produce noise, add targeted entries to `PSScriptAnalyzerSettings.psd1` rather than globally disabling analysis.
- Always run the PowerShell Script Analyzer after changing any PowerShell file.

## OutputType attribute

All exported functions and cmdlets **must** declare their return types using the `[OutputType()]` attribute. This helps PSScriptAnalyzer validate return statements and improves IntelliSense for consumers.

1. **Declare all possible return types** — if a function can return multiple types, list them all.
2. **Place `[OutputType()]` after `[CmdletBinding()]`** — this is the conventional order.
3. **Use full type names** — prefer `[int]` over `[System.Int32]` for common types, but be explicit.
4. **Document return types in `.OUTPUTS`** — the help comment should match the attribute.

Example of correct OutputType usage:

```powershell
function Get-ProcessingResult {
    <#
    .SYNOPSIS
    Processes input and returns result.
    
    .OUTPUTS
    Returns an integer exit code, or a hashtable with details when -PassThru is specified.
    #>
    [CmdletBinding()]
    [OutputType([int], [hashtable])]
    param(
        [Parameter()]
        [switch]$PassThru
    )
    
    if ($PassThru) {
        return @{ Status = 'Success'; Code = 0 }
    }
    return 0
}
```

Example of incorrect usage (missing OutputType):

```powershell
# Wrong - no OutputType declared
function Get-ProcessingResult {
    [CmdletBinding()]
    param()
    return 0  # PSScriptAnalyzer will warn about undeclared return type
}
```

## Indentation rules

PSScriptAnalyzer enforces consistent indentation via `PSUseConsistentIndentation`. Follow these rules to avoid warnings:

1. **Use 4 spaces for indentation** — never tabs. The `.editorconfig` and VS Code settings enforce this.
2. **Hashtable contents** inside `@{}` must be indented one level (4 spaces) deeper than the opening brace.
3. **Script blocks** (`{ ... }`) follow the same rule — contents indented 4 spaces from the brace.
4. **Parameter attributes** like `[Parameter(Position = 0)]` must have spaces around `=` operators.
5. **Array initializers** with `@()` containing multi-line content should have each item indented consistently.
6. **Switch parameters** should not have default values like `$true` — use `[switch]$Recurse` not `[switch]$Recurse = $true`.

Example of correct hashtable indentation:

```powershell
# Correct - hashtable contents indented 4 spaces from opening brace
$config = @{
    Name  = 'Example'
    Value = 123
}

# Correct - nested hashtables
PrivateData = @{
    PSData = @{
        Tags = @('Tag1', 'Tag2')
    }
}
```

Example of correct module manifest (`.psd1`) indentation:

```powershell
@{
    # Contents must be indented 4 spaces from the opening @{
    RootModule        = 'MyModule.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '00000000-0000-0000-0000-000000000000'
    Author            = 'Your Name'
    
    # Nested hashtables follow the same rule
    PrivateData       = @{
        PSData = @{
            Tags         = @('Tag1', 'Tag2')
            LicenseUri   = 'https://example.com/license'
            ProjectUri   = 'https://example.com/project'
        }
    }
}
```

Example of correct parameter attributes:

```powershell
# Correct - spaces around = in attributes
[Parameter(Position = 0, ValueFromPipeline)]

# Wrong - no spaces
[Parameter(Position=0, ValueFromPipeline)]
```

### Common Indentation Pitfalls

#### Nested hashtables in method calls

When passing a hashtable to a method or cmdlet that spans multiple lines, the hashtable contents must be indented relative to the opening `@{`, NOT relative to the start of the line:

```powershell
# CORRECT - hashtable contents indented 4 spaces from @{
$object | Add-Member -NotePropertyName Property -NotePropertyValue ([PSCustomObject]@{
        StatusCode = [PSCustomObject]@{ value__ = 404 }
    }) -Force

# WRONG - hashtable contents aligned with method call start
$object | Add-Member -NotePropertyName Property -NotePropertyValue ([PSCustomObject]@{
    StatusCode = [PSCustomObject]@{ value__ = 404 }
}) -Force
```

The key rule: **Each `@{` opening brace establishes a new indentation level. Content inside must be indented exactly 4 spaces deeper than the `@{`, regardless of where the `@{` appears on the line.**

#### Pipeline indentation with hashtables

When using hashtables in pipeline operations:

```powershell
# CORRECT - consistent 4-space indent from each opening brace
Get-Item | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Size = $_.Length
    }
}

# WRONG - inconsistent indentation
Get-Item | ForEach-Object {
    [PSCustomObject]@{
    Name = $_.Name
    Size = $_.Length
}
}
```

## File encoding and editor settings

All PowerShell source files in this repository MUST be encoded as UTF-8 with a BOM (Byte Order Mark). PSScriptAnalyzer and some Windows tools expect the BOM for correct parsing of non-ASCII characters.


## Fixing existing files

Use the supplied script `scripts/convert-to-utf8.ps1` to re-encode files to UTF-8 with BOM.

Dry-run (shows files that would be changed):

```powershell
pwsh -NoProfile ./scripts/convert-to-utf8.ps1 -WhatIf
```

Apply changes (re-encode files):

```powershell
pwsh -NoProfile ./scripts/convert-to-utf8.ps1
```

After re-encoding, run PSScriptAnalyzer to validate the repo (filter `TypeNotFound` info when desired):

## Quick checklist for contributors

- Create PowerShell files using UTF-8 with BOM encoding.
- Run `pwsh -NoProfile ./scripts/convert-to-utf8.ps1 -WhatIf` before committing to see potential encoding fixes.
- Run `Invoke-ScriptAnalyzer` (with the settings file) before opening a PR.
- After editing PowerShell classes, restart your PowerShell session to avoid class reloading problems.

## Running the script analyzer locally

Run the analyzer for all repo PowerShell files with:

```powershell
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1
```

To filter expected `TypeNotFound` warnings when invoking from CI or locally, use `Where-Object` to exclude that rule:

```powershell
Invoke-ScriptAnalyzer -Path "path/to/file.ps1" -Settings "./PSScriptAnalyzerSettings.psd1" | Where-Object { $_.RuleName -ne 'TypeNotFound' } | Format-Table Severity, RuleName, ScriptName, Line, Message -AutoSize
```
