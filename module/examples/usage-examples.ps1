#!/usr/bin/env pwsh
#############################################################################
# Example: Using the GitHubActionVersioning PowerShell Module
#############################################################################
# This script demonstrates various ways to use the module from the CLI.
#############################################################################

# Import the module
Import-Module "$PSScriptRoot/../GitHubActionVersioning.psd1" -Force

Write-Host "=== GitHub Action Versioning CLI Examples ===" -ForegroundColor Cyan
Write-Host ""

#############################################################################
# Example 1: Basic Validation
#############################################################################
Write-Host "Example 1: Basic validation of a repository" -ForegroundColor Green
Write-Host "Command: Test-GitHubActionVersioning -Repository 'actions/checkout'" -ForegroundColor Gray
Write-Host ""

# Note: This will fail without a token due to rate limiting, but shows the structure
# Uncomment to run:
# Test-GitHubActionVersioning -Repository 'actions/checkout'

Write-Host "Skipping actual API call (would require token)" -ForegroundColor Yellow
Write-Host ""

#############################################################################
# Example 2: Using PassThru for Detailed Results
#############################################################################
Write-Host "Example 2: Get detailed results with -PassThru" -ForegroundColor Green
Write-Host "Command: `$result = Test-GitHubActionVersioning -Repository 'owner/repo' -PassThru" -ForegroundColor Gray
Write-Host ""

Write-Host "The result would contain:" -ForegroundColor Yellow
Write-Host "  - Issues: Array of validation issues"
Write-Host "  - FixedCount: Number of issues fixed"
Write-Host "  - FailedCount: Number of failed fixes"
Write-Host "  - UnfixableCount: Number of unfixable issues"
Write-Host "  - ReturnCode: 0 for success, 1 for errors"
Write-Host ""

#############################################################################
# Example 3: Auto-Fix Mode
#############################################################################
Write-Host "Example 3: Auto-fix validation issues" -ForegroundColor Green
Write-Host "Command: Test-GitHubActionVersioning -Repository 'owner/repo' -AutoFix" -ForegroundColor Gray
Write-Host ""

Write-Host "Auto-fix will:" -ForegroundColor Yellow
Write-Host "  - Update floating version tags (v1, v1.0)"
Write-Host "  - Create missing releases"
Write-Host "  - Publish draft releases"
Write-Host "  - Convert branches to tags (or vice versa)"
Write-Host ""
Write-Host "Note: Requires write permissions to the repository" -ForegroundColor Red
Write-Host ""

#############################################################################
# Example 4: Run Specific Rules
#############################################################################
Write-Host "Example 4: Run only specific validation rules" -ForegroundColor Green
Write-Host "Command: Test-GitHubActionVersioning -Repository 'owner/repo' -Rules @('patch_release_required')" -ForegroundColor Gray
Write-Host ""

# List available rules
Write-Host "Available rules:" -ForegroundColor Yellow
. "$PSScriptRoot/../../lib/ValidationRules.ps1"
. "$PSScriptRoot/../../lib/StateModel.ps1"
. "$PSScriptRoot/../../lib/RemediationActions.ps1"
$rules = Get-ValidationRules
foreach ($rule in $rules) {
    Write-Host "  - $($rule.Name): $($rule.Description)"
}
Write-Host ""

#############################################################################
# Example 5: Ignore Specific Versions
#############################################################################
Write-Host "Example 5: Ignore specific versions" -ForegroundColor Green
Write-Host "Command: Test-GitHubActionVersioning -Repository 'owner/repo' -IgnoreVersions @('v1.0.0', 'v2.*')" -ForegroundColor Gray
Write-Host ""

Write-Host "This is useful for:" -ForegroundColor Yellow
Write-Host "  - Legacy versions that don't follow current conventions"
Write-Host "  - Versions with known issues that can't be fixed"
Write-Host "  - Test/preview versions"
Write-Host ""

#############################################################################
# Example 6: Custom Configuration
#############################################################################
Write-Host "Example 6: Custom validation configuration" -ForegroundColor Green
Write-Host @"
Command:
  Test-GitHubActionVersioning -Repository 'owner/repo' `
    -CheckMinorVersion 'warning' `
    -CheckReleases 'error' `
    -CheckReleaseImmutability 'none' `
    -IgnorePreviewReleases `$false `
    -FloatingVersionsUse 'branches'
"@ -ForegroundColor Gray
Write-Host ""

Write-Host "Configuration options:" -ForegroundColor Yellow
Write-Host "  - CheckMinorVersion: error, warning, none"
Write-Host "  - CheckReleases: error, warning, none"
Write-Host "  - CheckReleaseImmutability: error, warning, none"
Write-Host "  - CheckMarketplace: error, warning, none"
Write-Host "  - IgnorePreviewReleases: true, false"
Write-Host "  - FloatingVersionsUse: tags, branches"
Write-Host ""

#############################################################################
# Example 7: Marketplace Validation
#############################################################################
Write-Host "Example 7: Validate marketplace publication" -ForegroundColor Green
Write-Host @"
Command:
  Test-GitHubActionVersioning -Repository 'owner/repo' -CheckMarketplace 'warning'
"@ -ForegroundColor Gray
Write-Host ""

Write-Host "Marketplace validation checks:" -ForegroundColor Yellow
Write-Host "  - action.yaml exists with: name, description, branding.icon, branding.color"
Write-Host "  - README.md exists in repository root"
Write-Host "  - Latest release is published to GitHub Marketplace"
Write-Host ""
Write-Host "Note: Publishing to the marketplace must be done manually via GitHub UI." -ForegroundColor Red
Write-Host ""

#############################################################################
# Example 8: CI/CD Integration
#############################################################################
Write-Host "Example 8: CI/CD pipeline integration" -ForegroundColor Green
Write-Host @"
# In a CI/CD script:
`$result = Test-GitHubActionVersioning -Repository `$env:GITHUB_REPOSITORY -PassThru

if (`$result.ReturnCode -ne 0) {
    Write-Host "❌ Validation failed: `$(`$result.Issues.Count) issues found"
    
    # Print issues by status
    `$result.Issues | Group-Object Status | ForEach-Object {
        Write-Host "  `$(`$_.Name): `$(`$_.Count) issues"
    }
    
    exit `$result.ReturnCode
}

Write-Host "✅ All validations passed!"
"@ -ForegroundColor Gray
Write-Host ""

#############################################################################
# Example 9: Token Authentication
#############################################################################
Write-Host "Example 9: Token authentication options" -ForegroundColor Green
Write-Host ""

Write-Host "Option 1: Explicit token parameter" -ForegroundColor Yellow
Write-Host "  Test-GitHubActionVersioning -Repository 'owner/repo' -Token 'ghp_xxx'"
Write-Host ""

Write-Host "Option 2: GitHub CLI (automatically detected)" -ForegroundColor Yellow
Write-Host "  gh auth login"
Write-Host "  Test-GitHubActionVersioning -Repository 'owner/repo'"
Write-Host ""

Write-Host "Option 3: Environment variable" -ForegroundColor Yellow
Write-Host "  `$env:GITHUB_TOKEN = 'ghp_xxx'"
Write-Host "  Test-GitHubActionVersioning -Repository 'owner/repo'"
Write-Host ""

#############################################################################
# Done
#############################################################################
Write-Host "=== Examples Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "For more information, run: Get-Help Test-GitHubActionVersioning -Detailed" -ForegroundColor Green
Write-Host "Or see: module/README.md" -ForegroundColor Green
