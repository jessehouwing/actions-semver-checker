# PublishReleaseAction

Publishes a draft GitHub Release, making it visible and potentially immutable.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `TagName` | `string` | The tag name for the release (e.g., "v1.0.0") |
| `ReleaseId` | `int` | The GitHub release ID (optional, will be looked up if 0) |
| `Priority` | `int` | 40 (runs after release creation) |

## Constructors

```powershell
# Without release ID (will be looked up)
[PublishReleaseAction]::new([string]$tagName)

# With explicit release ID
[PublishReleaseAction]::new([string]$tagName, [int]$releaseId)
```

## Usage

```powershell
$action = [PublishReleaseAction]::new("v1.0.0", 12345)
$success = $action.Execute($state)
```

## Auto-Fix Behavior

When executed:
1. Looks up the release by tag name if `ReleaseId` is 0
2. Updates the release to set `draft: false`
3. If repository has immutable releases enabled, the release becomes immutable

## Manual Remediation

```bash
gh release edit v1.0.0 --draft=false
```

Or via the GitHub Web UI:
1. Navigate to **Releases**
2. Find the draft release
3. Click **Edit**
4. Click **Publish release**

## Limitations

### Tag Locked by Deleted Immutable Release

If a tag was previously used by an immutable release that was deleted, GitHub permanently blocks publishing new releases for that tag. The API returns HTTP 422.

**Resolution:**
- Add the version to `ignore-versions` input
- Delete the draft release and create a new patch version

When this occurs, the action marks the issue as `unfixable` and `GetManualCommands()` returns an empty array.

### Repository Must Have Release

This action fails if no release exists for the tag. Use `CreateReleaseAction` first to create the release.

## Related Actions

- [CreateReleaseAction](../CreateReleaseAction/README.md) - Create a new release
- [RepublishReleaseAction](../RepublishReleaseAction/README.md) - Republish to make immutable
- [DeleteReleaseAction](../DeleteReleaseAction/README.md) - Delete an existing release

## Related Rules

- [release_should_be_published](../../../rules/releases/release_should_be_published/README.md) - Rule that creates this action
