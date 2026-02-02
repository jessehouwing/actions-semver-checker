---
name: Executing tests for this project using Pester
description: Explains how to run tests efficiently for this project.
---

# Testing guidance
To ensure the quality and reliability of the code in this project, it's important to run the tests regularly. Below are the instructions on how to execute the tests effectively.

# Tools
This project uses the Pester framework for testing. Make sure you have Pester installed and that you are using at least version 5 in your PowerShell environment. You can install it via PowerShell Gallery if you haven't done so already:

```powershell
Install-Module -Name Pester -MinimumVersion 5 -Scope CurrentUser
```

WHEN POSSIBLE LEVERAGE TOOLS TO RUN TESTS. Leverage the following tools in Visual Studio Code to run tests:

 * use the vscode #runTests tool - to execute tests in the project
 * use the vscode #testFailure tool - to get access to the failing tests and details

 Sample prompt to run the tests:

 ```
 Run the tests using #runtests in the #folder:tests/unit
 ```

 Inspect the failed tests using the #testFailure tool.

# Efficiency

The tests are split up in several files to make it easier to run only a subset of tests when working on specific rules. You can run tests for a specific rule by executing the corresponding test file.

The following tests are FAST and can be run frequently during development:

 * lib/rules/<rule-name>/<rule-name>.tests.ps1
 * tests/Unit/*.tests.ps1

The following tests are SLOW and should be run less frequently, for example before committing code or creating a pull request:

 * tests/integration/*.tests.ps1
 * tests/e2e/*.tests.ps1

 When asked to run ALL tests, run the tests incrementally. Run the fast tests first, followed by the slow tests.

 # Running tests from the commandline

 When running Pester tests from the commandline, use the Pester v5 configuration object syntax. The legacy parameter syntax (`-OutputFormat`, `-OutputFile`, `-PassThru`) cannot be mixed with `-Configuration`.

 Example with configuration object:
 ```powershell
 $logDir = './artifacts/pester'
 New-Item -Path $logDir -ItemType Directory -Force | Out-Null
 $config = New-PesterConfiguration
 $config.Run.Path = './lib/rules/<rule-name>/<rule-name>.tests.ps1'
 $config.Run.PassThru = $true
 $config.Output.Verbosity = 'Detailed'
 $config.TestResult.Enabled = $true
 $config.TestResult.OutputFormat = 'NUnitXml'
 $config.TestResult.OutputPath = "$logDir/results.xml"
 $results = Invoke-Pester -Configuration $config
 $results | ConvertTo-Json -Depth 10 | Set-Content "$logDir/results.json"
 ```

 Simple syntax (without configuration object):
 ```powershell
 Invoke-Pester -Path tests/unit -Output Detailed
 ```

When running the tests fom the commandline, ALWAYS use a clean PowerShell session to avoid any interference from previously loaded modules or variables.

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path './tests/cli/GitHubActionVersioning.Tests.ps1' -Output Detailed"
```

 **Note:** `-PassThru` must be set via `$config.Run.PassThru = $true` when using configuration objects, not as a separate parameter.

 Rely on the XML/JSON output files to find failing tests without having to run tests again. Instead of running the tests twice to get additional details, use result files to find the failing tests and then optionally rerun only those tests if needed.