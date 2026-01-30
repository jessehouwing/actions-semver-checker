# Rule: latest_tag_missing

## What This Rule Checks

This rule suggests creating a "latest" tag when patch versions exist but no "latest" tag is present.

## Why This Is An Issue

While not strictly required, a "latest" tag provides significant convenience for users.

- **Impact:** Users cannot use the simple `uses: owner/repo@latest` syntax
- **Best Practice:** Many GitHub Actions provide a "latest" alias for convenience
- **User Experience:** Allows workflows to stay on the newest version automatically

**Note:** This rule generates **warnings** (not errors) because "latest" tags are optional.

## When This Rule Applies

This rule runs when:
- `floating-versions-use: tags` (default)
- At least one patch version exists
- No "latest" tag exists

## Configuration

| Input | Required Value | Description |
|-------|----------------|-------------|
| `floating-versions-use` | `tags` | Latest must be tracked as a tag |

## Manual Remediation

If you want to create the latest tag manually:

### Using GitHub CLI

```bash
# Find the highest patch version
HIGHEST=$(gh api repos/{owner}/{repo}/git/refs/tags | jq -r '.[] | select(.ref | contains("v")) | .ref' | sort -V | tail -1)

# Get the SHA
SHA=$(gh api repos/{owner}/{repo}/git/ref/${HIGHEST#refs/} --jq '.object.sha')

# Create the latest tag
gh api repos/{owner}/{repo}/git/refs \
  -f ref="refs/tags/latest" \
  -f sha="$SHA"
```

### Using Git

```bash
# Checkout the highest patch version
git checkout v2.5.3

# Create and push the latest tag
git tag latest
git push origin latest
```

### Using GitHub Web UI

1. Navigate to your repository's **Releases** page
2. Find the highest patch release
3. Click **"Create a new release"**
4. Set the tag to `latest`
5. Target the same commit as the highest patch
6. Publish the release

## Related Rules

- [`latest_tag_tracks_global_highest`](../latest_tag_tracks_global_highest/README.md) - Validates that existing latest tags point to the correct SHA
- [`latest_branch_missing`](../latest_branch_missing/README.md) - Branch equivalent for `floating-versions-use: branches`

## Examples

### Warning Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v2.0.0 → def456 (tag)
- v2.5.3 → ghi789 (tag)
- No "latest" tag

Warning: Latest tag is missing but patch versions exist. Consider creating 'latest' tag pointing to v2.5.3
Action: CreateTagAction (optional - warnings don't fail workflows)
```

### Passing Scenario

```
Repository state:
- v1.0.0 → abc123 (tag)
- v2.5.3 → ghi789 (tag)
- latest → ghi789 (tag)

Result: No issues - latest tag exists ✓
```

### Not Applicable (No Patches)

```
Repository state:
- v1 → abc123 (tag only, no patches)

Result: No issues - no patches exist to create latest from
```
