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

 When running pester tests from the commandline, enable the xml output format to capture the test results in an easy to parse format. You can do this by adding the `-OutputFormat NUnitXml` parameter to the `Invoke-Pester` command. Additionally, specify the output file using the `-OutputFile` parameter. For example:

 ```powershell
 Invoke-Pester -Path .\lib\rules\<rule-name>\<rule-name>.tests.ps1 -OutputFormat NUnitXml -OutputFile .\test-results\<rule-name>-tests.xml
 ```

 Rely on the XML output file to find failing tests without having to run tests again.

 Additionally you can run Pester with the `-PassThru` parameter to get a summary of the test results directly in the console. For example:

 ```powershell
 invoke-pester tests/unit -PassThru | ConvertTo-Json | out-File -FilePath .\test-results\TestResults.json
 ```

 Instead of running the tests twice to get additional details, use result files to find the failing tests and then optionally rerun only those tests if needed.