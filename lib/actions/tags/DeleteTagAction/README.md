# DeleteTagAction

Deletes an existing Git tag from the repository.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `TagName` | `string` | The tag name to delete (e.g., "v1.0.0") |
| `Priority` | `int` | 10 (runs first to clean up before creates/updates) |

## Constructor

```powershell
[DeleteTagAction]::new([string]$tagName)
```

## Usage

```powershell
$action = [DeleteTagAction]::new("v1.0.0")
$success = $action.Execute($state)
```

## Auto-Fix Behavior

When executed:
1. Deletes the tag via GitHub REST API
2. Removes the remote reference

## Priority

Delete actions have the highest priority (10) because:
1. Other operations may depend on the tag being removed first
2. Cleaning up before creating new refs prevents conflicts
3. Conversion operations (tag → branch) need the tag deleted before creating the branch

## Manual Remediation

```bash
# Delete local tag (if it exists)
git tag -d <tag_name>

# Delete remote tag
git push origin :refs/tags/<tag_name>
```

Example:
```bash
git tag -d v1.0.0
git push origin :refs/tags/v1.0.0
```

## Limitations

### Protected Tags

If the repository has tag protection rules that prevent deleting certain tags, this action will fail.

### Immutable Releases

If the tag has an associated **immutable release**, the tag cannot be deleted through normal means. GitHub protects immutable releases from tag modification.

**Note:** Even if you delete an immutable release through the UI, the tag remains "locked" and cannot be reused for a new immutable release. GitHub returns HTTP 422 if you try to publish a new release on the same tag.

## Warning

⚠️ **Be careful when deleting patch version tags** (e.g., `v1.0.0`). If users have pinned their workflows to this exact version, deleting the tag will break their workflows.

This action is typically used for:
- Removing duplicate tags
- Cleaning up before converting a tag to a branch
- Removing incorrectly created tags

## Related Actions

- [CreateTagAction](../CreateTagAction/README.md) - Create a new tag
- [UpdateTagAction](../UpdateTagAction/README.md) - Update an existing tag
- [ConvertTagToBranchAction](../../conversions/ConvertTagToBranchAction/README.md) - Convert tag to branch (uses delete internally)
