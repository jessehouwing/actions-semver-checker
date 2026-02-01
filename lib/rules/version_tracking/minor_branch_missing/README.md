# Rule: minor_branch_missing

## What This Rule Checks

This rule verifies that minor version branches (e.g., `v1.0`, `v2.1`) exist for all major.minor series that have at least one patch version.

## Why This Is An Issue

Minor version branches provide a convenient way for users to track the latest patch in a minor series without needing to know the exact patch number.

- **Impact:** Users cannot use minor version aliases (e.g., `uses: owner/repo@v1.0`) to get the latest patch in that series
- **Best Practice:** Each minor series with patches should have a corresponding minor branch pointing to the highest patch
- **Continuous Delivery:** Branches enable automatic updates via CI/CD workflows

## When This Rule Applies

This rule runs when:
- `floating-versions-use: branches`
- `check-minor-version: error` or `check-minor-version: warning`
- At least one patch version exists for a major.minor series

## Configuration

### Settings That Enable This Rule

| Input | Required Value | Effect |
|-------|----------------|--------|
| `floating-versions-use` | `branches` | Rule applies to branches |
| `check-minor-version` | `error` or `warning` | Enables minor version validation |

**Note:** If `floating-versions-use` is `tags` or `check-minor-version` is `none`, this rule is disabled.

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

If auto-fix is not enabled or fails, you can manually create the missing minor branch:

### Using GitHub CLI

```bash
# Find the highest patch for the minor series (e.g., v1.0.x)
gh api repos/{owner}/{repo}/git/refs/tags | jq -r '.[] | select(.ref | contains("v1.0.")) | .ref'

# Get the SHA of the highest patch
SHA=$(gh api repos/{owner}/{repo}/git/ref/tags/v1.0.2 --jq '.object.sha')

# Create the minor branch
gh api repos/{owner}/{repo}/git/refs \
  -f ref="refs/heads/v1.0" \
  -f sha="$SHA"
```

### Using Git

```bash
# Checkout the highest patch version
git checkout v1.0.2

# Create and push the minor branch
git checkout -b v1.0
git push origin v1.0
```

## Related Rules

- [`minor_branch_tracks_highest_patch`](../minor_branch_tracks_highest_patch/README.md) - Validates that existing minor branches point to the correct SHA
- [`major_branch_missing`](../major_branch_missing/README.md) - Similar validation for major version branches
- [`minor_tag_missing`](../minor_tag_missing/README.md) - Tag equivalent for `floating-versions-use: tags`

## Examples

### Failing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v1.0.1 → def456 (tag)
- v1.0.2 → ghi789 (tag)
- v1.0 branch is missing

Issue: Minor version branch v1.0 is missing but patch versions exist
Remediation: Create v1.0 branch pointing to ghi789 (same as v1.0.2)
```

### Passing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v1.0.1 → def456 (tag)
- v1.0.2 → ghi789 (tag)
- v1.0 → ghi789 (branch)

All minor version branches exist and point to the correct SHA ✓
```
