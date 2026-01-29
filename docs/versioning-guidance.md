# GitHub Actions Versioning Guidance

This document provides comprehensive guidance on versioning GitHub Actions following GitHub's official best practices.

## Table of Contents
- [Overview](#overview)
- [GitHub's Immutable Release Strategy](#githubs-immutable-release-strategy)
- [Release Types](#release-types)
- [Recommended Workflow](#recommended-workflow)
- [Why This Strategy?](#why-this-strategy)
- [Comparison with Alternative Strategies](#comparison-with-alternative-strategies)
- [Troubleshooting](#troubleshooting)

## Overview

This action implements [GitHub's recommended approach](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases) for managing action releases. The strategy balances two competing needs:

1. **Stability** - Users need reliable, unchanging reference points
2. **Convenience** - Users want automatic updates for compatible versions

## GitHub's Immutable Release Strategy

GitHub's approach uses two types of version references:

### 1. Patch Versions (v1.0.0, v1.0.1, etc.) - IMMUTABLE
- **Must have a GitHub Release**
- **Cannot be changed** once published (non-draft)
- Provides stable, unchangeable reference points
- Users can pin to exact versions: `uses: org/action@v1.0.0`

### 2. Floating Versions (v1, v1.0, latest) - MUTABLE
- **Git tags** that point to the latest compatible patch version
- **Updated via force push** when new patches are released
- Allow users to get latest compatible updates automatically
- Users get updates: `uses: org/action@v1`

## Release Types

### Semantic Patch Versions (Immutable)

**Examples:** `v1.0.0`, `v1.0.1`, `v2.3.4`

**Characteristics:**
- Full semantic version with all three parts (major.minor.patch)
- Each must have a GitHub Release
- Releases must be published (not draft) for immutability
- Once published, the tag cannot be moved to a different commit

**When to create:**
- Every release of your action
- When you want users to be able to pin to that exact version
- As the target for your floating version tags

**How to create:**
```bash
# Create release (preferred method - creates tag automatically)
gh release create v1.0.0 --title "v1.0.0" --notes "Release notes here"

# Or create tag first, then release
git tag v1.0.0
git push origin v1.0.0
gh release create v1.0.0 --title "v1.0.0" --notes "Release notes here"
```

### Floating Major Versions (Mutable)

**Examples:** `v1`, `v2`, `v3`

**Characteristics:**
- Git tag (not a release) that can be force-pushed
- Points to the latest patch version within that major version
- Updated when you release any new patch in that major version
- Allows users to get all compatible updates automatically

**When to update:**
- After releasing any new patch version in that major version
- Example: After releasing `v1.0.1`, update `v1` to point to it
- Example: After releasing `v1.1.0`, update `v1` to point to it

**How to update:**
```bash
# Update v1 to point to v1.0.1
git push origin <v1.0.1-sha>:refs/tags/v1 --force

# Or if you have the tag checked out locally
git tag -f v1 v1.0.1
git push origin v1 --force
```

### Floating Minor Versions (Mutable)

**Examples:** `v1.0`, `v1.1`, `v2.3`

**Characteristics:**
- Git tag (not a release) that can be force-pushed
- Points to the latest patch within that minor version
- Updated when you release a new patch in that minor version
- Allows users to get bug fixes without feature changes

**When to update:**
- After releasing any new patch version in that minor version
- Example: After releasing `v1.0.1`, update `v1.0` to point to it
- Do NOT update when releasing v1.1.0 (different minor version)

**How to update:**
```bash
# Update v1.0 to point to v1.0.1
git push origin <v1.0.1-sha>:refs/tags/v1.0 --force
```

### Latest (Optional, Mutable)

**Example:** `latest`

**Characteristics:**
- Points to the absolute latest stable release
- Useful for users who always want the newest version
- Can be a tag or branch depending on configuration

**When to update:**
- After releasing any new stable version
- Skip if using `ignore-preview-releases` and releasing a preview

**How to update:**
```bash
# As a tag
git push origin <v1.0.1-sha>:refs/tags/latest --force

# As a branch (if using floating-versions-use: branches)
git push origin <v1.0.1-sha>:refs/heads/latest --force
```

## Recommended Workflow

### Step 1: Develop Your Changes

```bash
# Create a feature or release branch
git checkout -b release-v1.0.1

# Make your changes, commit them
git add .
git commit -m "Fix: important bug fix"

# Push to remote for testing
git push origin release-v1.0.1
```

### Step 2: Create the Release

Use GitHub's release creation, which automatically creates the tag:

```bash
# Create and publish the release
gh release create v1.0.1 \
  --title "v1.0.1" \
  --notes "## Changes

- Fixed critical bug in X
- Improved performance of Y
- Updated dependencies

**Full Changelog**: https://github.com/org/repo/compare/v1.0.0...v1.0.1"
```

**Alternative: Create draft first (recommended for review):**
```bash
# Create as draft for review
gh release create v1.0.1 --draft \
  --title "v1.0.1" \
  --notes "Release notes..."

# Review the release on GitHub, then publish
gh release edit v1.0.1 --draft=false
```

### Step 3: Update Floating Version Tags

This is what the semver-checker action validates and can automate:

```bash
# Get the SHA for the new release
SHA=$(git rev-parse v1.0.1)

# Update major version tag
git push origin $SHA:refs/tags/v1 --force

# Update minor version tag
git push origin $SHA:refs/tags/v1.0 --force

# Update latest (optional)
git push origin $SHA:refs/tags/latest --force
```

**With auto-fix enabled**, the semver-checker action does this automatically.

### Step 4: Verify

Run the semver-checker action to verify everything is correct:

```bash
# Manually trigger the check
gh workflow run semver-check.yml
```

Or let it run automatically on tag push.

## Why This Strategy?

### ✅ Benefits of Immutable Releases

1. **Reliability**: Users can trust that `v1.0.0` will never change
2. **Debugging**: Easy to reproduce issues with specific versions
3. **Security**: Prevents malicious tag manipulation
4. **Compliance**: Audit trails for what code ran when
5. **Marketplace**: GitHub Marketplace requires stable releases

### ✅ Benefits of Mutable Tags

1. **Convenience**: Users can subscribe to `v1` for compatible updates
2. **Maintenance**: Fix bugs without forcing users to update workflows
3. **Adoption**: Lower friction for users to get improvements
4. **Semver Promise**: Major version changes signal breaking changes

### ⚖️ The Balance

By combining both:
- Conservative users can pin to `v1.0.0` (never changes)
- Trusting users can use `v1` (gets compatible updates)
- Everyone knows what to expect based on their choice

## Comparison with Alternative Strategies

### Strategy 1: Everything Immutable (NOT Recommended)

❌ **All versions are immutable releases, including `v1`**

```yaml
# User must update workflow for every patch
- uses: org/action@v1.0.0  # Stuck here forever
- uses: org/action@v1.0.1  # Manual update required
- uses: org/action@v1.0.2  # Manual update required
```

**Why not:**
- Users don't get bug fixes automatically
- Must change workflow for every patch release
- Defeats the purpose of semantic versioning
- Not aligned with GitHub's guidance
- Poor user experience

**When it makes sense:**
- Never. Even security-critical actions benefit from floating versions for patches.

### Strategy 2: Everything Mutable (NOT Recommended)

❌ **All versions are mutable tags, no releases**

```yaml
# Any version could change at any time
- uses: org/action@v1.0.0  # Could change unexpectedly!
- uses: org/action@v1      # Could change unexpectedly!
```

**Why not:**
- No stability guarantees
- Can't reproduce old behavior
- Security risk (tag manipulation)
- GitHub Marketplace won't accept it
- Breaks trust with users

**When it makes sense:**
- Never. Always have immutable releases for patch versions.

### Strategy 3: Branch-Based Floating Versions

⚠️ **Patch versions as releases, floating versions as branches**

```yaml
# Configure the action
floating-versions-use: branches
```

**Differences:**
- `v1` is a branch instead of a tag
- Updated via regular push (not force push)
- Can have unique commits not in any patch version

**Why it's different:**
- Branches can have their own commit history
- Can apply patches to branch without creating releases
- Updates don't require force push

**When to use:**
- You need branch-specific patches
- You want CI to run on floating version updates
- Your organization prefers branch-based workflows
- You have strong branch protection requirements

**Trade-offs:**
- More complex mental model (tags AND branches for versions)
- Potentially confusing for users (is `v1` a tag or branch?)
- Deviates from GitHub's standard guidance
- May need additional documentation for users

**GitHub's recommendation:** Use tags for floating versions (default).

### Strategy 4: GitHub's Recommended (Used by This Action)

✅ **Patch versions as immutable releases, floating versions as mutable tags**

```yaml
# Default configuration
check-releases: error                    # Enforce releases for patches
check-release-immutability: error       # Enforce immutability
floating-versions-use: tags             # Use tags (not branches)
```

**Why it's recommended:**
- Clear separation: releases = stable, tags = pointers
- Aligns with GitHub's official guidance
- Users get automatic updates when they want them
- Security through immutability where it matters
- Best of both worlds

## Troubleshooting

### Error: "Floating version exists but no patch versions found"

**Scenario:** You have a tag `v1` but no tags like `v1.0.0`, `v1.0.1`, etc.

**Why this happens:**
- Often occurs when initially setting up the action
- Tag was created manually without a corresponding release
- Testing with sample tags

**How to fix:**

1. Decide what commit `v1` should reference
2. Create a proper patch version:
   ```bash
   # Get the SHA from the v1 tag
   SHA=$(git rev-parse v1)
   
   # Create a release for that SHA
   gh release create v1.0.0 $SHA \
     --title "v1.0.0" \
     --notes "Initial release"
   ```

3. The action will now validate that `v1` points to the latest patch

**Prevention:**
- Always create patch versions (with releases) first
- Then create/update floating version tags to point to them
- Use auto-fix mode to handle this automatically

### Error: "Release is in draft status"

**Scenario:** You created a release but left it in draft mode.

**Why this matters:**
- Draft releases allow tags to be moved
- This breaks immutability guarantees
- Users could see different code for the same version tag

**How to fix:**

1. Visit the release page (link provided in error message)
2. Click "Publish release" button
3. Or use CLI:
   ```bash
   gh release edit v1.0.0 --draft=false
   ```

**Best practice:**
- Create releases as draft for review
- Publish them once approved
- Never leave releases in draft for production use

### Error: "Shallow clone detected"

**Scenario:** Checkout action used `fetch-depth: 1` (default).

**Why this happens:**
- Default checkout is shallow (only latest commit)
- Action needs full history to analyze versions

**How to fix:**

Update your workflow:
```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0      # Fetch full history
    fetch-tags: true    # Fetch all tags
```

### Warning: "No tags found"

**Scenario:** No version tags exist or weren't fetched.

**Possible causes:**
1. New repository with no releases yet
2. Checkout used `fetch-tags: false` (default)
3. Tags haven't been pushed to remote

**How to fix:**

If no releases exist yet:
```bash
# Create your first release
gh release create v1.0.0 --title "v1.0.0" --notes "Initial release"

# Create floating version tags
SHA=$(git rev-parse v1.0.0)
git push origin $SHA:refs/tags/v1
```

If tags exist but weren't fetched:
```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
    fetch-tags: true    # Add this!
```

### Auto-fix: "Token required"

**Scenario:** Auto-fix enabled but no token provided.

**Why this happens:**
- Auto-fix needs to push tag updates
- Requires authentication

**How to fix:**

```yaml
- uses: jessehouwing/actions-semver-checker@v2
  with:
    auto-fix: true
    token: ${{ secrets.GITHUB_TOKEN }}  # Add this!
```

### Auto-fix: "Permission denied"

**Scenario:** Auto-fix fails to push tags.

**Possible causes:**
1. Missing `contents: write` permission
2. Branch protection rules blocking the push
3. SSH remote with persist-credentials: false

**How to fix:**

1. Add required permission:
   ```yaml
   jobs:
     semver-check:
       permissions:
         contents: write  # Required for auto-fix
   ```

2. Check branch protection rules don't block tag pushes

3. Ensure token is provided:
   ```yaml
   - uses: actions/checkout@v4
     with:
       fetch-depth: 0
       fetch-tags: true
       token: ${{ secrets.GITHUB_TOKEN }}
   
   - uses: jessehouwing/actions-semver-checker@v2
     with:
       auto-fix: true
       token: ${{ secrets.GITHUB_TOKEN }}
   ```

## Additional Resources

- [GitHub: Using immutable releases and tags](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases)
- [GitHub: Release and maintain actions](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/release-and-maintain-actions)
- [Semantic Versioning Specification](https://semver.org/)
- [Checkout Action Documentation](https://github.com/marketplace/actions/checkout)

## Questions?

If you have questions or need clarification:
1. Check the [main README](../README.md) for configuration options
2. Review [GitHub's official guidance](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/using-immutable-releases-and-tags-to-manage-your-actions-releases)
3. Open an issue in the repository
