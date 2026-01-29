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

The codebase follows a modular architecture with a domain model at its core:

```
actions-semver-checker/
├── main.ps1              # Orchestrator script
├── lib/                  # Reusable modules
│   ├── StateModel.ps1    # Domain model classes
│   ├── GitHubApi.ps1     # GitHub REST API functions
│   ├── Remediation.ps1   # Auto-fix strategies
│   ├── Logging.ps1       # Safe output utilities
│   └── VersionParser.ps1 # Version parsing logic
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
└── action.yaml           # GitHub Action definition
```

### Design Principles

1. **Single Source of Truth**: All state tracked in `RepositoryState` domain model
2. **Status-Based Calculation**: Metrics calculated on-demand from issue statuses
3. **Separation of Concerns**: Each module has a single, well-defined responsibility
4. **Testability**: Modules can be tested independently
5. **Zero Breaking Changes**: Backward compatibility is paramount

## Module Guide

### main.ps1 (Orchestrator)

The main script coordinates the validation workflow:

1. **Initialize State**: Create `RepositoryState` object
2. **Load Modules**: Dot-source all lib/*.ps1 files
3. **Collect State**: Gather tags, branches, releases from repository
4. **Run Validations**: Execute validation logic and collect issues
5. **Execute Remediation**: Apply auto-fixes if enabled
6. **Report Results**: Display summary and exit with appropriate code

**Key responsibilities:**
- Workflow orchestration
- Input parsing and validation
- State collection from git/GitHub
- Validation logic execution
- Result reporting

### lib/StateModel.ps1 (Domain Model)

Core domain classes representing the problem space:

**Classes:**
- `VersionRef`: Represents a version tag or branch with semantic parsing
- `ReleaseInfo`: Represents a GitHub release with immutability status
- `ValidationIssue`: Tracks a validation issue with status ("pending", "fixed", "failed", "unfixable")
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
- `Test-ReleaseImmutability`: Check if release has attestations
- `New-GitHubRef`: Create new tag/branch reference
- `Remove-GitHubRef`: Delete tag/branch reference
- `New-GitHubRelease`: Create GitHub release (draft or published)
- `New-GitHubDraftRelease`: Alias for `New-GitHubRelease` (backward compatibility)
- `Remove-GitHubRelease`: Delete release
- `Publish-GitHubRelease`: Publish draft release

**When to modify:**
- Adding new API endpoints
- Changing API call patterns
- Implementing rate limiting/retry logic

### lib/Remediation.ps1 (Auto-fix Logic)

Strategies for fixing validation issues:

**Functions:**
- `Invoke-AutoFix`: Execute a single auto-fix action
- `Get-ImmutableReleaseRemediationCommands`: Generate commands for release conflicts

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
- **Functions**: PascalCase with Verb-Noun pattern (e.g., `Get-GitHubReleases`)
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
