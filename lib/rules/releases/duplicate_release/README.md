# Rule: duplicate_release

## What This Rule Checks

Validates that there are no duplicate draft releases pointing to the same patch version tag (e.g., `v1.0.0`). When duplicates are found, draft releases are deleted to leave only the primary release (preferring published/immutable releases over drafts).

## Why This Is An Issue

- **Impact:** Multiple releases for the same tag can cause confusion and may indicate failed release attempts or race conditions in CI/CD pipelines.
- **Best Practice:** Each patch version should have exactly one release. Draft duplicates are typically artifacts of retried release workflows and should be cleaned up.

## When This Rule Applies

This rule runs when:
- `check-releases` is set to `error` or `warning`
- AND multiple releases exist for the same patch version tag (vX.Y.Z)
- AND at least one of the duplicates is a draft release

**Note:** This rule only checks patch versions (vX.Y.Z). Floating version releases (vX, vX.Y) are handled by the `floating_version_no_release` rule.

## Configuration

| Input | Required Value | Description |
|-------|----------------|-------------|
| `check-releases` | `error` or `warning` | Enables release validation including duplicate detection |

## Required Permissions

**Important:** Draft releases are NOT visible via the GitHub API with `contents: read` permission. This rule can only detect duplicate draft releases if the workflow has `contents: write` permission.

```yaml
permissions:
  contents: write  # Required to see draft releases
```

## Which Release Is Kept?

When multiple releases exist for the same tag, the rule keeps one and marks others for deletion based on this priority:

1. **Published releases** are preferred over draft releases
2. **Immutable releases** are preferred over mutable releases
3. **Older releases** (lower ID) are preferred over newer ones

Only draft releases can be deleted. If multiple published/immutable releases exist for the same tag, no action is taken (this should not happen in normal circumstances).

## Automatic Remediation

When `auto-fix` is enabled, this rule uses `DeleteReleaseAction` which:

1. Deletes the duplicate draft release by its specific release ID
2. Preserves the primary release (published/immutable/oldest)

**Note:** Only draft releases can be deleted automatically. Published/immutable releases require manual intervention.

## Manual Remediation

If auto-fix is not enabled or fails, you can manually fix this issue:

### Using GitHub CLI

```bash
# List releases to identify duplicates
gh release list

# Delete a specific draft release by tag
gh release delete v1.0.0 --yes
```

**Warning:** The `gh release delete` command deletes by tag name, which may delete the wrong release if multiple exist. Use the GitHub web UI for precise control.

### Using GitHub Web UI

1. Navigate to **Releases** in your repository
2. Find the duplicate draft release (marked with "Draft")
3. Click the **Delete** button on the draft release
4. Confirm deletion

## Related Rules

- [`release_should_be_published`](../release_should_be_published/README.md) - Ensures draft releases are published (runs after duplicates are removed)
- [`patch_release_required`](../patch_release_required/README.md) - Ensures releases exist for patch versions
- [`floating_version_no_release`](../floating_version_no_release/README.md) - Ensures floating versions don't have releases

## Rule Coordination

This rule runs before other release rules:

1. `duplicate_release` (Priority 9) - Removes duplicate draft releases first
2. `patch_release_required` (Priority 10) - Creates releases for patch versions
3. `release_should_be_published` (Priority 11) - Publishes draft releases

By running first, this rule ensures that:
- `release_should_be_published` doesn't try to publish releases that will be deleted
- Only one release exists per tag before publish operations run

## Examples

### Failing Scenario - Draft duplicate of published release

```
Repository state:
- Tag: v1.0.0 → abc123
- Release: v1.0.0 (id: 100, published, immutable)
- Release: v1.0.0 (id: 200, draft)

Configuration:
- check-releases: error

Issue: duplicate_release for v1.0.0 (release ID: 200)
Action: DeleteReleaseAction (will delete release id 200)
```

### Failing Scenario - Multiple draft releases

```
Repository state:
- Tag: v1.0.0 → abc123
- Release: v1.0.0 (id: 100, draft)
- Release: v1.0.0 (id: 200, draft)

Configuration:
- check-releases: error

Issue: duplicate_release for v1.0.0 (release ID: 200)
Action: DeleteReleaseAction (will delete release id 200, keep id 100)
```

### Passing Scenario

```
Repository state:
- Tag: v1.0.0 → abc123
- Release: v1.0.0 (id: 100, published, immutable)

Result: No issues (only one release exists)
```
