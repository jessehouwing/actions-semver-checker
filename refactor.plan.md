# Refactoring Plan: Rule Engine Implementation (Alternative 2)

## Overview

This plan describes the incremental migration from the current monolithic validation logic in `main.ps1` to a declarative rule-based validation engine. The goal is to improve maintainability, testability, and extensibility while preserving existing behavior.

**Key Principles:**
- Convert one validation type at a time
- Create new tests before removing old tests
- Separate rules by configuration context (tags vs branches)
- No breaking changes to external behavior

---

## Single-Pass Validation Design

### How It Works

All rules operate on the **same immutable state snapshot**. Rules don't depend on issues created by other rules - they only read current state. This ensures:

1. **No cascading dependencies** - Each rule independently evaluates conditions
2. **No duplicate issues** - Condition functions ensure mutual exclusivity
3. **Deterministic results** - Same state always produces same issues
4. **Parallelizable** - Rules could theoretically run concurrently

### Priority Field Purpose

The `Priority` field determines **remediation execution order**, NOT validation order:
- Priority 5 fixes run before Priority 20 fixes
- All rules validate in the same pass
- Example: Convert branch→tag (Priority 5) before updating tag SHA (Priority 20)

### Condition Design Principles

To avoid redundant issues, each rule's Condition must be **mutually exclusive** with related rules:

| "Exists" Rules | "Missing" Rules | Mutual Exclusivity |
|----------------|-----------------|-------------------|
| `major_tag_tracks_highest_patch` | `major_tag_missing` | Condition: `Tags where IsMajor` vs `MajorNumbers without Tags` |
| `minor_tag_tracks_highest_patch` | `minor_tag_missing` | Condition: `Tags where IsMinor` vs `MinorNumbers without Tags` |
| `release_should_be_published` | `patch_release_required` | Condition: `Releases where IsDraft` vs `Tags without Release` |

### State Snapshot Includes All Ref Types

Rules that look for "missing" items must check **both** Tags and Branches to find the source SHA:

```powershell
# Get all patch versions regardless of ref type
$allPatches = ($State.Tags + $State.Branches) | Where-Object { $_.IsPatch }
```

This ensures we correctly handle cases like:
- v1.0.0 exists as branch → Still use its SHA for "missing v1" calculation
- v1 exists as tag, v1.0.0 as branch → Both found, can compare SHAs

### Rule Coordination: Tag + Release Creation

**Scenario:** v1 exists, v1.0.0 doesn't exist, no release for v1.0.0

When both tag AND release are missing, we avoid duplicate issues through **rule coordination**:

| `check-releases` | `patch_tag_missing` | `patch_release_required` | Result |
|------------------|---------------------|--------------------------|--------|
| `none` | Creates tag issue | Skipped | Tag only ✓ |
| `error`/`warning` | **Skipped** | Creates release issue | Release (creates tag implicitly) ✓ |

**Why this works:** GitHub's release API creates the tag if it doesn't exist. So when releases are required, we let `CreateReleaseAction` handle both.

**Immutability handling:** When `check-release-immutability` is `error` or `warning`, `CreateReleaseAction` is configured with `shouldAutoPublish = true`, making the release immutable immediately.

```
Scenario: v1 → abc123 (tag exists)
          v1.0.0 (doesn't exist)
          No release for v1.0.0
          check-releases: error
          check-release-immutability: error

Rule: patch_tag_missing
  Condition: check-releases != "none" → SKIP ✓

Rule: patch_release_required  
  Condition: Expected patch v1.0.0 from v1 → [v1.0.0] ✓
  Issue: "v1.0.0 needs release"
  Action: CreateReleaseAction("v1.0.0", sha=abc123, autoPublish=true)
  
Result: 
  - Release v1.0.0 created (published, immutable)
  - Tag v1.0.0 created implicitly by GitHub
```

---

## Testing Responsibilities

This section clarifies where different types of tests belong, to avoid duplication and ensure proper separation of concerns.

### Infrastructure vs Rules Tests

| Responsibility | Tested In | NOT Tested In |
|----------------|-----------|---------------|
| Version parsing (e.g., `v1.0.0` → Major=1, Minor=0, Patch=0) | `tests/unit/VersionParser.Tests.ps1` | Rules tests |
| `ignore-versions` input parsing (JSON, CSV, newline formats) | `tests/unit/` or `tests/integration/` | Rules tests |
| Prerelease status from GitHub Release API | `tests/integration/` | Rules tests |
| API pagination | `tests/unit/GitHubApi.Tests.ps1` | Rules tests |
| HTTP error handling and retries | `tests/unit/GitHubApi.Tests.ps1` | Rules tests |

### Important: Prerelease Detection

**Prerelease status is determined by the GitHub Release `isPrerelease` property**, NOT by parsing version suffixes like `-beta` or `-rc`. This is a design decision based on GitHub's official API.

- `VersionRef` does NOT have an `IsPrerelease` property - GitHub Actions doesn't use semver labels
- `ReleaseInfo.IsPrerelease`: Directly from GitHub API response `prerelease` field
- Use `Test-IsPrerelease -State $State -VersionRef $ref` to check prerelease status by looking up the associated release
- Version suffixes like `v1.0.0-beta` are NOT automatically treated as prereleases

Rules tests should use `Test-IsPrerelease` helper or set up `ReleaseInfo` objects with the correct `IsPrerelease` flag.

### What Rules Tests SHOULD Test

Rules tests should focus on:

1. **Condition filtering** - Which items from state are returned for validation
2. **Check logic** - Pass/fail for various valid/invalid states
3. **Issue creation** - Correct type, severity, message, and remediation action
4. **Configuration sensitivity** - Rule is disabled when config says so
5. **Respecting `IsIgnored` flag** - Ignored items should be skipped
6. **Respecting `IsPrerelease` flag** - Preview items filtered when `Config.ignorePreviewReleases=$true`

### State Initialization (Before Rules Run)

The following are set on `VersionRef` and `ReleaseInfo` objects **before** rules are invoked:

| Property | Set By | Rules Responsibility |
|----------|--------|---------------------|
| `IsIgnored` | Input parsing + state init | Respect the flag (skip ignored refs) |
| `IsPrerelease` (ReleaseInfo) | GitHub Release API `prerelease` field | Use `Test-IsPrerelease` helper when `Config.ignorePreviewReleases=$true` |
| `IsPatch`, `IsMajor`, `IsMinor` | State initialization | Use as filters in Condition/Check |
| `Major`, `Minor`, `Patch` | `VersionParser.ps1` | Read-only usage in comparisons |

### Example: Testing Ignored Versions in Rules

Rules don't need to test parsing `"v1, v2\nv3"` → they assume `IsIgnored` is already set:

```powershell
# CORRECT: Test that rule respects IsIgnored flag
It "Should skip ignored versions" {
    $state = [RepositoryState]::new()
    $state.Tags += [VersionRef]@{ Version = "v1"; IsIgnored = $true; IsMajor = $true }
    $state.Tags += [VersionRef]@{ Version = "v2"; IsIgnored = $false; IsMajor = $true }
    
    $result = & $rule.Condition $state $config
    $result.Count | Should -Be 1
    $result[0].Version | Should -Be "v2"
}

# WRONG: Don't test input parsing in rules tests
It "Should parse comma-separated versions" {  # ← This belongs in integration tests!
    $env:inputs = '{"ignore-versions": "v1, v2"}'
    # ...
}
```

### Example: Testing Prerelease Handling in Rules

Rules test that prerelease filtering works via `Test-IsPrerelease` helper that looks up the release:

```powershell
# CORRECT: Test that rule filters prereleases when configured
It "Should exclude prereleases when ignore-preview-releases is true" {
    $state = [RepositoryState]::new()
    # Create tags (no IsPrerelease property on VersionRef)
    $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
    $state.Tags += [VersionRef]::new("v1.0.1", "refs/tags/v1.0.1", "def456", "tag")
    
    # Mark v1.0.1 as prerelease via its release
    $releaseData = [PSCustomObject]@{
        tag_name = "v1.0.1"
        id = 1
        draft = $false
        prerelease = $true  # This is how prerelease is set
        html_url = ""
        target_commitish = "def456"
    }
    $state.Releases += [ReleaseInfo]::new($releaseData)
    
    $config = @{ 'ignore-preview-releases' = $true }
    $highest = Get-HighestPatchForMajor -State $state -Major 1 -ExcludePrereleases $true
    
    $highest.Version | Should -Be "v1.0.0"  # prerelease excluded
}

# WRONG: Don't test prerelease detection in rules tests
It "Should detect beta suffix as prerelease" {  # ← This belongs in integration/state tests!
    # Prereleases are detected from GitHub Release API, not version suffix
}
```

### Required Prerelease Filtering Tests

**IMPORTANT**: Each rule that uses `Test-IsPrerelease` or calculates "highest patch" MUST have tests that:

1. Create `ReleaseInfo` objects with `IsPrerelease = $true` to verify filtering actually works
2. Test both `'ignore-preview-releases' = $true` (excludes prereleases) and `$false` (includes them)

Rules requiring prerelease filtering tests:

| Rule | Test Needed | Status |
|------|-------------|--------|
| `major_tag_tracks_highest_patch` | Prerelease excluded when calculating expected SHA | ✅ Done |
| `minor_tag_tracks_highest_patch` | Prerelease excluded when calculating expected SHA | ✅ Done |
| `major_branch_tracks_highest_patch` | Prerelease excluded when calculating expected SHA | ✅ Done |
| `minor_branch_tracks_highest_patch` | Prerelease excluded when calculating expected SHA | ✅ Done |
| `latest_tag_tracks_global_highest` | Prerelease excluded when calculating global highest | ✅ Done |
| `latest_branch_tracks_global_highest` | Prerelease excluded when calculating global highest | ✅ Done |
| `major_tag_missing` | CreateIssue should use non-prerelease SHA | ✅ Done |
| `minor_tag_missing` | CreateIssue should use non-prerelease SHA | ✅ Done |
| `major_branch_missing` | CreateIssue should use non-prerelease SHA | ✅ Done |
| `minor_branch_missing` | CreateIssue should use non-prerelease SHA | ✅ Done |
| `latest_tag_missing` | Should create with non-prerelease highest SHA | ✅ Done |
| `latest_branch_missing` | Should create with non-prerelease highest SHA | ✅ Done |

