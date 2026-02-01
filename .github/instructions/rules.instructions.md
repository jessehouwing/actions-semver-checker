---
applyTo: 'lib/rules/**/*'
name: Development guidance for rules
description: This file provides guidance for implementing validation rules in the lib/rules/ directory.
---

# Rules Implementation Guide

This document provides essential context for implementing validation rules in the `lib/rules/` directory.

## ValidationRule Structure

The `ValidationRule` class (defined in `lib/ValidationRules.ps1`) has the following properties:

```powershell
class ValidationRule {
    [string]$Name            # Unique identifier (e.g., "patch_release_required")
    [string]$Description     # Human-readable description
    [int]$Priority           # Lower values run first (5-30 range)
    [string]$Category        # Grouping: ref_type, version_tracking, releases, latest
    [scriptblock]$Condition  # Returns items to validate
    [scriptblock]$Check      # Returns $true when a single item is valid
    [scriptblock]$CreateIssue # Creates a ValidationIssue for an invalid item
}
```

### Rule Definition Pattern

```powershell
$Rule_MyRuleName = [ValidationRule]@{
    Name = "my_rule_name"
    Description = "Brief description of what this rule validates"
    Priority = 10
    Category = "releases"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Filter based on configuration first
        if ($Config.'some-setting' -ne 'enabled') {
            return @()  # Rule doesn't apply
        }
        
        # Return array of items (VersionRef, ReleaseInfo) that need validation
        return $State.Tags | Where-Object { 
            -not $_.IsIgnored -and $_.IsPatch 
        }
    }
    
    Check = { param([VersionRef]$Item, [RepositoryState]$State, [hashtable]$Config)
        # Return $true if item is valid, $false if invalid
        # For simple cases, can just return $false if Condition already filtered
        return $false
    }
    
    CreateIssue = { param([VersionRef]$Item, [RepositoryState]$State, [hashtable]$Config)
        # Create and return a ValidationIssue
        $issue = [ValidationIssue]::new(
            "issue_type",
            "error",  # or "warning"
            "Human-readable message"
        )
        $issue.Version = $Item.Version
        $issue.RemediationAction = [SomeAction]::new($Item.Version, $Item.Sha)
        
        return $issue
    }
}

# Always export the rule variable
$Rule_MyRuleName
```

## Key Domain Objects

### VersionRef Constructor

**ALWAYS use the constructor** - never create VersionRef with hashtables:

```powershell
# CORRECT
$versionRef = [VersionRef]::new(
    "v1.0.0",                    # version
    "refs/tags/v1.0.0",          # ref (full Git ref path)
    "abc123def456",              # sha (commit hash)
    "tag"                        # type ("tag" or "branch")
)

# WRONG - will fail at runtime
$versionRef = [VersionRef]@{
    Version = "v1.0.0"
    SHA = "abc123"
    IsPatch = $true
}
```

**VersionRef Properties** (set automatically by constructor):
- `Version`, `Ref`, `Sha`, `Type` (from constructor params)
- `IsPatch`, `IsMinor`, `IsMajor` (parsed from version)
- `Major`, `Minor`, `Patch` (numeric parts)
- `IsIgnored` (must be set manually if needed)

**Note:** Prerelease status is determined from `ReleaseInfo.IsPrerelease` (GitHub Release API), not version suffixes. Use `Test-IsPrerelease -State $State -VersionRef $ref` helper function.

### ReleaseInfo Constructor

**ALWAYS use constructor with PSCustomObject**:

```powershell
# CORRECT
$releaseData = [PSCustomObject]@{
    tag_name = "v1.0.0"
    id = 123
    draft = $false
    prerelease = $false
    html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
    target_commitish = "abc123"
}
$release = [ReleaseInfo]::new($releaseData)

# WRONG - ReleaseInfo doesn't support hashtable initialization
$release = [ReleaseInfo]@{ TagName = "v1.0.0"; IsDraft = $false }
```

### RepositoryState Properties

```powershell
[RepositoryState]::new()  # Constructor takes no parameters

# State properties
$state.Tags              # [VersionRef[]] - all tags
$state.Branches          # [VersionRef[]] - all branches  
$state.Releases          # [ReleaseInfo[]] - all releases
$state.Issues            # [ValidationIssue[]] - accumulated issues
$state.IgnoreVersions    # [string[]] - versions to skip (e.g., ["v1.0.0", "v2.1.0"])

# Configuration properties (set by main.ps1)
$state.AutoFix
$state.CheckMinorVersion
$state.CheckReleases          # "error", "warning", "none"
$state.CheckImmutability      # "error", "warning", "none"
$state.IgnorePreviewReleases
$state.FloatingVersionsUse    # "tags", "branches"

# Repository info
$state.RepoOwner
$state.RepoName
$state.ApiUrl
$state.ServerUrl
$state.Token
```

