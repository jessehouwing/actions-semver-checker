# Rule: latest_branch_missing

## What This Rule Checks

This rule suggests creating a "latest" branch when patch versions exist but no "latest" branch is present.

## Why This Is An Issue

While not strictly required, a "latest" branch provides significant convenience for users when using branches for floating versions.

- **Impact:** Users cannot use the simple `uses: owner/repo@latest` syntax
- **Best Practice:** When using branches for floating versions, provide a "latest" alias for convenience
- **User Experience:** Allows workflows to stay on the newest version automatically

**Note:** This rule generates **warnings** (not errors) because "latest" branches are optional.

## When This Rule Applies

This rule runs when:
- `floating-versions-use: branches`
- At least one patch version exists
- No "latest" branch exists

## Configuration

| Input | Required Value | Description |
|-------|----------------|-------------|
| `floating-versions-use` | `branches` | Latest must be tracked as a branch |

## Manual Remediation

If you want to create the latest branch manually:

### Using GitHub CLI

```bash
# Find the highest patch version
HIGHEST_TAG=$(gh api repos/{owner}/{repo}/git/refs/tags | jq -r '.[] | select(.ref | contains("v")) | .ref' | sort -V | tail -1)

# Get the SHA
SHA=$(gh api repos/{owner}/{repo}/git/ref/${HIGHEST_TAG#refs/} --jq '.object.sha')

# Create the latest branch
gh api repos/{owner}/{repo}/git/refs \
  -f ref="refs/heads/latest" \
  -f sha="$SHA"
```

### Using Git

```bash
# Checkout the highest patch version
git checkout v2.5.3

# Create and push the latest branch
git checkout -b latest
git push origin latest
```

### Using GitHub Web UI

1. Navigate to your repository's **Branches** page
2. Click **"New branch"**
3. Name it `latest`
4. Select the highest patch version as the source
5. Create the branch

## Related Rules

- [`latest_branch_tracks_global_highest`](../latest_branch_tracks_global_highest/README.md) - Validates that existing latest branches point to the correct SHA
- [`latest_tag_missing`](../latest_tag_missing/README.md) - Tag equivalent for `floating-versions-use: tags`

## Examples

### Warning Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v2.0.0 → def456 (tag)
- v2.5.3 → ghi789 (tag)
- No "latest" branch

Warning: Latest branch is missing but patch versions exist. Consider creating 'latest' branch pointing to v2.5.3
Action: CreateBranchAction (optional - warnings don't fail workflows)
```

### Passing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v2.5.3 → ghi789 (tag)
- latest → ghi789 (branch)

Result: No issues - latest branch exists ✓
```

### Not Applicable (No Patches)

```
Repository state:
- v1 → abc123 (branch only, no patches)

Result: No issues - no patches exist to create latest from
```
