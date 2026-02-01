BeforeAll {
    $global:ProgressPreference = 'SilentlyContinue'
    . "$PSScriptRoot/../../lib/StateModel.ps1"
}

#############################################################################
# VersionRef Tests
#############################################################################

Describe "VersionRef" {
    Context "Version parsing" {
        It "parses patch version (v1.0.0) correctly" {
            $ref = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc1234", "tag")
            
            $ref.IsPatch | Should -BeTrue
            $ref.IsMinor | Should -BeFalse
            $ref.IsMajor | Should -BeFalse
            $ref.Major | Should -Be 1
            $ref.Minor | Should -Be 0
            $ref.Patch | Should -Be 0
        }
        
        It "parses minor version (v1.2) correctly" {
            $ref = [VersionRef]::new("v1.2", "refs/tags/v1.2", "abc1234", "tag")
            
            $ref.IsPatch | Should -BeFalse
            $ref.IsMinor | Should -BeTrue
            $ref.IsMajor | Should -BeFalse
            $ref.Major | Should -Be 1
            $ref.Minor | Should -Be 2
            $ref.Patch | Should -Be 0
        }
        
        It "parses major version (v2) correctly" {
            $ref = [VersionRef]::new("v2", "refs/tags/v2", "abc1234", "tag")
            
            $ref.IsPatch | Should -BeFalse
            $ref.IsMinor | Should -BeFalse
            $ref.IsMajor | Should -BeTrue
            $ref.Major | Should -Be 2
            $ref.Minor | Should -Be 0
            $ref.Patch | Should -Be 0
        }
        
        It "parses high version numbers correctly" {
            $ref = [VersionRef]::new("v123.456.789", "refs/tags/v123.456.789", "abc1234", "tag")
            
            $ref.IsPatch | Should -BeTrue
            $ref.Major | Should -Be 123
            $ref.Minor | Should -Be 456
            $ref.Patch | Should -Be 789
        }
        
        It "handles non-semver versions like 'latest'" {
            $ref = [VersionRef]::new("latest", "refs/tags/latest", "abc1234", "tag")
            
            $ref.IsPatch | Should -BeFalse
            $ref.IsMinor | Should -BeFalse
            $ref.IsMajor | Should -BeFalse
            $ref.Major | Should -Be 0
            $ref.Minor | Should -Be 0
            $ref.Patch | Should -Be 0
        }
        
        It "handles version without 'v' prefix" {
            $ref = [VersionRef]::new("1.0.0", "refs/tags/1.0.0", "abc1234", "tag")
            
            $ref.IsPatch | Should -BeTrue
            $ref.Major | Should -Be 1
            $ref.Minor | Should -Be 0
            $ref.Patch | Should -Be 0
        }
    }
    
    Context "Constructor properties" {
        It "stores all constructor parameters correctly" {
            $ref = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc1234567890", "tag")
            
            $ref.Version | Should -Be "v1.0.0"
            $ref.Ref | Should -Be "refs/tags/v1.0.0"
            $ref.Sha | Should -Be "abc1234567890"
            $ref.Type | Should -Be "tag"
        }
        
        It "supports branch type" {
            $ref = [VersionRef]::new("v1", "refs/heads/v1", "def5678", "branch")
            
            $ref.Type | Should -Be "branch"
            $ref.Ref | Should -Be "refs/heads/v1"
        }
    }
    
    Context "ToString" {
        It "formats output correctly" {
            $ref = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc1234", "tag")
            
            $ref.ToString() | Should -Be "v1.0.0 -> abc1234 (tag)"
        }
    }
    
    Context "IsIgnored property" {
        It "defaults to false" {
            $ref = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc1234", "tag")
            
            $ref.IsIgnored | Should -BeFalse
        }
        
        It "can be set to true" {
            $ref = [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc1234", "tag")
            $ref.IsIgnored = $true
            
            $ref.IsIgnored | Should -BeTrue
        }
    }
}

#############################################################################
# ReleaseInfo Tests
#############################################################################

Describe "ReleaseInfo" {
    Context "Constructor with explicit isImmutable parameter" {
        It "creates ReleaseInfo from REST API response with isImmutable=true" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 12345
                draft = $false
                prerelease = $false
                html_url = "https://github.com/owner/repo/releases/tag/v1.0.0"
                target_commitish = "abc1234567890"
            }
            
            $release = [ReleaseInfo]::new($apiResponse, $true)
            
            $release.TagName | Should -Be "v1.0.0"
            $release.Id | Should -Be 12345
            $release.IsDraft | Should -BeFalse
            $release.IsPrerelease | Should -BeFalse
            $release.IsImmutable | Should -BeTrue
            $release.Sha | Should -Be "abc1234567890"
            $release.HtmlUrl | Should -Be "https://github.com/owner/repo/releases/tag/v1.0.0"
        }
        
        It "creates ReleaseInfo from REST API response with isImmutable=false" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v2.0.0"
                id = 67890
                draft = $true
                prerelease = $true
                html_url = "https://github.com/owner/repo/releases/tag/v2.0.0"
            }
            
            $release = [ReleaseInfo]::new($apiResponse, $false)
            
            $release.IsDraft | Should -BeTrue
            $release.IsPrerelease | Should -BeTrue
            $release.IsImmutable | Should -BeFalse
        }
        
        It "reads IsLatest from is_latest property (REST API format)" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://example.com"
                is_latest = $true
            }
            
            $release = [ReleaseInfo]::new($apiResponse, $false)
            
            $release.IsLatest | Should -BeTrue
        }
        
        It "reads IsLatest from isLatest property (GraphQL format)" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://example.com"
                isLatest = $true
            }
            
            $release = [ReleaseInfo]::new($apiResponse, $false)
            
            $release.IsLatest | Should -BeTrue
        }
        
        It "defaults IsLatest to false when not present" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://example.com"
            }
            
            $release = [ReleaseInfo]::new($apiResponse, $false)
            
            $release.IsLatest | Should -BeFalse
        }
    }
    
    Context "Constructor with immutable property in response (GraphQL)" {
        It "reads immutable property from GraphQL response" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://example.com"
                immutable = $true
                isLatest = $false
            }
            
            $release = [ReleaseInfo]::new($apiResponse)
            
            $release.IsImmutable | Should -BeTrue
            $release.IsLatest | Should -BeFalse
        }
        
        It "defaults immutable to false when not present in response" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://example.com"
            }
            
            $release = [ReleaseInfo]::new($apiResponse)
            
            $release.IsImmutable | Should -BeFalse
        }
        
        It "reads both immutable and isLatest from GraphQL response" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v3.0.0"
                id = 999
                draft = $false
                prerelease = $false
                html_url = "https://example.com"
                immutable = $true
                isLatest = $true
            }
            
            $release = [ReleaseInfo]::new($apiResponse)
            
            $release.IsImmutable | Should -BeTrue
            $release.IsLatest | Should -BeTrue
        }
    }
    
    Context "ToString" {
        It "shows draft status" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $true
                prerelease = $false
                html_url = "https://example.com"
                immutable = $true
            }
            
            $release = [ReleaseInfo]::new($apiResponse)
            
            $release.ToString() | Should -Match "draft"
        }
        
        It "shows prerelease status" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $true
                html_url = "https://example.com"
                immutable = $true
            }
            
            $release = [ReleaseInfo]::new($apiResponse)
            
            $release.ToString() | Should -Match "prerelease"
        }
        
        It "shows mutable status when not immutable" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://example.com"
                immutable = $false
            }
            
            $release = [ReleaseInfo]::new($apiResponse)
            
            $release.ToString() | Should -Match "mutable"
        }
        
        It "shows latest status" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://example.com"
                immutable = $true
                isLatest = $true
            }
            
            $release = [ReleaseInfo]::new($apiResponse)
            
            $release.ToString() | Should -Match "latest"
        }
        
        It "shows multiple statuses" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $true
                prerelease = $true
                html_url = "https://example.com"
                immutable = $false
                isLatest = $true
            }
            
            $release = [ReleaseInfo]::new($apiResponse)
            $str = $release.ToString()
            
            $str | Should -Match "draft"
            $str | Should -Match "prerelease"
            $str | Should -Match "mutable"
            $str | Should -Match "latest"
        }
        
        It "shows no status brackets when immutable and not draft/prerelease/latest" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://example.com"
                immutable = $true
                isLatest = $false
            }
            
            $release = [ReleaseInfo]::new($apiResponse)
            
            $release.ToString() | Should -Be "v1.0.0"
        }
    }
    
    Context "IsIgnored property" {
        It "defaults to false" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://example.com"
            }
            
            $release = [ReleaseInfo]::new($apiResponse)
            
            $release.IsIgnored | Should -BeFalse
        }
        
        It "can be set to true" {
            $apiResponse = [PSCustomObject]@{
                tag_name = "v1.0.0"
                id = 123
                draft = $false
                prerelease = $false
                html_url = "https://example.com"
            }
            
            $release = [ReleaseInfo]::new($apiResponse)
            $release.IsIgnored = $true
            
            $release.IsIgnored | Should -BeTrue
        }
    }
}

