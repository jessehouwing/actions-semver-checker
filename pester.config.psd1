@{
    Run = @{
        Path = @(
            './tests'
            './lib/rules'
            './lib/actions'
        )
        ScriptBlock = {
            $env:GITHUB_API_DISABLE_API = 'true'
            $env:GITHUB_API_DISABLE_RETRY = 'true'
        }
        ExcludePath = @(
            './publish'
        )
    }
    Output = @{
        Verbosity = 'Detailed'
    }
    TestResult = @{
        Enabled = $true
        OutputFormat = 'NUnitXml'
        OutputPath = './artifacts/pester/results.xml'
    }
}
