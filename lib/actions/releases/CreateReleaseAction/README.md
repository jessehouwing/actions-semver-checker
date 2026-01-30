# CreateReleaseAction

Creates a new GitHub Release for a tag.

## Properties

| Property | Type | Description |
|----------|------|-------------|
| `TagName` | `string` | The tag name for the release (e.g., "v1.0.0") |
| `AutoPublish` | `bool` | If true, create as published (immutable); if false, create as draft |
| `Priority` | `int` | 30 (runs after tag operations) |

## Constructors

```powershell
# Simple constructor (isDraft controls AutoPublish inversely)
[CreateReleaseAction]::new([string]$tagName, [bool]$isDraft)

# Full constructor with explicit AutoPublish control
[CreateReleaseAction]::new([string]$tagName, [bool]$isDraft, [bool]$autoPublish)
```

## Usage

```powershell
# Create a draft release
$action = [CreateReleaseAction]::new("v1.0.0", $true)

# Create and immediately publish (immutable)
$action = [CreateReleaseAction]::new("v1.0.0", $false, $true)

$success = $action.Execute($state)
```

## Auto-Fix Behavior

When executed:
1. Creates a GitHub Release via REST API
2. If `AutoPublish` is true, creates directly as published (making it immutable if repo settings allow)
3. If `AutoPublish` is false, creates as draft for later review

## Why AutoPublish Matters

GitHub's immutable releases have a quirk: if a tag was previously used by an immutable release that was later deleted, you **cannot** publish a new release on that tag. GitHub returns HTTP 422.

By using `AutoPublish = $true`, the release is created directly as published, bypassing this limitation. This is why `check-release-immutability` configuration affects whether releases are auto-published.

## Manual Remediation

```bash
# Create a published release (immutable)
gh release create v1.0.0 --title "v1.0.0" --notes "Release v1.0.0"

# Create a draft release
gh release create v1.0.0 --draft --title "v1.0.0" --notes "Release v1.0.0"
```

Or via the GitHub Web UI:
1. Navigate to **Releases** → **Draft a new release**
2. Enter tag name, title, and description
3. Choose "Publish release" or "Save draft"

## Limitations

### Tag Locked by Deleted Immutable Release

If a tag was previously used by an immutable release that was deleted, GitHub permanently blocks creating new releases for that tag. The API returns HTTP 422.

**Resolution:**
- Add the version to `ignore-versions` input
- Create a new patch version (e.g., `v1.0.1` instead of `v1.0.0`)

When this occurs, the action marks the issue as `unfixable` and `GetManualCommands()` returns an empty array.

### Tag Must Exist

The GitHub Release API can create tags automatically, but if you need specific tag properties or the tag already exists, ensure it points to the correct commit.

## Related Actions

- [PublishReleaseAction](../PublishReleaseAction/README.md) - Publish a draft release
- [RepublishReleaseAction](../RepublishReleaseAction/README.md) - Republish to make immutable
- [DeleteReleaseAction](../DeleteReleaseAction/README.md) - Delete an existing release

## Related Rules

- [patch_release_required](../../../rules/releases/patch_release_required/README.md) - Rule that creates this action
- [release_should_be_published](../../../rules/releases/release_should_be_published/README.md) - Rule for draft releases