#############################################################################
# ValidationIssue Tests
#############################################################################

Describe "ValidationIssue" {
    Context "Constructor" {
        It "creates issue with all parameters" {
            $issue = [ValidationIssue]::new("missing_tag", "error", "Tag v1.0.0 is missing")
            
            $issue.Type | Should -Be "missing_tag"
            $issue.Severity | Should -Be "error"
            $issue.Message | Should -Be "Tag v1.0.0 is missing"
        }
        
        It "defaults IsAutoFixable to false" {
            $issue = [ValidationIssue]::new("test", "warning", "Test issue")
            
            $issue.IsAutoFixable | Should -BeFalse
        }
        
        It "defaults Status to pending" {
            $issue = [ValidationIssue]::new("test", "error", "Test issue")
            
            $issue.Status | Should -Be "pending"
        }
        
        It "defaults Dependencies to empty array" {
            $issue = [ValidationIssue]::new("test", "error", "Test issue")
            
            $issue.Dependencies | Should -Be @()
        }
    }
    
    Context "SetRemediationAction" {
        It "sets action and marks as auto-fixable" {
            $issue = [ValidationIssue]::new("test", "error", "Test")
            $mockAction = [PSCustomObject]@{ Name = "MockAction" }
            
            $issue.SetRemediationAction($mockAction)
            
            $issue.RemediationAction | Should -Be $mockAction
            $issue.IsAutoFixable | Should -BeTrue
        }
        
        It "sets auto-fixable to false when action is null" {
            $issue = [ValidationIssue]::new("test", "error", "Test")
            $issue.IsAutoFixable = $true  # Set to true first
            
            $issue.SetRemediationAction($null)
            
            $issue.RemediationAction | Should -BeNull
            $issue.IsAutoFixable | Should -BeFalse
        }
    }
    
    Context "ToString" {
        It "formats error correctly" {
            $issue = [ValidationIssue]::new("test", "error", "Something went wrong")
            
            $issue.ToString() | Should -Be "ERROR: Something went wrong"
        }
        
        It "formats warning correctly" {
            $issue = [ValidationIssue]::new("test", "warning", "Check this")
            
            $issue.ToString() | Should -Be "WARNING: Check this"
        }
    }
    
    Context "Status transitions" {
        It "can transition from pending to fixed" {
            $issue = [ValidationIssue]::new("test", "error", "Test")
            $issue.Status = "fixed"
            
            $issue.Status | Should -Be "fixed"
        }
        
        It "can transition from pending to failed" {
            $issue = [ValidationIssue]::new("test", "error", "Test")
            $issue.Status = "failed"
            
            $issue.Status | Should -Be "failed"
        }
        
        It "can transition from pending to unfixable" {
            $issue = [ValidationIssue]::new("test", "error", "Test")
            $issue.Status = "unfixable"
            
            $issue.Status | Should -Be "unfixable"
        }
        
        It "can transition from pending to manual_fix_required" {
            $issue = [ValidationIssue]::new("test", "error", "Test")
            $issue.Status = "manual_fix_required"
            
            $issue.Status | Should -Be "manual_fix_required"
        }
    }
}

