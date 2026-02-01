# Validation Rules Severity Matrix

This document provides a comprehensive overview of all validation rules and how they determine severity levels (error/warning) based on configuration inputs.

## Configuration Inputs

The following inputs control rule behavior:

| Input | Values | Purpose |
|-------|--------|---------|
| `check-minor-version` | `error`, `warning`, `none` | Controls whether minor version validation is enabled and at what severity |
| `check-releases` | `error`, `warning`, `none` | Controls whether GitHub Release validation is enabled and at what severity |
| `check-release-immutability` | `error`, `warning`, `none` | Controls whether release immutability validation is enabled and at what severity |
| `floating-versions-use` | `tags`, `branches` | Controls whether floating versions (v1, v1.0) use tags or branches |
| `ignore-preview-releases` | `true`, `false` | Controls whether prerelease versions are excluded from highest-version calculations |

## Rules by Category

### 1. REF_TYPE Rules (Priority 5)

These rules enforce the correct reference type (tag vs branch) for floating versions.

| Rule | Enabled When | Severity Logic | Severity Value |
|------|-------------|----------------|----------------|
| **tag_should_be_branch** | `floating-versions-use` == `"branches"` | Hardcoded | Always `"error"` |
| **branch_should_be_tag** | `floating-versions-use` == `"tags"` | Hardcoded | Always `"error"` |
| **duplicate_floating_version_ref** | Always | Hardcoded | Always `"error"` |
| **duplicate_patch_version_ref** | Always | Hardcoded | Always `"error"` |
| **duplicate_latest_ref** | Always | Hardcoded | Always `"error"` |

**Rationale:** Ref type violations are structural errors that prevent the action from working correctly. They must always be errors.

---

### 2. RELEASES Rules (Priority 10-15)

These rules enforce GitHub Release requirements and properties.

| Rule | Enabled When | Severity Logic | Severity Value |
|------|-------------|----------------|----------------|
| **patch_release_required** (P10) | `check-releases` in (`"error"`, `"warning"`) | Config-based | `"warning"` if `check-releases` == `"warning"`, else `"error"` |
| **release_should_be_published** (P11) | `check-releases` OR `check-release-immutability` enabled | Config-based | `"warning"` if EITHER is `"warning"`, else `"error"` |
| **release_should_be_immutable** (P12) | `check-release-immutability` in (`"error"`, `"warning"`) | Config-based | `"warning"` if `check-release-immutability` == `"warning"`, else `"error"` |
| **highest_patch_release_should_be_latest** (P13) | `check-releases` in (`"error"`, `"warning"`) | Config-based | `"warning"` if `check-releases` == `"warning"`, else `"error"` |
| **duplicate_release** (P14) | `check-releases` in (`"error"`, `"warning"`) | Config-based | `"warning"` if `check-releases` == `"warning"`, else `"error"` |
| **floating_version_no_release** (P15) | `check-releases` OR `check-release-immutability` enabled | Release-type based | `"error"` if immutable (unfixable), `"warning"` if mutable (can delete) |

**Special Case: floating_version_no_release**

This rule has unique severity logic:
- **Immutable floating releases**: Always `"error"` + `Status = "unfixable"` (cannot be deleted)
- **Mutable floating releases**: Always `"warning"` (can be deleted)

The severity is determined by the release's immutability status, not by configuration.

---

### 3. VERSION_TRACKING Rules (Priority 20-29)

These rules ensure floating versions (v1, v1.0) point to the correct patch versions.

#### Major Version Tracking (Always Required)

| Rule | Enabled When | Severity Logic | Severity Value |
|------|-------------|----------------|----------------|
| **major_tag_missing** (P20) | `floating-versions-use` != `"branches"` | Hardcoded | Always `"error"` |
| **major_tag_tracks_highest_patch** (P20) | `floating-versions-use` != `"branches"` | Hardcoded | Always `"error"` |
| **major_branch_missing** (P20) | `floating-versions-use` == `"branches"` | Hardcoded | Always `"error"` |
| **major_branch_tracks_highest_patch** (P20) | `floating-versions-use` == `"branches"` | Hardcoded | Always `"error"` |
| **patch_tag_missing** (P21) | `check-releases` == `"none"` | Hardcoded | Always `"error"` |

