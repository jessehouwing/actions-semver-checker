# Rule: duplicate_patch_version_ref

## What This Rule Checks

This rule validates that patch version references (vX.Y.Z) exist as **tags only**, not as both tags and branches simultaneously. Patch versions must always be tags to support immutable GitHub Releases.

## Why This Is An Issue

- **Impact:** Patch versions (vX.Y.Z) must be immutable tags linked to GitHub Releases. Having a branch with the same name creates ambiguity and violates GitHub Actions versioning best practices
- **Best Practice:** All patch versions should be tags. Branches should only be used for floating versions (vX, vX.Y) when `floating-versions-use: branches` is configured
- **Immutability:** GitHub Releases require patch versions to be tags. Branches are mutable and cannot be used for release tagging

## When This Rule Applies

This rule runs when:
- A patch version (vX.Y.Z) exists as both a tag and a branch
- Applies regardless of `floating-versions-use` setting (patches must always be tags)

## Configuration

### Settings That Enable This Rule

This rule is **always enabled** when duplicates exist. Duplicate patch version references are always structural errors.

### Settings That Affect Behavior

Patch versions **must always be tags**. The branch will always be deleted regardless of `floating-versions-use` setting.

### Settings That Affect Severity

Duplicate patch version references are **always** reported as **error** (not configurable). Patch versions must be immutable tags linked to GitHub Releases.

| Severity | Always |
|----------|--------|
| **error** | ✓ |

## Manual Remediation

If auto-fix is not enabled or fails, you can manually delete the branch:

### Using Git

```bash
# Delete the patch version branch (keep the tag)
git push origin :refs/heads/v1.0.0
```

### Using GitHub CLI

```bash
# Delete the branch
gh api repos/:owner/:repo/git/refs/heads/v1.0.0 -X DELETE
```

### Using GitHub Web UI

1. Navigate to the repository's **Branches** page
2. Find the patch version branch (e.g., `v1.0.0`)
3. Click the trash icon next to it
4. Confirm deletion

## Related Rules

- [`branch_should_be_tag`](../branch_should_be_tag/README.md) - Converts patch branches to tags when only branch exists
- [`duplicate_floating_version_ref`](../duplicate_floating_version_ref/README.md) - Handles duplicates for floating versions (vX, vX.Y)
- [`patch_release_required`](../../releases/patch_release_required/README.md) - Ensures patch versions have GitHub Releases

## Examples

### Failing Scenario

Repository has:
- Tag `v1.0.0` → abc123
- Branch `v1.0.0` → abc123 (or any SHA)

**Issue:** Patch version exists as both tag and branch

**Remediation:** Delete the `v1.0.0` branch, keep the tag

### Passing Scenario

Repository has:
- Tag `v1.0.0` → abc123
- ✅ No branch `v1.0.0`

**Result:** No issue - patch version is correctly a tag only

## Why Patches Must Be Tags

1. **Immutable Releases:** GitHub Releases require tags as anchors. Branches can be updated, breaking immutability
2. **GitHub Actions Versioning:** Users expect `uses: owner/repo@v1.0.0` to point to an immutable tag
3. **Semantic Versioning:** Patch versions represent specific, unchanging snapshots of code
4. **Release Strategy:** GitHub's recommended immutable release strategy requires patch versions to be tags

## Configuration Independence

Unlike floating versions, patch version ref types are **not influenced by `floating-versions-use`**:

| Version Type | `floating-versions-use: tags` | `floating-versions-use: branches` |
|--------------|------------------------------|----------------------------------|
| Patch (v1.0.0) | **Tag** (always) | **Tag** (always) |
| Minor (v1.0) | Tag | Branch |
| Major (v1) | Tag | Branch |
