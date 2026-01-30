# Rule: latest_tag_tracks_global_highest

## What This Rule Checks

This rule verifies that the "latest" tag points to the same commit SHA as the global highest patch version across all major versions.

## Why This Is An Issue

The "latest" tag provides users with a convenient way to always get the newest version without tracking specific version numbers.

- **Impact:** Users referencing `latest` expect the newest patch version. If it points to an old commit, they get outdated code
- **Best Practice:** The "latest" alias should always track the absolute highest patch version in the repository
- **User Experience:** Ensures `uses: owner/repo@latest` gets the most recent release

## When This Rule Applies

This rule runs when:
- `floating-versions-use: tags` (default)
- A "latest" tag exists

## Configuration

| Input | Required Value | Description |
|-------|----------------|-------------|
| `floating-versions-use` | `tags` | Latest must be tracked as a tag |
| `ignore-preview-releases` | `true`/`false` | Whether to exclude prereleases when finding highest patch |

## Manual Remediation

If auto-fix is not enabled or fails, you can manually update the latest tag:

### Using GitHub CLI

```bash
# Find the highest patch version
gh api repos/{owner}/{repo}/git/refs/tags | jq -r '.[] | select(.ref | contains("v")) | .ref' | sort -V | tail -1

# Get the SHA of the highest patch
SHA=$(gh api repos/{owner}/{repo}/git/ref/tags/v2.5.3 --jq '.object.sha')

# Force-update the latest tag
gh api repos/{owner}/{repo}/git/refs/tags/latest \
  -X PATCH \
  -f sha="$SHA" \
  -F force=true
```

### Using Git

```bash
# Checkout the highest patch version
git checkout v2.5.3

# Force-update and push the latest tag
git tag -f latest
git push origin latest --force
```

### Using GitHub Web UI

1. Navigate to your repository's **Tags** page
2. Delete the existing "latest" tag
3. Navigate to the highest patch release (e.g., v2.5.3)
4. Create a new tag named "latest" pointing to that release

## Related Rules

- [`latest_tag_missing`](../latest_tag_missing/README.md) - Creates the latest tag if it doesn't exist
- [`latest_branch_tracks_global_highest`](../latest_branch_tracks_global_highest/README.md) - Branch equivalent for `floating-versions-use: branches`

## Examples

### Failing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v2.0.0 → def456 (tag)
- v2.5.3 → ghi789 (tag, highest)
- latest → def456 (tag, pointing to old v2.0.0)

Issue: latest points to def456 but should point to ghi789
Action: UpdateTagAction (force-push latest to ghi789)
```

### Passing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v2.0.0 → def456 (tag)
- v2.5.3 → ghi789 (tag, highest)
- latest → ghi789 (tag)

Result: No issues - latest correctly tracks highest patch ✓
```

### Not Applicable (No Patches)

```
Repository state:
- latest → abc123 (tag)
- No patch versions exist

Result: No issues - no patches to track
```
