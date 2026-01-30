# DeleteBranchAction

Deletes an existing Git branch from the repository.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `BranchName` | `string` | The branch name to delete (e.g., "v1") |
| `Priority` | `int` | 10 (runs first to clean up before creates/updates) |

## Constructor

```powershell
[DeleteBranchAction]::new([string]$branchName)
```

## Usage

```powershell
$action = [DeleteBranchAction]::new("v1")
$success = $action.Execute($state)
```

## Auto-Fix Behavior

When executed:
1. Deletes the branch via GitHub REST API
2. Removes the remote reference

## Priority

Delete actions have the highest priority (10) because:
1. Other operations may depend on the branch being removed first
2. Cleaning up before creating new refs prevents conflicts
3. Conversion operations (branch → tag) need the branch deleted before creating the tag

## Manual Remediation

```bash
# Delete local branch (if it exists)
git branch -d <branch_name>

# Delete remote branch
git push origin :refs/heads/<branch_name>
```

Example:
```bash
git branch -d v1
git push origin :refs/heads/v1
```

## Limitations

### Branch Protection

If the repository has branch protection rules that prevent deleting certain branches, this action will fail.

### Default Branch

You cannot delete the repository's default branch (usually `main` or `master`).

### Open Pull Requests

Deleting a branch that is the head of an open pull request will close the PR. Be cautious when deleting branches that may have associated PRs.

## Warning

⚠️ **Be careful when deleting floating version branches**. If users have pinned their workflows to this branch, deleting it will break their workflows.

This action is typically used for:
- Removing duplicate branches
- Cleaning up before converting a branch to a tag
- Switching from `floating-versions-use: branches` to `floating-versions-use: tags`

## Related Actions

- [CreateBranchAction](../CreateBranchAction/README.md) - Create a new branch
- [UpdateBranchAction](../UpdateBranchAction/README.md) - Update an existing branch
- [ConvertBranchToTagAction](../../conversions/ConvertBranchToTagAction/README.md) - Convert branch to tag (uses delete internally)
