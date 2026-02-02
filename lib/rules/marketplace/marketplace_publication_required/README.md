# marketplace_publication_required Rule

## Overview

This rule verifies that your latest release has been published to the GitHub Marketplace. While publication itself is a manual action, this rule can detect whether a specific version has been published.

## What This Rule Checks

This rule verifies:

1. Marketplace metadata is valid (name, description, branding, README)
2. A "latest" release exists
3. The latest release is published to the GitHub Marketplace

## How Detection Works

The rule queries the public GitHub Marketplace URL:
```
https://github.com/marketplace/actions/{action-slug}?version={version}
```

When a version is published, the marketplace page displays "Use {version}". When not published, it falls back to "Use latest version". The rule detects this difference to determine publication status.

## Configuration

This rule is controlled by the `check-marketplace` input:

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    check-marketplace: error  # Options: error, warning, none
```

## Why This Matters

Publishing to the GitHub Marketplace:

- Makes your action discoverable to millions of GitHub users
- Provides a verified listing with your branding
- Enables usage statistics and insights
- Builds trust with the "Verified creator" badge (if eligible)

## Manual Publication Steps

To publish a release to the GitHub Marketplace:

1. Navigate to your release page: `https://github.com/{owner}/{repo}/releases/tag/{version}`
2. Click 'Edit' on the release
3. Check 'Publish this Action to the GitHub Marketplace'
4. Review and accept the GitHub Marketplace Developer Agreement (first time only)
5. Select appropriate categories for your action
6. Click 'Update release'

### Prerequisites

Before publishing, ensure:

- Your email is verified on GitHub
- `action.yaml` exists with `name`, `description`, and `branding` fields
- `README.md` exists in the repository root
- The release is not a draft

## Auto-Fix

This rule **cannot be auto-fixed** because:

- GitHub does not provide an API for marketplace publication
- Publication requires accepting the Marketplace Developer Agreement
- Category selection is a manual decision

When this rule detects a missing publication, it provides manual fix instructions with the exact steps needed.

## Related Rules

- `action_metadata_required` - Validates required marketplace metadata
- `release_should_be_immutable` - Checks release immutability
- `highest_patch_release_should_be_latest` - Ensures correct "latest" release

## Limitations

- The marketplace URL check requires network access to github.com
- GitHub Enterprise Server may not support marketplace features
- If the marketplace check fails due to network issues, the rule logs a warning but does not fail (to avoid false positives)
