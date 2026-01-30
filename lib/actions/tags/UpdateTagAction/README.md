# UpdateTagAction

Updates an existing Git tag to point to a different commit SHA.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `TagName` | `string` | The tag name to update (e.g., "v1") |
| `Sha` | `string` | The new commit SHA to point the tag at |
| `Force` | `bool` | Whether to force-push the tag update |
| `Priority` | `int` | 20 (same as create operations) |

## Constructor

```powershell
[UpdateTagAction]::new([string]$tagName, [string]$sha, [bool]$force)
```

## Usage

```powershell
# Update floating tag v1 to point to latest patch
$action = [UpdateTagAction]::new("v1", "abc123def456", $true)
$success = $action.Execute($state)
```

## Auto-Fix Behavior

When executed:
1. Updates the existing tag via GitHub REST API
2. Points the tag at the new commit SHA
3. If `Force` is true, will force-push to move the tag

## When to Use Force

- **Floating version tags** (`v1`, `v1.0`): Use `$force = $true` because these tags are expected to move
- **Patch version tags** (`v1.0.0`): Generally should NOT be moved; use with caution

## Manual Remediation

```bash
# Without force (requires tag to not exist remotely)
git push origin <sha>:refs/tags/<tag_name>

# With force (moves existing tag)
git push origin <sha>:refs/tags/<tag_name> --force
```

Example:
```bash
git push origin abc123def456:refs/tags/v1 --force
```

## Limitations

### Workflow File Permissions

If the target commit contains changes to `.github/workflows/*` files, the default `GITHUB_TOKEN` cannot update the tag. GitHub returns an error about missing `workflows` permission.

**Workarounds:**
1. Use a Personal Access Token (PAT) with `workflows` scope
2. Use a GitHub App token with `workflows` permission
3. Update the tag manually using `git push --force`

When this occurs, the action marks the issue as `manual_fix_required` with a helpful message.

### Protected Tags

If the repository has tag protection rules that prevent force-pushing certain tags, the update will fail even with `Force = $true`.

## Related Actions

- [CreateTagAction](../CreateTagAction/README.md) - Create a new tag
- [DeleteTagAction](../DeleteTagAction/README.md) - Delete an existing tag
- [UpdateBranchAction](../../branches/UpdateBranchAction/README.md) - Similar action for branches
