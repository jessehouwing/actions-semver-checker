# Rule: duplicate_floating_version_ref

## What This Rule Checks

This rule validates that floating version references (vX, vX.Y) exist as **either** a tag **or** a branch, but not both simultaneously.

## Why This Is An Issue

- **Impact:** Having both a tag and branch with the same version name creates ambiguity for users and may cause unexpected behavior in GitHub Actions workflows
- **Best Practice:** Each version reference should have a single canonical representation based on the `floating-versions-use` configuration

## When This Rule Applies

This rule runs when:
- A floating version (vX or vX.Y) exists as both a tag and a branch
- Applies regardless of `floating-versions-use` setting (rule will clean up the wrong ref type)

## Configuration

### Settings That Enable This Rule

This rule is **always enabled** when duplicates exist. Duplicate references are always structural errors.

### Settings That Affect Behavior

| Input | Value | Effect |
|-------|-------|--------|
| `floating-versions-use` | `tags` (default) | Deletes the branch, keeps the tag |
| `floating-versions-use` | `branches` | Deletes the tag, keeps the branch |

### Settings That Affect Severity

Duplicate references are **always** reported as **error** (not configurable). Having both a tag and branch with the same version name is a structural error.

| Severity | Always |
|----------|--------|
| **error** | ✓ |

## Manual Remediation

If auto-fix is not enabled or fails, you can manually remove the duplicate ref:

### When Using Tags Mode (default)

Delete the branch and keep the tag:

```bash
# Using Git
git push origin :refs/heads/v1

# Using GitHub CLI
gh api repos/:owner/:repo/git/refs/heads/v1 -X DELETE
```

### When Using Branches Mode

Delete the tag and keep the branch:

```bash
# Using Git
git push origin :refs/tags/v1

# Using GitHub CLI
gh api repos/:owner/:repo/git/refs/tags/v1 -X DELETE
```

### Using GitHub Web UI

**To delete a branch:**
1. Navigate to the repository's **Branches** page
2. Find the version (e.g., `v1`)
3. Click the trash icon next to it

**To delete a tag:**
1. Navigate to the repository's **Tags** page
2. Find the version (e.g., `v1`)
3. Click on the tag, then **Delete tag**

## Related Rules

- [`branch_should_be_tag`](../branch_should_be_tag/README.md) - Converts branches to tags when only branch exists
- [`tag_should_be_branch`](../tag_should_be_branch/README.md) - Converts tags to branches when only tag exists
- [`duplicate_latest_ref`](../duplicate_latest_ref/README.md) - Handles the same issue for "latest" version

## Examples

### Failing Scenario (Tags Mode)

Repository has:
- Tag `v1` → abc123
- Branch `v1` → abc123

Configuration:
```yaml
floating-versions-use: tags  # default
```

**Result:** Issue created, branch `v1` will be deleted (tag kept)

### Failing Scenario (Branches Mode)

Repository has:
- Tag `v1` → abc123
- Branch `v1` → abc123

Configuration:
```yaml
floating-versions-use: branches
```

**Result:** Issue created, tag `v1` will be deleted (branch kept)

### Passing Scenario

Repository has:
- Tag `v1` → abc123
- Branch `v2` → def456

**Result:** No issues (different version names, no duplicates)
