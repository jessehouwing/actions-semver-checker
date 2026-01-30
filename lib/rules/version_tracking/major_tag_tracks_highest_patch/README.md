# Rule: major_tag_tracks_highest_patch

## What This Rule Checks

Validates that major version tags (e.g., `v1`, `v2`) point to the same commit SHA as the highest patch version within that major version series (e.g., `v1.2.3`).

## Why This Is An Issue

- **Impact:** Users referencing `v1` expect to get the latest patch (`v1.x.x`). If the major tag points to an old commit, they get outdated code.
- **Best Practice:** GitHub Actions' [versioning strategy](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases) requires floating versions (major tags) to track the latest patch.

## When This Rule Applies

This rule runs when:
- `floating-versions-use` is set to `tags` (default)
- A major version tag exists (vX)

## Configuration

| Input | Required Value | Description |
|-------|----------------|-------------|
| `floating-versions-use` | `tags` | Use tags for floating versions (default) |
| `ignore-preview-releases` | `true`/`false` | Whether to exclude prereleases when finding highest patch |

## Automatic Remediation

When `auto-fix` is enabled, this rule uses `UpdateTagAction` which:

1. Force-pushes the major tag to point to the highest patch version's SHA
2. Preserves all other tags (only updates the major tag)

## Manual Remediation

Using Git:

```bash
# Update v1 to point to the same commit as v1.2.3
git tag -f v1 <sha-of-v1.2.3>
git push origin v1 --force
```

Using GitHub CLI:

```bash
# Get the SHA of the highest patch
SHA=$(git rev-parse v1.2.3)
# Force-update the major tag
git push origin $SHA:refs/tags/v1 --force
```

## Related Rules

- [`major_tag_missing`](../major_tag_missing/README.md) - Creates missing major tags
- [`major_branch_tracks_highest_patch`](../../version_tracking/major_branch_tracks_highest_patch/README.md) - Branch equivalent for `floating-versions-use: branches`

## Examples

### Failing Scenario

```
Repository state:
- Tag: v1 → abc123 (old commit)
- Tag: v1.0.0 → abc123
- Tag: v1.1.0 → def456 (latest)

Issue: v1 points to abc123 but should point to def456
Action: UpdateTagAction (force-push v1 to def456)
```

### Passing Scenario

```
Repository state:
- Tag: v1 → def456
- Tag: v1.0.0 → abc123
- Tag: v1.1.0 → def456 (latest)

Result: No issues - v1 correctly tracks latest patch
```

### Not Applicable (No Patches)

```
Repository state:
- Tag: v1 → abc123

Result: No issues - no patches exist to track
```
