# DeleteReleaseAction

Deletes a GitHub Release from the repository.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `TagName` | `string` | The tag name for the release (e.g., "v1.0.0") |
| `ReleaseId` | `int` | The GitHub release ID |
| `Priority` | `int` | 10 (runs first to clean up before other operations) |

## Constructor

```powershell
[DeleteReleaseAction]::new([string]$tagName, [int]$releaseId)
```

## Usage

```powershell
$action = [DeleteReleaseAction]::new("v1.0.0", 12345)
$success = $action.Execute($state)
```

## Auto-Fix Behavior

When executed:
1. Deletes the GitHub Release via REST API
2. Does **NOT** delete the associated tag

## Manual Remediation

```bash
gh release delete v1.0.0 --yes
```

Or via the GitHub Web UI:
1. Navigate to **Releases**
2. Find the release
3. Click **Delete** (trash icon)
4. Confirm deletion

## Warning: Immutable Release Consequences

⚠️ **Deleting an immutable release has permanent consequences:**

When you delete an immutable release, the associated tag becomes "locked." You **cannot**:
- Create a new release for that tag
- Publish a draft release for that tag

GitHub returns HTTP 422 if you try to create/publish a release for a tag that was previously used by a deleted immutable release.

**Resolution:**
- Create a new patch version (e.g., `v1.0.1` instead of `v1.0.0`)
- Add the old version to `ignore-versions`

## Priority

Delete actions have the highest priority (10) because:
1. Removing releases before creating new ones prevents conflicts
2. Clean state before other operations

## Tag Preservation

This action only deletes the release, not the tag. The tag remains in the repository. If you need to delete both:

```bash
gh release delete v1.0.0 --yes
git push origin :refs/tags/v1.0.0
```

## Related Actions

- [CreateReleaseAction](../CreateReleaseAction/README.md) - Create a new release
- [PublishReleaseAction](../PublishReleaseAction/README.md) - Publish a draft release
- [DeleteTagAction](../../tags/DeleteTagAction/README.md) - Delete the tag after release
