# RepublishReleaseAction

Republishes a GitHub Release to make it immutable (if repository settings allow).

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `TagName` | `string` | The tag name for the release (e.g., "v1.0.0") |
| `Priority` | `int` | 45 (runs after other release operations) |

## Constructor

```powershell
[RepublishReleaseAction]::new([string]$tagName)
```

## Usage

```powershell
$action = [RepublishReleaseAction]::new("v1.0.0")
$success = $action.Execute($state)
```

## Auto-Fix Behavior

When executed:
1. Sets the release to draft (`draft: true`)
2. Immediately republishes (`draft: false`)
3. Verifies immutability via GraphQL API
4. If still mutable, marks issue as `manual_fix_required`

## Why Republishing Makes Releases Immutable

GitHub's immutable releases feature locks a release when it's published **after** the feature is enabled. Releases that were published before enabling the feature remain mutable.

By republishing (draft → published), the release is processed through the immutability system and becomes locked.

## Manual Remediation

```bash
# Set to draft then republish
gh release edit v1.0.0 --draft=true
gh release edit v1.0.0 --draft=false
```

Or via the GitHub Web UI:
1. Navigate to **Releases**
2. Edit the release
3. Click **Save draft**
4. Edit again and click **Publish release**

## Repository Configuration Required

For republishing to make releases immutable, the repository must have immutable releases enabled:

1. Go to **Settings** → **General** → **Releases**
2. Enable "Release immutability"

If the repository doesn't have this enabled, the action will mark the issue as `manual_fix_required` with instructions to enable the setting.

## Limitations

### Repository Settings

If the repository doesn't have immutable releases enabled:
- Republishing will succeed but the release remains mutable
- The action marks the issue as `manual_fix_required`
- Manual commands return a comment with the settings URL

### Tag Locked by Deleted Immutable Release

If a tag was previously used by an immutable release that was deleted, GitHub permanently blocks any modification to releases for that tag.

When this occurs, the action marks the issue as `unfixable` and `GetManualCommands()` returns an empty array.

## Related Actions

- [CreateReleaseAction](../CreateReleaseAction/README.md) - Create a new release
- [PublishReleaseAction](../PublishReleaseAction/README.md) - Publish a draft release
- [DeleteReleaseAction](../DeleteReleaseAction/README.md) - Delete an existing release

## Related Rules

- [release_should_be_immutable](../../../rules/releases/release_should_be_immutable/README.md) - Rule that creates this action
