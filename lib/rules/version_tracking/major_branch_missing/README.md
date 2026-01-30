# Rule: major_branch_missing

## What This Rule Checks

This rule verifies that major version branches (e.g., `v1`, `v2`) exist for all major versions that have at least one patch version.

## Why This Is An Issue

Major version branches provide a convenient way for users to always get the latest version within a major series without needing to track specific patch numbers.

- **Impact:** Users cannot use major version aliases (e.g., `uses: owner/repo@v1`) to get the latest patch in that major version
- **Best Practice:** When using branches for floating versions, major branches should exist to track the latest patches
- **Continuous Delivery:** Branches enable automatic updates via CI/CD after each release

## When This Rule Applies

This rule runs when:
- `floating-versions-use: branches`
- At least one patch version exists for a major version (e.g., `v1.0.0`)
- No major version branch exists (e.g., `v1`)

## Configuration

| Input | Required Value | Description |
|-------|----------------|-------------|
| `floating-versions-use` | `branches` | Major versions must be tracked as branches |

## Manual Remediation

If auto-fix is not enabled or fails, you can manually create the missing major branch:

### Using GitHub CLI

```bash
# Find the highest patch for the major series (e.g., v1.x.x)
gh api repos/{owner}/{repo}/git/refs/tags | jq -r '.[] | select(.ref | contains("v1.")) | .ref'

# Get the SHA of the highest patch
SHA=$(gh api repos/{owner}/{repo}/git/ref/tags/v1.2.3 --jq '.object.sha')

# Create the major branch
gh api repos/{owner}/{repo}/git/refs \
  -f ref="refs/heads/v1" \
  -f sha="$SHA"
```

### Using Git

```bash
# Checkout the highest patch version
git checkout v1.2.3

# Create and push the major branch
git checkout -b v1
git push origin v1
```

## Related Rules

- [`major_branch_tracks_highest_patch`](../major_branch_tracks_highest_patch/README.md) - Validates that existing major branches point to the correct SHA
- [`minor_branch_missing`](../minor_branch_missing/README.md) - Similar validation for minor version branches
- [`major_tag_missing`](../major_tag_missing/README.md) - Tag equivalent for `floating-versions-use: tags`

## Examples

### Failing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v1.1.0 → def456 (tag)
- v1.2.0 → ghi789 (tag)
- v1 branch is missing

Issue: Major version branch v1 is missing but patch versions exist
Remediation: Create v1 branch pointing to ghi789 (same as v1.2.0)
```

### Passing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v1.1.0 → def456 (tag)
- v1.2.0 → ghi789 (tag)
- v1 → ghi789 (branch)

All major version branches exist and point to the correct SHA ✓
```