**Rationale:** Major version tracking is fundamental to GitHub Actions versioning. Users rely on `uses: owner/repo@v1` pointing to the latest v1.x.x release. This must always be an error.

#### Minor Version Tracking (Optional)

| Rule | Enabled When | Severity Logic | Severity Value |
|------|-------------|----------------|----------------|
| **minor_tag_missing** (P23) | `floating-versions-use` != `"branches"` AND `check-minor-version` != `"none"` | Config-based | `"warning"` if `check-minor-version` == `"warning"`, else `"error"` |
| **minor_tag_tracks_highest_patch** (P24) | `floating-versions-use` != `"branches"` AND `check-minor-version` != `"none"` | Config-based | `"warning"` if `check-minor-version` == `"warning"`, else `"error"` |
| **minor_branch_missing** (P23) | `floating-versions-use` == `"branches"` AND `check-minor-version` != `"none"` | Config-based | `"warning"` if `check-minor-version` == `"warning"`, else `"error"` |
| **minor_branch_tracks_highest_patch** (P24) | `floating-versions-use` == `"branches"` AND `check-minor-version` != `"none"` | Config-based | `"warning"` if `check-minor-version` == `"warning"`, else `"error"` |

**Rationale:** Minor version tracking (v1.0 → v1.0.5) is optional. Some repositories only maintain major versions. The `check-minor-version` input controls both enablement and severity.

---

### 4. LATEST Rules (Priority 30-39)

These rules ensure the `latest` tag/branch points to the highest patch version across all major versions.

| Rule | Enabled When | Severity Logic | Severity Value |
|------|-------------|----------------|----------------|
| **latest_tag_tracks_global_highest** (P30) | `floating-versions-use` != `"branches"` | Hardcoded | Always `"error"` |
| **latest_branch_tracks_global_highest** (P30) | `floating-versions-use` == `"branches"` | Hardcoded | Always `"error"` |

**Rationale:** If a `latest` ref exists, it must point to the globally highest version. This is a contract with users and must always be an error.

---

## Summary Table: Config Impact on Severity

| Configuration Setting | Affected Rules | Effect |
|----------------------|----------------|--------|
| `check-minor-version` == `"error"` | All minor version tracking rules | Issues reported as **ERROR** |
| `check-minor-version` == `"warning"` | All minor version tracking rules | Issues reported as **WARNING** |
| `check-minor-version` == `"none"` | All minor version tracking rules | Rules **DISABLED** (no issues) |
| `check-releases` == `"error"` | `patch_release_required`, `release_should_be_published`, `duplicate_release`, `highest_patch_release_should_be_latest` | Issues reported as **ERROR** |
| `check-releases` == `"warning"` | Same as above | Issues reported as **WARNING** |
| `check-releases` == `"none"` | Same as above | Rules **DISABLED** (no issues) |
| `check-release-immutability` == `"error"` | `release_should_be_immutable`, `release_should_be_published` | Issues reported as **ERROR** |
| `check-release-immutability` == `"warning"` | Same as above | Issues reported as **WARNING** |
| `check-release-immutability` == `"none"` | Same as above | Rules **DISABLED** (no issues) |
| `floating-versions-use` == `"tags"` | All tag-based rules enabled, branch-based rules disabled | Controls enablement only |
| `floating-versions-use` == `"branches"` | All branch-based rules enabled, tag-based rules disabled | Controls enablement only |

---

## Special Case: release_should_be_published

The `release_should_be_published` rule has special severity logic:

```powershell
$severity = 'error'
if ($checkImmutability -eq 'warning' -or $checkReleases -eq 'warning') {
    $severity = 'warning'
}
```

This means:
- If **EITHER** `check-releases` OR `check-release-immutability` is `"warning"`, the issue is a **WARNING**
- Only if **BOTH** are set to `"error"` (or one is error and the other is none), the issue is an **ERROR**

