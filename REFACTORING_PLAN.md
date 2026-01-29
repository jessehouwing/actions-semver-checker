# Refactoring Plan for actions-semver-checker

## Current State
- Single 1698-line main.ps1 file
- 81 passing tests in main.Tests.ps1
- Functions are defined inline in main.ps1
- No clear separation of concerns

## Goals
1. Improve maintainability and readability
2. Add state model with diff visualization  
3. Better error handling and retry logic
4. Clear separation between validation logic and remediation
5. Keep all 81 tests passing

## Architecture Design

### Module Structure
```
lib/
├── Logging.ps1          - Safe output, workflow command injection prevention
├── VersionParser.ps1    - Version parsing and comparison
├── GitHubApi.ps1        - All GitHub API interactions with retry logic
├── StateModel.ps1       - Domain model for current/desired state
├── Validator.ps1        - Validation rules and checks
└── Remediation.ps1      - Fix strategies (manual, auto-fix, what-if)
```

### Domain Model

```powershell
# Current State
class VersionRef {
    [string]$Version      # e.g., "v1.0.0"
    [string]$Ref          # e.g., "refs/tags/v1.0.0"
    [string]$Sha          # commit SHA
    [System.Version]$SemVer
    [bool]$IsPrerelease
    [bool]$IsPatch/IsMinor/IsMajorVersion
    [string]$Type         # "tag" or "branch"
}

class ReleaseInfo {
    [string]$TagName
    [string]$Sha
    [bool]$IsDraft
    [bool]$IsPrerelease
    [bool]$IsImmutable
    [int]$Id
}

class RepositoryState {
    [VersionRef[]]$Tags
    [VersionRef[]]$Branches
    [ReleaseInfo[]]$Releases
}

# Desired State
class ValidationIssue {
    [string]$Type         # "missing_version", "mismatched_sha", etc.
    [string]$Severity     # "error", "warning"
    [string]$Message
    [string]$FixCommand   # Manual fix command
    [bool]$IsAutoFixable
    [scriptblock]$AutoFixAction  # API or git command
}

# State Diff
class StateDiff {
    [string]$Action       # "create", "update", "delete"
    [string]$RefType      # "tag", "branch", "release"
    [string]$Version
    [string]$CurrentSha
    [string]$DesiredSha
    [string]$Reason
}
```

### Validation Flow

```
1. Collect Current State
   ├─ Local tags (git tag -l v*)
   ├─ Remote branches (git branch --remotes)
   └─ GitHub releases (REST API with pagination)

2. Calculate Desired State
   ├─ For each patch version vX.Y.Z:
   │  ├─ Should have minor vX.Y pointing to same/latest patch
   │  └─ Should have major vX pointing to same/latest patch
   ├─ Check for ambiguous refs (tag + branch with same version)
   └─ Check releases (exist, immutable, not on floating versions)

3. Generate State Diff
   └─ Compare current vs desired, output structured diffs

4. Display Diff
   ├─ Group by action type (create/update/delete)
   ├─ Color code (green=create, yellow=update, red=delete)
   └─ Show before/after SHAs

5. Execute Remediation
   ├─ Dry-run mode (default): Show manual commands
   ├─ Auto-fix mode: Execute via API/git with error handling
   └─ What-if mode: Log intended actions without executing
```

### Remediation Strategies

```powershell
class RemediationPlan {
    [ValidationIssue[]]$Issues
    [hashtable]$Dependencies  # Issue dependencies (tree structure)
    
    [ValidationIssue[]] GetExecutionOrder() {
        # Topological sort based on dependencies
        # Example: Create v1.0.0 before creating v1.0 pointing to it
    }
}
```

## Implementation Phases

### Phase 1: Code Organization and Visualization (Low Risk) ✓
- [x] Add comprehensive section headers to main.ps1
- [x] Create Write-StateSummary function for state visualization
- [x] Display current repository state before validation runs
- [x] Improve inline documentation
- [x] Create REFACTORING_PLAN.md document
- [x] All 81 tests passing

### Phase 2: Extract Utilities into Modules (Low Risk)
- [ ] Create lib/Logging.ps1
- [ ] Create lib/VersionParser.ps1  
- [ ] Create lib/GitHubApi.ps1
- [ ] Update main.ps1 to dot-source these modules
- [ ] Run tests to verify no breakage

### Phase 3: Add State Model (Medium Risk)
- [ ] Create lib/StateModel.ps1 with classes
- [ ] Add state collection functions
- [ ] Add state diff calculation
- [ ] Add diff visualization (write to console BEFORE any fixes)
- [ ] Run tests

### Phase 4: Refactor Validation Logic (Medium Risk)
- [ ] Extract validation functions to lib/Validator.ps1
- [ ] Keep existing validation flow but use cleaner functions
- [ ] Run tests

### Phase 5: Improve Remediation (Medium Risk)
- [ ] Create lib/Remediation.ps1
- [ ] Add dependency tree for changes
- [ ] Improve what-if mode logging
- [ ] Add better retry logic with exponential backoff
- [ ] Run tests

### Phase 6: Polish (Low Risk)
- [ ] Add comprehensive inline documentation
- [ ] Update README with architecture diagrams
- [ ] Add CONTRIBUTING.md with dev guidelines

## Testing Strategy

- Run `Invoke-Pester -Path ./main.Tests.ps1` after each change
- All 81 tests must pass before moving to next phase
- Add new tests for new functionality (state model, diff display)
- Manual testing with real repositories

## Rollback Plan

- Keep git history clean with atomic commits
- Each phase should be a separate commit
- Can revert to any previous phase if issues arise

## Future Enhancements

1. **Parallel API Calls**: Use PowerShell jobs/runspaces for faster release fetching
2. **Caching**: Cache API responses to avoid rate limits
3. **Config File**: Support .semver-checker.yml for per-repo configuration
4. **Multiple Major Versions**: Better support for v1, v2, v3 in same repo
5. **CI/CD Integration**: Special modes for different CI systems
