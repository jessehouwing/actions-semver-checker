# Rule: minor_tag_missing

## What This Rule Checks

This rule verifies that minor version tags (e.g., `v1.0`, `v2.1`) exist for all major.minor series that have at least one patch version.

## Why This Is An Issue

Minor version tags provide a convenient way for users to track the latest patch in a minor series without needing to know the exact patch number.

- **Impact:** Users cannot use minor version aliases (e.g., `uses: owner/repo@v1.0`) to get the latest patch in that series
- **Best Practice:** Each minor series with patches should have a corresponding minor tag pointing to the highest patch

## When This Rule Applies

This rule runs when:
- `floating-versions-use: tags` (default)
- `check-minor-version: error` or `check-minor-version: warning`
- At least one patch version exists for a major.minor series

## Configuration

### Settings That Enable This Rule

| Input | Required Value | Effect |
|-------|----------------|--------|
| `floating-versions-use` | `tags` | Rule applies to tags (default) |
| `check-minor-version` | `error` or `warning` | Enables minor version validation |

**Note:** If `floating-versions-use` is `branches` or `check-minor-version` is `none`, this rule is disabled.

### Settings That Affect Severity

| check-minor-version | Issue Severity |
|--------------------|----------------|
| `error` | **error** |
| `warning` | **warning** |
| `none` | (rule disabled) |

### Other Relevant Settings

| Input | Effect |
|-------|--------|
| `ignore-preview-releases` | When `true`, excludes prerelease versions from highest-patch calculation |

## Manual Remediation

If auto-fix is not enabled or fails, you can manually create the missing minor tag:

### Using GitHub CLI

```bash
# Find the highest patch for the minor series (e.g., v1.0.x)
gh api repos/{owner}/{repo}/git/refs/tags | jq -r '.[] | select(.ref | contains("v1.0.")) | .ref'

# Get the SHA of the highest patch
SHA=$(gh api repos/{owner}/{repo}/git/ref/tags/v1.0.2 --jq '.object.sha')

# Create the minor tag
gh api repos/{owner}/{repo}/git/refs \
  -f ref="refs/tags/v1.0" \
  -f sha="$SHA"
```

### Using Git

```bash
# Checkout the highest patch version
git checkout v1.0.2

# Create and push the minor tag
git tag -f v1.0
git push origin v1.0 --force
```

### Using GitHub Web UI

1. Navigate to your repository's **Releases** page
2. Find the highest patch release in the minor series (e.g., v1.0.2)
3. Click **"Create a new release"**
4. Set the tag to the minor version (e.g., `v1.0`)
5. Target the same commit as the highest patch
6. Mark as "Set as the latest release" if appropriate
7. Publish the release

## Related Rules

- [`minor_tag_tracks_highest_patch`](../minor_tag_tracks_highest_patch/README.md) - Validates that existing minor tags point to the correct SHA
- [`major_tag_missing`](../major_tag_missing/README.md) - Similar validation for major version tags
- [`patch_tag_missing`](../patch_tag_missing/README.md) - Ensures patch versions exist

## Examples

### Failing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v1.0.1 → def456 (tag)
- v1.0.2 → ghi789 (tag)
- v1.0 tag is missing

Issue: Minor version tag v1.0 is missing but patch versions exist
Remediation: Create v1.0 tag pointing to ghi789 (same as v1.0.2)
```

### Passing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v1.0.1 → def456 (tag)
- v1.0.2 → ghi789 (tag)
- v1.0 → ghi789 (tag)

All minor version tags exist and point to the correct SHA ✓
```
