# GitHubActionVersioning PowerShell Module

A PowerShell module for validating GitHub Action semantic versioning from the command line.

## Installation

### From PowerShell Gallery

Install from the [PowerShell Gallery](https://www.powershellgallery.com/packages/GitHubActionVersioning/):

```powershell
Install-Module -Name GitHubActionVersioning -Scope CurrentUser
```

After installation, import the module:

```powershell
Import-Module GitHubActionVersioning
```

### From Local Files

```powershell
Import-Module ./GitHubActionVersioning.psd1
```

### For Development

```powershell
# Import and force reload
Import-Module ./GitHubActionVersioning.psd1 -Force
```

## Usage

### Basic Usage

Validate a repository using default settings:

```powershell
Test-GitHubActionVersioning -Repository 'owner/repo'
```

### Using Environment Variables

The module will automatically use these environment variables if set:

- `GITHUB_REPOSITORY` - Repository in 'owner/repo' format
- `GITHUB_TOKEN` - GitHub authentication token
- `GITHUB_API_URL` - GitHub API URL (defaults to https://api.github.com)
- `GITHUB_SERVER_URL` - GitHub server URL (defaults to https://github.com)

```powershell
# Set environment variables
$env:GITHUB_REPOSITORY = 'owner/repo'
$env:GITHUB_TOKEN = 'your-token-here'

# Run without parameters
Test-GitHubActionVersioning
```

### Token Authentication

The module attempts to get a GitHub token in this order:

1. `-Token` parameter
2. `gh auth token` command (GitHub CLI)
3. `GITHUB_TOKEN` environment variable

```powershell
# Using explicit token
Test-GitHubActionVersioning -Repository 'owner/repo' -Token 'ghp_xxx'

# Let module find token automatically (tries gh CLI first)
Test-GitHubActionVersioning -Repository 'owner/repo'
```

### Auto-Fix Mode

Automatically fix validation issues:

```powershell
Test-GitHubActionVersioning -Repository 'owner/repo' -AutoFix
```

**Note:** Auto-fix requires write permissions to the repository.

### Get Detailed Results

Use `-PassThru` to get detailed information about issues:

```powershell
$result = Test-GitHubActionVersioning -Repository 'owner/repo' -PassThru

# Check results
Write-Host "Return code: $($result.ReturnCode)"
Write-Host "Fixed: $($result.FixedCount)"
Write-Host "Failed: $($result.FailedCount)"
Write-Host "Unfixable: $($result.UnfixableCount)"

# List issues
foreach ($issue in $result.Issues) {
    Write-Host "$($issue.Severity): $($issue.Message) [Status: $($issue.Status)]"
}

# Get manual remediation instructions
Get-ManualInstruction -State $result.State
```

### Run Specific Rules

Run only specific validation rules:

```powershell
# List available rules
Get-ValidationRules | Select-Object Name, Description

# Run specific rules
Test-GitHubActionVersioning -Repository 'owner/repo' `
    -Rules @('patch_release_required', 'major_tag_tracks_highest_patch')
```

### Ignore Versions

Ignore specific versions from validation:

```powershell
# Ignore specific versions
Test-GitHubActionVersioning -Repository 'owner/repo' `
    -IgnoreVersions @('v1.0.0', 'v2.0.0')

# Use wildcards
Test-GitHubActionVersioning -Repository 'owner/repo' `
    -IgnoreVersions @('v1.*', 'v2.0.*')
```

### Configuration Options

```powershell
Test-GitHubActionVersioning -Repository 'owner/repo' `
    -CheckMinorVersion 'error' `          # error, warning, none
    -CheckReleases 'error' `              # error, warning, none
    -CheckReleaseImmutability 'error' `   # error, warning, none
    -CheckMarketplace 'error' `           # error, warning, none (default: error)
    -IgnorePreviewReleases $true `        # true, false
    -FloatingVersionsUse 'tags'           # tags, branches
```

### Marketplace Validation

Check that the action has valid marketplace metadata and is published:

```powershell
# Validate marketplace requirements (as warnings)
Test-GitHubActionVersioning -Repository 'owner/repo' -CheckMarketplace 'warning'

# Fail if marketplace requirements are not met
Test-GitHubActionVersioning -Repository 'owner/repo' -CheckMarketplace 'error'
```

Marketplace validation checks:
- `action.yaml` exists with required fields: name, description, branding.icon, branding.color
- `README.md` exists in the repository root
- Latest release is published to GitHub Marketplace

## Examples

### Example 1: Quick Validation

```powershell
# Validate current repository
$env:GITHUB_REPOSITORY = 'myorg/my-action'
Test-GitHubActionVersioning
```

### Example 2: Validation with Auto-Fix

```powershell
# Validate and auto-fix issues
Test-GitHubActionVersioning -Repository 'myorg/my-action' -AutoFix
```

### Example 3: CI/CD Integration

```powershell
# In a CI/CD pipeline
$result = Test-GitHubActionVersioning -Repository $env:GITHUB_REPOSITORY -PassThru

if ($result.ReturnCode -ne 0) {
    Write-Host "Validation failed with $($result.Issues.Count) issues"
    exit $result.ReturnCode
}

Write-Host "✓ All validations passed"
```

### Example 4: Custom Validation

```powershell
# Only check releases, ignore minor version checks
Test-GitHubActionVersioning -Repository 'owner/repo' `
    -CheckMinorVersion 'none' `
    -CheckReleases 'error' `
    -IgnorePreviewReleases $false
```

### Example 5: Detailed Issue Analysis

```powershell
$result = Test-GitHubActionVersioning -Repository 'owner/repo' -PassThru

# Group by status
$byStatus = $result.Issues | Group-Object -Property Status

foreach ($group in $byStatus) {
    Write-Host "`n$($group.Name) issues: $($group.Count)"
    foreach ($issue in $group.Group) {
        Write-Host "  - $($issue.Message)"
    }
}

# Show auto-fixable issues
$autoFixable = $result.Issues | Where-Object { $_.IsAutoFixable -and $_.Status -eq 'pending' }
Write-Host "`nAuto-fixable issues: $($autoFixable.Count)"
```

## Return Values

### Without -PassThru

Returns an integer exit code:
- `0` - All validations passed
- `1` - Validation errors found

### With -PassThru

Returns a hashtable with:

```powershell
@{
    Issues          # Array of ValidationIssue objects
    FixedCount      # Number of issues that were auto-fixed
    FailedCount     # Number of auto-fix attempts that failed
    UnfixableCount  # Number of issues that cannot be fixed
    ReturnCode      # Overall exit code (0 or 1)
}
```

## ValidationIssue Object

Each issue has the following properties:

- `Type` - Issue type identifier (e.g., "missing_version", "mismatched_sha")
- `Severity` - "error" or "warning"
- `Message` - Human-readable description
- `Version` - The version this issue relates to
- `Status` - Current status:
  - `pending` - Not yet processed
  - `fixed` - Successfully auto-fixed
  - `failed` - Auto-fix attempted but failed
  - `unfixable` - Cannot be fixed automatically
  - `manual_fix_required` - Needs manual intervention
- `IsAutoFixable` - Whether this issue can be auto-fixed
- `RemediationAction` - The action that would fix this issue

## Troubleshooting

### "No GitHub token available"

Provide a token using one of these methods:

1. Use `-Token` parameter
2. Run `gh auth login` (requires GitHub CLI)
3. Set `GITHUB_TOKEN` environment variable

### "Repository not specified"

Provide repository using:

1. `-Repository` parameter
2. Set `GITHUB_REPOSITORY` environment variable

### API Rate Limits

Without authentication, GitHub's API rate limit is 60 requests/hour. With authentication, it increases to 5000 requests/hour.

## Requirements

- PowerShell 5.1 or later
- Internet access to GitHub API
- GitHub token (optional, but recommended for higher rate limits)
- GitHub CLI (optional, for automatic token retrieval)

## Compatibility

Tested on:
- PowerShell 7.x (Windows, Linux, macOS)
- Windows PowerShell 5.1

## See Also

- [GitHub Actions Versioning Best Practices](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases)
- [Main Repository](https://github.com/jessehouwing/actions-semver-checker)
- [Project Documentation](../docs/)
