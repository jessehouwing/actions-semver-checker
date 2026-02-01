# Rule: major_tag_missing

## What This Rule Checks

This rule verifies that major version tags (e.g., `v1`, `v2`) exist for all major versions that have at least one patch version.

## Why This Is An Issue

Major version tags provide a convenient way for users to always get the latest version within a major series without needing to track specific patch numbers.

- **Impact:** Users cannot use major version aliases (e.g., `uses: owner/repo@v1`) to get the latest patch in that major version
- **Best Practice:** GitHub Actions' [versioning strategy](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases) recommends providing major version tags for convenience
- **User Experience:** Major tags allow workflows to stay updated with patches automatically

## When This Rule Applies

This rule runs when:
- `floating-versions-use: tags` (default)
- At least one patch version exists for a major version (e.g., `v1.0.0`)
- No major version tag exists (e.g., `v1`)

## Configuration

### Settings That Enable This Rule

| Input | Required Value | Effect |
|-------|----------------|--------|
| `floating-versions-use` | `tags` (default) or not `branches` | Rule applies to tags |

**Note:** Major version tracking is **always required** when using tags. This rule cannot be disabled.

### Settings That Affect Severity

Major version tracking is **always** reported as **error** (not configurable). Major versions are fundamental to GitHub Actions versioning - users depend on `uses: owner/repo@v1`.

| Severity | Always |
|----------|--------|
| **error** | ✓ |

### Other Relevant Settings

| Input | Effect |
|-------|--------|
| `ignore-preview-releases` | When `true`, excludes prerelease versions from highest-patch calculation |

## Manual Remediation

If auto-fix is not enabled or fails, you can manually create the missing major tag:

### Using GitHub CLI

```bash
# Find the highest patch for the major series (e.g., v1.x.x)
gh api repos/{owner}/{repo}/git/refs/tags | jq -r '.[] | select(.ref | contains("v1.")) | .ref'

# Get the SHA of the highest patch
SHA=$(gh api repos/{owner}/{repo}/git/ref/tags/v1.2.3 --jq '.object.sha')

# Create the major tag
gh api repos/{owner}/{repo}/git/refs \
  -f ref="refs/tags/v1" \
  -f sha="$SHA"
```

### Using Git

```bash
# Checkout the highest patch version
git checkout v1.2.3

# Create and push the major tag
git tag v1
git push origin v1
```

### Using GitHub Web UI

1. Navigate to your repository's **Releases** page
2. Find the highest patch release in the major series (e.g., v1.2.3)
3. Click **"Create a new release"**
4. Set the tag to the major version (e.g., `v1`)
5. Target the same commit as the highest patch
6. Mark as "Set as the latest release" if appropriate
7. Publish the release

## Related Rules

- [`major_tag_tracks_highest_patch`](../major_tag_tracks_highest_patch/README.md) - Validates that existing major tags point to the correct SHA
- [`minor_tag_missing`](../minor_tag_missing/README.md) - Similar validation for minor version tags
- [`major_branch_missing`](../../version_tracking/major_branch_missing/README.md) - Branch equivalent for `floating-versions-use: branches`

## Examples

### Failing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v1.1.0 → def456 (tag)
- v1.2.0 → ghi789 (tag)
- v1 tag is missing

Issue: Major version tag v1 is missing but patch versions exist
Remediation: Create v1 tag pointing to ghi789 (same as v1.2.0)
```

### Passing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v1.1.0 → def456 (tag)
- v1.2.0 → ghi789 (tag)
- v1 → ghi789 (tag)

All major version tags exist and point to the correct SHA ✓
```

### Not Applicable (No Patches)

```
Repository state:
- v2 tag exists but no v2.x.x patches

This rule does not apply - no patches to track
```
