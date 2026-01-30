# Rule: release_should_be_immutable

## What This Rule Checks

Validates that published (non-draft) releases for patch versions are truly immutable according to GitHub's internal immutability flag. This requires the "Release immutability" feature to be enabled in the repository settings.

## Why This Is An Issue

- **Impact:** Even published releases can remain mutable if the repository doesn't have the "Release immutability" setting enabled. This violates GitHub's immutable release strategy and allows releases to be deleted or modified.
- **Best Practice:** GitHub's [immutable release strategy](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases) requires that releases have the `immutable: true` flag, which can only be set by enabling "Release immutability" in repository settings.

## When This Rule Applies

This rule runs when:
- `check-release-immutability` is set to `error` or `warning`
- A published (non-draft) release exists for a patch version (vX.Y.Z)
- The release does not have the `immutable: true` flag (checked via GraphQL API)

**Note:** This rule only checks patch versions. Floating versions (vX, vX.Y) should not have releases at all.

## Configuration

| Input | Required Value | Description |
|-------|----------------|-------------|
| `check-release-immutability` | `error` or `warning` | Enforces that releases are truly immutable |

## Automatic Remediation

When `auto-fix` is enabled, this rule uses `RepublishReleaseAction` which:

1. Converts the release to draft
2. Republishes it
3. Verifies the `immutable: true` flag is set

**Important:** If the repository does not have "Release immutability" enabled in settings, the republish will succeed but the release will still be mutable. The action will detect this and mark the issue as "manual_fix_required" with instructions to enable the setting.

**Note:** If the tag was previously used by a deleted immutable release, GitHub will return HTTP 422 and the issue will be marked as **unfixable**.

## Manual Remediation

### Step 1: Enable Release Immutability in Repository Settings

1. Navigate to **Settings** > **General** in your repository
2. Scroll to the **Releases** section
3. Enable **Release immutability**
4. Save changes

### Step 2: Republish the Release

Using GitHub CLI:

```bash
# Convert to draft then republish
gh release edit v1.0.0 --draft=true
gh release edit v1.0.0 --draft=false
```

Using GitHub Web UI:

1. Navigate to **Releases** in your repository
2. Find the release and click **Edit**
3. Check **Save as draft** and save
4. Edit again, uncheck **Save as draft**, and publish

## Related Rules

- [`patch_release_required`](../patch_release_required/README.md) - Ensures releases exist for patch versions
- [`release_should_be_published`](../release_should_be_published/README.md) - Ensures draft releases are published
- [`floating_version_no_release`](../floating_version_no_release/README.md) - Ensures floating versions don't have releases

## How Immutability Is Checked

This rule uses GitHub's GraphQL API to check the `immutable` field:

```graphql
query($owner: String!, $name: String!, $tag: String!) {
  repository(owner: $owner, name: $name) {
    release(tagName: $tag) {
      immutable
    }
  }
}
```

The `immutable` field is only `true` when:
1. The release is published (not draft)
2. The repository has "Release immutability" enabled in settings
3. The release was published after the setting was enabled

## Rule Priority and Coordination

- **Priority 12** - Runs after `release_should_be_published` (Priority 11)
- Only checks published releases (drafts are handled by the previous rule)
- Always creates **warning** issues (not errors) since this requires repository settings

## Examples

### Failing Scenario

```
Repository state:
- Tag: v1.0.0 → abc123
- Release: v1.0.0 (published, immutable=false)

Repository settings:
- Release immutability: Disabled

Issue: non_immutable_release for v1.0.0
Action: RepublishReleaseAction (will detect setting is disabled and require manual fix)
```

### Passing Scenario

```
Repository state:
- Tag: v1.0.0 → abc123
- Release: v1.0.0 (published, immutable=true)

Repository settings:
- Release immutability: Enabled

Result: No issues
```

### Not Applicable (Draft Release)

```
Repository state:
- Tag: v1.0.0 → abc123
- Release: v1.0.0 (draft)

Result: This rule does NOT apply to drafts
Note: The release_should_be_published rule will flag this
```
