# CreateTagAction

Creates a new Git tag at a specified commit SHA.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `TagName` | `string` | The tag name to create (e.g., "v1.0.0") |
| `Sha` | `string` | The commit SHA to point the tag at |
| `Priority` | `int` | 20 (runs after deletes, before releases) |

## Constructor

```powershell
[CreateTagAction]::new([string]$tagName, [string]$sha)
```

## Usage

```powershell
$action = [CreateTagAction]::new("v1.0.0", "abc123def456")
$success = $action.Execute($state)
```

## Auto-Fix Behavior

When executed:
1. Creates a new lightweight tag via GitHub REST API
2. Points the tag at the specified commit SHA
3. Does NOT force-push (fails if tag already exists)

## Manual Remediation

```bash
git push origin <sha>:refs/tags/<tag_name>
```

Example:
```bash
git push origin abc123def456:refs/tags/v1.0.0
```

## Limitations

### Workflow File Permissions

If the target commit contains changes to `.github/workflows/*` files, the default `GITHUB_TOKEN` cannot create the tag. GitHub returns an error about missing `workflows` permission.

**Workarounds:**
1. Use a Personal Access Token (PAT) with `workflows` scope
2. Use a GitHub App token with `workflows` permission
3. Create the tag manually using `git push`

When this occurs, the action marks the issue as `manual_fix_required` with a helpful message.

### Tag Already Exists

If a tag with the same name already exists, this action will fail. Use `UpdateTagAction` instead if you need to move an existing tag.

## Related Actions

- [UpdateTagAction](../UpdateTagAction/README.md) - Update an existing tag to a new SHA
- [DeleteTagAction](../DeleteTagAction/README.md) - Delete an existing tag
- [CreateBranchAction](../../branches/CreateBranchAction/README.md) - Similar action for branches
