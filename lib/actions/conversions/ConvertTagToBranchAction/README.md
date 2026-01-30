# ConvertTagToBranchAction

Converts a Git tag to a branch, typically used when changing `floating-versions-use` from `tags` to `branches`.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `Name` | `string` | The version name (e.g., "v1") |
| `Sha` | `string` | The commit SHA |
| `Priority` | `int` | 25 (runs after deletes, before create/update) |

## Constructor

```powershell
[ConvertTagToBranchAction]::new([string]$name, [string]$sha)
```

## Usage

```powershell
$action = [ConvertTagToBranchAction]::new("v1", "abc123def456")
$success = $action.Execute($state)
```

## Auto-Fix Behavior

The action follows these steps:

1. **Check immutability** - If the tag has an immutable release, mark as unfixable
2. **Check if branch exists** - If a branch with the same name already exists:
   - Delete only the tag (branch takes precedence)
3. **Full conversion** - If no branch exists:
   - Create the branch at the same SHA
   - Delete the tag

## Manual Remediation

When the branch doesn't exist:
```bash
git push origin <sha>:refs/heads/<name>
git push origin :refs/tags/<name>
```

When the branch already exists (just remove the duplicate tag):
```bash
git push origin :refs/tags/<name>
```

## Limitations

### Immutable Releases

If the tag has an associated **immutable release**, the tag cannot be deleted. The action will:
- Mark the issue as `unfixable`
- Return an empty array from `GetManualCommands()`

**Workarounds:**
- Keep the tag instead of converting to branch
- Add the version to `ignore-versions`

### Workflow File Permissions

If the target commit contains changes to `.github/workflows/*` files, the default `GITHUB_TOKEN` cannot create the branch.

**Workarounds:**
- Use a PAT with `workflows` scope
- Convert manually using `git push`

When this occurs, the action marks the issue as `manual_fix_required`.

### Partial Failure

If the branch is created but the tag deletion fails, you'll have both a tag and a branch with the same name. This is valid but may cause confusion. Manually delete the tag to complete the conversion.

## Use Cases

1. **Changing `floating-versions-use`** - When switching from `tags` to `branches` for floating versions
2. **Duplicate refs** - When both a tag and branch exist for the same version
3. **Workflow preferences** - When your CI/CD expects branches instead of tags

## Related Actions

- [ConvertBranchToTagAction](../ConvertBranchToTagAction/README.md) - Opposite conversion
- [CreateBranchAction](../../branches/CreateBranchAction/README.md) - Used internally
- [DeleteTagAction](../../tags/DeleteTagAction/README.md) - Used internally

## Related Rules

- [tag_should_be_branch](../../../rules/ref_type/tag_should_be_branch/README.md) - Rule that creates this action
- [duplicate_floating_version_ref](../../../rules/ref_type/duplicate_floating_version_ref/README.md) - May also use this action