**Coverage Complete**: All 12 rules that use prerelease filtering now have appropriate tests in their "Prerelease Filtering" context.

---

## Rule File Structure

Each validation rule lives in its own folder with dedicated files for implementation, testing, and documentation.

**IMPORTANT**: Before implementing any rule, read [lib/rules/RULES_INSTRUCTIONS.md](lib/rules/RULES_INSTRUCTIONS.md) for:
- ValidationRule class structure and patterns
- Correct constructors for VersionRef, ReleaseInfo, ValidationIssue
- RemediationAction parameter signatures
- Common mistakes to avoid
- Test patterns

### Folder Structure

```
lib/
├── ValidationRules.ps1          # Base class, engine, and helper functions
├── rules/
│   ├── ref_type/
│   │   ├── branch_should_be_tag/
│   │   │   ├── branch_should_be_tag.ps1
│   │   │   ├── branch_should_be_tag.Tests.ps1
│   │   │   └── README.md
│   │   ├── tag_should_be_branch/
│   │   │   ├── tag_should_be_branch.ps1
│   │   │   ├── tag_should_be_branch.Tests.ps1
│   │   │   └── README.md
│   │   └── latest_wrong_ref_type/
│   │       ├── ...
│   ├── releases/
│   │   ├── patch_release_required/
│   │   │   ├── patch_release_required.ps1
│   │   │   ├── patch_release_required.Tests.ps1
│   │   │   └── README.md
│   │   ├── release_should_be_published/
│   │   │   ├── ...
│   │   ├── release_should_be_immutable/
│   │   │   ├── ...
│   │   └── floating_version_no_release/
│   │       ├── ...
│   ├── version_tracking/
│   │   ├── major_tag_tracks_highest_patch/
│   │   │   ├── ...
│   │   ├── major_tag_missing/
│   │   │   ├── ...
│   │   ├── minor_tag_tracks_highest_patch/
│   │   │   ├── ...
│   │   ├── minor_tag_missing/
│   │   │   ├── ...
│   │   ├── patch_tag_missing/
│   │   │   ├── ...
│   │   ├── major_branch_tracks_highest_patch/
│   │   │   ├── ...
│   │   ├── major_branch_missing/
│   │   │   ├── ...
│   │   ├── minor_branch_tracks_highest_patch/
│   │   │   ├── ...
│   │   └── minor_branch_missing/
│   │       ├── ...
│   └── latest/
│       ├── latest_tag_tracks_global_highest/
│       │   ├── ...
│       ├── latest_tag_missing/
│       │   ├── ...
│       ├── latest_branch_tracks_global_highest/
│       │   ├── ...
│       └── latest_branch_missing/
│           ├── ...
```

### Rule File Template: `{rule_name}.ps1`

```powershell
#############################################################################
# Rule: {rule_name}
# Category: {category}
# Priority: {priority}
#############################################################################

$Rule_{RuleName} = [ValidationRule]@{
    Name = "{rule_name}"
    Description = "{description}"
    Category = "{category}"
    Priority = {priority}
    Condition = {
        param($State, $Config)
        # Return items to validate
    }
    Check = {
        param($Item, $State, $Config)
        # Return $true if valid, $false if issue
    }
    CreateIssue = {
        param($Item, $State, $Config)
        # Create and return ValidationIssue
    }
}

# Export the rule
$Rule_{RuleName}
```

### Rule Test Template: `{rule_name}.Tests.ps1`

```powershell
#############################################################################
# Tests for Rule: {rule_name}
#############################################################################

BeforeAll {
    . "$PSScriptRoot/../../../../lib/StateModel.ps1"
    . "$PSScriptRoot/../../../../lib/ValidationRules.ps1"
    . "$PSScriptRoot/{rule_name}.ps1"
}

Describe "{rule_name}" {
    Context "Condition" {
        It "Should return items when rule applies" {
            # Test condition logic
        }
        
        It "Should return empty when rule does not apply" {
            # Test condition skips correctly
        }
    }
    
    Context "Check" {
        It "Should return true when valid" {
            # Test passing case
        }
        
        It "Should return false when invalid" {
            # Test failing case
        }
    }
    
    Context "CreateIssue" {
        It "Should create issue with correct type" {
            # Test issue creation
        }
        
        It "Should set correct remediation action" {
            # Test remediation action
        }
    }
}
```

### Rule README Template: `README.md`

Each rule folder contains a README.md that explains:

1. **What the rule checks** - The validation being performed
2. **Why this is an issue** - Impact on users of the action
3. **When this rule applies** - Configuration conditions
4. **Manual remediation** - How to fix without auto-fix
5. **Related rules** - Other rules that may interact

**Template:**

```markdown
# Rule: {rule_name}

## What This Rule Checks

{Description of what the rule validates}

## Why This Is An Issue

{Explanation of why this matters for GitHub Actions users}

- **Impact:** {What happens if not fixed}
- **Best Practice:** {What the correct state should be}

## When This Rule Applies

This rule runs when:
- {Configuration condition 1}
- {Configuration condition 2}

## Configuration

| Input | Required Value | Description |
|-------|----------------|-------------|
| `floating-versions-use` | `tags` | {explanation} |
| `check-releases` | `error` or `warning` | {explanation} |

## Manual Remediation

If auto-fix is not enabled or fails, you can manually fix this issue:

### Using GitHub CLI

\`\`\`bash
{gh command}
\`\`\`

### Using Git

\`\`\`bash
{git command}
\`\`\`

### Using GitHub Web UI

1. Navigate to {location}
2. {Step 2}
3. {Step 3}

## Related Rules

- [`{related_rule_1}`](../related_rule_1/README.md) - {relationship}
- [`{related_rule_2}`](../related_rule_2/README.md) - {relationship}

## Examples

### Failing Scenario

{Description of a scenario that triggers this rule}

### Passing Scenario

{Description of a correct setup}
```

### Rule Loading

The engine loads all rules from the folder structure:

```powershell
function Get-AllValidationRules {
    $rules = @()
    $rulesFolderPath = "$PSScriptRoot/rules"
    
    # Recursively find all rule .ps1 files (not .Tests.ps1)
    $ruleFiles = Get-ChildItem -Path $rulesFolderPath -Recurse -Filter "*.ps1" |
        Where-Object { $_.Name -notmatch '\.Tests\.ps1$' }
    
    foreach ($file in $ruleFiles) {
        $rule = . $file.FullName
        if ($rule -is [ValidationRule]) {
            $rules += $rule
        }
    }
    
    return $rules | Sort-Object Priority
}
```

---

## Phase 0: Infrastructure Setup

### 0.1 Create ValidationRule Class

**File:** `lib/ValidationRules.ps1`

```powershell
class ValidationRule {
    [string]$Name              # Unique identifier (e.g., "patch_release_required")
    [string]$Description       # Human-readable description
    [int]$Priority             # Lower = runs first (for dependency ordering)
    [string]$Category          # Grouping: "ref_type", "version_tracking", "releases"
    [scriptblock]$Condition    # Returns items to validate
    [scriptblock]$Check        # Returns $true if valid
    [scriptblock]$CreateIssue  # Creates ValidationIssue if check fails
}
```

### 0.2 Create Rule Engine Functions

**File:** `lib/ValidationRules.ps1`

```powershell
function Invoke-ValidationRules {
    param(
        [RepositoryState]$State,
        [hashtable]$Config,
        [ValidationRule[]]$Rules
    )
    # Execute rules in priority order
}

function Get-ValidationRules {
    param([hashtable]$Config)
    # Returns filtered ruleset based on configuration
}
```

### 0.3 Create Helper Functions

**File:** `lib/ValidationRules.ps1`

```powershell
function Get-HighestPatchForMajor {
    param([RepositoryState]$State, [int]$Major, [bool]$ExcludePrereleases)
}

function Get-HighestPatchForMinor {
    param([RepositoryState]$State, [int]$Major, [int]$Minor, [bool]$ExcludePrereleases)
}

function Get-HighestMinorForMajor {
    param([RepositoryState]$State, [int]$Major, [bool]$ExcludePrereleases)
}
```

### 0.4 Create Test Infrastructure

**File:** `tests/unit/ValidationRules.Tests.ps1`

- Test harness for rule execution
- Mock state builder helpers
- Config builder helpers

**Deliverables:**
- [x] `lib/ValidationRules.ps1` with base classes and engine
- [x] `tests/unit/ValidationRules.Tests.ps1` with infrastructure
- [x] All existing tests still pass

**Status:** ✅ **COMPLETE** - Phase 0 infrastructure is implemented and tested

---

## Phase 1: Ref Type Validation Rules

**Status:** ✅ **COMPLETE** - All 5 rules implemented with 67 passing tests

These rules run **first** (Priority 5-10) because they may convert refs before other validations.

### 1.1 Rule: `branch_should_be_tag` (Priority: 5)

**Status:** ✅ **COMPLETE** - 14 tests passing

**Applies when:** `floating-versions-use: tags` (default)

**Condition:** All branches that are floating versions (vX, vX.Y) or patch versions (vX.Y.Z)

**Check:** Branch exists but corresponding tag does not exist (if both exist, let duplicate rule handle it)

**Issue Type:** `wrong_ref_type`

**Remediation:** `ConvertBranchToTagAction`

```powershell
[ValidationRule]@{
    Name = "branch_should_be_tag"
    Category = "ref_type"
    Priority = 5
    Condition = {
        param($State, $Config)
        if ($Config.useBranches) { return @() }
        $State.Branches | Where-Object { 
            -not $_.IsIgnored -and ($_.IsPatch -or $_.IsMajor -or $_.IsMinor)
        }
    }
    Check = { param($Item, $State, $Config) $false }  # Always fails - branch exists
    CreateIssue = {
        param($Item, $State, $Config)
        $msg = if ($Item.IsPatch) {
            "Patch version $($Item.Version) is a branch but should be a tag"
        } else {
            "Floating version $($Item.Version) is a branch but should be a tag"
        }
        $issue = [ValidationIssue]::new("wrong_ref_type", "error", $msg)
        $issue.Version = $Item.Version
        $issue.SetRemediationAction([ConvertBranchToTagAction]::new($Item.Version, $Item.Sha))
        return $issue
    }
}
```

