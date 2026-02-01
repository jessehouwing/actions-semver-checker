<#
.SYNOPSIS
Convert PowerShell files to UTF-8 with BOM safely.

.DESCRIPTION
Reads files using a StreamReader that detects existing byte-order-marks,
removes any stray BOM character that may be embedded in the text, and
writes the files back using UTF-8 with BOM. Useful to fix encoding issues
and satisfy PSScriptAnalyzer's BOM rule.

.PARAMETER Path
Root path to search (default: current directory)
.PARAMETER Include
Array of file name patterns to include (default: '*.ps1','*.psm1','*.psd1')
.PARAMETER Recurse
Recurse into subdirectories (default: $true)
.PARAMETER WhatIf
If specified, only shows which files would be changed.
#>

[CmdletBinding()]
param(
    [string]$Path = '.',
    [string[]]$Include = @('*.ps1', '*.psm1', '*.psd1'),
    [switch]$Recurse,
    [switch]$WhatIf
)

$files = @()
foreach ($pattern in $Include) {
    $files += Get-ChildItem -Path $Path -Filter $pattern -File -ErrorAction SilentlyContinue -Recurse:$Recurse
}
$files = $files | Sort-Object -Unique

if (-not $files -or $files.Count -eq 0) {
    Write-Host "No files found for patterns: $($Include -join ', ') in path: $Path"
    return
}

$utf8Bom = New-Object System.Text.UTF8Encoding $true

foreach ($file in $files) {
    try {
        # Read with BOM/encoding detection
        $reader = New-Object System.IO.StreamReader($file.FullName, $true)
        $text = $reader.ReadToEnd()
        $reader.Close()

        # Remove any stray BOM character at start of text (U+FEFF)
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
            $text = $text.Substring(1)
        }

        if ($WhatIf) {
            Write-Host "Would re-encode: $($file.FullName)"
            continue
        }

        # Write back as UTF-8 with BOM
        [System.IO.File]::WriteAllText($file.FullName, $text, $utf8Bom)
        Write-Host "Re-encoded: $($file.FullName)"
    }
    catch {
        Write-Warning "Failed to process $($file.FullName): $($_.Exception.Message)"
    }
}
