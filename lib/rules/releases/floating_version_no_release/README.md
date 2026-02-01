# Rule: floating_version_no_release

## What This Rule Checks

Validates that floating versions (e.g., `v1`, `v1.0`, `latest`) do not have GitHub Releases. Releases should only exist for immutable patch versions (e.g., `v1.0.0`), while floating versions should use tags or branches that can be moved.

## Why This Is An Issue

- **Impact:** Floating versions are meant to be mutable pointers that track the latest patch. If they have releases (especially immutable ones), they cannot be updated to point to new patches.
- **Best Practice:** GitHub's [immutable release strategy](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases) requires releases only for patch versions. Floating versions use tags/branches that can be force-pushed.

## When This Rule Applies

This rule runs when:
- `check-releases` is set to `error` or `warning`, OR
- `check-release-immutability` is set to `error` or `warning`
- A release exists for a floating version (vX, vX.Y, or latest)

## Configuration

| Input | Required Value | Description |
|-------|----------------|-------------|
| `check-releases` | `error` or `warning` | Enables checking for inappropriate releases |
| `check-release-immutability` | `error` or `warning` | Enables checking for inappropriate releases |

**Note:** Either setting being enabled will trigger this rule.

## Required Permissions

**Important:** Draft releases are NOT visible via the GitHub API with `contents: read` permission. This rule can only detect draft releases on floating versions if the workflow has `contents: write` permission.

```yaml
permissions:
  contents: write  # Required to see draft releases
```

## Automatic Remediation

When `auto-fix` is enabled, this rule uses `DeleteReleaseAction` for **mutable** (draft) releases:

1. Deletes the release
2. Leaves the tag/branch intact (to preserve the version pointer)

**Important:** If the release is **immutable** (published and repository has immutability enabled), it cannot be deleted. The issue will be marked as **unfixable** and the user must add the version to `ignore-versions`.

## Manual Remediation

### For Mutable (Draft) Releases

Using GitHub CLI:

```bash
# Delete the release (keeps the tag)
gh release delete v1 --yes
```

Using GitHub Web UI:

1. Navigate to **Releases** in your repository
2. Find the floating version release
3. Click **Delete**
4. Confirm deletion

### For Immutable Releases

Immutable releases **cannot be deleted**. You have two options:

1. **Add to ignore-versions** (recommended):
   ```yaml
   - uses: jessehouwing/actions-semver-checker@v1
     with:
       ignore-versions: 'v1,v1.0,latest'
   ```

2. **Contact GitHub Support** to request deletion (only for exceptional cases)

## Related Rules

- [`patch_release_required`](../patch_release_required/README.md) - Ensures patch versions have releases
- [`release_should_be_published`](../release_should_be_published/README.md) - Ensures releases are published
- [`release_should_be_immutable`](../release_should_be_immutable/README.md) - Validates release immutability

## Issue Types

This rule creates different issue types based on release mutability:

| Issue Type | Severity | Remediation | Occurs When |
|------------|----------|-------------|-------------|
| `mutable_floating_release` | warning | `DeleteReleaseAction` | Release is draft (mutable) |
| `immutable_floating_release` | error | None (unfixable) | Release is published and immutable |

## Examples

### Failing Scenario - Mutable Release (Fixable)

```
Repository state:
- Tag: v1 → abc123
- Release: v1 (draft, mutable)

Configuration:
- check-releases: error

Issue: mutable_floating_release for v1
Action: DeleteReleaseAction (will delete the release)
```

### Failing Scenario - Immutable Release (Unfixable)

```
Repository state:
- Tag: v1 → abc123
- Release: v1 (published, immutable)

Configuration:
- check-release-immutability: error

Issue: immutable_floating_release for v1
Status: unfixable
Manual Fix: Add v1 to ignore-versions
```

### Passing Scenario

```
Repository state:
- Tag: v1 → abc123
- No release for v1

Result: No issues
```

### Not Applicable (Patch Version)

```
Repository state:
- Tag: v1.0.0 → abc123
- Release: v1.0.0 (published, immutable)

Result: This rule does NOT apply to patch versions
Note: Patch versions SHOULD have releases
```

## Why Floating Versions Should Not Have Releases

Floating versions serve as **mutable aliases** that always point to the latest compatible patch:

- `v1` → always points to latest `v1.x.x`
- `v1.0` → always points to latest `v1.0.x`
- `latest` → always points to globally latest version

To update these pointers:
- **Tags:** Force-push with `git tag -f v1 <new-sha>`
- **Branches:** Regular push with `git push -f origin v1`

If a floating version has an immutable release:
- The tag cannot be moved (GitHub prevents it)
- Users get "old" code when they reference the version
- The only solution is to delete the release (requires support) or ignore the version