**Tests:**
- [x] Patch branch (v1.0.0 as branch) → should create issue
- [x] Major branch (v1 as branch) → should create issue
- [x] Minor branch (v1.0 as branch) → should create issue
- [x] Ignored version → should skip
- [x] With `floating-versions-use: branches` → rule should not apply

---

### 1.2 Rule: `tag_should_be_branch` (Priority: 5)

**Status:** ✅ **COMPLETE** - 14 tests passing

**Applies when:** `floating-versions-use: branches`

**Condition:** All tags that are floating versions (vX, vX.Y) - NOT patch versions

**Check:** Tag exists but corresponding branch does not exist (if both exist, let duplicate rule handle it)

**Issue Type:** `wrong_ref_type`

**Remediation:** `ConvertTagToBranchAction`

```powershell
[ValidationRule]@{
    Name = "tag_should_be_branch"
    Category = "ref_type"
    Priority = 5
    Condition = {
        param($State, $Config)
        if (-not $Config.useBranches) { return @() }
        $State.Tags | Where-Object { 
            -not $_.IsIgnored -and ($_.IsMajor -or $_.IsMinor)
        }
    }
    Check = { param($Item, $State, $Config) $false }
    CreateIssue = {
        param($Item, $State, $Config)
        $issue = [ValidationIssue]::new("wrong_ref_type", "error", 
            "Floating version $($Item.Version) is a tag but should be a branch")
        $issue.Version = $Item.Version
        $issue.SetRemediationAction([ConvertTagToBranchAction]::new($Item.Version, $Item.Sha))
        return $issue
    }
}
```

**Tests:**
- [x] Major tag (v1) with branches mode → should create issue
- [x] Minor tag (v1.0) with branches mode → should create issue
- [x] Patch tag (v1.0.0) with branches mode → should NOT create issue (patches are always tags)
- [x] Ignored version → should skip
- [x] With `floating-versions-use: tags` → rule should not apply

---

### 1.3 Rule: `duplicate_floating_version_ref` (Priority: 6)

**Status:** ✅ **COMPLETE** - 14 tests passing

**Applies when:** Both a tag AND branch exist for the same floating version (vX or vX.Y)

**Condition:** Floating versions that exist as both tag and branch simultaneously

**Check:** Only one ref type should exist per floating version

**Issue Type:** `duplicate_ref`

**Remediation:** 
- If `floating-versions-use: tags`: `DeleteBranchAction` (keep tag)
- If `floating-versions-use: branches`: `DeleteTagAction` (keep branch)

**Note:** This rule specifically handles the case where both ref types exist simultaneously. The `branch_should_be_tag` and `tag_should_be_branch` rules will pass (skip) when they detect both ref types exist, deferring to this duplicate rule. This separation ensures each rule has a single responsibility: conversion (when only wrong type exists) vs. duplicate cleanup (when both exist).

```powershell
[ValidationRule]@{
    Name = "duplicate_floating_version_ref"
    Category = "ref_type"
    Priority = 6  # Run after convert rules
    Condition = {
        param($State, $Config)
        $results = @()
        
        # Find floating versions that exist as both tag and branch
        $floatingTags = $State.Tags | Where-Object { 
            -not $_.IsIgnored -and ($_.IsMajor -or $_.IsMinor) -and $_.Version -ne "latest"
        }
        
        foreach ($tag in $floatingTags) {
            $matchingBranch = $State.Branches | Where-Object { $_.Version -eq $tag.Version }
            if ($matchingBranch) {
                $results += [PSCustomObject]@{
                    Version = $tag.Version
                    TagSha = $tag.Sha
                    BranchSha = $matchingBranch.Sha
                    UseBranches = $Config.useBranches
                }
            }
        }
        
        return $results
    }
    Check = { param($Item, $State, $Config) $false }  # Always fails - duplicate exists
    CreateIssue = {
        param($Item, $State, $Config)
        $keepType = if ($Config.useBranches) { "branch" } else { "tag" }
        $deleteType = if ($Config.useBranches) { "tag" } else { "branch" }
        
        $issue = [ValidationIssue]::new("duplicate_ref", "error",
            "Floating version $($Item.Version) exists as both tag and branch - keeping $keepType, deleting $deleteType")
        $issue.Version = $Item.Version
        
        if ($Config.useBranches) {
            # Keep branch, delete tag
            $issue.SetRemediationAction([DeleteTagAction]::new($Item.Version))
        } else {
            # Keep tag, delete branch
            $issue.SetRemediationAction([DeleteBranchAction]::new($Item.Version))
        }
        
        return $issue
    }
}
```

**Tests:**
- [x] v1 exists as both tag and branch, tags mode → should delete branch (keep tag)
- [x] v1 exists as both tag and branch, branches mode → should delete tag (keep branch)
- [x] v1.0 exists as both tag and branch → same behavior
- [x] Only tag exists → should pass (not a duplicate)
- [x] Only branch exists → should pass (not a duplicate)
- [x] Patch version as both → handled by branch_should_be_tag rule (patches must be tags)
- [x] "latest" as both → handled by latest_wrong_ref_type rule

---

### 1.4 Rule: `duplicate_latest_ref` (Priority: 6)

**Status:** ✅ **COMPLETE** - 13 tests passing

**Applies when:** Both a "latest" tag AND "latest" branch exist

**Condition:** "latest" exists as both tag and branch simultaneously

**Check:** Only one ref type should exist for "latest"

**Issue Type:** `duplicate_latest_ref`

**Remediation:** 
- If `floating-versions-use: tags`: `DeleteBranchAction` (keep tag)
- If `floating-versions-use: branches`: `DeleteTagAction` (keep branch)

```powershell
[ValidationRule]@{
    Name = "duplicate_latest_ref"
    Category = "ref_type"
    Priority = 6
    Condition = {
        param($State, $Config)
        $latestTag = $State.Tags | Where-Object { $_.Version -eq "latest" }
        $latestBranch = $State.Branches | Where-Object { $_.Version -eq "latest" }
        
        if ($latestTag -and $latestBranch) {
            return @([PSCustomObject]@{
                TagSha = $latestTag.Sha
                BranchSha = $latestBranch.Sha
                UseBranches = $Config.useBranches
            })
        }
        return @()
    }
    Check = { param($Item, $State, $Config) $false }
    CreateIssue = {
        param($Item, $State, $Config)
        $keepType = if ($Config.useBranches) { "branch" } else { "tag" }
        $deleteType = if ($Config.useBranches) { "tag" } else { "branch" }
        
        $issue = [ValidationIssue]::new("duplicate_latest_ref", "error",
            "'latest' exists as both tag and branch - keeping $keepType, deleting $deleteType")
        $issue.Version = "latest"
        
        if ($Config.useBranches) {
            $issue.SetRemediationAction([DeleteTagAction]::new("latest"))
        } else {
            $issue.SetRemediationAction([DeleteBranchAction]::new("latest"))
        }
        
        return $issue
    }
}
```

**Tests:**
- [x] latest exists as both tag and branch, tags mode → should delete branch
- [x] latest exists as both tag and branch, branches mode → should delete tag
- [x] Only latest tag exists → should pass
- [x] Only latest branch exists → should pass

---

### 1.5 Rule: `duplicate_patch_version_ref` (Priority: 6)

**Status:** ✅ **COMPLETE** - 12 tests passing

**Applies when:** A patch version (vX.Y.Z) exists as both a tag and a branch

**Condition:** Patch versions that exist as both tag and branch simultaneously

**Check:** Only tag should exist for patches (always returns false if both exist)

**Issue Type:** `duplicate_patch_ref`

**Remediation:** `DeleteBranchAction` (always delete branch, patches must be tags)

**Note:** Unlike floating versions, patch versions **always** use tags regardless of `floating-versions-use` configuration. This is because patches must be immutable and linked to GitHub Releases. If both a tag and branch exist for a patch version, the branch is always deleted.

```powershell
[ValidationRule]@{
    Name = "duplicate_patch_version_ref"
    Category = "ref_type"
    Priority = 6
    Condition = {
        param($State, $Config)
        # Find patch versions that exist as both tag and branch
        $patchTags = $State.Tags | Where-Object { 
            -not $_.IsIgnored -and $_.IsPatch
        }
        foreach ($tag in $patchTags) {
            $matchingBranch = $State.Branches | Where-Object {
                $_.Version -eq $tag.Version -and -not $_.IsIgnored
            }
            if ($matchingBranch) {
                # Return hashtable with both refs
                yield @{
                    Version = $tag.Version
                    Tag = $tag
                    Branch = $matchingBranch
                }
            }
        }
    }
    Check = { param($Item, $State, $Config) $false }
    CreateIssue = {
        param($Item, $State, $Config)
        $issue = [ValidationIssue]::new("duplicate_patch_ref", "error",
            "Patch version '$($Item.Version)' exists as both tag and branch - branch will be deleted (patches must be tags)")
        $issue.Version = $Item.Version
        $issue.SetRemediationAction([DeleteBranchAction]::new($Item.Version))
        return $issue
    }
}
```

**Tests:**
- [x] Patch version exists as both tag and branch → should delete branch
- [x] Only tag exists → should pass
- [x] Only branch exists → handled by branch_should_be_tag rule
- [x] Ignored versions → should skip
- [x] Multiple duplicate patches → creates multiple issues
- [x] Floating versions → not handled by this rule
- [x] Works regardless of floating-versions-use setting → always deletes branch

---

## Phase 2: Release Validation Rules

**Status:** ✅ **COMPLETE** - All 4 rules implemented (48 tests passing)

These rules validate GitHub Releases (Priority 10-20).

### 2.1 Rule: `patch_release_required` (Priority: 10)

**Status:** ✅ **COMPLETE** - 13 tests passing

**Applies when:** `check-releases: error|warning`

**Condition:** All patch version tags (vX.Y.Z)

**Check:** Release exists for this tag

**Issue Type:** `missing_release`

**Remediation:** `CreateReleaseAction`

