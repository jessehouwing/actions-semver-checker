# CreateBranchAction

Creates a new Git branch at a specified commit SHA.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `BranchName` | `string` | The branch name to create (e.g., "v1") |
| `Sha` | `string` | The commit SHA to point the branch at |
| `Priority` | `int` | 20 (runs after deletes, before releases) |

## Constructor

```powershell
[CreateBranchAction]::new([string]$branchName, [string]$sha)
```

## Usage

```powershell
$action = [CreateBranchAction]::new("v1", "abc123def456")
$success = $action.Execute($state)
```

## Auto-Fix Behavior

When executed:
1. Creates a new branch via GitHub REST API
2. Points the branch at the specified commit SHA
3. Does NOT force-push (fails if branch already exists)

## When to Use Branches vs Tags

The `floating-versions-use` configuration determines whether floating versions use branches or tags:

| Configuration | Floating Versions | Example |
|---------------|-------------------|---------|
| `tags` (default) | Tags | `v1` → tag |
| `branches` | Branches | `v1` → branch |

Use branches when:
- You want to allow direct commits to floating versions
- Your CI/CD pipeline expects branches for deployment
- You prefer branch protection rules over tag protection

## Manual Remediation

```bash
git push origin <sha>:refs/heads/<branch_name>
```

Example:
```bash
git push origin abc123def456:refs/heads/v1
```

## Limitations

### Workflow File Permissions

If the target commit contains changes to `.github/workflows/*` files, the default `GITHUB_TOKEN` cannot create the branch. GitHub returns an error about missing `workflows` permission.

**Workarounds:**
1. Use a Personal Access Token (PAT) with `workflows` scope
2. Use a GitHub App token with `workflows` permission
3. Create the branch manually using `git push`

When this occurs, the action marks the issue as `manual_fix_required` with a helpful message.

### Branch Already Exists

If a branch with the same name already exists, this action will fail. Use `UpdateBranchAction` instead if you need to move an existing branch.

## Related Actions

- [UpdateBranchAction](../UpdateBranchAction/README.md) - Update an existing branch to a new SHA
- [DeleteBranchAction](../DeleteBranchAction/README.md) - Delete an existing branch
- [CreateTagAction](../../tags/CreateTagAction/README.md) - Similar action for tags
- [ConvertTagToBranchAction](../../conversions/ConvertTagToBranchAction/README.md) - Convert a tag to a branch
