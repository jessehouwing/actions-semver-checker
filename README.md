# Actions SemVer Checker Action

Every time you publish a new version of a GitHub Action, say `v1.2.3`, it's customary to also update the tags for `v1.2` and `v1` to point to the same commit. That way people can subscribe to  either an exact version or a floating version that's automatically updated when the action's author pushes a new version.

Unfortunately, GitHub's creative use of tags doesn't do this automatically and many actions don't auto-update their major and minor versions whenever they release a new  patch.

You can run this action for your GitHub Action's repository to ensure the correct tags have been created and point to the correct commits.

## Features

- ✅ Validates that major (`v1`) and minor (`v1.0`) version tags point to the latest patch version
- ✅ Checks that every patch version (`v1.0.0`) has a corresponding GitHub Release
- ✅ Verifies that releases are immutable (not in draft status)
- ✅ Supports filtering preview/pre-release versions from major/minor tag calculations
- ✅ Can enforce that major/minor versions use branches instead of tags
- ✅ Provides suggested commands to fix any issues
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

# Usage

## Basic Usage

```yaml  
- uses: actions/checkout@v4
  # Check out with fetch-depth: 0 to get all tags
  with:
    fetch-depth: 0

- uses: jessehouwing/actions-semver-checker@v2
  with:
    # Configures warnings for minor versions.
    # Default: true
    check-minor-version: 'true'
```

## Configuration Options

### `check-minor-version`
**Default:** `true`

Configures whether to check minor versions (e.g., `v1.0`) in addition to major versions.

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    check-minor-version: 'true'
```

### `check-releases`
**Default:** `true`

Check that every build version (e.g., `v1.0.0`) has a corresponding GitHub Release.

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    check-releases: 'true'
```

### `check-release-immutability`
**Default:** `true`

Check that releases are immutable (not in draft status). Draft releases allow tag changes, making them mutable.

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    check-release-immutability: 'true'
```

### `ignore-preview-releases`
**Default:** `false`

Ignore preview/pre-release versions when calculating which version major/minor tags should point to. When enabled:
- Preview releases are excluded from `v1` and `v1.0` tag calculations
- If `v1.1.1` (stable) exists and `v1.1.2` (preview), `v1` and `v1.1` will point to `v1.1.1`

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    ignore-preview-releases: 'true'
```

### `use-branches`
**Default:** `false`

Require that major and minor versions use branches instead of tags. This is useful when you want mutable major/minor versions that can be updated via branch commits.

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    use-branches: 'true'
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

      - uses: jessehouwing/actions-semver-checker@v2
        with:
          use-branches: 'true'
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

      - uses: jessehouwing/actions-semver-checker@v2
        with:
          ignore-preview-releases: 'true'
          check-releases: 'true'
```

## Suggested Fixes

When issues are detected, the action provides specific commands to fix them:

### Creating a Release
```bash
gh release create v1.0.0 --draft --title "v1.0.0" --notes "Release v1.0.0"
gh release edit v1.0.0 --draft=false
```

**Note:** Creating releases as drafts first is important to maintain immutability checks.

### Updating Version Tags
```bash
git push origin <sha>:refs/tags/v1 --force
git push origin <sha>:refs/tags/v1.0 --force
```

### Updating Version Branches
```bash
git push origin <sha>:refs/heads/v1 --force
git push origin <sha>:refs/heads/v1.0 --force
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

- **New features enabled by default:**
  - `check-releases: true` - Now checks for GitHub Releases
  - `check-release-immutability: true` - Validates releases are not drafts

- **Opt-in features (disabled by default):**
  - `ignore-preview-releases: false` - Set to `true` to exclude prereleases
  - `use-branches: false` - Set to `true` to enforce branches over tags
  - `auto-fix: false` - Set to `true` to automatically fix issues

If you want v1 behavior exactly, disable the new checks:

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    check-releases: 'false'
    check-release-immutability: 'false'
```
