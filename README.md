# Actions SemVer Checker Action

Every time you publish a new version of a GitHub Action, say `v1.2.3`, it's customary to also update the tags for `v1.2` and `v1` to point to the same commit. That way people can subscribe to  either an exact version or a floating version that's automatically updated when the action's author pushes a new version.

Unfortunately, GitHub's creative use of tags doesn't do this automatically and many actions don't auto-update their major and minor versions whenever they release a new  patch.

You can run this action for your GitHub Action's repository to ensure the correct tags have been created and point to the correct commits.

**NEW:** Now available as a [PowerShell module](module/README.md) for running from the command line!

## GitHub's Immutable Release Strategy

This action implements [GitHub's recommended approach](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases) for versioning actions:

- **Patch versions (v1.0.0, v1.0.1)** → Immutable GitHub Releases that never change
- **Floating versions (v1, v1.0, latest)** → Mutable Git tags that point to the latest compatible release

This strategy balances **stability** (pinned versions never change) with **convenience** (floating versions get updates automatically).

📖 **[Read the comprehensive versioning guidance](docs/versioning-guidance.md)** for detailed best practices, workflows, and troubleshooting.

## Features

- ✅ Validates that major (`v1`) and minor (`v1.0`) version tags point to the latest patch version
- ✅ Checks that every patch version (`v1.0.0`) has a corresponding GitHub Release (via REST API)
- ✅ Verifies that releases are immutable (not in draft status)
- ✅ Supports filtering preview/pre-release versions from major/minor tag calculations
- ✅ Can configure floating versions (major/minor/latest) to use branches or tags
- ✅ Provides suggested commands to fix any issues with direct links to GitHub release pages
- ✅ Optional auto-fix mode to automatically update version tags/branches
- ✅ **NEW in v2:** No checkout required - uses GitHub REST API exclusively
- ✅ **NEW:** Ignore specific versions from validation (useful for legacy versions)
- ✅ **NEW:** Auto-fix automatically republishes non-immutable releases to make them immutable (when `check-release-immutability` is enabled)
- ✅ **NEW:** Retry logic with exponential backoff for better reliability
- ✅ **NEW:** PowerShell module for CLI usage on Windows and Linux - see [module/README.md](module/README.md)

Example output:

> ### Annotations
>
> 🔴 Incorrect version
> ```
> Version: v1 ref 59499a44cd4482b68a7e989a5e7dd781414facfa must match: v1.0.6 ref 1a13fd188ebef96fb179faedfabcc8de5cb6189d
> ```
> 
> 🔴 Incorrect version
> ```
> Version: v1.0 ref 59499a44cd4482b68a7e989a5e7dd781414facfa must match: v1.0.6 ref 1a13fd188ebef96fb179faedfabcc8de5cb6189d
> ```
> 🔴 Incorrect version
> ```
> Version: latest ref 59499a44cd4482b68a7e989a5e7dd781414facfa must match: v1.0.6 ref 1a13fd188ebef96fb179faedfabcc8de5cb6189d
> ```

And a set of suggested Git commands to fix this:

> ### Suggested fix:
> ```
> git push origin 1a13fd188ebef96fb179faedfabcc8de5cb6189d:refs/tags/v1 --force
> git push origin 1a13fd188ebef96fb179faedfabcc8de5cb6189d:refs/tags/v1.0 --force
> git push origin 1a13fd188ebef96fb179faedfabcc8de5cb6189d:latest --force
> ```

# Prerequisites

## v2 (Current)

**No checkout required!** Version 2 uses the GitHub REST API exclusively, so you don't need to checkout the repository:

```yaml
- uses: jessehouwing/actions-semver-checker@v2
```

This is a significant improvement over v1, making the action faster and simpler to use.

## v1 (Legacy)

<details>
<summary>If using v1, you still need full git history...</summary>

Version 1 requires full git history and tags:

```yaml
- uses: actions/checkout@v6
  with:
    fetch-depth: 0      # Required for v1: Fetches full git history
    fetch-tags: true    # Required for v1: Fetches all tags
```

</details>

## Auto-fix Mode Prerequisites

If you're using the `auto-fix` feature to automatically update version tags/branches:

```yaml
jobs:
  check-semver:
    permissions:
      contents: write  # Required for auto-fix to push tags/branches
    steps:
      - uses: jessehouwing/actions-semver-checker@v2
        with:
          auto-fix: true
          token: ${{ secrets.GITHUB_TOKEN }}  # Required for auto-fix API calls
```

**Requirements:**
- **`contents: write` permission** - Required to push tag/branch updates via REST API
- **`token`** - GitHub token for API calls (create releases, update refs)

## Using Custom Tokens for Workflow File Changes

The default `GITHUB_TOKEN` **cannot** push tags or branches that would modify files in `.github/workflows/`. This is a security feature of GitHub Actions. If your action repository has workflow files that change between versions, auto-fix will fail with a permission error.

To work around this limitation, you can use either:
1. **GitHub App Token** (Recommended for organizations)
2. **Fine-grained Personal Access Token** (Simpler for personal repositories)

### Option 1: GitHub App Token (Recommended)

Using a GitHub App provides the most secure and manageable approach, especially for organizations.

**Step 1:** Create a GitHub App with the following permissions:
- **Repository permissions:**
  - `Contents`: Read and write
  - `Workflows`: Read and write *(this is the key permission)*
  - `Metadata`: Read-only (automatically selected)

**Step 2:** Install the App on your repository

**Step 3:** Use the [actions/create-github-app-token](https://github.com/marketplace/actions/create-github-app-token) action:

```yaml
name: Auto-fix SemVer

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  fix-semver:
    runs-on: ubuntu-latest
    steps:
      - name: Generate GitHub App Token
        id: app-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ vars.APP_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}
          # Scope the token to only this repository
          owner: ${{ github.repository_owner }}
          repositories: ${{ github.event.repository.name }}

      - uses: jessehouwing/actions-semver-checker@v2
        with:
          auto-fix: true
          token: ${{ steps.app-token.outputs.token }}
```

**Benefits:**
- Fine-grained permissions scoped to specific repositories
- Can be managed at organization level
- Token automatically expires (more secure than PATs)
- Audit logging for all actions taken

### Option 2: Fine-grained Personal Access Token

For personal repositories or simpler setups, a fine-grained PAT works well.

**Step 1:** Create a Fine-grained PAT at [GitHub Settings → Developer Settings → Personal Access Tokens → Fine-grained tokens](https://github.com/settings/tokens?type=beta)

**Step 2:** Configure the token with these permissions:
- **Repository access:** Select your action repository
- **Repository permissions:**
  - `Contents`: Read and write
  - `Workflows`: Read and write *(this is the key permission)*
  - `Metadata`: Read-only (automatically selected)

**Step 3:** Add the token as a repository secret (e.g., `SEMVER_TOKEN`)

**Step 4:** Use the token in your workflow:

```yaml
name: Auto-fix SemVer

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  fix-semver:
    runs-on: ubuntu-latest
    steps:
      - uses: jessehouwing/actions-semver-checker@v2
        with:
          auto-fix: true
          token: ${{ secrets.SEMVER_TOKEN }}
```

> **⚠️ Security Note:** PATs are tied to a user account. If the user leaves the organization or their account is compromised, the token may need to be rotated. For organizations, GitHub App tokens are preferred.

### When Do You Need a Custom Token?

You need a custom token with `workflows` permission if:
- Your action repository contains `.github/workflows/` files
- These workflow files change between versions
- You want to use `auto-fix: true` to push tags/branches

If your repository has no workflow files, or workflow files don't change between versions, the default `GITHUB_TOKEN` with `contents: write` permission is sufficient.

### Troubleshooting Token Issues

If auto-fix fails with a permission error like:
```
refusing to allow a GitHub App to create or update workflow
```

This indicates the token lacks `workflows` permission. Follow one of the options above to use a properly configured token.

# Usage

## Basic Usage

```yaml  
- uses: jessehouwing/actions-semver-checker@v2
  with:
    # Configures warnings for minor versions.
    # Default: true
    check-minor-version: 'error'
```

## Configuration Options

### `token`
**Default:** `""` (uses GITHUB_TOKEN)

GitHub token for API access. If not provided, falls back to the GITHUB_TOKEN environment variable.

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
```

### `check-minor-version`
**Default:** `error`

Configures whether to check minor versions (e.g., `v1.0`) in addition to major versions.

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    check-minor-version: 'error'
```

### `check-releases`
**Default:** `error`

Check that every build version (e.g., `v1.0.0`) has a corresponding GitHub Release.

**Options:** `error`, `warning`, or `none`
- `error`: Report as error and fail the action
- `warning`: Report as warning but don't fail
- `none`: Skip this check entirely

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    check-releases: 'error'
```

### `check-release-immutability`
**Default:** `error`

Check that releases are immutable (not in draft status). Draft releases allow tag changes, making them mutable.

**Options:** `error`, `warning`, or `none`
- `error`: Report as error and fail the action
- `warning`: Report as warning but don't fail
- `none`: Skip this check entirely

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    check-release-immutability: 'error'
```

### `ignore-preview-releases`
**Default:** `true` ✅ **Recommended**

Ignore preview/pre-release versions when calculating which version major/minor tags should point to. When enabled (default):
- Preview releases are excluded from `v1` and `v1.0` tag calculations
- If `v1.1.1` (stable) exists and `v1.1.2` (preview), `v1` and `v1.1` will point to `v1.1.1`

```yaml
# Default behavior (preview releases ignored)
- uses: jessehouwing/actions-semver-checker@v2

# Or explicitly set to false to include preview releases
- uses: jessehouwing/actions-semver-checker@v2
  with:
    ignore-preview-releases: 'false'
```

### `floating-versions-use`
**Default:** `tags`

Specify whether floating versions (major like `v1`, minor like `v1.0`, and `latest`) should use tags or branches. This is useful when you want mutable major/minor versions that can be updated via branch commits.

**Options:** `tags` or `branches`

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    floating-versions-use: 'branches'
```

### `auto-fix`
**Default:** `false`

Automatically fix major/minor version tags or branches when a build tag is pushed. 

**⚠️ Important:** When enabling auto-fix, you must grant `contents: write` permission:

```yaml
jobs:
  check-semver:
    permissions:
      contents: write  # Required for auto-fix
    steps:
      - uses: jessehouwing/actions-semver-checker@v2
        with:
          auto-fix: 'true'
```

**Note:** 
- Auto-fix handles all operations via REST API (no checkout required)
- When `check-release-immutability` is set to `error` or `warning` (default), auto-fix will also automatically republish non-immutable releases to make them immutable
- GitHub Release creation for new versions must be done manually (auto-fix creates draft releases only)

**Auto-fix behavior for releases:**
When `auto-fix: true` is enabled and `check-release-immutability` is set to `error` or `warning`:
1. Creates draft releases for missing patch versions (vX.Y.Z)
2. Attempts to publish draft releases automatically
3. **Republishes non-immutable releases** by temporarily converting them to draft and publishing again to make them immutable

This automatic republishing helps migrate repositories to GitHub's immutable release strategy without manual intervention.

### `ignore-versions`
**Default:** `""` (empty)

List of versions to ignore during validation. This is useful for skipping legacy or problematic versions that you don't want to validate.

**Supported formats:**

```yaml
# Comma-separated
ignore-versions: 'v1.0.0,v2.0.0,v3.0.0'

# Newline-separated (using YAML literal block)
ignore-versions: |
  v1.0.0
  v2.0.0
  v3.0.0

# JSON array
ignore-versions: '["v1.0.0", "v2.0.0", "v3.0.0"]'
```

**Wildcard support:**

You can use wildcards to match multiple versions:

```yaml
# Ignore all v1.x versions
ignore-versions: 'v1.*'

# Ignore all preview releases and specific version
ignore-versions: 'v1.0.0'
```

**Use cases:**
- Skip validation for legacy versions that don't follow current standards
- Ignore problematic versions that can't be fixed
- Exclude pre-release versions from validation
- Bulk ignore version ranges using wildcards

## Examples

### Complete Workflow Example

```yaml
name: Check SemVer

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:

jobs:
  check-semver:
    concurrency:
      group: '${{ github.workflow }}'
      cancel-in-progress: true
    runs-on: ubuntu-latest
    steps:
      - uses: jessehouwing/actions-semver-checker@v2
        with:
          check-minor-version: 'true'
          check-releases: 'true'
          check-release-immutability: 'true'
```

### Auto-fix with Branches

```yaml
name: Auto-fix SemVer

on:
  push:
    tags:
      - 'v*.*.*'  # Only trigger on patch versions

jobs:
  fix-semver:
    permissions:
      contents: write  # Required for auto-fix
    runs-on: ubuntu-latest
    steps:
      - uses: jessehouwing/actions-semver-checker@v2
        with:
          floating-versions-use: 'branches'
          auto-fix: 'true'
```

### With Preview Release Support

```yaml
name: Check SemVer (Stable Only)

on:
  push:
    tags:
      - 'v*'

jobs:
  check-semver:
    runs-on: ubuntu-latest
    steps:
      - uses: jessehouwing/actions-semver-checker@v2
        with:
          check-releases: 'error'
          # ignore-preview-releases: true (default)
```

## Suggested Fixes

When issues are detected, the action provides specific commands to fix them, including direct links to GitHub release pages:

### Creating a Release
```bash
gh release create v1.0.0 --draft --title "v1.0.0" --notes "Release v1.0.0"
gh release edit v1.0.0 --draft=false  # Or edit at: https://github.com/{owner}/{repo}/releases/edit/v1.0.0
```

**Note:** Creating releases as drafts first is important to maintain immutability checks. The action provides direct links to the GitHub release edit page for convenience.

### Updating Version Tags
```bash
git push origin <sha>:refs/tags/v1 --force
git push origin <sha>:refs/tags/v1.0 --force
```

### Updating Version Branches
```bash
git push origin <sha>:refs/heads/v1 --force
git push origin <sha>:refs/heads/v1.0 --force
git push origin <sha>:refs/heads/latest --force
```

## Permissions

### Read-only Mode (Default)
No special permissions required. The action only checks and reports issues.

### Auto-fix Mode
Requires `contents: write` permission to push tag/branch updates:

```yaml
jobs:
  check-semver:
    permissions:
      contents: write
```

## Architecture

This action uses a modular architecture with a domain model at its core, making it maintainable, testable, and extensible.

### Module Structure

```
actions-semver-checker/
├── main.ps1              # Orchestrator (1,407 lines)
│   ├── Initialize State
│   ├── Collect tags, branches, releases
│   ├── Run validations
│   ├── Execute remediation (auto-fix)
│   └── Report results
│
├── lib/                  # Reusable modules (1,114 lines)
│   ├── StateModel.ps1    # Domain model (420 lines)
│   │   ├── VersionRef class
│   │   ├── ReleaseInfo class
│   │   ├── ValidationIssue class (with status tracking)
│   │   ├── RepositoryState class (single source of truth)
│   │   └── RemediationPlan class (dependency ordering)
│   │
│   ├── GitHubApi.ps1     # GitHub REST API (432 lines)
│   │   ├── Get releases with pagination
│   │   ├── Create/delete tags and branches
│   │   ├── Manage releases and attestations
│   │   └── Handle rate limiting
│   │
│   ├── Remediation.ps1   # Auto-fix strategies (144 lines)
│   │   ├── Execute fixes via REST API
│   │   ├── Calculate next available version
│   │   └── Generate manual fix commands
│   │
│   ├── Logging.ps1       # Safe output (75 lines)
│   │   ├── Workflow command injection protection
│   │   └── GitHub Actions formatting
│   │
│   └── VersionParser.ps1 # Version parsing (43 lines)
│       └── Semantic version validation
│
└── main.Tests.ps1        # Comprehensive test suite (81 tests)
```

### Domain Model

**RepositoryState** (single source of truth):
- **Tags/Branches**: `VersionRef[]` with semantic parsing
- **Releases**: `ReleaseInfo[]` with immutability status
- **Issues**: `ValidationIssue[]` with lifecycle tracking
- **Calculated metrics**: Counts derived from issue statuses

**ValidationIssue statuses**:
- `pending` → Not yet processed
- `fixed` → Auto-fix succeeded
- `failed` → Auto-fix failed
- `unfixable` → Requires manual intervention

### Design Principles

1. **Single Source of Truth**: All state tracked in `RepositoryState` domain model
2. **Status-Based Calculation**: Metrics calculated on-demand (no manual counters)
3. **Separation of Concerns**: Each module has a single responsibility
4. **Zero Breaking Changes**: 100% backward compatibility maintained

### Validation Flow

```
1. Initialize
   └── Create RepositoryState with configuration

2. Collect
   ├── Git tags (git tag -l v*)
   ├── Git branches (git branch --remotes)
   └── GitHub releases (REST API with pagination)

3. Validate
   ├── Check floating versions point to correct patches
   ├── Verify releases exist for patch versions
   ├── Ensure releases are immutable (not drafts)
   └── Detect ambiguous refs (tag + branch conflicts)

4. Remediate (if auto-fix enabled)
   ├── Create/update tags via REST API
   ├── Create/update branches via REST API
   ├── Create draft releases via REST API
   └── Track status: fixed/failed/unfixable

5. Report
   ├── Display state summary
   ├── Show fixed/failed/unfixable counts
   ├── Provide manual fix commands
   └── Exit with appropriate code
```

### Contributing

Want to contribute? See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Development setup
- Module guide with detailed responsibilities
- Testing guidelines
- Code style conventions
- Pull request process

## Migration from v1 to v2

v2 is backward compatible with v1. The main differences:

- **New input options:**
  - `token` - Explicit GitHub token input
  - `check-releases` - Now accepts "error" (default), "warning", or "none"
  - `check-release-immutability` - Now accepts "error" (default), "warning", or "none"
  - `ignore-versions` - Comma-separated list of versions to ignore (NEW in v2.1)

- **Configuration improvements:**
  - `floating-versions-use` replaces `use-branches` - Now accepts `tags` (default) or `branches`
  - Release suggestions include direct GitHub edit links
  - Link header-based pagination for better API performance
  - Retry logic with exponential backoff for better reliability (NEW in v2.1)

- **Opt-in features:**
  - `ignore-preview-releases: true` (default) - Set to `false` to include prereleases in floating version calculations
  - `floating-versions-use: tags` (default) - Set to `branches` to use branches for floating versions
  - `auto-fix: false` (default) - Set to `true` to automatically fix missing/incorrect tags
  - **NEW in v2.1:** When `auto-fix: true` and `check-release-immutability` is enabled, automatically republishes non-immutable releases to make them immutable

If you want warnings instead of errors for release checks:

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    check-releases: 'warning'
    check-release-immutability: 'warning'
```

To disable release checks entirely (v1 behavior):

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    check-releases: 'none'
    check-release-immutability: 'none'
```

To skip validation for specific versions:

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    ignore-versions: 'v1.0.0,v2.0.0-beta'
```

To automatically fix issues including republishing non-immutable releases:

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    auto-fix: 'true'
    check-release-immutability: 'error'  # or 'warning' - enables automatic republishing
```
