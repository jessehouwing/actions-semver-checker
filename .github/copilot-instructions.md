# Copilot Instructions for Actions SemVer Checker

## Project Overview

This is a GitHub Action that validates semantic versioning tags in GitHub Action repositories. It checks that version tags (like `v1`, `v1.0`, `v1.0.0`) are properly created and point to the correct commits, following GitHub Actions best practices where major and minor version tags should float to the latest patch release.

The action helps maintainers ensure their action's version tags are correctly maintained, providing clear error messages and suggested git commands to fix any issues found.

## Tech Stack

- **PowerShell 7+** (pwsh) - Primary scripting language
- **Git** - For version tag inspection and validation
- **Pester** - PowerShell testing framework
- **GitHub Actions** - Composite action runtime environment

## Coding Guidelines & Conventions

### PowerShell Standards
- Use PowerShell 7+ syntax (pwsh, not Windows PowerShell)
- Follow PowerShell best practices for function naming (`Verb-Noun` format)
- Use `param()` blocks for function parameters with type hints
- Prefer explicit variable scoping (`$script:`, `$global:`)
- Use `Write-Output` for user-facing messages

### Version Validation Logic
- Versions must follow semantic versioning: `vMAJOR`, `vMAJOR.MINOR`, or `vMAJOR.MINOR.PATCH`
- Major version tags (e.g., `v1`) should point to the latest minor version
- Minor version tags (e.g., `v1.0`) should point to the latest patch version
- The `latest` tag should point to the highest semantic version
- Support both tags and branches for version references

### Error Handling
- Use `write-actions-error` for validation failures (sets exit code to 1)
- Use `write-actions-warning` for non-critical issues
- Always provide suggested git commands to fix issues
- Format error messages using GitHub Actions annotation syntax: `::error title=...`

### Testing
- All logic should be testable with Pester tests in `main.Tests.ps1`
- Tests should create temporary git repositories to validate behavior
- Use `BeforeAll`, `BeforeEach`, `Context`, and `It` blocks appropriately
- Test both success and failure scenarios
- Include parameterized tests for multiple scenarios

## Project Structure

```
.
├── .github/
│   ├── workflows/          # CI/CD workflows (Pester tests, CodeQL, etc.)
│   ├── dependabot.yml      # Dependency update configuration
│   └── renovate.json       # Renovate bot configuration
├── action.yaml             # GitHub Action metadata and entry point
├── main.ps1                # Main validation logic
├── main.Tests.ps1          # Pester test suite
├── README.md               # User documentation
├── SECURITY.md             # Security policy
└── LICENSE                 # MIT license
```

## Build, Test & Validation Instructions

### Running Tests Locally
```bash
# Install Pester (if not already installed)
pwsh -Command "Install-Module -Name Pester -Force -Scope CurrentUser"

# Run tests
pwsh -Command "Invoke-Pester -Path ./main.Tests.ps1"

# Run tests with detailed output
pwsh -Command "Invoke-Pester -Path ./main.Tests.ps1 -Output Detailed"

# Run tests in CI mode (used by GitHub Actions)
pwsh -Command "Invoke-Pester -Path ./main.Tests.ps1 -CI"
```

### Manual Testing
To manually test the action in a repository:
1. Ensure the repository has git tags following semver (e.g., `v1.0.0`)
2. Clone with full history: `git clone --depth=0 <repo>`
3. Run the script: `pwsh -Command "./main.ps1"`
4. Check the output for any errors or suggested fixes

### CI/CD
- Pester tests run on every push and pull request to `main`
- Tests must pass before merging
- CodeQL security scanning is enabled
- Dependabot and Renovate keep dependencies up to date

## Boundaries & Restrictions

### Files to Never Modify
- `.github/dependabot.yml` - Managed by repository owner
- `.github/renovate.json` - Managed by repository owner
- `LICENSE` - MIT license terms
- `.github/CODEOWNERS` - Repository ownership configuration
- `.github/FUNDING.yml` - Sponsorship configuration

### Code Practices to Avoid
- Do not use Windows PowerShell-specific cmdlets (must work on Linux/macOS with pwsh)
- Do not use hard-coded paths - use relative paths from `$env:GITHUB_ACTION_PATH`
- Do not modify git state (no checkouts, commits, pushes) - only read operations
- Do not add external dependencies or modules - keep the action self-contained
- Avoid breaking changes to the action's inputs or outputs without major version bump

### Security Considerations
- Never log or expose sensitive information (tokens, credentials)
- Validate all input parameters before use
- Use safe git operations (read-only where possible)
- Follow principle of least privilege in permissions

## Testing Philosophy

- **Unit tests** validate individual functions and logic paths
- **Integration tests** verify git operations with real repositories
- **Parameterized tests** cover multiple scenarios efficiently
- Tests should be fast and not require external dependencies
- Mock external services when necessary
- Use temporary directories (`$TestDrive`) for test isolation

## Common Tasks

### Adding a new validation rule
1. Add the validation logic in `main.ps1`
2. Write comprehensive Pester tests in `main.Tests.ps1`
3. Update README.md if the behavior affects users
4. Ensure suggested fix commands are generated
5. Run all tests to verify no regressions

### Fixing a bug
1. Add a failing test that reproduces the bug
2. Fix the bug in `main.ps1`
3. Verify the test now passes
4. Run full test suite to check for regressions

### Adding a new input parameter
1. Add the input to `action.yaml` with description and default
2. Read the input using `${env:INPUT_<NAME>}` in `main.ps1`
3. Add tests for the new parameter's behavior
4. Document the parameter in README.md
