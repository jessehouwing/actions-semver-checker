# Rule: tag_should_be_branch

## What This Rule Checks

This rule validates that floating version references (vX, vX.Y) exist as **branches** rather than tags when the action is configured to use branches for floating versions.

**Important:** Patch versions (vX.Y.Z) must always remain as tags regardless of this setting, as they need to be immutable and linked to GitHub Releases.

**Note:** This rule only triggers when a tag exists but the corresponding branch does not. If both a tag and branch exist for the same version, a separate duplicate detection rule will handle that scenario.

## Why This Is An Issue

- **Impact:** When using branches mode, floating versions need to be branches to allow easy updates without force-pushing tags
- **Best Practice:** Branches are mutable by default and can be updated normally. Some teams prefer this approach for floating versions while keeping patch versions as immutable tags

## When This Rule Applies

This rule runs when:
- `floating-versions-use` is set to `branches`
- Tags exist for major (vX) or minor (vX.Y) versions that should be branches

## Configuration

### Settings That Enable This Rule

| Input | Required Value | Effect |
|-------|----------------|--------|
| `floating-versions-use` | `branches` | Rule is enabled - floating versions must be branches |

**Note:** This rule only applies to floating versions (vX, vX.Y). Patch versions (vX.Y.Z) must always be tags regardless of this setting.

### Settings That Affect Severity

Ref type violations are **always** reported as **error** (not configurable). Using the wrong reference type (tag vs branch) is a structural error that prevents the action from working correctly.

| Severity | Always |
|----------|--------|
| **error** | ✓ |

## Manual Remediation

If auto-fix is not enabled or fails, you can manually convert tags to branches:

### Using Git

```bash
# Convert tag to branch (preserves the same commit SHA)
git fetch origin refs/tags/v1:refs/heads/v1
git push origin :refs/tags/v1
git push origin refs/heads/v1
```

### Using GitHub CLI

```bash
# Get the SHA from the tag
SHA=$(gh api repos/:owner/:repo/git/refs/tags/v1 --jq '.object.sha')

# Create the branch
gh api repos/:owner/:repo/git/refs -f ref='refs/heads/v1' -f sha="$SHA"

# Delete the tag
gh api repos/:owner/:repo/git/refs/tags/v1 -X DELETE
```

### Using GitHub Web UI

1. Navigate to the repository's **Code** tab
2. Click on the branch dropdown
3. Type the version name (e.g., `v1`) in the search box
4. Click **Create branch: v1 from 'main'** (or select the appropriate base)
5. Navigate to **Tags** and delete the tag version

Note: You'll need to ensure the branch points to the same commit as the tag before deleting the tag.

## Related Rules

- [`branch_should_be_tag`](../branch_should_be_tag/README.md) - Opposite rule when using tags mode (default)
- [`duplicate_floating_version_ref`](../duplicate_floating_version_ref/README.md) - Handles cases where both tag and branch exist

## Examples

### Failing Scenario

Repository has:
- Tag `v1` → abc123
- Tag `v1.0` → abc123
- Tag `v1.0.0` → abc123

Configuration:
```yaml
floating-versions-use: branches
```

**Result:** 2 issues created for v1 and v1.0 (NOT v1.0.0, as patches must remain tags)

### Passing Scenario

Repository has:
- Branch `v1` → abc123
- Branch `v1.0` → abc123
- Tag `v1.0.0` → abc123 (with release)

Configuration:
```yaml
floating-versions-use: branches
```

**Result:** No issues (floating versions are branches, patch is a tag)
