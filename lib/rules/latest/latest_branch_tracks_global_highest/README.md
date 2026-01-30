# Rule: latest_branch_tracks_global_highest

## What This Rule Checks

This rule verifies that the "latest" branch points to the same commit SHA as the global highest patch version across all major versions.

## Why This Is An Issue

When using branches for floating versions, the "latest" branch provides users with a convenient way to always get the newest version.

- **Impact:** Users referencing `latest` expect the newest patch version. If it points to an old commit, they get outdated code
- **Best Practice:** The "latest" alias should always track the absolute highest patch version in the repository
- **User Experience:** Ensures `uses: owner/repo@latest` gets the most recent release

## When This Rule Applies

This rule runs when:
- `floating-versions-use: branches`
- A "latest" branch exists

## Configuration

| Input | Required Value | Description |
|-------|----------------|-------------|
| `floating-versions-use` | `branches` | Latest must be tracked as a branch |
| `ignore-preview-releases` | `true`/`false` | Whether to exclude prereleases when finding highest patch |

## Manual Remediation

If auto-fix is not enabled or fails, you can manually update the latest branch:

### Using GitHub CLI

```bash
# Find the highest patch version
HIGHEST_TAG=$(gh api repos/{owner}/{repo}/git/refs/tags | jq -r '.[] | select(.ref | contains("v")) | .ref' | sort -V | tail -1)

# Get the SHA
SHA=$(gh api repos/{owner}/{repo}/git/ref/${HIGHEST_TAG#refs/} --jq '.object.sha')

# Force-update the latest branch
gh api repos/{owner}/{repo}/git/refs/heads/latest \
  -X PATCH \
  -f sha="$SHA" \
  -F force=true
```

### Using Git

```bash
# Checkout the highest patch version
git checkout v2.5.3

# Force-update and push the latest branch
git branch -f latest
git push origin latest --force
```

### Using GitHub Web UI

1. Navigate to your repository's **Branches** page
2. Find the "latest" branch
3. Use the "..." menu to delete it
4. Create a new branch named "latest" from the highest patch tag

## Related Rules

- [`latest_branch_missing`](../latest_branch_missing/README.md) - Creates the latest branch if it doesn't exist
- [`latest_tag_tracks_global_highest`](../latest_tag_tracks_global_highest/README.md) - Tag equivalent for `floating-versions-use: tags`

## Examples

### Failing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v2.0.0 → def456 (tag)
- v2.5.3 → ghi789 (tag, highest)
- latest → def456 (branch, pointing to old v2.0.0)

Issue: latest points to def456 but should point to ghi789
Action: UpdateBranchAction (force-push latest to ghi789)
```

### Passing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v2.0.0 → def456 (tag)
- v2.5.3 → ghi789 (tag, highest)
- latest → ghi789 (branch)

Result: No issues - latest correctly tracks highest patch ✓
```

### Not Applicable (No Patches)

```
Repository state:
- latest → abc123 (branch)
- No patch versions exist

Result: No issues - no patches to track
```
