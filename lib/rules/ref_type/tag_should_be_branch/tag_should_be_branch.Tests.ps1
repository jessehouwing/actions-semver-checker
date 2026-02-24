#############################################################################
# Tests for Rule: tag_should_be_branch
#############################################################################

BeforeAll {
    $global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../../lib/StateModel.ps1"
    . "$PSScriptRoot/../../../../lib/ValidationRules.ps1"
    . "$PSScriptRoot/../../../../lib/RemediationActions.ps1"
    . "$PSScriptRoot/tag_should_be_branch.ps1"
}

Describe "tag_should_be_branch" {
    Context "Condition" {
        It "returns major tags when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "branches" }

            $result = & $Rule_TagShouldBeBranch.Condition $state $config

            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1"
        }

        It "returns minor tags when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "branches" }

            $result = & $Rule_TagShouldBeBranch.Condition $state $config

            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v1.0"
        }

        It "does not return patch tags when floating-versions-use is 'branches'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "branches" }

            $result = & $Rule_TagShouldBeBranch.Condition $state $config

            $result.Count | Should -Be 0
        }

        It "returns empty array when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "tags" }

            $result = & $Rule_TagShouldBeBranch.Condition $state $config

            $result.Count | Should -Be 0
        }

        It "excludes ignored versions" {
            $state = [RepositoryState]::new()
            $ignored = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $ignored.IsIgnored = $true
            $state.Tags += $ignored
            $state.Tags += [VersionRef]::new("v2", "refs/tags/v2", "def456", "tag")
            $config = @{ 'floating-versions-use' = "branches" }

            $result = & $Rule_TagShouldBeBranch.Condition $state $config

            $result.Count | Should -Be 1
            $result[0].Version | Should -Be "v2"
        }

        It "uses 'tags' as default (returns empty) when config is not set" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $config = @{}

            $result = & $Rule_TagShouldBeBranch.Condition $state $config

            $result.Count | Should -Be 0
        }

        It "returns both major and minor tags when both exist" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v2", "refs/tags/v2", "def456", "tag")
            $config = @{ 'floating-versions-use' = "branches" }

            $result = & $Rule_TagShouldBeBranch.Condition $state $config

            $result.Count | Should -Be 3
        }
    }

    Context "Check" {
        It "returns false when tag exists but branch does not" {
            $state = [RepositoryState]::new()
            $tag = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += $tag
            $config = @{}

            $result = & $Rule_TagShouldBeBranch.Check $tag $state $config

            $result | Should -Be $false
        }

        It "returns true when both tag and branch exist (let duplicate rule handle)" {
            $state = [RepositoryState]::new()
            $tag = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $branch = [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $state.Tags += $tag
            $state.Branches += $branch
            $config = @{}

            $result = & $Rule_TagShouldBeBranch.Check $tag $state $config

            $result | Should -Be $true
        }

        It "returns false when tag exists, branch exists but is ignored" {
            $state = [RepositoryState]::new()
            $tag = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $branch = [VersionRef]::new("v1", "refs/heads/v1", "abc123", "branch")
            $branch.IsIgnored = $true
            $state.Tags += $tag
            $state.Branches += $branch
            $config = @{}

            $result = & $Rule_TagShouldBeBranch.Check $tag $state $config

            $result | Should -Be $false
        }
    }

    Context "CreateIssue" {
        It "creates issue with ConvertTagToBranchAction for major tag" {
            $state = [RepositoryState]::new()
            $tag = [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "branches" }

            $issue = & $Rule_TagShouldBeBranch.CreateIssue $tag $state $config

            $issue | Should -Not -BeNullOrEmpty
            $issue.Type | Should -Be "wrong_ref_type"
            $issue.Severity | Should -Be "error"
            $issue.Version | Should -Be "v1"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "ConvertTagToBranchAction"
            $issue.RemediationAction.Version | Should -Be "v1"
        }

        It "creates issue with ConvertTagToBranchAction for minor tag" {
            $state = [RepositoryState]::new()
            $tag = [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "branches" }

            $issue = & $Rule_TagShouldBeBranch.CreateIssue $tag $state $config

            $issue | Should -Not -BeNullOrEmpty
            $issue.Type | Should -Be "wrong_ref_type"
            $issue.Version | Should -Be "v1.0"
            $issue.RemediationAction | Should -Not -BeNullOrEmpty
            $issue.RemediationAction.GetType().Name | Should -Be "ConvertTagToBranchAction"
        }

        It "uses highest patch SHA for major tag conversion when tag SHA is stale and includes warning" {
            $state = [RepositoryState]::new()
            $staleTag = [VersionRef]::new("v6", "refs/tags/v6", "767b16506b540fdce093ac79ebb8441f5f0a0e08", "tag")
            $latestPatch = [VersionRef]::new("v6.0.0", "refs/tags/v6.0.0", "452e2d19b81542ae14b68e36469883b9499fca79", "tag")
            $state.Tags += $staleTag
            $state.Tags += $latestPatch
            $config = @{ 'floating-versions-use' = "branches" }

            $issue = & $Rule_TagShouldBeBranch.CreateIssue $staleTag $state $config

            $issue.RemediationAction.GetType().Name | Should -Be "ConvertTagToBranchAction"
            $issue.RemediationAction.Sha | Should -Be "452e2d19b81542ae14b68e36469883b9499fca79"
            $issue.Message | Should -Match "WARNING: Conversion will change SHA"
        }
    }

    Context "Integration with Invoke-ValidationRule" {
        It "creates issues for floating version tags only" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0.0", "refs/tags/v1.0.0", "abc123", "tag")  # Patch - should NOT trigger
            $config = @{ 'floating-versions-use' = "branches" }

            $issues = Invoke-ValidationRule -State $state -Config $config -Rules @($Rule_TagShouldBeBranch)

            $issues.Count | Should -Be 2
            $issues[0].Version | Should -Be "v1"
            $issues[1].Version | Should -Be "v1.0"
        }

        It "creates no issues when floating-versions-use is 'tags'" {
            $state = [RepositoryState]::new()
            $state.Tags += [VersionRef]::new("v1", "refs/tags/v1", "abc123", "tag")
            $state.Tags += [VersionRef]::new("v1.0", "refs/tags/v1.0", "abc123", "tag")
            $config = @{ 'floating-versions-use' = "tags" }

            $issues = Invoke-ValidationRule -State $state -Config $config -Rules @($Rule_TagShouldBeBranch)

            $issues.Count | Should -Be 0
        }
    }
}
