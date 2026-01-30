# UpdateBranchAction

Updates an existing Git branch to point to a different commit SHA.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `BranchName` | `string` | The branch name to update (e.g., "v1") |
| `Sha` | `string` | The new commit SHA to point the branch at |
| `Force` | `bool` | Whether to force-push the branch update |
| `Priority` | `int` | 20 (same as create operations) |

## Constructor

```powershell
[UpdateBranchAction]::new([string]$branchName, [string]$sha, [bool]$force)
```

## Usage

```powershell
# Update floating branch v1 to point to latest patch
$action = [UpdateBranchAction]::new("v1", "abc123def456", $true)
$success = $action.Execute($state)
```

## Auto-Fix Behavior

When executed:
1. Updates the existing branch via GitHub REST API
2. Points the branch at the new commit SHA
3. If `Force` is true, will force-push to move the branch

## When to Use Force

- **Floating version branches** (`v1`, `v1.0`): Use `$force = $true` because these branches are expected to be updated
- **Fast-forward updates**: Can use `$force = $false` if the new SHA is a descendant of the current HEAD

## Manual Remediation

```bash
# Without force (fast-forward only)
git push origin <sha>:refs/heads/<branch_name>

# With force (moves branch HEAD)
git push origin <sha>:refs/heads/<branch_name> --force
```

Example:
```bash
git push origin abc123def456:refs/heads/v1 --force
```

## Limitations

### Workflow File Permissions

If the target commit contains changes to `.github/workflows/*` files, the default `GITHUB_TOKEN` cannot update the branch. GitHub returns an error about missing `workflows` permission.

**Workarounds:**
1. Use a Personal Access Token (PAT) with `workflows` scope
2. Use a GitHub App token with `workflows` permission
3. Update the branch manually using `git push --force`

### Branch Protection Rules

If the repository has branch protection rules that:
- Require pull request reviews
- Require status checks
- Restrict who can push

Then force-pushing may be blocked. Consider:
- Temporarily disabling protection
- Using a bypass token
- Pushing through a pull request

## Related Actions

- [CreateBranchAction](../CreateBranchAction/README.md) - Create a new branch
- [DeleteBranchAction](../DeleteBranchAction/README.md) - Delete an existing branch
- [UpdateTagAction](../../tags/UpdateTagAction/README.md) - Similar action for tags
