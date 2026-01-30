# Rule: patch_release_required

## What This Rule Checks

Validates that every patch version tag (e.g., `v1.0.0`) has a corresponding GitHub Release. This ensures that GitHub Actions users can depend on immutable releases for patch versions.

The rule also detects when floating versions (e.g., `v1`, `v1.0`) exist but their expected patch versions (e.g., `v1.0.0`) don't have releases yet.

## Why This Is An Issue

- **Impact:** Without releases, patch versions are just mutable tags that can be force-pushed, breaking the immutability contract that GitHub Actions expects.
- **Best Practice:** GitHub's [immutable release strategy](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases) requires that patch versions use published releases to prevent tag movement.

## When This Rule Applies

This rule runs when:
- `check-releases` is set to `error` or `warning`

## Configuration

| Input | Required Value | Description |
|-------|----------------|-------------|
| `check-releases` | `error` or `warning` | Enforces that releases exist for patch versions |
| `check-release-immutability` | `error` or `warning` | When enabled, created releases will be automatically published (immutable) |

## Automatic Remediation

When `auto-fix` is enabled, this rule uses `CreateReleaseAction` which:

1. Creates a GitHub Release for the patch version
2. If `check-release-immutability` is enabled, publishes the release immediately (making it immutable)
3. If the tag doesn't exist yet, GitHub's API will create it automatically

**Note:** If the tag was previously used by a deleted immutable release, GitHub will return HTTP 422 and the issue will be marked as **unfixable**. In this case, create a new patch version or add the version to `ignore-versions`.

## Manual Remediation

If auto-fix is not enabled or fails, you can manually fix this issue:

### Using GitHub CLI

```bash
# Create a published release (immutable)
gh release create v1.0.0 --title "v1.0.0" --notes "Release v1.0.0"

# Or create a draft release (can be edited later)
gh release create v1.0.0 --title "v1.0.0" --notes "Release v1.0.0" --draft
```

### Using GitHub Web UI

1. Navigate to **Releases** in your repository
2. Click **Draft a new release**
3. Enter the tag name (e.g., `v1.0.0`)
4. Add a title and description
5. Click **Publish release** (for immutable) or **Save draft**

## Related Rules

- [`release_should_be_published`](../release_should_be_published/README.md) - Ensures draft releases are published
- [`release_should_be_immutable`](../release_should_be_immutable/README.md) - Validates that published releases are truly immutable
- [`patch_tag_missing`](../../version_tracking/patch_tag_missing/README.md) - Handles tag creation when releases are not required

## Coordination with patch_tag_missing Rule

When `check-releases` is enabled (not `none`), the `patch_tag_missing` rule is automatically skipped. This is because:

1. GitHub's release API creates tags implicitly if they don't exist
2. Avoiding duplicate issues for the same problem
3. Ensuring the proper order: Release creation → Tag creation (implicit)

## Examples

### Failing Scenario

```
Repository state:
- Tag: v1 → abc123
- No tag: v1.0.0
- No release: v1.0.0

Configuration:
- check-releases: error
- check-release-immutability: error

Issue: missing_release for v1.0.0
Action: CreateReleaseAction (will create both release and tag)
```

### Passing Scenario

```
Repository state:
- Tag: v1.0.0 → abc123
- Release: v1.0.0 (published, immutable)

Result: No issues
```