**Important:** There is NO `IsVersionIgnored()` method. Use the `IsIgnored` property on VersionRef instead:

```powershell
# CORRECT
$results = $State.Tags | Where-Object { -not $_.IsIgnored }

# WRONG - method doesn't exist
if ($State.IsVersionIgnored($version)) { ... }
```

### ValidationIssue Creation

**3-parameter constructor only**, then set RemediationAction separately:

```powershell
# CORRECT
$issue = [ValidationIssue]::new(
    "issue_type",      # Type identifier
    "error",           # Severity: "error" or "warning"
    "Error message"    # Human-readable message
)
$issue.Version = $versionRef.Version
$issue.RemediationAction = [CreateTagAction]::new($version, $sha)

# WRONG - ValidationIssue doesn't accept 4 parameters
$issue = [ValidationIssue]::new("issue_type", "error", "Message", $action)
```

**ValidationIssue Properties:**
- `Type`, `Severity`, `Message` (from constructor)
- `Version` (must set manually)
- `CurrentSha`, `ExpectedSha` (optional)
- `RemediationAction` (set via property, not constructor)
- `IsAutoFixable` (automatically set to true when RemediationAction is assigned)
- `Status` (managed by remediation engine: "pending", "fixed", "failed", "unfixable", "manual_fix_required")

## Common RemediationAction Constructors

### Tag Actions

```powershell
[CreateTagAction]::new($version, $sha)
[UpdateTagAction]::new($version, $currentSha, $newSha)
[DeleteTagAction]::new($version, $sha)
```

### Branch Actions

```powershell
[CreateBranchAction]::new($version, $sha)
[UpdateBranchAction]::new($version, $currentSha, $newSha)
[DeleteBranchAction]::new($version, $sha)
```

### Release Actions

```powershell
# CreateReleaseAction has two constructors:
[CreateReleaseAction]::new($tagName, $isDraft)
[CreateReleaseAction]::new($tagName, $isDraft, $autoPublish)

# Note: autoPublish=true means "create as published immediately"
# isDraft should typically be the opposite of autoPublish

# Example: Create immutable release
$isDraft = $false
$autoPublish = $true
[CreateReleaseAction]::new("v1.0.0", $isDraft, $autoPublish)

# Other release actions:
[PublishReleaseAction]::new($tagName, $releaseId)
[RepublishReleaseAction]::new($tagName, $releaseId)
[DeleteReleaseAction]::new($tagName, $releaseId, $isImmutable)
```

### Conversion Actions

```powershell
[ConvertTagToBranchAction]::new($version, $sha)
[ConvertBranchToTagAction]::new($version, $sha)
```

**Important Properties:**
- All actions have `Priority` (controls execution order)
- Release actions have `AutoPublish` (NOT `ShouldAutoPublish`)

## Configuration Input Patterns

Configuration comes from the `$Config` hashtable passed to Condition and CreateIssue:

```powershell
# Reading configuration
$checkReleases = $Config.'check-releases'  # "error", "warning", "none"
$floatingUse = $Config.'floating-versions-use' ?? "tags"  # Default to "tags"

# Typical pattern: Skip rule if not enabled
Condition = { param([RepositoryState]$State, [hashtable]$Config)
    if ($Config.'check-releases' -ne 'error' -and $Config.'check-releases' -ne 'warning') {
        return @()  # Rule doesn't apply
    }
    # ... continue with validation logic
}

# Dynamic severity based on configuration
CreateIssue = { param([VersionRef]$Item, [RepositoryState]$State, [hashtable]$Config)
    $severity = if ($Config.'check-releases' -eq 'warning') { 'warning' } else { 'error' }
    # ...
}
```

## Common Patterns

### Finding Related Items

```powershell
# Get all patches (from both tags and branches)
$allPatches = ($State.Tags + $State.Branches) | Where-Object { $_.IsPatch }

# Find release for a tag
$release = $State.Releases | Where-Object { $_.TagName -eq $version }

# Get highest patch for a major version
$highest = $allPatches | 
    Where-Object { $_.Major -eq 1 -and -not $_.IsIgnored } |
    Sort-Object Major, Minor, Patch -Descending |
    Select-Object -First 1
```

