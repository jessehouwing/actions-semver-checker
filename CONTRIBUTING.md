# Contributing to Actions SemVer Checker

Thank you for your interest in contributing to the Actions SemVer Checker! This document provides guidelines and information to help you contribute effectively.

## Table of Contents

- [Development Setup](#development-setup)
- [Architecture Overview](#architecture-overview)
- [Module Guide](#module-guide)
- [Testing Guidelines](#testing-guidelines)
- [Code Style](#code-style)
- [Pull Request Process](#pull-request-process)
- [Reporting Issues](#reporting-issues)

## Development Setup

### Prerequisites

- **PowerShell 7+**: Required for development and testing
- **Git**: For version control
- **Pester**: PowerShell testing framework (included in PowerShell 7+)

### Clone and Setup

```bash
git clone https://github.com/jessehouwing/actions-semver-checker.git
cd actions-semver-checker
```

### Running Tests

Run all tests:
```powershell
Invoke-Pester -Path ./tests
```

Run tests with detailed output:
```powershell
Invoke-Pester -Path ./tests -Output Detailed
```

Run specific test category:
```powershell
# Unit tests only
Invoke-Pester -Path ./tests/unit

# Integration tests only
Invoke-Pester -Path ./tests/integration

# End-to-end tests only
Invoke-Pester -Path ./tests/e2e
```

**Important**: All tests must pass before submitting a PR.

## Architecture Overview

The codebase follows a modular architecture with a rule-based validation system:

```
actions-semver-checker/
├── main.ps1              # Orchestrator script (~350 lines)
├── lib/                  # Core modules (~3,246 lines total)
│   ├── StateModel.ps1    # Domain model classes (~639 lines)
│   ├── GitHubApi.ps1     # GitHub REST API functions (~1,165 lines)
│   ├── ValidationRules.ps1  # Rule engine (~163 lines)
│   ├── RemediationActions.ps1  # Action base class (~48 lines)
│   ├── Remediation.ps1   # Auto-fix coordination (~301 lines)
│   ├── InputValidation.ps1  # Input parsing (~325 lines)
│   ├── Logging.ps1       # Safe output utilities (~105 lines)
│   └── VersionParser.ps1 # Version parsing logic (~150 lines)
│
├── lib/rules/            # Validation rules (20 rules organized by category)
│   ├── ref_type/         # Reference type validation (5 rules)
│   │   ├── tag_should_be_branch/
│   │   ├── branch_should_be_tag/
│   │   ├── duplicate_floating_version_ref/
│   │   ├── duplicate_latest_ref/
│   │   └── duplicate_patch_version_ref/
│   │
│   ├── releases/         # Release validation (4 rules)
│   │   ├── patch_release_required/
│   │   ├── release_should_be_published/
│   │   ├── release_should_be_immutable/
│   │   └── floating_version_no_release/
│   │
│   ├── version_tracking/ # Version tracking (9 rules)
│   │   ├── major_tag_missing/
│   │   ├── major_tag_tracks_highest_patch/
│   │   ├── major_branch_missing/
│   │   ├── major_branch_tracks_highest_patch/
│   │   ├── minor_tag_missing/
│   │   ├── minor_tag_tracks_highest_patch/
│   │   ├── minor_branch_missing/
│   │   ├── minor_branch_tracks_highest_patch/
│   │   └── patch_tag_missing/
│   │
│   └── latest/           # Latest version tracking (2 rules)
│       ├── latest_tag_tracks_global_highest/
│       └── latest_branch_tracks_global_highest/
│
├── lib/actions/          # Remediation actions (13 actions organized by type)
│   ├── base/             # Base class and documentation
│   ├── tags/             # Tag operations (3 actions)
│   │   ├── CreateTagAction/
│   │   ├── UpdateTagAction/
│   │   └── DeleteTagAction/
│   │
│   ├── branches/         # Branch operations (3 actions)
│   │   ├── CreateBranchAction/
│   │   ├── UpdateBranchAction/
│   │   └── DeleteBranchAction/
│   │
│   ├── releases/         # Release operations (4 actions)
│   │   ├── CreateReleaseAction/
│   │   ├── PublishReleaseAction/
│   │   ├── RepublishReleaseAction/
│   │   └── DeleteReleaseAction/
│   │
│   └── conversions/      # Type conversions (2 actions)
│       ├── ConvertTagToBranchAction/
│       └── ConvertBranchToTagAction/
│
├── tests/                # Test suite
│   ├── TestHelpers.psm1  # Shared test utilities
│   ├── unit/             # Unit tests for modules
│   │   ├── GitHubApi.Tests.ps1
│   │   ├── Logging.Tests.ps1
│   │   ├── RemediationActions.Tests.ps1
│   │   └── VersionParser.Tests.ps1
│   ├── integration/      # Integration tests (example-based)
│   │   └── SemVerChecker.Tests.ps1
│   └── e2e/              # End-to-end validation tests
│       └── SemVerValidation.Tests.ps1
│
└── action.yaml           # GitHub Action definition
```

### Design Principles

1. **Rule-Based Validation**: All checks implemented as modular rules that can be independently configured
2. **Single Source of Truth**: All state tracked in `RepositoryState` domain model
3. **Status-Based Calculation**: Metrics calculated on-demand from issue statuses
4. **Separation of Concerns**: Each module and rule has a single, well-defined responsibility
5. **Priority-Based Execution**: Rules execute in priority order to handle dependencies correctly
6. **Action Composition**: Complex fixes composed from simple, reusable actions
7. **Testability**: Modules and rules can be tested independently
8. **Zero Breaking Changes**: Backward compatibility is paramount

## Module Guide

### main.ps1 (Orchestrator)

The main script coordinates the validation workflow:

1. **Initialize State**: Create `RepositoryState` object
2. **Load Modules**: Dot-source all lib/*.ps1 files
3. **Parse Inputs**: Read and validate action inputs from environment
4. **Collect State**: Gather tags, branches, releases from GitHub API
5. **Load Rules**: Auto-discover validation rules from lib/rules/
6. **Execute Rules**: Run validation rules in priority order
7. **Execute Remediation**: Apply auto-fixes if enabled
8. **Report Results**: Display summary and exit with appropriate code

**Key responsibilities:**
- Workflow orchestration
- Input parsing and validation
- State collection from GitHub API
- Rule loading and execution
- Result reporting

### lib/StateModel.ps1 (Domain Model)

Core domain classes representing the problem space:

**Classes:**
- `VersionRef`: Represents a version tag or branch with semantic parsing
- `ReleaseInfo`: Represents a GitHub release with immutability status
- `ValidationIssue`: Tracks a validation issue with status ("pending", "fixed", "failed", "unfixable", "manual_fix_required")
- `RepositoryState`: Central state object containing all data and configuration
- `RemediationPlan`: Handles issue dependencies and execution ordering

**Calculated Methods:**
- `GetFixedIssuesCount()`: Count of successfully fixed issues
- `GetFailedFixesCount()`: Count of failed fix attempts
- `GetUnfixableIssuesCount()`: Count of issues that cannot be auto-fixed
- `GetReturnCode()`: Calculate exit code based on error presence

**When to modify:**
- Adding new domain entities
- Adding calculated properties
- Extending validation issue types

### lib/GitHubApi.ps1 (External Integration)

All GitHub REST API interactions:

**Functions:**
- `Get-ApiHeaders`: Build authorization headers
- `Get-GitHubRepoInfo`: Retrieve repository information
- `Get-GitHubReleases`: Fetch releases with pagination
- `Get-GitHubTags`: Fetch tags via REST API
- `Get-GitHubBranches`: Fetch branches via REST API
- `Test-ReleaseImmutability`: Check if release has attestations
- `New-GitHubRef`: Create new tag/branch reference
- `Update-GitHubRef`: Update existing tag/branch reference
- `Remove-GitHubRef`: Delete tag/branch reference
- `New-GitHubRelease`: Create GitHub release (draft or published)
- `New-GitHubDraftRelease`: Alias for `New-GitHubRelease` (backward compatibility)
- `Remove-GitHubRelease`: Delete release
- `Publish-GitHubRelease`: Publish draft release
- `Invoke-WithRetry`: Retry wrapper with exponential backoff

**When to modify:**
- Adding new API endpoints
- Changing API call patterns
- Implementing rate limiting/retry logic

### lib/ValidationRules.ps1 (Rule Engine)

Rule discovery and execution engine:

**Classes:**
- `ValidationRule`: Base class for all validation rules with Priority, Category, Condition, Check, CreateIssue

**Functions:**
- `Get-ValidationRule`: Auto-discover rules from lib/rules/ directory
- `Invoke-ValidationRule`: Execute rules in priority order
- `Test-IsPrerelease`: Helper to check if a version is a prerelease

**When to modify:**
- Changing rule discovery logic
- Adding new rule execution patterns
- Implementing rule filtering

### lib/RemediationActions.ps1 (Action Base)

Base class for all remediation actions:

**Classes:**
- `RemediationAction`: Abstract base class with Execute() and GetManualCommands() methods

**When to modify:**
- Extending base action functionality
- Adding common action behaviors

### lib/Remediation.ps1 (Auto-fix Coordination)

Strategies for coordinating and executing fixes:

**Functions:**
- `Invoke-AutoFix`: Execute a single auto-fix action
- `Get-ImmutableReleaseRemediationCommands`: Generate commands for release conflicts
- `New-RemediationPlan`: Create execution plan with priority ordering

**When to modify:**
- Adding new auto-fix strategies
- Changing remediation coordination logic
- Implementing new fix patterns

### lib/InputValidation.ps1 (Input Parsing)

Action input parsing and validation:

**Functions:**
- `Read-ActionInput`: Parse inputs from environment JSON
- `Test-ActionInput`: Validate input configuration
- `Write-InputDebugInfo`: Output debug information

**When to modify:**
- Adding new input parameters
- Changing input validation logic
- Implementing input normalization

### lib/Logging.ps1 (Safe Output)

Workflow command injection protection:

**Functions:**
- `Write-SafeOutput`: Safely output untrusted data
- `Write-ActionsError`: Log error with optional State tracking
- `Write-ActionsWarning`: Log warning
- `Write-ActionsMessage`: Log message with severity

**When to modify:**
- Adding new output patterns
- Changing error handling
- Implementing new logging levels

### lib/VersionParser.ps1 (Parsing)

Version string parsing and validation:

**Functions:**
- `ConvertTo-Version`: Parse semantic version strings

**When to modify:**
- Changing version parsing logic
- Supporting new version formats
- Adding validation rules

### lib/rules/ (Validation Rules)

Individual validation rule implementations. Each rule is a self-contained PowerShell script that exports a `ValidationRule` object.

**Rule Structure:**
- `Name`: Unique identifier (e.g., "patch_release_required")
- `Description`: Human-readable description
- `Priority`: Execution order (5-40, lower runs first)
- `Category`: Grouping (ref_type, releases, version_tracking, latest)
- `Condition`: ScriptBlock that filters items to validate
- `Check`: ScriptBlock that returns $true if item is valid
- `CreateIssue`: ScriptBlock that creates ValidationIssue + RemediationAction

**Adding New Rules:**
1. Create a new directory in the appropriate category (ref_type, releases, version_tracking, latest)
2. Add a `.ps1` file with the rule implementation
3. Add a `README.md` documenting the rule
4. Export the ValidationRule object at the end of the file
5. The rule will be automatically discovered and loaded

**When to modify:**
- Adding new validation checks
- Changing existing rule behavior
- Updating rule priorities

### lib/actions/ (Remediation Actions)

Individual remediation action implementations. Each action is a PowerShell class that extends `RemediationAction`.

**Action Structure:**
- Inherits from `RemediationAction` base class
- Implements `Execute([RepositoryState]$state)` method
- Implements `GetManualCommands([RepositoryState]$state)` method
- Has a `Priority` property for execution ordering

**Action Categories:**
- **tags/**: CreateTagAction, UpdateTagAction, DeleteTagAction
- **branches/**: CreateBranchAction, UpdateBranchAction, DeleteBranchAction
- **releases/**: CreateReleaseAction, PublishReleaseAction, RepublishReleaseAction, DeleteReleaseAction
- **conversions/**: ConvertTagToBranchAction, ConvertBranchToTagAction

**Adding New Actions:**
1. Create a new directory in the appropriate category
2. Add a `.ps1` file with the action class implementation
3. Add a `README.md` documenting the action
4. The action is referenced by rules via ValidationIssue.RemediationAction

**When to modify:**
- Adding new types of fixes
- Changing existing action behavior
- Updating action priorities

**When to modify:**
- Adding new auto-fix strategies
- Changing remediation logic
- Implementing new fix patterns

### lib/Logging.ps1 (Safe Output)

Workflow command injection protection:

**Functions:**
- `Write-SafeOutput`: Safely output untrusted data
- `Write-ActionsError`: Log error with optional State tracking
- `Write-ActionsWarning`: Log warning
- `Write-ActionsMessage`: Log message with severity

**When to modify:**
- Adding new output patterns
- Changing error handling
- Implementing new logging levels

### lib/VersionParser.ps1 (Parsing)

Version string parsing and validation:

**Functions:**
- `ConvertTo-Version`: Parse semantic version strings

**When to modify:**
- Changing version parsing logic
- Supporting new version formats
- Adding validation rules

## Testing Guidelines

### Test Structure

Tests are organized into three categories:

```
tests/
├── TestHelpers.psm1      # Shared test utilities (mock creation, repo setup)
├── unit/                 # Unit tests - test individual functions in isolation
├── integration/          # Integration tests - test module interactions
└── e2e/                  # End-to-end tests - test complete workflows
```

**Unit Tests** (`tests/unit/`): Test individual functions from lib/ modules with mocked dependencies.

**Integration Tests** (`tests/integration/`): Test module interactions with example-based scenarios.

**End-to-End Tests** (`tests/e2e/`): Test complete validation workflows by running main.ps1 with various configurations against temporary git repositories.

### Writing Tests

1. **Use descriptive test names**: Clearly state what is being tested
   ```powershell
   It "Should detect missing minor version tags" {
       # Test code
   }
   ```

2. **Isolate tests**: Each test should be independent
3. **Clean up**: Tests use temporary directories that are cleaned automatically
4. **Mock external calls**: Use `New-GitBasedApiMock` from TestHelpers for API mocking

### Test Categories

- **Version validation tests**: Check floating version logic (e2e)
- **Release validation tests**: Verify release requirements (e2e)
- **Auto-fix tests**: Ensure fixes work correctly (e2e)
- **Edge case tests**: Handle unusual scenarios (e2e)
- **API tests**: GitHub API interaction (unit/integration)
- **Parsing tests**: Version string parsing (unit)
- **Rule tests**: Individual validation rule behavior (unit)

### Testing Rules

Each validation rule should have a corresponding test file (e.g., `patch_release_required.Tests.ps1`) that tests:

1. **Condition Block**: Verify the rule applies only when expected
2. **Check Block**: Test the validation logic
3. **CreateIssue Block**: Ensure issues are created correctly with proper RemediationAction

**Example Rule Test Structure:**

```powershell
BeforeAll {
    . "$PSScriptRoot/../../../StateModel.ps1"
    . "$PSScriptRoot/../../../ValidationRules.ps1"
    . "$PSScriptRoot/../../../RemediationActions.ps1"
    . "$PSScriptRoot/patch_release_required.ps1"
}

Describe "patch_release_required" {
    Context "Condition" {
        It "should return items when rule applies" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $config = @{ 'check-releases' = 'error' }
            
            $result = & $Rule_PatchReleaseRequired.Condition $state $config
            
            $result.Count | Should -Be 1
        }
    }
    
    Context "CreateIssue" {
        It "should create issue with CreateReleaseAction" {
            $versionRef = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $state = [RepositoryState]::new()
            $config = @{ 'check-releases' = 'error' }
            
            $issue = & $Rule_PatchReleaseRequired.CreateIssue $versionRef $state $config
            
            $issue.Type | Should -Be "missing_release"
            $issue.RemediationAction.GetType().Name | Should -Be "CreateReleaseAction"
        }
    }
}
```

### Testing Actions

Each remediation action should have tests that verify:

1. **Execute Method**: Test successful execution and error handling
2. **GetManualCommands Method**: Verify manual fix commands are correct
3. **Priority**: Ensure priority is set correctly for execution ordering

**Example Action Test Structure:**

```powershell
Describe "CreateTagAction" {
    It "should execute successfully" {
        $state = [RepositoryState]::new()
        $action = [CreateTagAction]::new("v1.0.0", "abc123")
        
        # Mock the API call
        Mock New-GitHubRef { return $true }
        
        $result = $action.Execute($state)
        
        $result | Should -Be $true
        Should -Invoke New-GitHubRef -Times 1
    }
    
    It "should generate correct manual commands" {
        $state = [RepositoryState]::new()
        $action = [CreateTagAction]::new("v1.0.0", "abc123")
        
        $commands = $action.GetManualCommands($state)
        
        $commands | Should -Contain "git push origin abc123:refs/tags/v1.0.0"
    }
}
```

### Adding New Tests

When adding new functionality:

1. Add tests first (TDD approach)
2. Ensure tests fail initially
3. Implement functionality
4. Verify tests pass
5. Run full test suite

## Code Style

### PowerShell Style Guide

**Naming Conventions:**
- **Functions**: PascalCase with Verb-Noun pattern (e.g., `Get-GitHubRelease`)
- **Variables**: camelCase (e.g., `$autoFix`)
- **Parameters**: PascalCase (e.g., `-TagName`)
- **Classes**: PascalCase (e.g., `RepositoryState`)

**Best Practices:**
- Use `[Parameter()]` attributes for function parameters
- Add comment-based help to public functions
- Use `$null` comparisons explicitly
- Prefer `-eq`, `-ne`, `-gt` over `==`, `!=`, `>`
- Use approved PowerShell verbs (Get, Set, New, Remove, etc.)

**Error Handling:**
- Use try/catch for error handling
- Log errors with `Write-SafeOutput` to prevent injection
- Return meaningful error messages

**Comments:**
- Add comments for complex logic
- Document non-obvious behavior
- Explain "why" not just "what"

### Example Code Style

```powershell
function Get-VersionInfo {
    <#
    .SYNOPSIS
    Retrieves version information from a repository.
    
    .PARAMETER State
    The repository state object.
    
    .PARAMETER Version
    The version string to retrieve.
    #>
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        
        [Parameter(Mandatory)]
        [string]$Version
    )
    
    try {
        $versionRef = $State.FindVersion($Version, "tag")
        
        if ($null -eq $versionRef) {
            Write-Host "Version $Version not found"
            return $null
        }
        
        return $versionRef
    }
    catch {
        Write-SafeOutput -Message $_.Exception.Message -Prefix "::error::"
        return $null
    }
}
```

## Pull Request Process

### Before Submitting

1. **Run all tests**: Ensure all 81 tests pass
   ```powershell
   Invoke-Pester -Path ./main.Tests.ps1
   ```

2. **Check code style**: Follow PowerShell conventions

3. **Update documentation**: If adding features, update README.md

4. **Add tests**: Include tests for new functionality

### PR Guidelines

**Title Format:**
- Use clear, descriptive titles
- Start with verb (Add, Fix, Update, etc.)
- Example: "Add support for configuration files"

**Description:**
- Explain the problem being solved
- Describe the solution approach
- List any breaking changes
- Include test results

**Checklist:**
- [ ] All tests pass
- [ ] Code follows style guidelines
- [ ] Documentation updated
- [ ] No breaking changes (or clearly documented)
- [ ] Commits are atomic and well-described

### Review Process

1. Submit PR with detailed description
2. Address review feedback
3. Maintain test coverage
4. Squash commits if requested
5. Wait for approval from maintainer

## Reporting Issues

### Bug Reports

Include:
- **Description**: Clear explanation of the issue
- **Steps to Reproduce**: Detailed steps
- **Expected Behavior**: What should happen
- **Actual Behavior**: What actually happens
- **Environment**: PowerShell version, OS, etc.
- **Logs**: Relevant error messages or logs

### Feature Requests

Include:
- **Use Case**: Why is this feature needed?
- **Proposed Solution**: How might it work?
- **Alternatives**: Other approaches considered
- **Additional Context**: Any other relevant information

## Development Workflow

### Typical Workflow

1. **Fork and clone** the repository
2. **Create feature branch**: `git checkout -b feature/your-feature`
3. **Make changes** following style guide
4. **Add tests** for new functionality
5. **Run tests**: `Invoke-Pester -Path ./main.Tests.ps1`
6. **Commit changes**: Use descriptive commit messages
7. **Push branch**: `git push origin feature/your-feature`
8. **Create PR** with detailed description

### Commit Messages

Follow conventional commit format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Adding tests
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `chore`: Maintenance tasks

**Examples:**
```
feat(validation): Add support for preview release filtering

Add new validation logic to filter preview/pre-release versions
from floating version calculations.

Closes #123
```

```
fix(api): Handle rate limiting errors gracefully

Add retry logic with exponential backoff for GitHub API calls
to prevent failures due to rate limiting.
```

## Questions or Help

If you have questions or need help:

1. Check existing [documentation](docs/)
2. Review [refactoring documents](REFACTORING_COMPLETE.md)
3. Search [existing issues](https://github.com/jessehouwing/actions-semver-checker/issues)
4. Open a new issue with the question label

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (see [LICENSE](LICENSE)).

---

Thank you for contributing to Actions SemVer Checker! 🎉
