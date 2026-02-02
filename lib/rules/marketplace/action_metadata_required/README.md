# Rule: action_metadata_required

## What This Rule Checks

Validates that all required metadata for GitHub Marketplace publication exists in the repository. This includes the action manifest file (`action.yaml` or `action.yml`) with required fields and a `README.md` file.

## Why This Is An Issue

- **Impact:** Without proper marketplace metadata, your action cannot be published to the GitHub Marketplace and users won't be able to discover it through search.
- **Best Practice:** GitHub requires specific metadata fields for marketplace listing, including action name, description, and branding (icon and color).

## Requirements Checked

GitHub Marketplace requires the following for an action to be published:

1. **action.yaml or action.yml** must exist with:
   - `name` - The action's name (displayed in marketplace)
   - `description` - A brief description of what the action does
   - `branding.icon` - A Feather icon name (see https://feathericons.com/)
   - `branding.color` - One of: white, yellow, blue, green, orange, red, purple, gray-dark

2. **README.md** must exist in the repository root

## When This Rule Applies

This rule runs when:

- `check-marketplace` is set to `error` or `warning`
- The repository is being validated for marketplace readiness

**Note:** This rule checks metadata availability, not content quality. It verifies that required fields exist but does not validate their values beyond basic format checks.

## Configuration

### Settings That Enable This Rule

| Input | Required Value | Effect |
|-------|----------------|--------|
| `check-marketplace` | `error` or `warning` | Enables this rule |

**Note:** If `check-marketplace` is `none`, this rule is disabled.

### Settings That Affect Severity

| check-marketplace | Issue Severity |
|-------------------|----------------|
| `error` | **error** |
| `warning` | **warning** |
| `none` | (rule disabled) |

## Automatic Remediation

This rule **cannot be auto-fixed**. The metadata must be manually added by the action author because:

- The action name and description are creative decisions
- The icon and color choices are branding decisions
- The README content requires documentation effort

When this rule detects missing metadata, it provides a detailed message indicating which specific fields are missing.

## Manual Remediation

### Step 1: Create or Update action.yaml

Ensure your `action.yaml` (or `action.yml`) contains all required fields:

```yaml
name: 'My Awesome Action'
description: 'Performs awesome tasks in your workflow'
branding:
  icon: 'zap'        # See https://feathericons.com/
  color: 'yellow'    # white, yellow, blue, green, orange, red, purple, gray-dark

inputs:
  # ... your inputs

runs:
  # ... your runs configuration
```

### Step 2: Create README.md

Ensure a `README.md` file exists in the repository root with:

- Description of what the action does
- Usage examples with YAML snippets
- Input/output documentation
- Any prerequisites or requirements

## Related Rules

- [`marketplace_publication_required`](../marketplace_publication_required/README.md) - Verifies marketplace publication status
- [`release_should_be_immutable`](../../releases/release_should_be_immutable/README.md) - Checks release immutability status

## Rule Priority and Coordination

- **Priority 45** - Runs before `marketplace_publication_required` (Priority 50)
- If metadata is invalid, the `marketplace_publication_required` rule will skip checking publication status
- This ensures users fix metadata issues before worrying about publication

## Examples

### Failing Scenario - Missing Branding

```yaml
# action.yaml
name: 'My Action'
description: 'Does something useful'
# Missing: branding section

runs:
  using: 'node20'
  main: 'dist/index.js'
```

**Issue:** `missing_marketplace_metadata`  
**Message:** Missing required marketplace metadata: branding.icon, branding.color

### Failing Scenario - Missing README

```
Repository structure:
├── action.yaml (complete)
├── src/
│   └── index.js
└── (no README.md)
```

**Issue:** `missing_marketplace_metadata`  
**Message:** Missing required marketplace metadata: README.md

### Passing Scenario

```yaml
# action.yaml
name: 'My Awesome Action'
description: 'Performs awesome tasks in your workflow'
branding:
  icon: 'zap'
  color: 'yellow'
runs:
  using: 'node20'
  main: 'dist/index.js'
```

```
Repository structure:
├── action.yaml
├── README.md
└── src/
    └── index.js
```

**Result:** No issues

## Valid Branding Colors

The `branding.color` field must be one of:

| Color | Preview |
|-------|---------|
| `white` | ![white](https://img.shields.io/badge/-white-white) |
| `yellow` | ![yellow](https://img.shields.io/badge/-yellow-yellow) |
| `blue` | ![blue](https://img.shields.io/badge/-blue-blue) |
| `green` | ![green](https://img.shields.io/badge/-green-green) |
| `orange` | ![orange](https://img.shields.io/badge/-orange-orange) |
| `red` | ![red](https://img.shields.io/badge/-red-red) |
| `purple` | ![purple](https://img.shields.io/badge/-purple-purple) |
| `gray-dark` | ![gray-dark](https://img.shields.io/badge/-gray--dark-gray) |

## Valid Branding Icons

The `branding.icon` field must be a valid [Feather icon](https://feathericons.com/) name. Common choices include:

- `activity`, `airplay`, `alert-circle`, `alert-triangle`
- `check`, `check-circle`, `code`, `command`
- `git-branch`, `git-commit`, `git-merge`, `git-pull-request`
- `package`, `play`, `plus`, `refresh-cw`
- `shield`, `star`, `terminal`, `upload`, `zap`

See the full list at https://feathericons.com/
