# action_metadata_required Rule

## Overview

This rule validates that all required metadata for GitHub Marketplace publication exists before creating immutable releases.

## Requirements Checked

GitHub Marketplace requires the following for an action to be published:

1. **action.yaml or action.yml** must exist with:
   - `name` - The action's name
   - `description` - A brief description of what the action does
   - `branding.icon` - A Feather icon name (see https://feathericons.com/)
   - `branding.color` - One of: white, yellow, blue, green, orange, red, purple, gray-dark

2. **README.md** must exist in the repository root

## Configuration

This rule is controlled by the `check-marketplace` input:

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    check-marketplace: error  # Options: error, warning, none
```

## Why This Matters

When you publish a GitHub Action to the marketplace, GitHub requires all this metadata. Without it:

- The action cannot be listed in the marketplace
- Users searching for actions won't find yours
- The action will lack proper branding/visual identity

This rule helps catch missing metadata early, before you try to make a release immutable.

## Auto-Fix

This rule **cannot be auto-fixed**. The metadata must be manually added by the action author because:

- The action name and description are creative decisions
- The icon and color choices are branding decisions
- The README content requires documentation effort

## Related Rules

- `release_should_be_immutable` - Checks release immutability status
- `marketplace_publication_required` - Checks marketplace publication status

## Example action.yaml

```yaml
name: 'My Awesome Action'
description: 'Performs awesome tasks in your workflow'
branding:
  icon: 'zap'
  color: 'yellow'
inputs:
  # ... your inputs
runs:
  # ... your runs configuration
```
