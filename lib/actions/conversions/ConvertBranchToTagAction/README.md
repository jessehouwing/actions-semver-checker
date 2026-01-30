# ConvertBranchToTagAction

Converts a Git branch to a tag, typically used when changing `floating-versions-use` from `branches` to `tags`.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `Name` | `string` | The version name (e.g., "v1.0.0") |
| `Sha` | `string` | The commit SHA |
| `Priority` | `int` | 25 (runs after deletes, before create/update) |

## Constructor

```powershell
[ConvertBranchToTagAction]::new([string]$name, [string]$sha)
```

## Usage

```powershell
$action = [ConvertBranchToTagAction]::new("v1.0.0", "abc123def456")
$success = $action.Execute($state)
```

## Auto-Fix Behavior

The action follows these steps:

1. **Check if tag exists** - If a tag with the same name already exists:
   - Delete only the branch (tag takes precedence)
2. **Full conversion** - If no tag exists:
   - Create the tag at the same SHA
   - Delete the branch

## Manual Remediation

When the tag doesn't exist:
```bash
git push origin <sha>:refs/tags/<name>
git push origin :refs/heads/<name>
```

When the tag already exists (just remove the duplicate branch):
```bash
git push origin :refs/heads/<name>
```

## Limitations

### Workflow File Permissions

If the target commit contains changes to `.github/workflows/*` files, the default `GITHUB_TOKEN` cannot create the tag.

**Workarounds:**
- Use a PAT with `workflows` scope
- Convert manually using `git push`

When this occurs, the action marks the issue as `manual_fix_required`.

### Branch Protection

If the branch has protection rules preventing deletion, the action will fail even after successfully creating the tag. You'll need to:
- Temporarily disable branch protection
- Use an admin token with bypass capabilities
- Delete the branch manually

### Partial Failure

If the tag is created but the branch deletion fails, you'll have both a tag and a branch with the same name. This is valid but may cause confusion. Manually delete the branch to complete the conversion.

## Use Cases

1. **Changing `floating-versions-use`** - When switching from `branches` to `tags` for floating versions
2. **Duplicate refs** - When both a tag and branch exist for the same version
3. **Patch version cleanup** - Patch versions (e.g., `v1.0.0`) should typically be tags, not branches

## Related Actions

- [ConvertTagToBranchAction](../ConvertTagToBranchAction/README.md) - Opposite conversion
- [CreateTagAction](../../tags/CreateTagAction/README.md) - Used internally
- [DeleteBranchAction](../../branches/DeleteBranchAction/README.md) - Used internally

## Related Rules

- [branch_should_be_tag](../../../rules/ref_type/branch_should_be_tag/README.md) - Rule that creates this action
- [duplicate_patch_version_ref](../../../rules/ref_type/duplicate_patch_version_ref/README.md) - May also use this action
