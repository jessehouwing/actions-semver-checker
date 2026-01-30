# Rule: minor_tag_tracks_highest_patch

## What This Rule Checks

Validates that minor version tags (e.g., `v1.0`, `v1.1`) point to the same commit SHA as the highest patch version within that minor version series (e.g., `v1.0.3`).

## Why This Is An Issue

- **Impact:** Users referencing `v1.0` expect to get the latest patch in that minor series (`v1.0.x`). If the minor tag points to an old commit, they get outdated code with potential bugs or missing features.
- **Best Practice:** GitHub Actions' [versioning strategy](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases) requires floating versions (minor tags) to track the latest patch in their series.

## When This Rule Applies

This rule runs when:
- `floating-versions-use` is set to `tags` (default)
- `check-minor-version` is set to `error` or `warning`
- A minor version tag exists (vX.Y)

## Configuration

| Input | Required Value | Description |
|-------|----------------|-------------|
| `floating-versions-use` | `tags` | Use tags for floating versions (default) |
| `check-minor-version` | `error` or `warning` | Enable minor version validation |
| `ignore-preview-releases` | `true`/`false` | Whether to exclude prereleases when finding highest patch |

## Automatic Remediation

When `auto-fix` is enabled, this rule uses `UpdateTagAction` which:

1. Force-pushes the minor tag to point to the highest patch version's SHA within that minor series
2. Preserves all other tags (only updates the minor tag)

## Manual Remediation

Using Git:

```bash
# Update v1.0 to point to the same commit as v1.0.3 (highest patch in v1.0.x series)
git tag -f v1.0 <sha-of-v1.0.3>
git push origin v1.0 --force
```

Using GitHub CLI:

```bash
# Get the SHA of the highest patch in the minor series
SHA=$(git rev-parse v1.0.3)
# Force-update the minor tag
git push origin $SHA:refs/tags/v1.0 --force
```

## Related Rules

- [`minor_tag_missing`](../minor_tag_missing/README.md) - Creates missing minor tags
- [`major_tag_tracks_highest_patch`](../major_tag_tracks_highest_patch/README.md) - Similar validation for major version tags
- [`minor_branch_tracks_highest_patch`](../../version_tracking/minor_branch_tracks_highest_patch/README.md) - Branch equivalent for `floating-versions-use: branches`

## Examples

### Failing Scenario

```
Repository state:
- Tag: v1.0 → abc123 (old commit)
- Tag: v1.0.0 → abc123
- Tag: v1.0.1 → def456
- Tag: v1.0.2 → ghi789 (latest in v1.0.x series)

Issue: v1.0 points to abc123 but should point to ghi789
Action: UpdateTagAction (force-push v1.0 to ghi789)
```

### Passing Scenario

```
Repository state:
- Tag: v1.0 → ghi789
- Tag: v1.0.0 → abc123
- Tag: v1.0.1 → def456
- Tag: v1.0.2 → ghi789 (latest in v1.0.x series)

Result: No issues - v1.0 correctly tracks latest patch
```

### Not Applicable (No Patches in Series)

```
Repository state:
- Tag: v1.0 → abc123

Result: No issues - no patches exist in this minor series to track
```

### Severity: Warning

When `check-minor-version` is set to `warning`, this rule reports issues with warning severity instead of error:

```yaml
inputs:
  check-minor-version: warning
```

This allows minor version mismatches to be flagged without failing the workflow.
