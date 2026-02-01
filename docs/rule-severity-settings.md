# Rule Severity Settings - Quick Reference

This document provides a concise mapping of configuration settings to rule severity levels, as requested in the problem statement.

## Configuration Inputs

Three configuration inputs control rule severity:

1. **`check-minor-version`** → Controls minor version validation
   - `error`: Minor version issues are errors
   - `warning`: Minor version issues are warnings
   - `none`: Minor version rules disabled

2. **`check-releases`** → Controls GitHub Release validation
   - `error`: Release issues are errors
   - `warning`: Release issues are warnings
   - `none`: Release rules disabled

3. **`check-release-immutability`** → Controls release immutability validation
   - `error`: Immutability issues are errors
   - `warning`: Immutability issues are warnings
   - `none`: Immutability rules disabled

## Settings Matrix

### Scenario 1: check-minor-version

| Setting Value | Affected Rules | Severity | Enabled? |
|--------------|----------------|----------|----------|
| `error` (default) | `minor_tag_missing`<br>`minor_tag_tracks_highest_patch`<br>`minor_branch_missing`<br>`minor_branch_tracks_highest_patch` | **ERROR** | ✅ Yes |
| `warning` | Same rules as above | **WARNING** | ✅ Yes |
| `none` | Same rules as above | N/A | ❌ No (disabled) |

**Example:** User sets `check-minor-version: warning`
- Result: Missing v1.0 tags/branches report as **warnings**, not errors
- Use case: Repository doesn't track minor versions but wants reminders

---

### Scenario 2: check-releases

| Setting Value | Affected Rules | Severity | Enabled? |
|--------------|----------------|----------|----------|
| `error` (default) | `patch_release_required`<br>`highest_patch_release_should_be_latest`<br>`duplicate_release`<br>`patch_tag_missing`*<br>`release_should_be_published`** | **ERROR** | ✅ Yes |
| `warning` | Same rules as above | **WARNING** | ✅ Yes |
| `none` | Same rules as above | N/A | ❌ No (disabled) |

**Note:**
- \* `patch_tag_missing` only runs when `check-releases` is `none` (creates tags without releases)
- \*\* `release_should_be_published` also considers `check-release-immutability` (see Scenario 4)

**Example:** User sets `check-releases: none`
- Result: No release validation, but patch tags are still required
- Use case: Repository doesn't use GitHub Releases

---

### Scenario 3: check-release-immutability

| Setting Value | Affected Rules | Severity | Enabled? |
|--------------|----------------|----------|----------|
| `error` (default) | `release_should_be_immutable`<br>`release_should_be_published`** | **ERROR** | ✅ Yes |
| `warning` | Same rules as above | **WARNING** | ✅ Yes |
| `none` | Same rules as above | N/A | ❌ No (disabled) |

**Note:** \*\* `release_should_be_published` also considers `check-releases` (see Scenario 4)

**Example:** User sets `check-release-immutability: warning`
- Result: Non-immutable releases report as **warnings**
- Use case: Repository is working toward enabling immutability

---

### Scenario 4: Combined Settings (release_should_be_published)

The `release_should_be_published` rule has special logic that considers **both** `check-releases` and `check-release-immutability`.

| check-releases | check-release-immutability | Result Severity | Enabled? |
|---------------|---------------------------|-----------------|----------|
| `error` | `error` | **ERROR** | ✅ Yes |
| `error` | `warning` | **WARNING** | ✅ Yes |
| `warning` | `error` | **WARNING** | ✅ Yes |
| `warning` | `warning` | **WARNING** | ✅ Yes |
| `none` | `error` | **ERROR** | ✅ Yes |
| `error` | `none` | **ERROR** | ✅ Yes |
| `none` | `none` | N/A | ❌ No (disabled) |

**Logic:** If **either** setting is `warning`, the issue is a **warning**. Both must be `error` for an error.

**Rationale:** Publishing a draft release serves two purposes:
1. Complete the release workflow (related to `check-releases`)
2. Make the release immutable (related to `check-release-immutability`)