```powershell
[ValidationRule]@{
    Name = "patch_release_required"
    Category = "releases"
    Priority = 10
    Condition = {
        param($State, $Config)
        if ($Config.checkReleases -eq "none") { return @() }
        $State.Tags | Where-Object { $_.IsPatch -and -not $_.IsIgnored }
    }
    Check = {
        param($Item, $State, $Config)
        $release = $State.Releases | Where-Object { $_.TagName -eq $Item.Version }
        return $null -ne $release
    }
    CreateIssue = {
        param($Item, $State, $Config)
        $severity = $Config.checkReleases
        $issue = [ValidationIssue]::new("missing_release", $severity,
            "Version $($Item.Version) does not have a GitHub Release")
        $issue.Version = $Item.Version
        $shouldPublish = ($Config.checkImmutability -ne "none")
        $issue.SetRemediationAction([CreateReleaseAction]::new($Item.Version, $true, $shouldPublish))
        return $issue
    }
}
```

**Tests:**
- [x] Patch tag without release → should create issue
- [x] Patch tag with release → should pass
- [x] Ignored version → should skip
- [x] `check-releases: none` → rule should not apply
- [x] `check-releases: warning` → issue severity is warning
- [x] `check-release-immutability: error` → CreateReleaseAction should auto-publish

---

### 2.2 Rule: `release_should_be_published` (Priority: 11)

**Status:** ✅ **COMPLETE** - 11 tests passing

**Applies when:** `check-release-immutability: error|warning`

**Condition:** All releases for patch versions that are drafts

**Check:** Release is not a draft

**Issue Type:** `draft_release`

**Remediation:** `PublishReleaseAction`

```powershell
[ValidationRule]@{
    Name = "release_should_be_published"
    Category = "releases"
    Priority = 11
    Condition = {
        param($State, $Config)
        if ($Config.checkImmutability -eq "none") { return @() }
        $State.Releases | Where-Object { 
            $_.TagName -match "^v\d+\.\d+\.\d+$" -and 
            -not $_.IsIgnored -and
            $_.IsDraft
        }
    }
    Check = { param($Item, $State, $Config) $false }  # Condition already filters drafts
    CreateIssue = {
        param($Item, $State, $Config)
        $severity = $Config.checkImmutability
        $issue = [ValidationIssue]::new("draft_release", $severity,
            "Release $($Item.TagName) is still in draft status, publish it.")
        $issue.Version = $Item.TagName
        $issue.SetRemediationAction([PublishReleaseAction]::new($Item.TagName, $Item.Id))
        return $issue
    }
}
```

**Tests:**
- [x] Draft release for patch version → should create issue
- [x] Published release → should pass
- [x] Draft release for floating version → should NOT apply (different rule)
- [x] `check-release-immutability: none` → rule should not apply

---

### 2.3 Rule: `release_should_be_immutable` (Priority: 12)

**Status:** ✅ **COMPLETE** - 12 tests passing

**Applies when:** `check-release-immutability: error|warning`

**Condition:** All published (non-draft) releases for patch versions

**Check:** Release has `immutable: true` via GraphQL API

**Issue Type:** `non_immutable_release`

**Remediation:** `RepublishReleaseAction`

```powershell
[ValidationRule]@{
    Name = "release_should_be_immutable"
    Category = "releases"
    Priority = 12
    Condition = {
        param($State, $Config)
        if ($Config.checkImmutability -eq "none") { return @() }
        $State.Releases | Where-Object { 
            $_.TagName -match "^v\d+\.\d+\.\d+$" -and 
            -not $_.IsIgnored -and
            -not $_.IsDraft
        }
    }
    Check = {
        param($Item, $State, $Config)
        # Note: Need to call Test-ReleaseImmutability here or cache result
        return $Item.IsImmutable
    }
    CreateIssue = {
        param($Item, $State, $Config)
        $issue = [ValidationIssue]::new("non_immutable_release", "warning",
            "Release $($Item.TagName) is published but remains mutable")
        $issue.Version = $Item.TagName
        $issue.SetRemediationAction([RepublishReleaseAction]::new($Item.TagName))
        return $issue
    }
}
```

**Tests:**
- [x] Published release that is not immutable → should create warning
- [x] Published release that is immutable → should pass
- [x] Draft release → should NOT apply (different rule handles drafts)

---

### 2.4 Rule: `floating_version_no_release` (Priority: 15)

**Status:** ✅ **COMPLETE** - 12 tests passing

**Applies when:** `check-releases: error|warning` OR `check-release-immutability: error|warning`

**Condition:** All releases for floating versions (vX, vX.Y, latest)

**Check:** Release should NOT exist for floating versions

**Issue Type:** `mutable_floating_release` or `immutable_floating_release`

**Remediation:** `DeleteReleaseAction` (if mutable) or mark unfixable (if immutable)

```powershell
[ValidationRule]@{
    Name = "floating_version_no_release"
    Category = "releases"
    Priority = 15
    Condition = {
        param($State, $Config)
        if ($Config.checkReleases -eq "none" -and $Config.checkImmutability -eq "none") { 
            return @() 
        }
        $State.Releases | Where-Object { 
            -not $_.IsIgnored -and
            ($_.TagName -match "^v\d+$" -or $_.TagName -match "^v\d+\.\d+$" -or $_.TagName -eq "latest")
        }
    }
    Check = { param($Item, $State, $Config) $false }  # Floating releases should not exist
    CreateIssue = {
        param($Item, $State, $Config)
        if ($Item.IsImmutable) {
            $issue = [ValidationIssue]::new("immutable_floating_release", "error",
                "Floating version $($Item.TagName) has an immutable release - cannot be auto-fixed")
            $issue.Version = $Item.TagName
            $issue.Status = "unfixable"
        } else {
            $issue = [ValidationIssue]::new("mutable_floating_release", "warning",
                "Floating version $($Item.TagName) has a mutable release, which should be removed")
            $issue.Version = $Item.TagName
            $issue.SetRemediationAction([DeleteReleaseAction]::new($Item.TagName, $Item.Id))
        }
        return $issue
    }
}
```

**Tests:**
- [x] Mutable release for major version (v1) → should create warning with delete action
- [x] Mutable release for minor version (v1.0) → should create warning with delete action
- [x] Mutable release for "latest" → should create warning with delete action
- [x] Immutable release for floating version → should create unfixable error
- [x] Both checks disabled → rule should not apply

---

## Phase 3: Version Tracking Rules (Tags Mode)

**Status:** ✅ **COMPLETE** - All 5 rules implemented (68 tests passing)

These rules validate that floating versions point to correct patches (Priority 20-30).

### 3.1 Rule: `major_tag_tracks_highest_patch` (Priority: 20)

**Status:** ✅ **COMPLETE** - 13 tests passing

**Applies when:** `floating-versions-use: tags` (default)

**Condition:** All major version tags (vX) that exist

**Check:** Tag points to same SHA as highest patch (vX.Y.Z)

**Issue Type:** `incorrect_version`

**Remediation:** `UpdateTagAction`