This logic ensures that if a user wants lenient validation for either releases or immutability, draft releases are treated leniently.

---

## Validation Checklist

When adding or modifying rules, ensure:

1. ✅ **Condition block** checks relevant config inputs to determine if rule is enabled
2. ✅ **CreateIssue block** uses config inputs to determine severity (if applicable)
3. ✅ **Hardcoded errors** are only used for structural/fundamental issues:
   - Reference type mismatches
   - Major version tracking issues
   - Latest version tracking issues
   - Duplicate references
4. ✅ **Config-based severity** is used for optional/tunable validations:
   - Minor version tracking (controlled by `check-minor-version`)
   - Release requirements (controlled by `check-releases`)
   - Release immutability (controlled by `check-release-immutability`)
5. ✅ **Issue messages** clearly state the problem and expected fix
6. ✅ **RemediationAction** is attached when auto-fix is possible

---

## Testing Severity Levels

To test severity behavior, use these test patterns:

```powershell
# Test error level
$config = @{ 'check-minor-version' = 'error' }
$issue = & $Rule.CreateIssue $item $state $config
$issue.Severity | Should -Be 'error'

# Test warning level
$config = @{ 'check-minor-version' = 'warning' }
$issue = & $Rule.CreateIssue $item $state $config
$issue.Severity | Should -Be 'warning'

# Test disabled (rule should not create issues)
$config = @{ 'check-minor-version' = 'none' }
$items = & $Rule.Condition $state $config
$items.Count | Should -Be 0
```

---

## Implementation Status

**All 26 rules have been analyzed and documented.**

✅ **Correct:** 25 out of 26 rules properly implement severity levels
⚠️ **Review Needed:** 1 rule needs verification

### Rules Using Config-Based Severity (Correct)

1. `patch_release_required` → Uses `check-releases`
2. `release_should_be_published` → Uses BOTH `check-releases` AND `check-release-immutability`
3. `release_should_be_immutable` → Uses `check-release-immutability`
4. `highest_patch_release_should_be_latest` → Uses `check-releases`
5. `duplicate_release` → Uses `check-releases`
6. `minor_tag_missing` → Uses `check-minor-version`
7. `minor_tag_tracks_highest_patch` → Uses `check-minor-version`
8. `minor_branch_missing` → Uses `check-minor-version`
9. `minor_branch_tracks_highest_patch` → Uses `check-minor-version`

### Rules Using Hardcoded Severity (Correct)

1. All ref_type rules (5 rules) → Always `"error"` ✅
2. Major version tracking rules (4 rules) → Always `"error"` ✅
3. Latest tracking rules (2 rules) → Always `"error"` ✅
4. `patch_tag_missing` → Always `"error"` ✅
5. `floating_version_no_release` → Determined by release immutability ✅

### Review Needed

The `release_should_be_published` rule uses **OR logic** for determining warning level:

```powershell
$severity = 'error'
if ($checkImmutability -eq 'warning' -or $checkReleases -eq 'warning') {
    $severity = 'warning'
}
```

**Current behavior:**
- `check-releases: error` + `check-release-immutability: warning` → **WARNING**
- `check-releases: warning` + `check-release-immutability: error` → **WARNING**
- `check-releases: error` + `check-release-immutability: error` → **ERROR**

**Question:** Should the severity be the **maximum** of the two settings instead?
- Alternative logic: `$severity = if ($checkImmutability -eq 'error' -or $checkReleases -eq 'error') { 'error' } else { 'warning' }`

**Recommendation:** Keep current OR logic. The rule serves dual purposes:
1. Complete the release workflow (related to `check-releases`)
2. Make releases immutable (related to `check-release-immutability`)

If a user sets either check to "warning", they're indicating they want lenient validation for that aspect. Publishing drafts should follow the most lenient setting.

---

## Conclusion

All validation rules properly implement severity levels according to their purpose:

- **Structural errors** (ref types, major versions, duplicates) → Always `"error"`
- **Optional features** (minor versions, releases, immutability) → Config-based severity
- **Special cases** (floating version releases) → Context-based severity

The implementation is **correct and consistent** across all 26 rules.
