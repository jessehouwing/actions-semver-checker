# Rule: branch_should_be_tag

## What This Rule Checks

This rule validates that floating version references (vX, vX.Y) and patch versions (vX.Y.Z) exist as **tags** rather than branches when the action is configured to use tags for floating versions.

**Note:** This rule only triggers when a branch exists but the corresponding tag does not. If both a branch and tag exist for the same version, a separate duplicate detection rule will handle that scenario.

## Why This Is An Issue

- **Impact:** GitHub Actions users expect floating versions to be tags by default, as this is the standard convention for GitHub Actions versioning
- **Best Practice:** Patch versions (vX.Y.Z) must always be immutable tags that point to GitHub Releases. Floating versions (vX, vX.Y) should also be tags by default to enable version pinning with automatic updates (e.g., `uses: owner/repo@v1`)

## When This Rule Applies

This rule runs when:
- `floating-versions-use` is set to `tags` (the default)
- Branches exist for versions that should be tags

## Configuration

### Settings That Enable This Rule

| Input | Required Value | Effect |
|-------|----------------|--------|
| `floating-versions-use` | `tags` (default) or not `branches` | Rule is enabled - versions must be tags |

**Note:** Patch versions (vX.Y.Z) must always be tags. This rule also applies to floating versions (vX, vX.Y) when using tags mode.

### Settings That Affect Severity

Ref type violations are **always** reported as **error** (not configurable). Using the wrong reference type (tag vs branch) is a structural error that prevents the action from working correctly.

| Severity | Always |
|----------|--------|
| **error** | ✓ |

## Manual Remediation

If auto-fix is not enabled or fails, you can manually convert branches to tags:

### Using Git

```bash
# Convert branch to tag (preserves the same commit SHA)
git fetch origin refs/heads/v1:refs/tags/v1
git push origin :refs/heads/v1
git push origin refs/tags/v1
```

### Using GitHub CLI

```bash
# Get the SHA from the branch
SHA=$(gh api repos/:owner/:repo/git/refs/heads/v1 --jq '.object.sha')

# Create the tag
gh api repos/:owner/:repo/git/refs -f ref='refs/tags/v1' -f sha="$SHA"

# Delete the branch
gh api repos/:owner/:repo/git/refs/heads/v1 -X DELETE
```

### Using GitHub Web UI

1. Navigate to the repository's **Releases** page
2. Click **Create a new release**
3. In the tag field, enter the version (e.g., `v1`)
4. Set the target to the branch you want to convert
5. Publish the release
6. Navigate to **Branches** and delete the branch

## Related Rules

- [`tag_should_be_branch`](../tag_should_be_branch/README.md) - Opposite rule when using branches mode
- [`duplicate_floating_version_ref`](../duplicate_floating_version_ref/README.md) - Handles cases where both tag and branch exist

## Examples

### Failing Scenario

Repository has:
- Branch `v1` → abc123
- Branch `v1.0` → abc123
- Branch `v1.0.0` → abc123

Configuration:
```yaml
floating-versions-use: tags  # default
```

**Result:** 3 issues created, suggesting conversion to tags

### Passing Scenario

Repository has:
- Tag `v1` → abc123
- Tag `v1.0` → abc123
- Tag `v1.0.0` → abc123

Configuration:
```yaml
floating-versions-use: tags  # default
```

**Result:** No issues (all versions are correctly using tags)