```powershell
[ValidationRule]@{
    Name = "major_tag_tracks_highest_patch"
    Category = "version_tracking"
    Priority = 20
    Condition = {
        param($State, $Config)
        if ($Config.useBranches) { return @() }
        $State.Tags | Where-Object { $_.IsMajor -and -not $_.IsIgnored }
    }
    Check = {
        param($Item, $State, $Config)
        $highestPatch = Get-HighestPatchForMajor -State $State -Major $Item.Major `
            -ExcludePrereleases $Config.ignorePreviewReleases
        if (-not $highestPatch) { return $true }  # No patches to track
        return ($Item.Sha -eq $highestPatch.Sha)
    }
    CreateIssue = {
        param($Item, $State, $Config)
        $highestPatch = Get-HighestPatchForMajor -State $State -Major $Item.Major `
            -ExcludePrereleases $Config.ignorePreviewReleases
        $issue = [ValidationIssue]::new("incorrect_version", "error",
            "v$($Item.Major) ref $($Item.Sha) must match $($highestPatch.Version) ref $($highestPatch.Sha)")
        $issue.Version = "v$($Item.Major)"
        $issue.CurrentSha = $Item.Sha
        $issue.ExpectedSha = $highestPatch.Sha
        $issue.SetRemediationAction([UpdateTagAction]::new("v$($Item.Major)", $highestPatch.Sha, $true))
        return $issue
    }
}
```

**Tests:**
- [x] Major tag pointing to wrong SHA → should create issue with UpdateTagAction
- [x] Major tag pointing to correct SHA → should pass
- [x] Major tag with no patch versions → should pass (nothing to track)
- [x] Prerelease handling with ignore-preview-releases
- [x] `floating-versions-use: branches` → rule should not apply

---

### 3.2 Rule: `major_tag_missing` (Priority: 21)

**Status:** ✅ **COMPLETE** - 11 tests passing

**Applies when:** `floating-versions-use: tags`

**Condition:** All unique major versions that have at least one patch

**Check:** Major tag (vX) exists

**Issue Type:** `missing_major_version`

**Remediation:** `CreateTagAction`

```powershell
[ValidationRule]@{
    Name = "major_tag_missing"
    Category = "version_tracking"
    Priority = 21
    Condition = {
        param($State, $Config)
        if ($Config.useBranches) { return @() }
        # Get all unique major versions from patches
        $majorNumbers = $State.GetPatchVersions() | 
            Where-Object { -not $_.IsIgnored } |
            ForEach-Object { $_.Major } | 
            Select-Object -Unique
        # Return those that don't have a major tag
        $majorNumbers | ForEach-Object {
            $major = $_
            $exists = $State.Tags | Where-Object { $_.Version -eq "v$major" }
            if (-not $exists) {
                [PSCustomObject]@{ Major = $major }
            }
        }
    }
    Check = { param($Item, $State, $Config) $false }  # Condition already filters missing
    CreateIssue = {
        param($Item, $State, $Config)
        $highestPatch = Get-HighestPatchForMajor -State $State -Major $Item.Major `
            -ExcludePrereleases $Config.ignorePreviewReleases
        $issue = [ValidationIssue]::new("missing_major_version", "error",
            "v$($Item.Major) does not exist and must match $($highestPatch.Version)")
        $issue.Version = "v$($Item.Major)"
        $issue.ExpectedSha = $highestPatch.Sha
        $issue.SetRemediationAction([CreateTagAction]::new("v$($Item.Major)", $highestPatch.Sha))
        return $issue
    }
}
```

**Tests:**
- [x] Missing major tag with existing patch → should create issue
- [x] Existing major tag → should pass (not in condition output)
- [x] All patches ignored → should not create issue

---

### 3.3 Rule: `minor_tag_tracks_highest_patch` (Priority: 22)

**Status:** ✅ **COMPLETE** - 14 tests passing

**Applies when:** `floating-versions-use: tags` AND `check-minor-version: error|warning`

**Condition:** All minor version tags (vX.Y) that exist

**Check:** Tag points to same SHA as highest patch (vX.Y.Z)

**Issue Type:** `incorrect_minor_version`

**Remediation:** `UpdateTagAction`

```powershell
[ValidationRule]@{
    Name = "minor_tag_tracks_highest_patch"
    Category = "version_tracking"
    Priority = 22
    Condition = {
        param($State, $Config)
        if ($Config.useBranches) { return @() }
        if ($Config.checkMinorVersion -eq "none") { return @() }
        $State.Tags | Where-Object { $_.IsMinor -and -not $_.IsIgnored }
    }
    Check = {
        param($Item, $State, $Config)
        $highestPatch = Get-HighestPatchForMinor -State $State `
            -Major $Item.Major -Minor $Item.Minor `
            -ExcludePrereleases $Config.ignorePreviewReleases
        if (-not $highestPatch) { return $true }
        return ($Item.Sha -eq $highestPatch.Sha)
    }
    CreateIssue = {
        param($Item, $State, $Config)
        $highestPatch = Get-HighestPatchForMinor -State $State `
            -Major $Item.Major -Minor $Item.Minor `
            -ExcludePrereleases $Config.ignorePreviewReleases
        $severity = $Config.checkMinorVersion
        $issue = [ValidationIssue]::new("incorrect_minor_version", $severity,
            "v$($Item.Major).$($Item.Minor) must match $($highestPatch.Version)")
        $issue.Version = "v$($Item.Major).$($Item.Minor)"
        $issue.CurrentSha = $Item.Sha
        $issue.ExpectedSha = $highestPatch.Sha
        $issue.SetRemediationAction([UpdateTagAction]::new($issue.Version, $highestPatch.Sha, $true))
        return $issue
    }
}
```

**Tests:**
- [x] Minor tag pointing to wrong SHA → should create issue
- [x] Minor tag pointing to correct SHA → should pass
- [x] `check-minor-version: none` → rule should not apply
- [x] `check-minor-version: warning` → issue severity is warning

---

### 3.4 Rule: `minor_tag_missing` (Priority: 23)

**Status:** ✅ **COMPLETE** - 14 tests passing

**Applies when:** `floating-versions-use: tags` AND `check-minor-version: error|warning`

**Condition:** All unique major.minor versions that have patches but no minor tag

**Check:** Minor tag (vX.Y) exists

**Issue Type:** `missing_minor_version`

**Remediation:** `CreateTagAction`

**Tests:**
- [x] Missing minor tag with existing patch → should create issue
- [x] `check-minor-version: none` → rule should not apply

---

### 3.5 Rule: `patch_tag_missing` (Priority: 25)

**Status:** ✅ **COMPLETE** - 16 tests passing

**Applies when:** `check-releases: none` (otherwise release creation handles tag)

**Condition:** Floating versions (vX, vX.Y) that exist but have no corresponding patch version

**Check:** At least one patch exists for the floating version

**Issue Type:** `missing_patch_version`

**Remediation:** `CreateTagAction`

**Note:** When `check-releases` is enabled, this rule is SKIPPED because the `patch_release_required` rule will create both the release AND the tag (GitHub creates tags implicitly when creating releases).

```powershell
[ValidationRule]@{
    Name = "patch_tag_missing"
    Category = "version_tracking"
    Priority = 25
    Condition = {
        param($State, $Config)
        # If releases are required, the release creation will also create the tag
        # So only create tag-only issues when releases are NOT being checked
        if ($Config.checkReleases -ne "none") { return @() }
        
        # Find major versions without any patches
        $allVersions = $State.Tags + $State.Branches
        $majorsWithoutPatches = @()
        
        $majorVersions = $allVersions | Where-Object { $_.IsMajor -and -not $_.IsIgnored }
        foreach ($major in $majorVersions) {
            $hasAnyPatch = $allVersions | Where-Object { 
                $_.IsPatch -and $_.Major -eq $major.Major 
            }
            if (-not $hasAnyPatch) {
                $majorsWithoutPatches += [PSCustomObject]@{
                    Version = "v$($major.Major).0.0"
                    SourceVersion = $major.Version
                    Sha = $major.Sha
                    Major = $major.Major
                }
            }
        }
        
        # Also check minors without patches (when check-minor-version is enabled)
        if ($Config.checkMinorVersion -ne "none") {
            $minorVersions = $allVersions | Where-Object { $_.IsMinor -and -not $_.IsIgnored }
            foreach ($minor in $minorVersions) {
                $hasAnyPatch = $allVersions | Where-Object { 
                    $_.IsPatch -and $_.Major -eq $minor.Major -and $_.Minor -eq $minor.Minor
                }
                if (-not $hasAnyPatch) {
                    # Check if already covered by major
                    $alreadyCovered = $majorsWithoutPatches | Where-Object { 
                        $_.Major -eq $minor.Major 
                    }
                    if (-not $alreadyCovered) {
                        $majorsWithoutPatches += [PSCustomObject]@{
                            Version = "v$($minor.Major).$($minor.Minor).0"
                            SourceVersion = $minor.Version
                            Sha = $minor.Sha
                            Major = $minor.Major
                        }
                    }
                }
            }
        }
        
        return $majorsWithoutPatches
    }
    Check = { param($Item, $State, $Config) $false }  # Condition already filters
    CreateIssue = {
        param($Item, $State, $Config)
        $issue = [ValidationIssue]::new("missing_patch_version", "error",
            "Version $($Item.Version) does not exist and must match $($Item.SourceVersion) ref $($Item.Sha)")
        $issue.Version = $Item.Version
        $issue.ExpectedSha = $Item.Sha
        $issue.SetRemediationAction([CreateTagAction]::new($Item.Version, $Item.Sha))
        return $issue
    }
}
```

**Tests:**
- [x] Major tag (v1) with no patches, `check-releases: none` → should create tag issue
- [x] Major tag (v1) with no patches, `check-releases: error` → should NOT create issue (release rule handles it)
- [x] Minor tag (v1.0) with no patches → should suggest creating v1.0.0
- [x] Draft release exists for patch → should skip (release publish will create tag)

---

## Phase 4: Version Tracking Rules (Branches Mode)

**Status:** ✅ **COMPLETE** - All 4 rules implemented (56 tests passing)

Mirror of Phase 3 but for branches. Only floating versions use branches; patches remain tags.

### 4.1 Rule: `major_branch_tracks_highest_patch` (Priority: 20)

**Status:** ✅ **COMPLETE** - 13 tests passing

**Applies when:** `floating-versions-use: branches`

**Condition:** All major version branches (vX) that exist

**Check:** Branch points to same SHA as highest patch (vX.Y.Z)

**Issue Type:** `incorrect_version`

**Remediation:** `UpdateBranchAction`

```powershell
[ValidationRule]@{
    Name = "major_branch_tracks_highest_patch"
    Category = "version_tracking"
    Priority = 20
    Condition = {
        param($State, $Config)
        if (-not $Config.useBranches) { return @() }
        $State.Branches | Where-Object { $_.IsMajor -and -not $_.IsIgnored }
    }
    Check = {
        param($Item, $State, $Config)
        $highestPatch = Get-HighestPatchForMajor -State $State -Major $Item.Major `
            -ExcludePrereleases $Config.ignorePreviewReleases
        if (-not $highestPatch) { return $true }  # No patches to track
        return ($Item.Sha -eq $highestPatch.Sha)
    }
    CreateIssue = {
        param($Item, $State, $Config)
        $highestPatch = Get-HighestPatchForMajor -State $State -Major $Item.Major `
            -ExcludePrereleases $Config.ignorePreviewReleases
        $issue = [ValidationIssue]::new("incorrect_version", "error",
            "v$($Item.Major) (branch) ref $($Item.Sha) must match $($highestPatch.Version) ref $($highestPatch.Sha)")
        $issue.Version = "v$($Item.Major)"
        $issue.CurrentSha = $Item.Sha
        $issue.ExpectedSha = $highestPatch.Sha
        $issue.SetRemediationAction([UpdateBranchAction]::new("v$($Item.Major)", $highestPatch.Sha, $true))
        return $issue
    }
}
```

**Tests:**
- [x] Major branch pointing to wrong SHA → should create issue with UpdateBranchAction
- [x] Major branch pointing to correct SHA → should pass
- [x] Major branch with no patch versions → should pass (nothing to track)
- [x] Prerelease handling with ignore-preview-releases
- [x] `floating-versions-use: tags` → rule should not apply

---

### 4.2 Rule: `major_branch_missing` (Priority: 21)

**Status:** ✅ **COMPLETE** - 11 tests passing

**Applies when:** `floating-versions-use: branches`

**Condition:** All unique major versions that have at least one patch but no branch

**Check:** Major branch (vX) exists

**Issue Type:** `missing_major_version`

**Remediation:** `CreateBranchAction`

```powershell
[ValidationRule]@{
    Name = "major_branch_missing"
    Category = "version_tracking"
    Priority = 21
    Condition = {
        param($State, $Config)
        if (-not $Config.useBranches) { return @() }
        # Get all unique major versions from patches (patches are always tags)
        $majorNumbers = $State.Tags | 
            Where-Object { $_.IsPatch -and -not $_.IsIgnored } |
            ForEach-Object { $_.Major } | 
            Select-Object -Unique
        # Return those that don't have a major branch
        $majorNumbers | ForEach-Object {
            $major = $_
            $exists = $State.Branches | Where-Object { $_.Version -eq "v$major" }
            if (-not $exists) {
                [PSCustomObject]@{ Major = $major }
            }
        }
    }
    Check = { param($Item, $State, $Config) $false }  # Condition already filters missing
    CreateIssue = {
        param($Item, $State, $Config)
        $highestPatch = Get-HighestPatchForMajor -State $State -Major $Item.Major `
            -ExcludePrereleases $Config.ignorePreviewReleases
        $issue = [ValidationIssue]::new("missing_major_version", "error",
            "v$($Item.Major) (branch) does not exist and must match $($highestPatch.Version)")
        $issue.Version = "v$($Item.Major)"
        $issue.ExpectedSha = $highestPatch.Sha
        $issue.SetRemediationAction([CreateBranchAction]::new("v$($Item.Major)", $highestPatch.Sha))
        return $issue
    }
}
```

**Tests:**
- [x] Missing major branch with existing patch tag → should create issue with CreateBranchAction
- [x] Existing major branch → should pass (not in condition output)
- [x] All patches ignored → should not create issue
- [x] `floating-versions-use: tags` → rule should not apply

---

### 4.3 Rule: `minor_branch_tracks_highest_patch` (Priority: 22)

**Status:** ✅ **COMPLETE** - 14 tests passing

**Applies when:** `floating-versions-use: branches` AND `check-minor-version: error|warning`

**Condition:** All minor version branches (vX.Y) that exist

**Check:** Branch points to same SHA as highest patch (vX.Y.Z)

**Issue Type:** `incorrect_minor_version`

**Remediation:** `UpdateBranchAction`

```powershell
[ValidationRule]@{
    Name = "minor_branch_tracks_highest_patch"
    Category = "version_tracking"
    Priority = 22
    Condition = {
        param($State, $Config)
        if (-not $Config.useBranches) { return @() }
        if ($Config.checkMinorVersion -eq "none") { return @() }
        $State.Branches | Where-Object { $_.IsMinor -and -not $_.IsIgnored }
    }
    Check = {
        param($Item, $State, $Config)
        $highestPatch = Get-HighestPatchForMinor -State $State `
            -Major $Item.Major -Minor $Item.Minor `
            -ExcludePrereleases $Config.ignorePreviewReleases
        if (-not $highestPatch) { return $true }
        return ($Item.Sha -eq $highestPatch.Sha)
    }
    CreateIssue = {
        param($Item, $State, $Config)
        $highestPatch = Get-HighestPatchForMinor -State $State `
            -Major $Item.Major -Minor $Item.Minor `
            -ExcludePrereleases $Config.ignorePreviewReleases
        $severity = $Config.checkMinorVersion
        $issue = [ValidationIssue]::new("incorrect_minor_version", $severity,
            "v$($Item.Major).$($Item.Minor) (branch) must match $($highestPatch.Version)")
        $issue.Version = "v$($Item.Major).$($Item.Minor)"
        $issue.CurrentSha = $Item.Sha
        $issue.ExpectedSha = $highestPatch.Sha
        $issue.SetRemediationAction([UpdateBranchAction]::new($issue.Version, $highestPatch.Sha, $true))
        return $issue
    }
}
```

**Tests:**
- [x] Minor branch pointing to wrong SHA → should create issue with UpdateBranchAction
- [x] Minor branch pointing to correct SHA → should pass
- [x] `check-minor-version: none` → rule should not apply
- [x] `check-minor-version: warning` → issue severity is warning
- [x] `floating-versions-use: tags` → rule should not apply

---

### 4.4 Rule: `minor_branch_missing` (Priority: 23)

**Status:** ✅ **COMPLETE** - 14 tests passing

**Applies when:** `floating-versions-use: branches` AND `check-minor-version: error|warning`

**Condition:** All unique major.minor versions that have patches but no minor branch

**Check:** Minor branch (vX.Y) exists

**Issue Type:** `missing_minor_version`

**Remediation:** `CreateBranchAction`

```powershell
[ValidationRule]@{
    Name = "minor_branch_missing"
    Category = "version_tracking"
    Priority = 23
    Condition = {
        param($State, $Config)
        if (-not $Config.useBranches) { return @() }
        if ($Config.checkMinorVersion -eq "none") { return @() }
        
        # Get all unique major.minor versions from patches (patches are always tags)
        $minorNumbers = $State.Tags | 
            Where-Object { $_.IsPatch -and -not $_.IsIgnored } |
            ForEach-Object { [PSCustomObject]@{ Major = $_.Major; Minor = $_.Minor } } | 
            Sort-Object Major, Minor -Unique
        
        # Return those that don't have a minor branch
        $minorNumbers | ForEach-Object {
            $major = $_.Major
            $minor = $_.Minor
            $exists = $State.Branches | Where-Object { $_.Version -eq "v$major.$minor" }
            if (-not $exists) {
                [PSCustomObject]@{ Major = $major; Minor = $minor }
            }
        }
    }
    Check = { param($Item, $State, $Config) $false }  # Condition already filters missing
    CreateIssue = {
        param($Item, $State, $Config)
        $highestPatch = Get-HighestPatchForMinor -State $State `
            -Major $Item.Major -Minor $Item.Minor `
            -ExcludePrereleases $Config.ignorePreviewReleases
        $severity = $Config.checkMinorVersion
        $issue = [ValidationIssue]::new("missing_minor_version", $severity,
            "v$($Item.Major).$($Item.Minor) (branch) does not exist and must match $($highestPatch.Version)")
        $issue.Version = "v$($Item.Major).$($Item.Minor)"
        $issue.ExpectedSha = $highestPatch.Sha
        $issue.SetRemediationAction([CreateBranchAction]::new($issue.Version, $highestPatch.Sha))
        return $issue
    }
}
```

**Tests:**
- [x] Missing minor branch with existing patch tag → should create issue with CreateBranchAction
- [x] Existing minor branch → should pass
- [x] `check-minor-version: none` → rule should not apply
- [x] `floating-versions-use: tags` → rule should not apply

---

## Phase 5: Latest Version Rules

**Status:** ✅ **COMPLETE** - All 4 rules implemented (44 tests passing)

### 5.1 Rule: `latest_tag_tracks_global_highest` (Priority: 30)

**Status:** ✅ **COMPLETE** - 13 tests passing

**Applies when:** `floating-versions-use: tags`

**Condition:** "latest" tag exists

**Check:** Points to global highest patch version

**Issue Type:** `incorrect_latest_tag`

**Remediation:** `UpdateTagAction`

```powershell
[ValidationRule]@{
    Name = "latest_tag_tracks_global_highest"
    Category = "latest"
    Priority = 30
    Condition = {
        param($State, $Config)
        if ($Config.useBranches) { return @() }
        $State.Tags | Where-Object { $_.Version -eq "latest" }
    }
    Check = {
        param($Item, $State, $Config)
        $globalHighest = Get-GlobalHighestPatch -State $State `
            -ExcludePrereleases $Config.ignorePreviewReleases
        if (-not $globalHighest) { return $true }
        return ($Item.Sha -eq $globalHighest.Sha)
    }
    CreateIssue = {
        param($Item, $State, $Config)
        $globalHighest = Get-GlobalHighestPatch -State $State `
            -ExcludePrereleases $Config.ignorePreviewReleases
        $issue = [ValidationIssue]::new("incorrect_latest_tag", "error",
            "latest tag ref $($Item.Sha) must match $($globalHighest.Version) ref $($globalHighest.Sha)")
        $issue.Version = "latest"
        $issue.CurrentSha = $Item.Sha
        $issue.ExpectedSha = $globalHighest.Sha
        $issue.SetRemediationAction([UpdateTagAction]::new("latest", $globalHighest.Sha, $true))
        return $issue
    }
}
```

**Tests:**
- [x] latest tag pointing to wrong SHA → should create issue with UpdateTagAction
- [x] latest tag pointing to correct SHA → should pass
- [x] No patches exist → should pass (nothing to track)
- [x] `floating-versions-use: branches` → rule should not apply

---

### 5.2 Rule: `latest_tag_missing` (Priority: 31)

**Status:** ✅ **COMPLETE** - 9 tests passing

**Applies when:** `floating-versions-use: tags` AND at least one patch exists

**Condition:** "latest" tag does not exist

**Check:** Latest tag exists

**Issue Type:** `missing_latest_tag`

**Remediation:** `CreateTagAction`

**Note:** This is optional - not all repos want a "latest" alias. Consider making this configurable or leaving as warning only.

```powershell
[ValidationRule]@{
    Name = "latest_tag_missing"
    Category = "latest"
    Priority = 31
    Condition = {
        param($State, $Config)
        if ($Config.useBranches) { return @() }
        # Only suggest if there are patches and no latest tag
        $hasPatches = ($State.Tags | Where-Object { $_.IsPatch }).Count -gt 0
        $hasLatest = ($State.Tags | Where-Object { $_.Version -eq "latest" }).Count -gt 0
        if ($hasPatches -and -not $hasLatest) {
            return @([PSCustomObject]@{ ShouldExist = $true })
        }
        return @()
    }
    Check = { param($Item, $State, $Config) $false }
    CreateIssue = {
        param($Item, $State, $Config)
        $globalHighest = Get-GlobalHighestPatch -State $State `
            -ExcludePrereleases $Config.ignorePreviewReleases
        # Note: This is a suggestion, not an error - use warning severity
        $issue = [ValidationIssue]::new("missing_latest_tag", "warning",
            "Consider creating a 'latest' tag pointing to $($globalHighest.Version)")
        $issue.Version = "latest"
        $issue.ExpectedSha = $globalHighest.Sha
        $issue.SetRemediationAction([CreateTagAction]::new("latest", $globalHighest.Sha))
        return $issue
    }
}
```

**Tests:**
- [x] No latest tag with existing patches → should create warning (suggestion)
- [x] latest tag exists → should pass
- [x] No patches → should not create issue
- [x] `floating-versions-use: branches` → rule should not apply

---

### 5.3 Rule: `latest_branch_tracks_global_highest` (Priority: 30)

**Status:** ✅ **COMPLETE** - 13 tests passing

**Applies when:** `floating-versions-use: branches`

**Condition:** "latest" branch exists

**Check:** Points to global highest patch version

**Issue Type:** `incorrect_latest_branch`

**Remediation:** `UpdateBranchAction`

```powershell
[ValidationRule]@{
    Name = "latest_branch_tracks_global_highest"
    Category = "latest"
    Priority = 30
    Condition = {
        param($State, $Config)
        if (-not $Config.useBranches) { return @() }
        $State.Branches | Where-Object { $_.Version -eq "latest" }
    }
    Check = {
        param($Item, $State, $Config)
        $globalHighest = Get-GlobalHighestPatch -State $State `
            -ExcludePrereleases $Config.ignorePreviewReleases
        if (-not $globalHighest) { return $true }
        return ($Item.Sha -eq $globalHighest.Sha)
    }
    CreateIssue = {
        param($Item, $State, $Config)
        $globalHighest = Get-GlobalHighestPatch -State $State `
            -ExcludePrereleases $Config.ignorePreviewReleases
        $issue = [ValidationIssue]::new("incorrect_latest_branch", "error",
            "latest branch ref $($Item.Sha) must match $($globalHighest.Version) ref $($globalHighest.Sha)")
        $issue.Version = "latest"
        $issue.CurrentSha = $Item.Sha
        $issue.ExpectedSha = $globalHighest.Sha
        $issue.SetRemediationAction([UpdateBranchAction]::new("latest", $globalHighest.Sha, $true))
        return $issue
    }
}
```

**Tests:**
- [x] latest branch pointing to wrong SHA → should create issue with UpdateBranchAction
- [x] latest branch pointing to correct SHA → should pass
- [x] No patches exist → should pass (nothing to track)
- [x] `floating-versions-use: tags` → rule should not apply

---

### 5.4 Rule: `latest_branch_missing` (Priority: 31)

**Status:** ✅ **COMPLETE** - 9 tests passing

**Applies when:** `floating-versions-use: branches` AND at least one patch exists

**Condition:** "latest" branch does not exist

**Check:** Latest branch exists

**Issue Type:** `missing_latest_branch`

**Remediation:** `CreateBranchAction`

```powershell
[ValidationRule]@{
    Name = "latest_branch_missing"
    Category = "latest"
    Priority = 31
    Condition = {
        param($State, $Config)
        if (-not $Config.useBranches) { return @() }
        # Only suggest if there are patches and no latest branch
        $hasPatches = ($State.Tags | Where-Object { $_.IsPatch }).Count -gt 0
        $hasLatest = ($State.Branches | Where-Object { $_.Version -eq "latest" }).Count -gt 0
        if ($hasPatches -and -not $hasLatest) {
            return @([PSCustomObject]@{ ShouldExist = $true })
        }
        return @()
    }
    Check = { param($Item, $State, $Config) $false }
    CreateIssue = {
        param($Item, $State, $Config)
        $globalHighest = Get-GlobalHighestPatch -State $State `
            -ExcludePrereleases $Config.ignorePreviewReleases
        $issue = [ValidationIssue]::new("missing_latest_branch", "warning",
            "Consider creating a 'latest' branch pointing to $($globalHighest.Version)")
        $issue.Version = "latest"
        $issue.ExpectedSha = $globalHighest.Sha
        $issue.SetRemediationAction([CreateBranchAction]::new("latest", $globalHighest.Sha))
        return $issue
    }
}
```

**Tests:**
- [x] No latest branch with existing patches → should create warning (suggestion)
- [x] latest branch exists → should pass
- [x] No patches → should not create issue
- [x] `floating-versions-use: tags` → rule should not apply

---

### 5.5 Rule: `latest_wrong_ref_type` (Priority: 5)

**Applies when:** "latest" exists as wrong ref type for configuration

**Condition:** 
- Using tags: "latest" exists as branch
- Using branches: "latest" exists as tag

**Issue Type:** `latest_wrong_ref_type`

**Remediation:** 
- If `floating-versions-use: tags`: `ConvertBranchToTagAction`
- If `floating-versions-use: branches`: `ConvertTagToBranchAction`

**Note:** Auto-fix is opinionated based on the `floating-versions-use` configuration. The action will convert the "latest" ref to match the configured ref type, preserving the SHA it points to.

```powershell
[ValidationRule]@{
    Name = "latest_wrong_ref_type"
    Category = "ref_type"
    Priority = 5
    Condition = {
        param($State, $Config)
        $results = @()
        
        if ($Config.useBranches) {
            # Using branches, but latest exists as tag
            $latestTag = $State.Tags | Where-Object { $_.Version -eq "latest" }
            if ($latestTag) {
                $results += [PSCustomObject]@{
                    CurrentType = "tag"
                    ExpectedType = "branch"
                    Sha = $latestTag.Sha
                }
            }
        } else {
            # Using tags, but latest exists as branch
            $latestBranch = $State.Branches | Where-Object { $_.Version -eq "latest" }
            if ($latestBranch) {
                $results += [PSCustomObject]@{
                    CurrentType = "branch"
                    ExpectedType = "tag"
                    Sha = $latestBranch.Sha
                }
            }
        }
        
        return $results
    }
    Check = { param($Item, $State, $Config) $false }
    CreateIssue = {
        param($Item, $State, $Config)
        $issue = [ValidationIssue]::new("latest_wrong_ref_type", "error",
            "'latest' exists as $($Item.CurrentType) but should be a $($Item.ExpectedType) based on floating-versions-use setting")
        $issue.Version = "latest"
        $issue.CurrentSha = $Item.Sha
        
        # Auto-fix: Convert to the configured ref type
        # This is opinionated based on the floating-versions-use configuration
        if ($Item.ExpectedType -eq "branch") {
            # Need to delete tag, then create branch
            $issue.SetRemediationAction([ConvertTagToBranchAction]::new("latest", $Item.Sha))
        } else {
            # Need to delete branch, then create tag
            $issue.SetRemediationAction([ConvertBranchToTagAction]::new("latest", $Item.Sha))
        }
        
        return $issue
    }
}
```

**Note:** Uses existing `ConvertTagToBranchAction` and `ConvertBranchToTagAction` from `lib/RemediationActions.ps1`. These actions already handle:
- Immutability checks (tags with immutable releases cannot be converted)
- Cases where the target ref already exists (just delete the source)
- Manual fix requirements when workflow file changes require `workflows` permission
- Proper create-then-delete order to avoid data loss

**Tests:**
- [ ] latest as branch when using tags → should create issue with ConvertBranchToTagAction
- [ ] latest as tag when using branches → should create issue with ConvertTagToBranchAction
- [ ] Auto-fix converts branch to tag (preserves SHA)
- [ ] Auto-fix converts tag to branch (preserves SHA)
- [ ] Immutable tag cannot be converted → marked as unfixable
- [ ] Workflow file changes → marked as manual_fix_required
- [ ] latest as correct type → should pass
- [ ] No latest exists → should pass

---

### 5.6 Helper Function: `Get-GlobalHighestPatch`

```powershell
function Get-GlobalHighestPatch {
    param(
        [RepositoryState]$State,
        [bool]$ExcludePrereleases = $false
    )
    
    # Get all patch versions (always tags)
    $patches = $State.Tags | Where-Object { $_.IsPatch -and -not $_.IsIgnored }
    
    if ($ExcludePrereleases) {
        # Use Test-IsPrerelease helper to check via ReleaseInfo
        $patches = $patches | Where-Object { -not (Test-IsPrerelease -State $State -VersionRef $_) }
    }
    
    # If all filtered out, use all patches
    if ($patches.Count -eq 0) {
        $patches = $State.Tags | Where-Object { $_.IsPatch -and -not $_.IsIgnored }
    }
    
    # Sort by version components and return highest
    $patches | Sort-Object -Property Major, Minor, Patch -Descending | Select-Object -First 1
}
```

---

## Phase 6: Integration and Migration

### 6.1 Create Rule Registry

**File:** `lib/ValidationRules.ps1`

```powershell
$script:AllRules = @(
    # Phase 1: Ref type
    $Rule_BranchShouldBeTag,
    $Rule_TagShouldBeBranch,
    $Rule_LatestWrongRefType,
    $Rule_DuplicateFloatingVersionRef,
    $Rule_DuplicateLatestRef,
    
    # Phase 2: Releases
    $Rule_PatchReleaseRequired,
    $Rule_ReleaseShouldBePublished,
    $Rule_ReleaseShouldBeImmutable,
    $Rule_FloatingVersionNoRelease,
    
    # Phase 3: Version tracking (tags)
    $Rule_MajorTagTracksHighestPatch,
    $Rule_MajorTagMissing,
    $Rule_MinorTagTracksHighestPatch,
    $Rule_MinorTagMissing,
    $Rule_PatchTagMissing,
    
    # Phase 4: Version tracking (branches)
    $Rule_MajorBranchTracksHighestPatch,
    $Rule_MajorBranchMissing,
    $Rule_MinorBranchTracksHighestPatch,
    $Rule_MinorBranchMissing,
    
    # Phase 5: Latest (tracking rules only, wrong ref type handled in Phase 1)
    $Rule_LatestTagTracksGlobalHighest,
    $Rule_LatestTagMissing,
    $Rule_LatestBranchTracksGlobalHighest,
    $Rule_LatestBranchMissing
)
```

### 6.2 Modify main.ps1 Incrementally

**Step 1:** Add rule engine import and call at end of validation section:

```powershell
. "$PSScriptRoot/lib/ValidationRules.ps1"

# After existing validation code, also run rule engine (duplicates filtered)
$config = @{
    useBranches = $useBranches
    checkMinorVersion = $checkMinorVersion
    checkReleases = $checkReleases
    checkImmutability = $checkReleaseImmutability
    ignorePreviewReleases = $ignorePreviewReleases
}
# Invoke-ValidationRules -State $State -Config $config  # Uncomment when ready
```

**Step 2:** For each phase, enable the rules and remove corresponding old code:

1. Enable Phase 1 rules → Remove lines 502-542 (wrong ref type checks)
2. Enable Phase 2 rules → Remove lines 593-726 (release validations)
3. Enable Phase 3 rules → Remove lines 758-993 (version tracking for tags)
4. Enable Phase 4 rules → (already covered by Phase 3 with branches)
5. Enable Phase 5 rules → Remove lines 1000-1050 (latest handling)

### 6.3 Deduplication Strategy

During migration, both old and new code may create duplicate issues. Add deduplication:

```powershell
# In RepositoryState.AddIssue()
[void]AddIssue([ValidationIssue]$issue) {
    # Check for duplicate by Type + Version
    $existing = $this.Issues | Where-Object { 
        $_.Type -eq $issue.Type -and $_.Version -eq $issue.Version 
    }
    if (-not $existing) {
        $this.Issues += $issue
    }
}
```

---

## Implementation Order Checklist

### Week 1: Infrastructure
- [ ] Create `lib/ValidationRules.ps1` with base classes
- [ ] Create helper functions (Get-HighestPatchForMajor, etc.)
- [ ] Create `tests/unit/ValidationRules.Tests.ps1` infrastructure
- [ ] Verify all 244 existing tests still pass

### Week 2: Phase 1 (Ref Type)
For each rule, create folder structure per "Rule File Structure" section above.

- [ ] Create `lib/rules/ref_type/branch_should_be_tag/` folder
- [ ] Implement `branch_should_be_tag.ps1` rule file
- [ ] Write `branch_should_be_tag.Tests.ps1` unit tests
- [ ] Write `README.md` with rule documentation
- [ ] Create `lib/rules/ref_type/tag_should_be_branch/` folder
- [ ] Implement `tag_should_be_branch.ps1` rule file
- [ ] Write `tag_should_be_branch.Tests.ps1` unit tests
- [ ] Write `README.md` with rule documentation
- [ ] Create `lib/rules/ref_type/latest_wrong_ref_type/` folder
- [ ] Implement `latest_wrong_ref_type.ps1` rule file
- [ ] Write `latest_wrong_ref_type.Tests.ps1` unit tests
- [ ] Write `README.md` with rule documentation
- [ ] Create `lib/rules/ref_type/duplicate_floating_version_ref/` folder
- [ ] Implement `duplicate_floating_version_ref.ps1` rule file
- [ ] Write `duplicate_floating_version_ref.Tests.ps1` unit tests
- [ ] Write `README.md` with rule documentation
- [ ] Create `lib/rules/ref_type/duplicate_latest_ref/` folder
- [ ] Implement `duplicate_latest_ref.ps1` rule file
- [ ] Write `duplicate_latest_ref.Tests.ps1` unit tests
- [ ] Write `README.md` with rule documentation
- [ ] Enable Phase 1 rules in main.ps1
- [ ] Verify E2E tests pass
- [ ] Remove old ref type code from main.ps1

### Week 3: Phase 2 (Releases)
For each rule, create folder structure per "Rule File Structure" section above.

- [ ] Create `lib/rules/releases/patch_release_required/` folder
- [ ] Implement rule file, tests, and README
- [ ] Create `lib/rules/releases/release_should_be_published/` folder
- [ ] Implement rule file, tests, and README
- [ ] Create `lib/rules/releases/release_should_be_immutable/` folder
- [ ] Implement rule file, tests, and README
- [ ] Create `lib/rules/releases/floating_version_no_release/` folder
- [ ] Implement rule file, tests, and README
- [ ] Enable Phase 2 rules
- [ ] Remove old release validation code

### Week 4: Phase 3 (Version Tracking - Tags)
For each rule, create folder structure per "Rule File Structure" section above.

- [ ] Create `lib/rules/version_tracking/major_tag_tracks_highest_patch/` folder
- [ ] Implement rule file, tests, and README
- [ ] Create `lib/rules/version_tracking/major_tag_missing/` folder
- [ ] Implement rule file, tests, and README
- [ ] Create `lib/rules/version_tracking/minor_tag_tracks_highest_patch/` folder
- [ ] Implement rule file, tests, and README
- [ ] Create `lib/rules/version_tracking/minor_tag_missing/` folder
- [ ] Implement rule file, tests, and README
- [ ] Create `lib/rules/version_tracking/patch_tag_missing/` folder
- [ ] Implement rule file, tests, and README
- [ ] Enable Phase 3 rules
- [ ] Remove old version tracking code

### Week 5: Phase 4 & 5 (Branches + Latest)
For each rule, create folder structure per "Rule File Structure" section above.

Branch rules (in `lib/rules/version_tracking/`):
- [ ] `major_branch_tracks_highest_patch/` - rule, tests, README
- [ ] `major_branch_missing/` - rule, tests, README
- [ ] `minor_branch_tracks_highest_patch/` - rule, tests, README
- [ ] `minor_branch_missing/` - rule, tests, README

Latest rules (in `lib/rules/latest/`):
- [ ] `latest_tag_tracks_global_highest/` - rule, tests, README
- [ ] `latest_tag_missing/` - rule, tests, README
- [ ] `latest_branch_tracks_global_highest/` - rule, tests, README
- [ ] `latest_branch_missing/` - rule, tests, README
- [ ] Enable all Phase 4 & 5 rules
- [ ] Remove old code

**Note:** `latest_wrong_ref_type` and `duplicate_latest_ref` are implemented in Phase 1 (Week 2) since they are ref_type rules.

### Week 6: Cleanup
- [ ] Remove any remaining old validation code
- [ ] Remove deduplication workaround
- [ ] Update documentation
- [ ] Final test pass

---

## Rule Summary Table

| Rule Name | Priority | Category | Applies When | Issue Type | Remediation |
|-----------|----------|----------|--------------|------------|-------------|
| `branch_should_be_tag` | 5 | ref_type | tags mode | wrong_ref_type | ConvertBranchToTagAction |
| `tag_should_be_branch` | 5 | ref_type | branches mode | wrong_ref_type | ConvertTagToBranchAction |
| `latest_wrong_ref_type` | 5 | ref_type | latest exists as wrong type | latest_wrong_ref_type | ConvertTagToBranchAction / ConvertBranchToTagAction |
| `duplicate_floating_version_ref` | 6 | ref_type | both tag & branch exist for vX/vX.Y | duplicate_ref | DeleteTagAction / DeleteBranchAction |
| `duplicate_latest_ref` | 6 | ref_type | both tag & branch exist for latest | duplicate_latest_ref | DeleteTagAction / DeleteBranchAction |
| `patch_release_required` | 10 | releases | check-releases ≠ none | missing_release | CreateReleaseAction |
| `release_should_be_published` | 11 | releases | check-immutability ≠ none | draft_release | PublishReleaseAction |
| `release_should_be_immutable` | 12 | releases | check-immutability ≠ none | non_immutable_release | RepublishReleaseAction |
| `floating_version_no_release` | 15 | releases | any release check | mutable/immutable_floating_release | DeleteReleaseAction |
| `major_tag_tracks_highest_patch` | 20 | version_tracking | tags mode | incorrect_version | UpdateTagAction |
| `major_tag_missing` | 21 | version_tracking | tags mode | missing_major_version | CreateTagAction |
| `minor_tag_tracks_highest_patch` | 22 | version_tracking | tags mode, minor check | incorrect_minor_version | UpdateTagAction |
| `minor_tag_missing` | 23 | version_tracking | tags mode, minor check | missing_minor_version | CreateTagAction |
| `patch_tag_missing` | 25 | version_tracking | check-releases = none | missing_patch_version | CreateTagAction |
| `major_branch_tracks_highest_patch` | 20 | version_tracking | branches mode | incorrect_version | UpdateBranchAction |
| `major_branch_missing` | 21 | version_tracking | branches mode | missing_major_version | CreateBranchAction |
| `minor_branch_tracks_highest_patch` | 22 | version_tracking | branches mode, minor check | incorrect_minor_version | UpdateBranchAction |
| `minor_branch_missing` | 23 | version_tracking | branches mode, minor check | missing_minor_version | CreateBranchAction |
| `latest_tag_tracks_global_highest` | 30 | latest | tags mode, latest tag exists | incorrect_latest_tag | UpdateTagAction |
| `latest_tag_missing` | 31 | latest | tags mode, patches exist, no latest | missing_latest_tag (warning) | CreateTagAction |
| `latest_branch_tracks_global_highest` | 30 | latest | branches mode, latest branch exists | incorrect_latest_branch | UpdateBranchAction |
| `latest_branch_missing` | 31 | latest | branches mode, patches exist, no latest | missing_latest_branch (warning) | CreateBranchAction |

**Total: 23 rules**

**All 12 Remediation Actions now used:**
- CreateReleaseAction, PublishReleaseAction, RepublishReleaseAction, DeleteReleaseAction
- CreateTagAction, UpdateTagAction, DeleteTagAction
- CreateBranchAction, UpdateBranchAction, DeleteBranchAction
- ConvertTagToBranchAction, ConvertBranchToTagAction

---

## Success Criteria

1. **All 244+ existing tests pass** after each phase
2. **No behavior changes** - same issues created for same inputs
3. **Each rule has dedicated unit tests** testing:
   - Condition filtering (what items are checked)
   - Check logic (pass/fail scenarios)
   - Issue creation (correct type, severity, remediation action)
   - Configuration sensitivity (rule disabled when config says so)
   - Respects `IsIgnored` flag on refs
   - Respects `IsPrerelease` flag when `ignorePreviewReleases` is configured
4. **main.ps1 validation section** reduced from ~500 lines to ~50 lines
5. **New rules can be added** by creating a single `ValidationRule` object

### What Rules Tests Do NOT Need to Cover

The following are tested elsewhere and should NOT be duplicated in rules tests:

- **Input parsing** (`ignore-versions` formats like JSON, CSV, newlines) → integration tests
- **Version string parsing** (`v1.0.0` → Major, Minor, Patch components) → `VersionParser.Tests.ps1`
- **Prerelease detection** (from GitHub Release API `isPrerelease` property) → integration tests
- **API pagination** → `GitHubApi.Tests.ps1`
- **HTTP error handling** → `GitHubApi.Tests.ps1`

Rules tests assume state is already properly initialized with correct `IsIgnored`, `IsPrerelease`, etc. flags.

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Duplicate issues during migration | Add deduplication in AddIssue() |
| Rule order dependencies | Use Priority field, document dependencies |
| Performance regression | Rules are simple predicates, should be fast |
| Test coverage gaps | Convert E2E tests to also be rule unit tests |
| Edge cases in helper functions | Extract from existing code that already handles them |
