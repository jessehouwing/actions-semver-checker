# Rule: duplicate_latest_ref

## What This Rule Checks

This rule validates that the `latest` version reference exists as **either** a tag **or** a branch, but not both simultaneously.

## Why This Is An Issue

- **Impact:** Having both a tag and branch named "latest" creates ambiguity for users and may cause unexpected behavior in GitHub Actions workflows
- **Best Practice:** The "latest" reference should have a single canonical representation based on the `floating-versions-use` configuration

## When This Rule Applies

This rule runs when:
- Both a tag named `latest` and a branch named `latest` exist
- Applies regardless of `floating-versions-use` setting (rule will clean up the wrong ref type)

## Configuration

### Settings That Enable This Rule

This rule is **always enabled** when duplicates exist. Duplicate "latest" references are always structural errors.

### Settings That Affect Behavior

| Input | Value | Effect |
|-------|-------|--------|
| `floating-versions-use` | `tags` (default) | Deletes the "latest" branch, keeps the tag |
| `floating-versions-use` | `branches` | Deletes the "latest" tag, keeps the branch |

### Settings That Affect Severity

Duplicate "latest" references are **always** reported as **error** (not configurable). Having both a tag and branch named "latest" is a structural error.

| Severity | Always |
|----------|--------|
| **error** | ✓ |

## Manual Remediation

If auto-fix is not enabled or fails, you can manually remove the duplicate ref:

### When Using Tags Mode (default)

Delete the branch and keep the tag:

```bash
# Using Git
git push origin :refs/heads/latest

# Using GitHub CLI
gh api repos/:owner/:repo/git/refs/heads/latest -X DELETE
```

### When Using Branches Mode

Delete the tag and keep the branch:

```bash
# Using Git
git push origin :refs/tags/latest

# Using GitHub CLI
gh api repos/:owner/:repo/git/refs/tags/latest -X DELETE
```

### Using GitHub Web UI

**To delete a branch:**
1. Navigate to the repository's **Branches** page
2. Find the `latest` branch
3. Click the trash icon next to it

**To delete a tag:**
1. Navigate to the repository's **Tags** page
2. Find the `latest` tag
3. Click on the tag, then **Delete tag**

## Related Rules

- [`duplicate_floating_version_ref`](../duplicate_floating_version_ref/README.md) - Handles the same issue for version numbers (vX, vX.Y)
- Rules for tracking "latest" to the highest version will be implemented in Phase 3

## Examples

### Failing Scenario (Tags Mode)

Repository has:
- Tag `latest` → abc123
- Branch `latest` → abc123

Configuration:
```yaml
floating-versions-use: tags  # default
```

**Result:** Issue created, branch `latest` will be deleted (tag kept)

### Failing Scenario (Branches Mode)

Repository has:
- Tag `latest` → abc123
- Branch `latest` → abc123

Configuration:
```yaml
floating-versions-use: branches
```

**Result:** Issue created, tag `latest` will be deleted (branch kept)

### Passing Scenario

Repository has:
- Tag `latest` → abc123
- No `latest` branch

Configuration:
```yaml
floating-versions-use: tags  # default
```

**Result:** No issues (only one "latest" ref exists)