#############################################################################
# RepositoryState Tests
#############################################################################

Describe "RepositoryState" {
    Context "Constructor" {
        It "initializes with empty collections" {
            $state = [RepositoryState]::new()
            
            $state.Tags | Should -Be @()
            $state.Branches | Should -Be @()
            $state.Releases | Should -Be @()
            $state.Issues | Should -Be @()
        }
    }
    
    Context "AddIssue" {
        It "adds issue to collection" {
            $state = [RepositoryState]::new()
            $issue = [ValidationIssue]::new("test", "error", "Test issue")
            
            $state.AddIssue($issue)
            
            $state.Issues.Count | Should -Be 1
            $state.Issues[0].Type | Should -Be "test"
        }
        
        It "can add multiple issues" {
            $state = [RepositoryState]::new()
            
            $state.AddIssue([ValidationIssue]::new("issue1", "error", "First"))
            $state.AddIssue([ValidationIssue]::new("issue2", "warning", "Second"))
            
            $state.Issues.Count | Should -Be 2
        }
    }
    
    Context "GetErrorIssues" {
        It "returns only error issues" {
            $state = [RepositoryState]::new()
            $state.AddIssue([ValidationIssue]::new("err1", "error", "Error 1"))
            $state.AddIssue([ValidationIssue]::new("warn1", "warning", "Warning 1"))
            $state.AddIssue([ValidationIssue]::new("err2", "error", "Error 2"))
            
            $errors = $state.GetErrorIssues()
            
            $errors.Count | Should -Be 2
            $errors | ForEach-Object { $_.Severity | Should -Be "error" }
        }
    }
    
    Context "GetWarningIssues" {
        It "returns only warning issues" {
            $state = [RepositoryState]::new()
            $state.AddIssue([ValidationIssue]::new("err1", "error", "Error 1"))
            $state.AddIssue([ValidationIssue]::new("warn1", "warning", "Warning 1"))
            
            $warnings = $state.GetWarningIssues()
            
            $warnings.Count | Should -Be 1
            $warnings[0].Severity | Should -Be "warning"
        }
    }
    
    Context "GetAutoFixableIssues" {
        It "returns only auto-fixable issues" {
            $state = [RepositoryState]::new()
            
            $fixable = [ValidationIssue]::new("fix", "error", "Fixable")
            $fixable.IsAutoFixable = $true
            
            $notFixable = [ValidationIssue]::new("nofix", "error", "Not fixable")
            
            $state.AddIssue($fixable)
            $state.AddIssue($notFixable)
            
            $autoFix = $state.GetAutoFixableIssues()
            
            $autoFix.Count | Should -Be 1
            $autoFix[0].Type | Should -Be "fix"
        }
    }
    
    Context "GetManualFixIssues" {
        It "returns issues with manual fix commands that are not auto-fixable" {
            $state = [RepositoryState]::new()
            
            $manual = [ValidationIssue]::new("manual", "error", "Manual fix")
            $manual.ManualFixCommand = "git tag v1.0.0"
            
            $autoFix = [ValidationIssue]::new("auto", "error", "Auto fixable")
            $autoFix.IsAutoFixable = $true
            $autoFix.ManualFixCommand = "git tag v1.0.0"
            
            $noFix = [ValidationIssue]::new("none", "error", "No fix")
            
            $state.AddIssue($manual)
            $state.AddIssue($autoFix)
            $state.AddIssue($noFix)
            
            $manualFixes = $state.GetManualFixIssues()
            
            $manualFixes.Count | Should -Be 1
            $manualFixes[0].Type | Should -Be "manual"
        }
    }
    
    Context "GetFixedIssuesCount" {
        It "counts issues with fixed status" {
            $state = [RepositoryState]::new()
            
            $fixed1 = [ValidationIssue]::new("fix1", "error", "Fixed 1")
            $fixed1.Status = "fixed"
            
            $fixed2 = [ValidationIssue]::new("fix2", "error", "Fixed 2")
            $fixed2.Status = "fixed"
            
            $pending = [ValidationIssue]::new("pending", "error", "Pending")
            
            $state.AddIssue($fixed1)
            $state.AddIssue($fixed2)
            $state.AddIssue($pending)
            
            $state.GetFixedIssuesCount() | Should -Be 2
        }
    }
    
    Context "GetFailedFixesCount" {
        It "counts issues with failed status" {
            $state = [RepositoryState]::new()
            
            $failed = [ValidationIssue]::new("fail", "error", "Failed")
            $failed.Status = "failed"
            
            $fixed = [ValidationIssue]::new("fix", "error", "Fixed")
            $fixed.Status = "fixed"
            
            $state.AddIssue($failed)
            $state.AddIssue($fixed)
            
            $state.GetFailedFixesCount() | Should -Be 1
        }
    }
    
    Context "GetUnfixableIssuesCount" {
        It "counts issues with unfixable status" {
            $state = [RepositoryState]::new()
            
            $unfixable = [ValidationIssue]::new("unfix", "error", "Unfixable")
            $unfixable.Status = "unfixable"
            
            $pending = [ValidationIssue]::new("pending", "error", "Pending")
            
            $state.AddIssue($unfixable)
            $state.AddIssue($pending)
            
            $state.GetUnfixableIssuesCount() | Should -Be 1
        }
    }
    
    Context "GetManualFixRequiredCount" {
        It "counts issues with manual_fix_required status" {
            $state = [RepositoryState]::new()
            
            $manual = [ValidationIssue]::new("manual", "error", "Manual")
            $manual.Status = "manual_fix_required"
            
            $fixed = [ValidationIssue]::new("fix", "error", "Fixed")
            $fixed.Status = "fixed"
            
            $state.AddIssue($manual)
            $state.AddIssue($fixed)
            
            $state.GetManualFixRequiredCount() | Should -Be 1
        }
    }
    
    Context "GetReturnCode" {
        It "returns 0 when all issues are fixed" {
            $state = [RepositoryState]::new()
            
            $fixed = [ValidationIssue]::new("fix", "error", "Fixed")
            $fixed.Status = "fixed"
            
            $state.AddIssue($fixed)
            
            $state.GetReturnCode() | Should -Be 0
        }
        
        It "returns 0 when no issues exist" {
            $state = [RepositoryState]::new()
            
            $state.GetReturnCode() | Should -Be 0
        }
        
        It "returns 1 when there are failed issues" {
            $state = [RepositoryState]::new()
            
            $failed = [ValidationIssue]::new("fail", "error", "Failed")
            $failed.Status = "failed"
            
            $state.AddIssue($failed)
            
            $state.GetReturnCode() | Should -Be 1
        }
        
        It "returns 1 when there are unfixable issues" {
            $state = [RepositoryState]::new()
            
            $unfixable = [ValidationIssue]::new("unfix", "error", "Unfixable")
            $unfixable.Status = "unfixable"
            
            $state.AddIssue($unfixable)
            
            $state.GetReturnCode() | Should -Be 1
        }
        
        It "returns 1 when there are manual_fix_required issues" {
            $state = [RepositoryState]::new()
            
            $manual = [ValidationIssue]::new("manual", "error", "Manual")
            $manual.Status = "manual_fix_required"
            
            $state.AddIssue($manual)
            
            $state.GetReturnCode() | Should -Be 1
        }
        
        It "returns 0 when pending issues exist but nothing failed" {
            $state = [RepositoryState]::new()
            
            $pending = [ValidationIssue]::new("pending", "error", "Pending")
            $pending.Status = "pending"
            
            $state.AddIssue($pending)
            
            # Pending issues don't cause failure - they haven't been processed yet
            # This is consistent with the implementation in GetReturnCode()
            $state.GetReturnCode() | Should -Be 0
        }
    }
    
    Context "GetPatchVersions" {
        It "returns patch versions from both tags and branches" {
            $state = [RepositoryState]::new()
            $state.Tags = @(
                [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "sha1", "tag"),
                [VersionRef]::new("v1", "refs/tags/v1", "sha2", "tag")
            )
            $state.Branches = @(
                [VersionRef]::new("v2.0.0", "refs/heads/v2.0.0", "sha3", "branch")
            )
            
            $patches = $state.GetPatchVersions()
            
            $patches.Count | Should -Be 2
            $patches | Where-Object { $_.Version -eq "v1.0.0" } | Should -Not -BeNullOrEmpty
            $patches | Where-Object { $_.Version -eq "v2.0.0" } | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "GetMinorVersions" {
        It "returns minor versions from both tags and branches" {
            $state = [RepositoryState]::new()
            $state.Tags = @(
                [VersionRef]::new("v1.0", "refs/tags/v1.0", "sha1", "tag")
            )
            $state.Branches = @(
                [VersionRef]::new("v2.1", "refs/heads/v2.1", "sha2", "branch")
            )
            
            $minors = $state.GetMinorVersions()
            
            $minors.Count | Should -Be 2
        }
    }
    
    Context "GetMajorVersions" {
        It "returns major versions from both tags and branches" {
            $state = [RepositoryState]::new()
            $state.Tags = @(
                [VersionRef]::new("v1", "refs/tags/v1", "sha1", "tag")
            )
            $state.Branches = @(
                [VersionRef]::new("v2", "refs/heads/v2", "sha2", "branch")
            )
            
            $majors = $state.GetMajorVersions()
            
            $majors.Count | Should -Be 2
        }
    }
    
    Context "FindVersion" {
        BeforeEach {
            $script:state = [RepositoryState]::new()
            $script:state.Tags = @(
                [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "sha1", "tag"),
                [VersionRef]::new("v2.0.0", "refs/tags/v2.0.0", "sha2", "tag")
            )
            $script:state.Branches = @(
                [VersionRef]::new("v1.0.0", "refs/heads/v1.0.0", "sha3", "branch"),
                [VersionRef]::new("v3.0.0", "refs/heads/v3.0.0", "sha4", "branch")
            )
        }
        
        It "finds version in tags when type is tag" {
            $found = $script:state.FindVersion("v1.0.0", "tag")
            
            $found | Should -Not -BeNullOrEmpty
            $found.Type | Should -Be "tag"
            $found.Sha | Should -Be "sha1"
        }
        
        It "finds version in branches when type is branch" {
            $found = $script:state.FindVersion("v1.0.0", "branch")
            
            $found | Should -Not -BeNullOrEmpty
            $found.Type | Should -Be "branch"
            $found.Sha | Should -Be "sha3"
        }
        
        It "searches tags first when type is not specified" {
            $found = $script:state.FindVersion("v1.0.0", $null)
            
            $found | Should -Not -BeNullOrEmpty
            $found.Type | Should -Be "tag"
        }
        
        It "falls back to branches when not found in tags" {
            $found = $script:state.FindVersion("v3.0.0", $null)
            
            $found | Should -Not -BeNullOrEmpty
            $found.Type | Should -Be "branch"
        }
        
        It "returns null when version not found" {
            $found = $script:state.FindVersion("v9.9.9", "tag")
            
            $found | Should -BeNullOrEmpty
        }
    }
    
    Context "FindRelease" {
        It "finds release by tag name" {
            $state = [RepositoryState]::new()
            $state.Releases = @(
                [ReleaseInfo]::new([PSCustomObject]@{
                    tag_name = "v1.0.0"
                    id = 100
                    draft = $false
                    prerelease = $false
                    html_url = "https://example.com"
                }),
                [ReleaseInfo]::new([PSCustomObject]@{
                    tag_name = "v2.0.0"
                    id = 200
                    draft = $false
                    prerelease = $false
                    html_url = "https://example.com"
                })
            )
            
            $found = $state.FindRelease("v2.0.0")
            
            $found | Should -Not -BeNullOrEmpty
            $found.Id | Should -Be 200
        }
        
        It "returns null when release not found" {
            $state = [RepositoryState]::new()
            $state.Releases = @()
            
            $found = $state.FindRelease("v1.0.0")
            
            $found | Should -BeNullOrEmpty
        }
    }
}