If the user wants lenient validation for either aspect, publishing should be lenient.

---

## Rules That Always Use Error Severity

The following rules **always** report as **ERROR** regardless of configuration:

### Category: ref_type (5 rules)
- `tag_should_be_branch`
- `branch_should_be_tag`
- `duplicate_floating_version_ref`
- `duplicate_patch_version_ref`
- `duplicate_latest_ref`

**Rationale:** Using the wrong reference type (tag vs branch) breaks GitHub Actions. This is a structural error.

---

### Category: version_tracking - Major versions (4 rules)
- `major_tag_missing`
- `major_tag_tracks_highest_patch`
- `major_branch_missing`
- `major_branch_tracks_highest_patch`

**Rationale:** Major version tracking (v1 → v1.x.x) is fundamental to GitHub Actions. Users depend on `uses: owner/repo@v1` pointing to the latest v1 release.

---

### Category: version_tracking - Patches (1 rule)
- `patch_tag_missing` (when `check-releases` is `none`)

**Rationale:** If releases are disabled, patch versions must still exist as tags for versioning to work.

---

### Category: latest (2 rules)
- `latest_tag_tracks_global_highest`
- `latest_branch_tracks_global_highest`

**Rationale:** If a `latest` ref exists, it's a contract with users that it points to the globally highest version.

---

## Special Case: floating_version_no_release

This rule has **context-based severity** determined by the release's immutability:

| Release Type | Severity | Status | Reason |
|-------------|----------|--------|--------|
| **Immutable** (published) | **ERROR** | `unfixable` | Cannot delete immutable releases |
| **Mutable** (draft) | **WARNING** | `pending` | Can be auto-fixed by deleting |

**Example:** User has a published release for `v1` tag
- Result: **ERROR** with status `unfixable`
- Solution: Add `v1` to `ignore-versions` input

---

## Common Configuration Patterns

### Pattern 1: Strict Validation (Default)
```yaml
check-minor-version: error
check-releases: error
check-release-immutability: error
```
- All issues are **errors**
- Recommended for production repositories

---

### Pattern 2: Lenient Minor Versions
```yaml
check-minor-version: warning
check-releases: error
check-release-immutability: error
```
- Minor version issues are **warnings**
- Release issues are **errors**
- Use case: Repository only tracks major versions (v1, v2) but wants reminders about minor versions

---

### Pattern 3: Working Toward Immutability
```yaml
check-minor-version: error
check-releases: error
check-release-immutability: warning
```
- Most issues are **errors**
- Non-immutable releases are **warnings**
- Use case: Repository plans to enable immutability setting but hasn't yet

---

### Pattern 4: No Release Validation
```yaml
check-minor-version: error
check-releases: none
check-release-immutability: none
```
- No release validation
- Only version tracking validated
- Use case: Repository doesn't use GitHub Releases, only tags

---

### Pattern 5: All Warnings (Monitoring Mode)
```yaml
check-minor-version: warning
check-releases: warning
check-release-immutability: warning
```
- All issues are **warnings**
- Action never fails
- Use case: Initial setup, want to see issues without blocking CI

---

## Summary Table

| Configuration | # Rules Affected | Configurable Severity? | Default Severity |
|--------------|------------------|----------------------|------------------|
| `check-minor-version` | 4 | ✅ Yes | `error` |
| `check-releases` | 5 | ✅ Yes | `error` |
| `check-release-immutability` | 2 | ✅ Yes | `error` |
| `floating-versions-use` | 12 | ❌ No (enablement only) | `tags` |
| Major version rules | 4 | ❌ No (always error) | `error` |
| Ref type rules | 5 | ❌ No (always error) | `error` |
| Latest rules | 2 | ❌ No (always error) | `error` |
| `floating_version_no_release` | 1 | ❌ No (context-based) | `error` or `warning` |

---

## Validation Status

✅ **All 26 rules have been validated**
✅ **All rules correctly implement severity levels**
✅ **All rules respect configuration settings**
✅ **Tests confirm correct behavior**

See `docs/rule-severity-matrix.md` for detailed analysis of each rule.
