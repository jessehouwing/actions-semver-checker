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
1. Queries whether release immutability is enabled for the repository
2. If disabled, enables it (`PUT /repos/{owner}/{repo}/immutable-releases`); if that fails (e.g. no admin permission), marks the issue as `manual_fix_required` with the `gh api -X PUT` command and stops
3. Sets the release to draft (`draft: true`)
4. Immediately republishes (`draft: false`)
5. Verifies immutability via GraphQL API
6. If still mutable, marks issue as `manual_fix_required`

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

For republishing to make releases immutable, the repository must have immutable releases enabled. The action enables it automatically when permitted. Manually:

```bash
gh api -X PUT "repos/{owner}/{repo}/immutable-releases"
```

This needs repository admin rights; the default Actions `GITHUB_TOKEN` typically cannot do it, so provide a PAT/GitHub App token via `token` if you want auto-fix to enable it.

## Limitations

### Repository Settings

If the repository doesn't have immutable releases enabled:
- The action tries to enable it; if that fails the issue is `manual_fix_required` and nothing is republished
- Manual commands include the `gh api -X PUT` command to enable it

### Tag Locked by Deleted Immutable Release

If a tag was previously used by an immutable release that was deleted, GitHub permanently blocks any modification to releases for that tag.

A deleted release most likely indicates a security problem, so when GitHub returns HTTP 422 the action runs [DeleteTagAction](../../tags/DeleteTagAction/README.md) for the tag. This prevents the tag from being referenced any longer, and the issue is treated as fixed.

If deleting the tag fails (for example because a tag ruleset forbids deletion), the action:

1. Queries the repository and inherited organization rulesets (`GET /repos/{owner}/{repo}/rulesets?includes_parents=true`) via `Get-GitHubTagProtection` to find active tag rulesets with a `deletion` rule whose `ref_name` conditions match the tag. This requires a token that can read rulesets; if the lookup fails, no rulesets are reported.
2. Marks the issue as `manual_fix_required` and lists the blocking rulesets in the message.
3. Returns manual commands that name each ruleset to bypass or disable (with a link), followed by the command to delete the tag remotely:

```bash
# Tag deletion is blocked by repository owner/repo ruleset 'Protect tags' (active): add yourself to its bypass list or disable it: https://github.com/owner/repo/rules/1
git push origin :refs/tags/v1.0.0
```

Legacy tag protection rules are not checked.

## Related Actions

- [DeleteTagAction](../../tags/DeleteTagAction/README.md) - Delete the tag of a deleted immutable release
- [CreateReleaseAction](../CreateReleaseAction/README.md) - Create a new release
- [PublishReleaseAction](../PublishReleaseAction/README.md) - Publish a draft release
- [DeleteReleaseAction](../DeleteReleaseAction/README.md) - Delete an existing release

## Related Rules

- [release_should_be_immutable](../../../rules/releases/release_should_be_immutable/README.md) - Rule that creates this action
