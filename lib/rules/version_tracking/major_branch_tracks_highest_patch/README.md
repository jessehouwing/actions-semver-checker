# Rule: major_branch_tracks_highest_patch

## What This Rule Checks

Validates that major version branches (e.g., `v1`, `v2`) point to the same commit SHA as the highest patch version within that major version series (e.g., `v1.2.3`).

## Why This Is An Issue

- **Impact:** Users referencing `v1` expect to get the latest patch (`v1.x.x`). If the major branch points to an old commit, they get outdated code.
- **Best Practice:** When using branches for floating versions, they should track the latest stable patch to ensure users get the most up-to-date code.
- **Branch Advantage:** Unlike tags, branches can be automatically updated via CI/CD workflows after each release.

## When This Rule Applies

This rule runs when:
- `floating-versions-use` is set to `branches`
- A major version branch exists (vX)

## Configuration

| Input | Required Value | Description |
|-------|----------------|-------------|
| `floating-versions-use` | `branches` | Use branches for floating versions |
| `ignore-preview-releases` | `true`/`false` | Whether to exclude prereleases when finding highest patch |

## Automatic Remediation

When `auto-fix` is enabled, this rule uses `UpdateBranchAction` which:

1. Updates the major branch to point to the highest patch version's SHA
2. Force-pushes the branch reference
3. Preserves all other branches (only updates the major branch)

## Manual Remediation

Using Git:

```bash
# Update v1 to point to the same commit as v1.2.3
git checkout v1.2.3
git branch -f v1
git push origin v1 --force
```

Using GitHub CLI:

```bash
# Get the SHA of the highest patch
SHA=$(git rev-parse v1.2.3)
# Force-update the major branch
gh api repos/{owner}/{repo}/git/refs/heads/v1 -X PATCH -f sha="$SHA" -F force=true
```

## Related Rules

- [`major_branch_missing`](../major_branch_missing/README.md) - Creates missing major branches
- [`major_tag_tracks_highest_patch`](../major_tag_tracks_highest_patch/README.md) - Tag equivalent for `floating-versions-use: tags`
- [`minor_branch_tracks_highest_patch`](../minor_branch_tracks_highest_patch/README.md) - Similar validation for minor version branches

## Examples

### Failing Scenario

```
Repository state:
- Branch: v1 → abc123 (old commit)
- Tag: v1.0.0 → abc123
- Tag: v1.1.0 → def456 (latest)

Issue: v1 points to abc123 but should point to def456
Action: UpdateBranchAction (force-push v1 to def456)
```

### Passing Scenario

```
Repository state:
- Branch: v1 → def456
- Tag: v1.0.0 → abc123
- Tag: v1.1.0 → def456 (latest)

Result: No issues - v1 correctly tracks latest patch
```

### Not Applicable (Using Tags)

```
Configuration:
  floating-versions-use: tags

Result: This rule does not apply
```
