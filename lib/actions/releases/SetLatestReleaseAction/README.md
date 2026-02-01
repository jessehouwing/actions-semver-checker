# SetLatestReleaseAction

## Overview

This action sets a specific release as the "latest" release in GitHub using the `make_latest` API parameter.

## When This Action Is Used

This action is created by the `release_should_be_latest` rule when the wrong release is currently marked as latest in GitHub.

## Execution

The action:

1. Looks up the release ID if not provided
2. Calls the GitHub API to update the release with `make_latest: true`
3. Reports success or failure

## Constructor

```powershell
# With tag name only (release ID will be looked up from state)
[SetLatestReleaseAction]::new("v1.0.0")

# With tag name and release ID
[SetLatestReleaseAction]::new("v1.0.0", 12345)
```

## Properties

| Property    | Type   | Description                              |
| ----------- | ------ | ---------------------------------------- |
| `TagName`   | string | The version tag name (inherited)         |
| `ReleaseId` | int    | The GitHub release ID                    |
| `Priority`  | int    | 50 (runs after other release operations) |

## Manual Command

```bash
gh release edit v1.0.0 --latest
```

## API Call

```http
PATCH /repos/{owner}/{repo}/releases/{release_id}
{
  "make_latest": "true"
}
```

## Related Actions

- `CreateReleaseAction` - Can set `MakeLatest=false` to prevent becoming latest
- `PublishReleaseAction` - Can set `MakeLatest=false` to prevent becoming latest