### Filtering Ignored Versions

Always use the `IsIgnored` property on VersionRef:

```powershell
# In Condition block - filter out ignored versions
$State.Tags | Where-Object { -not $_.IsIgnored -and $_.IsPatch }

# When iterating over floating versions
foreach ($floatingRef in $floatingVersions) {
    if ($floatingRef.IsIgnored) {
        continue  # Skip this version
    }
    # ...
}
```

### Creating Synthetic VersionRef Objects

When you need to represent a version that doesn't exist yet (e.g., expected patch from floating version):

```powershell
# Use constructor with dummy ref path
$expectedVersion = "v1.0.0"
$syntheticRef = [VersionRef]::new(
    $expectedVersion,
    "refs/tags/$expectedVersion",  # Dummy path
    $floatingRef.Sha,              # Use parent's SHA
    "tag"
)
```

## Test Patterns

### Test Structure

```powershell
BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/my_rule_name.ps1"
}

Describe "my_rule_name" {
    Context "Condition" {
        It "should return items when rule applies" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $config = @{ 'some-setting' = 'enabled' }
            
            $result = & $Rule_MyRuleName.Condition $state $config
            
            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1.0.0"
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with correct properties" {
            $versionRef = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state = [RepositoryState]::new()
            $config = @{ 'some-setting' = 'error' }
            
            $issue = & $Rule_MyRuleName.CreateIssue $versionRef $state $config
            
            $issue.Type | Should -Be "expected_type"
            $issue.Severity | Should -Be "error"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "SomeAction"
        }
    }
}
```

### Creating Test Data

```powershell
# Tags
$state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")

# Branches  
$state.Branches += [VersionRef]::new("v1", "refs/heads/v1", "def456", "branch")

# Ignored version
$ignored = [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "ghi789", "tag")
$ignored.IsIgnored = $true
$state.Tags += $ignored

# Releases (requires PSCustomObject)
$releaseData = [PSCustomObject]@{
    tag_name = "v1.0.0"
    id = 123
    draft = $false
    prerelease = $false
    html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
    target_commitish = "abc123"
}
$state.Releases += [ReleaseInfo]::new($releaseData)
```

## Priority Ranges

Use these priority ranges to ensure proper execution order:

- **5-10**: Ref type validation (convert branches↔tags before other checks)
- **10-20**: Release validation (create/publish releases)
- **20-30**: Version tracking (update floating versions to point to correct patches)
- **30-40**: Latest version handling

Within each range, coordinate related rules:
- "Missing" rules (create new items) typically run before "tracking" rules (update existing)
- Example: `patch_release_required` (10) runs before `release_should_be_published` (11)

## Coordination Between Rules

When multiple rules could create issues for the same problem, use conditional logic to avoid duplicates:

```powershell
# Example: Skip tag creation if release creation will handle it
Condition = { param([RepositoryState]$State, [hashtable]$Config)
    # If releases are required, let the release rule create both release AND tag
    if ($Config.'check-releases' -eq 'error' -or $Config.'check-releases' -eq 'warning') {
        return @()  # Skip - patch_release_required will handle it
    }
    # Otherwise, this rule creates just the tag
    # ...
}
```

Document these relationships in the rule's README.md under "Related Rules".

## Common Mistakes to Avoid

1. ❌ Using hashtables for VersionRef/ReleaseInfo instead of constructors
2. ❌ Calling `$State.IsVersionIgnored($version)` instead of checking `$_.IsIgnored`
3. ❌ Passing 4 parameters to ValidationIssue constructor
4. ❌ Using wrong property names (e.g., `ShouldAutoPublish` vs `AutoPublish`)
5. ❌ Forgetting to check `IsIgnored` in Condition blocks
6. ❌ Using `$state.IgnoredVersions` instead of `$state.IgnoreVersions`
7. ❌ Not exporting the rule variable at the end of the file
8. ❌ Forgetting to set `$issue.Version` after creating the issue

## Rule Loading

Rules are automatically loaded by `Get-ValidationRule` which:
1. Recursively scans `lib/rules/` for `*.ps1` files
2. Excludes `*.Tests.ps1` files
3. Dot-sources each file and collects ValidationRule objects
4. Sorts by Priority, then Name

The rule file **must** export the ValidationRule variable:

```powershell
# At end of rule file
$Rule_MyRuleName
```
