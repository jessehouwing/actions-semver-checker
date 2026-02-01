# Copilot Instructions for actions-semver-checker

## Project Overview

PowerShell-based GitHub Action that validates semantic versioning tags and branches. Ensures floating versions (`v1`, `v1.0`) point to the latest patch release and that releases follow GitHub's immutable release strategy.

## GitHub Actions Versioning Strategy

This action enforces [GitHub's immutable release strategy](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases):

| Version Type | Example | Mutability | Mechanism |
|-------------|---------|------------|-----------|
| Patch (full semver) | `v1.0.0` | **Immutable** | GitHub Release (non-draft) |
| Major floating | `v1` | Mutable | Git tag, force-pushed |
| Minor floating | `v1.0` | Mutable | Git tag, force-pushed |
| Latest | `latest` | Mutable | Git tag or branch |

**Key rules:**
- Every patch version (`v1.0.0`) must have a published GitHub Release
- Floating versions (`v1`, `v1.0`) must point to the latest compatible patch
- Releases become immutable once published (non-draft) - tags cannot be moved

### CRITICAL: Prerelease Status Determination

**GitHub Actions does NOT support semver prerelease suffixes.** The prerelease status is determined **exclusively** from the GitHub Release API's `prerelease` field.

| Approach | Supported | Notes |
|----------|-----------|-------|
| GitHub Release `prerelease: true` | ✅ Yes | The ONLY way to mark a release as prerelease |
| Tag suffix `-beta`, `-rc`, `-preview` | ❌ No | These have NO special meaning in GitHub Actions |
| Tag suffix `-alpha`, `-dev` | ❌ No | Ignored - will cause parsing errors |

**Examples:**
```yaml
# CORRECT: Use clean semver tags, set prerelease via GitHub Release
v1.0.0  # Tag name
prerelease: true  # Set on GitHub Release object

# WRONG: Do NOT use semver suffixes
v1.0.0-beta    # ❌ Not recognized as prerelease
v1.0.0-rc1     # ❌ Will cause VersionRef parsing errors
v2.0.0-preview # ❌ Suffix is meaningless to GitHub Actions
```

When checking if a version is a prerelease, always use `ReleaseInfo.IsPrerelease` from the GitHub Release API.

## Architecture

```
main.ps1 (orchestrator) → lib/*.ps1 (modules) → GitHub REST API
                       ↓
              $script:State (RepositoryState singleton)
```

**Key design principle**: All state lives in `$script:State` (a `RepositoryState` object). Modules read/write to this single source of truth. Never introduce additional script-level state variables.

## Core Domain Model (lib/StateModel.ps1)

- **`VersionRef`**: Tag or branch with parsed semantic version (`Major`, `Minor`, `Patch`, `IsPatch`, `IsIgnored`). **Does NOT support semver suffixes** like `-beta` or `-rc`.
- **`ReleaseInfo`**: GitHub release with immutability and prerelease status. **`IsPrerelease` comes from GitHub Release API only** - never from tag name parsing.
- **`ValidationIssue`**: Problem found during validation with status (`pending` → `fixed`/`failed`/`unfixable`)
- **`RepositoryState`**: Central state container with calculated methods (`GetFixedIssuesCount()`, `GetReturnCode()`)
- **`RemediationAction`**: Base class for auto-fix actions (see `lib/RemediationActions.ps1` for implementations)

## Action Inputs

| Input | Purpose | Default |
|-------|---------|---------|
| `token` | GitHub API access (falls back to `GITHUB_TOKEN`) | `""` |
| `check-minor-version` | Validate minor version tags | `error` |
| `check-releases` | Require releases for patch versions | `error` |
| `check-release-immutability` | Require releases to be published (not draft) | `error` |
| `ignore-preview-releases` | Exclude prereleases from floating version calculation | `true` |
| `floating-versions-use` | Use `tags` or `branches` for floating versions | `tags` |
| `auto-fix` | Automatically fix issues (requires `contents: write`) | `false` |
| `ignore-versions` | Comma-separated list of versions to skip | `""` |

### Input Access Pattern

Inputs are passed as JSON via `$env:inputs` (set by `action.yaml` using `tojson(inputs)`):

```powershell
$inputs = $env:inputs | ConvertFrom-Json
$checkReleases = $inputs.'check-releases' ?? "error"
```

### GitHub Context Variables

GitHub context is accessed via `$env:GITHUB_*` environment variables ([docs](https://docs.github.com/en/actions/reference/workflows-and-actions/variables)):

| Variable | Purpose |
|----------|---------|
| `$env:GITHUB_REPOSITORY` | `owner/repo` string |
| `$env:GITHUB_TOKEN` | Default authentication token |
| `$env:GITHUB_API_URL` | API base URL (for GHES) |
| `$env:GITHUB_SERVER_URL` | Server URL (for GHES) |

## GitHub Actions Workflow Commands

This action uses [workflow commands](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands) for GitHub Actions integration:

### Used Commands
| Command | Purpose | Example |
|---------|---------|---------|
| `::add-mask::` | Hide sensitive values in logs | `Write-Host "::add-mask::$token"` |
| `::error::` | Report validation errors | `Write-Host "::error::Missing release"` |
| `::warning::` | Report non-critical issues | `Write-Host "::warning::Tag mismatch"` |
| `::debug::` | Debug output (hidden by default) | `Write-Host "::debug::Found 5 tags"` |
| `##[group]` / `##[endgroup]` | Collapsible log sections | Used in `lib/StateModel.ps1` |
| `::stop-commands::` | Prevent command injection | Used in `lib/Logging.ps1` |

### Preventing Workflow Command Injection

When outputting untrusted data (user content, error messages), use `Write-SafeOutput` from `lib/Logging.ps1`:

```powershell
# WRONG - untrusted message could contain ::set-env or other commands
Write-Host "::warning::$untrustedMessage"

# CORRECT - wraps untrusted content in stop-commands
Write-SafeOutput -Message $untrustedMessage -Prefix "::warning::"
```

## GitHub Actions Token Limitations

The default `GITHUB_TOKEN` **cannot** perform certain operations:

| Operation | GITHUB_TOKEN | PAT/GitHub App |
|-----------|--------------|----------------|
| Push tags | ✅ | ✅ |
| Push tags that modify `.github/workflows/*` | ❌ | ✅ |
| Create releases | ✅ | ✅ |
| Trigger workflow runs | ❌ | ✅ |

**Workaround:** Users needing to update workflow files must provide a Personal Access Token or GitHub App token via the `token` input.

## Module Responsibilities

| Module | Purpose |
|--------|---------|
| `main.ps1` | Orchestration, input parsing, validation logic |
| `lib/StateModel.ps1` | Domain classes - add new entities here |
| `lib/GitHubApi.ps1` | All REST API calls with retry logic |
| `lib/Remediation.ps1` | Auto-fix coordination and manual instructions |
| `lib/RemediationActions.ps1` | Concrete fix implementations |
| `lib/VersionParser.ps1` | Version string parsing utilities |
| `lib/Logging.ps1` | GitHub Actions-safe output functions |
| `lib/ValidationRules.ps1` | Rule engine base classes and helpers |
| `lib/rules/**/*.ps1` | Individual validation rule implementations |

## RemediationAction Classes

To add a new auto-fix action, subclass `RemediationAction` in `lib/RemediationActions.ps1`:

```powershell
class MyNewAction : RemediationAction {
    MyNewAction([string]$version) : base("Description", $version) {
        $this.Priority = 30  # Lower = runs first
    }
    
    [bool] Execute([RepositoryState]$state) {
        # Return $true on success, $false on failure
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        # Return array of CLI commands for manual fix
    }
}
```

**Existing actions:** `CreateTagAction`, `UpdateTagAction`, `DeleteTagAction`, `CreateBranchAction`, `UpdateBranchAction`, `CreateReleaseAction`, `PublishReleaseAction`, `RepublishReleaseAction`

## Error Handling

### Unfixable Errors (HTTP 422)

When GitHub returns HTTP 422 for release operations, the issue is marked as **unfixable**. This happens when:
- A tag was previously used by an **immutable release that was deleted**
- GitHub permanently blocks recreating releases on that tag

```powershell
# In RemediationAction.Execute():
if ($this.IsUnfixableError($result)) {
    $this.MarkAsUnfixable($state, "missing_release", "Cannot create - tag locked by deleted immutable release")
    return $false
}
```

**Resolution:** Add the version to `ignore-versions` input or manually create a new patch version.

### Issue Statuses
- `pending` → Not yet processed
- `fixed` → Auto-fix succeeded
- `failed` → Auto-fix attempted but failed (retryable)
- `unfixable` → Cannot be fixed automatically (e.g., 422 errors)
- `manual_fix_required` → Needs human intervention

## GitHub API Coverage

### REST API (Used)
| Endpoint | Function | Purpose |
|----------|----------|---------|
| `GET /repos/{owner}/{repo}/releases` | `Get-GitHubRelease` | List all releases |
| `GET /repos/{owner}/{repo}/git/refs/tags` | `Get-GitHubTag` | List all tags |
| `GET /repos/{owner}/{repo}/branches` | `Get-GitHubBranch` | List all branches |
| `POST /repos/{owner}/{repo}/git/refs` | `New-GitHubRef` | Create tag/branch |
| `PATCH /repos/{owner}/{repo}/git/refs/{ref}` | `Update-GitHubRef` | Update tag/branch |
| `DELETE /repos/{owner}/{repo}/git/refs/{ref}` | `Remove-GitHubRef` | Delete tag/branch |
| `POST /repos/{owner}/{repo}/releases` | `New-GitHubRelease` | Create release |
| `DELETE /repos/{owner}/{repo}/releases/{id}` | `Remove-GitHubRelease` | Delete release |
| `PATCH /repos/{owner}/{repo}/releases/{id}` | `Publish-GitHubRelease` | Publish draft release |

### GraphQL API (Used)
| Query | Function | Purpose | Queried Fields |
|-------|----------|---------|----------------|
| `repository.release` (single) | `Test-ReleaseImmutability` | Check if release is immutable | `tagName`, `isDraft`, `immutable` |
| `repository.releases` (list) | `Get-GitHubRelease` | List all releases with metadata | `databaseId`, `tagName`, `isPrerelease`, `isDraft`, `immutable`, `isLatest` |

**CRITICAL:** When code uses properties from GraphQL responses (e.g., `IsLatest`, `immutable`), a unit test in `tests/unit/GitHubApi.Tests.ps1` MUST verify that the GraphQL query includes those fields. See "Get-GitHubRelease GraphQL query validation" test for the pattern. This prevents runtime errors from missing fields in queries.

### Missing APIs (Not Available from GitHub)
| Feature | Status | Workaround |
|---------|--------|------------|
| Check if repo has immutable releases enabled | ❌ Not exposed | Infer from 422 errors on publish |
| Check if tag is blocked by deleted immutable release | ❌ Not exposed | Only discoverable via 422 error on create |
| Force-delete immutable release | ❌ Not possible | Must use `ignore-versions` |

## Testing Patterns

### Test Structure
```
tests/
├── unit/          # Test individual module functions
├── integration/   # Example-based scenario tests
└── e2e/           # Full validation workflow tests
```

### Running Tests
```powershell
Invoke-Pester -Path ./tests -Output Detailed    # All tests
Invoke-Pester -Path ./tests/unit               # Unit only
```

### Mocking GitHub API

Tests mock `Invoke-WebRequestWrapper` to intercept API calls. The mock uses local git commands to return API-formatted responses:

```powershell
# In test file - set up mock before running main.ps1
function global:Invoke-WebRequestWrapper { param($Uri, $Headers, $Method, $TimeoutSec)
    if ($Uri -match '/git/refs/tags') {
        $tags = git tag -l
        # ... format as GitHub API response
        return @{ Content = ($refs | ConvertTo-Json); Headers = @{} }
    }
}
. "$PSScriptRoot/../../main.ps1"
```

See `tests/e2e/SemVerValidation.Tests.ps1` function `New-GitBasedApiMock` for the full pattern.

### Test Repo Setup
Tests create temporary git repos in `$TestDrive`. Use the `Initialize-TestRepo` helper:

```powershell
Initialize-TestRepo -Path $script:testRepoPath -WithRemote
git tag v1.0.0  # Create test tags
git tag v1
```

### Efficient Pester Runs
- Prefer Pester v5 configuration objects; use `New-PesterConfiguration` or simple `-Path` syntax.
- Always emit logs to disk on every run so failures are inspectable without re-running:
    - XML: enable `TestResult` with `OutputFormat = 'NUnitXml'` and `OutputPath = './artifacts/pester/results.xml'` (create the folder if absent).
    - JSON: write results object using `ConvertTo-Json -Depth 10` to `./artifacts/pester/results.json`.
    - Example (configuration object):
        ```powershell
        $logDir = './artifacts/pester'
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        $config = New-PesterConfiguration
        $config.Run.Path = './tests'
        $config.Run.PassThru = $true
        $config.Output.Verbosity = 'Detailed'
        $config.TestResult.Enabled = $true
        $config.TestResult.OutputFormat = 'NUnitXml'
        $config.TestResult.OutputPath = "$logDir/results.xml"
        $results = Invoke-Pester -Configuration $config
        $results | ConvertTo-Json -Depth 10 | Set-Content "$logDir/results.json"
        ```
    - Example (simple syntax):
        ```powershell
        Invoke-Pester -Path ./tests -Output Detailed
        ```
- Reuse the same log paths across runs so Copilot can read previous failures directly.

## Critical Conventions

1. **No `git` commands for tag/branch fetching** - Use `Get-GitHubTag`/`Get-GitHubBranch` from `lib/GitHubApi.ps1`
2. **Status-based calculations** - Never store counts; calculate from issue statuses via `RepositoryState` methods
3. **Retry wrapper** - All API calls use `Invoke-WithRetry` for transient failures
4. **GitHub Actions output** - Use `Write-SafeHost`, `Write-SafeWarning` from `lib/Logging.ps1` to prevent injection
5. **Token masking** - Always call `::add-mask::` when handling tokens
6. **PowerShell class reloading** - After editing any PowerShell class (`VersionRef`, `ReleaseInfo`, `ValidationIssue`, `RepositoryState`, `RemediationAction`, `ValidationRule`), **ALWAYS** start a fresh PowerShell terminal before running tests or validation. PowerShell creates new class definitions with different assembly versions when classes are reloaded in the same session, causing type comparison failures (`-is [ClassName]` returns false). Close the existing terminal and open a new one to ensure clean class loading.
7. **PSScriptAnalyzer TypeNotFound warnings** - TypeNotFound warnings are expected and should be ignored. PSScriptAnalyzer is a static analyzer that examines each file independently and cannot follow dot-sourcing paths or resolve classes defined in other files. When running PSScriptAnalyzer, always filter out TypeNotFound warnings: `Invoke-ScriptAnalyzer ... | Where-Object { $_.RuleName -ne 'TypeNotFound' }`. These warnings don't indicate actual problems - the test suite validates that types are correctly defined and used.
8. **GraphQL query field validation** - When adding new GraphQL queries or modifying existing ones, **ALWAYS** add or update a unit test in `tests/unit/GitHubApi.Tests.ps1` that validates all required fields are present in the query. This prevents runtime errors from missing fields. See the "Get-GitHubRelease GraphQL query validation" test as an example. When code relies on a GraphQL property (e.g., `IsLatest`, `immutable`), the corresponding test must verify that property is queried.
9. **GraphQL-to-model field mapping** - When adding a new field to a GraphQL query in `lib/GitHubApi.ps1`, you **MUST** also update all code that maps the API response to domain objects. Specifically:
   - Update `main.ps1` where `$releaseData` PSCustomObject is created (around line 213-221) to include the new field
   - Update `lib/StateModel.ps1` if the corresponding class (e.g., `ReleaseInfo`, `VersionRef`) needs to read the new property
   - The GraphQL response returns camelCase properties (e.g., `isLatest`), while REST API uses snake_case (e.g., `is_latest`). The `ReleaseInfo` constructor handles both formats.
   - **Example**: Adding `isLatest` to GraphQL requires: (1) add to query, (2) add `isLatest = $release.isLatest` to `$releaseData` in main.ps1, (3) ensure `ReleaseInfo` constructor reads it

## Adding New Validation Rules

1. Add validation logic in `main.ps1` in the validation section (~line 800+)
2. Create `ValidationIssue` objects with appropriate `RemediationAction`
3. If auto-fixable, implement a `RemediationAction` subclass in `lib/RemediationActions.ps1`
4. Add tests in `tests/e2e/SemVerValidation.Tests.ps1`

## Adding New API Endpoints

1. Add function to `lib/GitHubApi.ps1`
2. Wrap calls in `Invoke-WithRetry` for reliability
3. Check for `Invoke-WebRequestWrapper` to enable test mocking:
   ```powershell
   if (Get-Command Invoke-WebRequestWrapper -ErrorAction SilentlyContinue) {
       Invoke-WebRequestWrapper -Uri $url ...
   } else {
       Invoke-WebRequest -Uri $url ...
   }
   ```

## GitHub Actions Integration

- Entry point: `action.yaml` → runs `main.ps1` via `pwsh`
- Inputs passed as JSON via `$env:inputs` (using `tojson(inputs)`)
- GitHub context via `$env:GITHUB_*` variables
- Outputs set via `echo "name=value" >> $env:GITHUB_OUTPUT`
- Exit code 0 = success, 1 = validation errors found
