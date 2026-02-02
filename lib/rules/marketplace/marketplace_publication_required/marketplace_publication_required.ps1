#############################################################################
# Rule: marketplace_publication_required
# Category: marketplace
# Priority: 50
#############################################################################
# This rule checks that the latest non-prerelease version has been published
# to the GitHub Marketplace by querying the public marketplace URL.
#
# The check works by fetching the marketplace page:
# https://github.com/marketplace/actions/{slug}?version={version}
# 
# If the version is published, the page shows "Use {version}".
# If not published, it falls back to "Use latest version".
#
# Publishing to the marketplace is a manual action that cannot be automated
# via API - the rule can only detect and report missing publications.
#
# This check runs late (priority 50) because it only matters after releases
# are properly set up and metadata validation has passed.
#############################################################################

# Load shared marketplace helpers
. "$PSScriptRoot/../MarketplaceRulesHelper.ps1"

$Rule_MarketplacePublicationRequired = [ValidationRule]@{
    Name = "marketplace_publication_required"
    Description = "The latest release should be published to GitHub Marketplace"
    Priority = 50
    Category = "marketplace"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when check-marketplace is enabled
        $checkMarketplace = $Config.'check-marketplace'
        if ($checkMarketplace -ne 'error' -and $checkMarketplace -ne 'warning') {
            return @()
        }
        
        # Only check if marketplace metadata is valid (otherwise action_metadata_required handles it)
        $metadata = $State.MarketplaceMetadata
        if (-not $metadata -or -not $metadata.IsValid()) {
            return @()
        }
        
        # Find the release marked as "latest" by GitHub
        $latestRelease = $State.Releases | Where-Object { 
            $_.IsLatest -and -not $_.IsIgnored 
        } | Select-Object -First 1
        
        if (-not $latestRelease) {
            # No release marked as latest - this is handled by other rules
            return @()
        }
        
        # Return the latest release for checking
        # Note: We can't actually verify marketplace publication via API,
        # so this rule serves as a reminder to the user
        return @($latestRelease)
    }
    
    Check = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        # Query the public GitHub Marketplace to verify publication status
        $metadata = $State.MarketplaceMetadata
        if (-not $metadata -or -not $metadata.HasName) {
            # Can't check without the action name - skip (metadata rule will catch this)
            return $true
        }
        
        $result = Test-MarketplaceVersionPublished `
            -ActionName $metadata.Name `
            -Version $ReleaseInfo.TagName `
            -ServerUrl $State.ServerUrl
        
        # If there was an error checking, log it but don't fail (avoid false positives)
        if ($result.Error) {
            Write-Host "::warning::Could not verify marketplace publication for $($ReleaseInfo.TagName): $($result.Error)"
            return $true
        }
        
        return $result.IsPublished
    }
    
    CreateIssue = { param([ReleaseInfo]$ReleaseInfo, [RepositoryState]$State, [hashtable]$Config)
        # This CreateIssue is called when Check returns $false (version not published to marketplace)
        
        $version = $ReleaseInfo.TagName
        $severity = if ($Config.'check-marketplace' -eq 'warning') { 'warning' } else { 'error' }
        
        $repoUrl = "$($State.ServerUrl)/$($State.RepoOwner)/$($State.RepoName)"
        
        # Get the marketplace URL for display
        $metadata = $State.MarketplaceMetadata
        $marketplaceUrl = ""
        if ($metadata -and $metadata.HasName) {
            $slug = ConvertTo-MarketplaceSlug -ActionName $metadata.Name
            $marketplaceUrl = "$($State.ServerUrl)/marketplace/actions/$slug"
        }
        
        $issue = [ValidationIssue]::new(
            "marketplace_not_published",
            $severity,
            "Release $version is not published to GitHub Marketplace"
        )
        $issue.Version = $version
        
        # No auto-fix available - marketplace publication is manual
        $issue.Status = "manual_fix_required"
        $issue.ManualFixCommand = @"
# To publish $version to GitHub Marketplace:
# 
# 1. Go to: $repoUrl/releases/tag/$version
# 2. Click 'Edit' on the release
# 3. Check 'Publish this Action to the GitHub Marketplace'
# 4. Review and accept the GitHub Marketplace Developer Agreement (if not already done)
# 5. Select the appropriate categories for your action
# 6. Click 'Update release'
#
# After publishing, the action will be available at:
# $marketplaceUrl`?version=$version
#
# Note: You must have verified your email and have a published README.md
# with action.yaml containing name, description, and branding fields.
"@
        
        return $issue
    }
}

# Export the rule
$Rule_MarketplacePublicationRequired
