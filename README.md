# Actions SemVer Checker Action

Every time you publish a new version of a GitHub Action, say `v1.2.3`, it's customary to also update the tags for `v1.2` and `v1` to point to the same commit. That way people can subscribe to  either an exact version or a floating version that's automatically updated when the action's author pushes a new version.

Unfortunately, GitHub's creative use of tags doesn't do this automatically and many actions don't auto-update their major and minor versions whenever they release a new  patch.

You can run this action for your GitHub Action's repository to ensure the correct tags have been created and point to the correct commits.

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

This action requires full git history and tags to function properly. Configure the [Checkout action](https://github.com/marketplace/actions/checkout) correctly:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0      # Required: Fetches full git history
    fetch-tags: true    # Required: Fetches all tags
```

**Why these settings are required:**

- **`fetch-depth: 0`** ([docs](https://github.com/actions/checkout#usage)) - The action needs full git history to analyze all version tags and commits. The default shallow clone (`fetch-depth: 1`) only includes the latest commit. Without this, you'll see: `::error::Shallow clone detected`.

- **`fetch-tags: true`** ([docs](https://github.com/actions/checkout#usage)) - The action validates version tags. The default (`fetch-tags: false`) does not fetch tags from the remote repository. Without this, the action may report: `::warning::No tags found`.

Learn more about [configuring the checkout action](https://github.com/marketplace/actions/checkout).

## Auto-fix Mode Prerequisites

If you're using the `auto-fix` feature to automatically update version tags/branches, additional configuration applies:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
    fetch-tags: true
    persist-credentials: true  # Required for auto-fix (this is the default)
    token: ${{ secrets.GITHUB_TOKEN }}

- uses: jessehouwing/actions-semver-checker@v2
  with:
    auto-fix: true
    token: ${{ secrets.GITHUB_TOKEN }}  # Required for auto-fix
```

**About `persist-credentials`** ([docs](https://github.com/actions/checkout#persist-credentials)):
- Default is `true` - checkout action saves credentials for subsequent git operations
- If set to `false`, the semver-checker action will automatically configure git credentials using the provided token
- Either way works, but `true` (default) is simpler

Learn more about [checkout action authentication](https://github.com/marketplace/actions/checkout).

# Usage

## Basic Usage

```yaml  
- uses: actions/checkout@v4
  with:
    fetch-depth: 0      # Required: Full git history
    fetch-tags: true    # Required: All tags

- uses: jessehouwing/actions-semver-checker@v2
  with:
    # Configures warnings for minor versions.
    # Default: true
    check-minor-version: 'true'
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
**Default:** `true`

Configures whether to check minor versions (e.g., `v1.0`) in addition to major versions.

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    check-minor-version: 'true'
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
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - uses: jessehouwing/actions-semver-checker@v2
        with:
          auto-fix: 'true'
```

**Note:** Auto-fix only handles git push commands for tags/branches. GitHub Release creation commands must be executed manually.

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
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-tags: true

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
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-tags: true

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
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-tags: true

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

## Migration from v1 to v2

v2 is backward compatible with v1. The main differences:

- **New input options:**
  - `token` - Explicit GitHub token input
  - `check-releases` - Now accepts "error" (default), "warning", or "none"
  - `check-release-immutability` - Now accepts "error" (default), "warning", or "none"

- **Configuration improvements:**
  - `floating-versions-use` replaces `use-branches` - Now accepts `tags` (default) or `branches`
  - Release suggestions include direct GitHub edit links
  - Link header-based pagination for better API performance

- **Opt-in features:**
  - `ignore-preview-releases: true` (default) - Set to `false` to include prereleases in floating version calculations
  - `floating-versions-use: tags` (default) - Set to `branches` to use branches for floating versions
  - `auto-fix: false` (default) - Set to `true` to automatically fix missing/incorrect tags

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
