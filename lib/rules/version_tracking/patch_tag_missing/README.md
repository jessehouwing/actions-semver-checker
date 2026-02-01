# Rule: patch_tag_missing

## What This Rule Checks

This rule verifies that at least one patch version (e.g., `v1.0.0`) exists for every floating version tag or branch (e.g., `v1`, `v1.0`, `latest`).

## Why This Is An Issue

Floating versions should always point to a concrete patch version. If a floating version exists but no patch exists, the floating version has no valid target.

- **Impact:** The floating version tag/branch points to a commit that isn't properly versioned with a semantic version patch tag
- **Best Practice:** Every floating version should be derived from a published patch version
- **Action Workflow:** Users expect floating versions to resolve to stable, released patches

## When This Rule Applies

This rule runs when:
- `check-releases: none` (when releases are required, the `patch_release_required` rule handles both tag and release creation)
- At least one floating version exists (`v1`, `v1.0`, or `latest`)
- No corresponding patch version exists

**Important:** When `check-releases` is `error` or `warning`, this rule is **skipped** because the `patch_release_required` rule will create both the release AND the tag (GitHub creates tags implicitly when creating releases).

## Configuration

### Settings That Enable This Rule

| Input | Required Value | Effect |
|-------|----------------|--------|
| `check-releases` | `none` | Rule is enabled (patches tracked without releases) |

**Note:** When `check-releases` is `error` or `warning`, this rule is **disabled** because `patch_release_required` handles both release and tag creation.

### Settings That Affect Severity

Patch version tracking is **always** reported as **error** (not configurable). Patch versions are fundamental to semantic versioning.

| Severity | Always |
|----------|--------|
| **error** | ✓ |

### Other Relevant Settings

| Input | Effect |
|-------|--------|
| `floating-versions-use` | Determines whether to look for floating versions in tags or branches |

## Manual Remediation

If auto-fix is not enabled or fails, you can manually create the missing patch tag:

### Using GitHub CLI

```bash
# Get the SHA of the floating version
SHA=$(gh api repos/{owner}/{repo}/git/ref/tags/v1 --jq '.object.sha')

# Create the patch tag (e.g., v1.0.0)
gh api repos/{owner}/{repo}/git/refs \
  -f ref="refs/tags/v1.0.0" \
  -f sha="$SHA"
```

### Using Git

```bash
# Checkout the floating version
git checkout v1

# Create and push the patch tag
git tag v1.0.0
git push origin v1.0.0
```

### Using GitHub Web UI

1. Navigate to your repository's **Releases** page
2. Click **"Draft a new release"**
3. Set the tag to the patch version (e.g., `v1.0.0`)
4. Target the same commit as the floating version
5. Add release notes
6. Publish the release

## Related Rules

- [`patch_release_required`](../../releases/patch_release_required/README.md) - Creates releases (and tags) when `check-releases` is enabled
- [`major_tag_missing`](../major_tag_missing/README.md) - Creates major floating versions
- [`minor_tag_missing`](../minor_tag_missing/README.md) - Creates minor floating versions

## Rule Coordination

This rule coordinates with `patch_release_required`:

| `check-releases` | `patch_tag_missing` | `patch_release_required` | Result |
|------------------|---------------------|--------------------------|--------|
| `none` | ✅ Creates tag | Skipped | Tag only |
| `error`/`warning` | Skipped | ✅ Creates release + tag | Release (tag created implicitly) |

When releases are required, GitHub's release API creates the tag automatically, so we let the release rule handle both operations.

## Examples

### Failing Scenario (check-releases: none)

```
Repository state:
- v1 → abc123 (tag)
- No v1.0.0 tag exists

Issue: Floating version v1 exists but no corresponding patch version found. Expected: v1.0.0
Remediation: Create v1.0.0 tag pointing to abc123 (same as v1)
```

### Passing Scenario

```
Repository state:
- v1 → abc123 (tag)
- v1.0.0 → abc123 (tag)

Floating version has a corresponding patch ✓
```

### Skipped Scenario (check-releases: error)

```
Repository state:
- v1 → abc123 (tag)
- No v1.0.0 tag exists

This rule does NOT apply because check-releases is enabled.
The patch_release_required rule will create both the release and tag.
```
