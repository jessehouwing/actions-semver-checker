# Base Remediation Action Classes

This folder contains the base classes for all remediation actions in the semver-checker action.

## RemediationAction

The `RemediationAction` class is the abstract base class for all remediation actions.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `Description` | `string` | Human-readable description of the action |
| `Version` | `string` | The version this action applies to (e.g., "v1.0.0") |
| `Priority` | `int` | Execution order priority (lower = runs first, default: 50) |

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `Execute($state)` | `bool` | Performs the auto-fix action. Returns `$true` on success. |
| `GetManualCommands($state)` | `string[]` | Returns CLI commands for manual remediation. |
| `ToString()` | `string` | Returns a formatted description (e.g., "Create tag for v1.0.0") |

### Implementing a New Action

To create a new remediation action:

1. Create a new class that inherits from `RemediationAction`
2. Call the base constructor with description and version
3. Set an appropriate `Priority` value
4. Override `Execute()` to perform the action
5. Override `GetManualCommands()` to provide manual CLI commands

```powershell
class MyNewAction : RemediationAction {
    [string]$CustomProperty
    
    MyNewAction([string]$version, [string]$customValue) : base("My action", $version) {
        $this.CustomProperty = $customValue
        $this.Priority = 25  # Set appropriate priority
    }
    
    [bool] Execute([RepositoryState]$state) {
        # Implement the auto-fix logic
        Write-Host "Auto-fix: Performing action for $($this.Version)"
        # ... actual work ...
        return $true  # or $false on failure
    }
    
    [string[]] GetManualCommands([RepositoryState]$state) {
        return @("some-cli-command $($this.Version)")
    }
}
```

## Priority Ranges

Actions are sorted by priority before execution. Use these ranges:

| Range | Purpose | Examples |
|-------|---------|----------|
| 10 | Delete operations | `DeleteTagAction`, `DeleteBranchAction`, `DeleteReleaseAction` |
| 20 | Create/Update refs | `CreateTagAction`, `UpdateTagAction`, `CreateBranchAction`, `UpdateBranchAction` |
| 25 | Conversion operations | `ConvertTagToBranchAction`, `ConvertBranchToTagAction` |
| 30 | Create releases | `CreateReleaseAction` |
| 40 | Publish releases | `PublishReleaseAction` |
| 45 | Republish releases | `RepublishReleaseAction` |
| 50 | Default (avoid using) | - |

## Issue Status Management

Actions can update the status of `ValidationIssue` objects in the state:

| Status | Description |
|--------|-------------|
| `pending` | Not yet processed |
| `fixed` | Auto-fix succeeded |
| `failed` | Auto-fix attempted but failed (retryable) |
| `unfixable` | Cannot be fixed automatically (e.g., HTTP 422 errors) |
| `manual_fix_required` | Needs human intervention (e.g., workflow permissions) |

## Related Classes

- `ReleaseRemediationAction` - Base class for release-specific actions with helper methods
- See individual action folders for concrete implementations
