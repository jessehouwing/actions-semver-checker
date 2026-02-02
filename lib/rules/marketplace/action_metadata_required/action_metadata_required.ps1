#############################################################################
# Rule: action_metadata_required
# Category: marketplace
# Priority: 5
#############################################################################
# This rule validates that all required marketplace metadata exists before
# creating immutable releases. GitHub Marketplace requires:
# - action.yaml or action.yml with name, description, branding.icon, branding.color
# - README.md in the repository root
#
# This check runs early (priority 5) because if metadata is missing,
# there's no point in proceeding with release immutability.
#############################################################################

# Load shared marketplace helpers
. "$PSScriptRoot/../MarketplaceRulesHelper.ps1"

$Rule_ActionMetadataRequired = [ValidationRule]@{
    Name = "action_metadata_required"
    Description = "Action metadata (name, description, branding) and README.md are required for GitHub Marketplace"
    Priority = 5
    Category = "marketplace"
    
    Condition = { param([RepositoryState]$State, [hashtable]$Config)
        # Only apply when check-marketplace is enabled
        $checkMarketplace = $Config.'check-marketplace'
        if ($checkMarketplace -ne 'error' -and $checkMarketplace -ne 'warning') {
            return @()
        }
        
        # Check if marketplace metadata is valid
        $metadata = $State.MarketplaceMetadata
        if (-not $metadata) {
            # Return a synthetic item to trigger the check
            return @([PSCustomObject]@{ Type = 'metadata_check' })
        }
        
        if (-not $metadata.IsValid()) {
            # Return a synthetic item to trigger the check
            return @([PSCustomObject]@{ Type = 'metadata_check'; Metadata = $metadata })
        }
        
        return @()
    }
    
    Check = { param($Item, [RepositoryState]$State, [hashtable]$Config)
        # If we got here from Condition, metadata is invalid
        return $false
    }
    
    CreateIssue = { param($Item, [RepositoryState]$State, [hashtable]$Config)
        $metadata = $State.MarketplaceMetadata
        $missing = $metadata.GetMissingRequirements()
        
        $severity = if ($Config.'check-marketplace' -eq 'warning') { 'warning' } else { 'error' }
        
        $message = "GitHub Marketplace requires: $($missing -join '; ')"
        
        $issue = [ValidationIssue]::new(
            "missing_marketplace_metadata",
            $severity,
            $message
        )
        
        # No auto-fix available - user must manually add the missing metadata
        $issue.Status = "manual_fix_required"
        $issue.ManualFixCommand = @"
# Missing marketplace metadata. Please add the following to your repository:

"@
        
        if (-not $metadata.ActionFileExists) {
            $issue.ManualFixCommand += @"

# Create action.yaml with required fields:
cat > action.yaml << 'EOF'
name: 'Your Action Name'
description: 'A brief description of what your action does'
branding:
  icon: 'check-circle'  # See: https://feathericons.com/
  color: 'blue'         # Options: white, yellow, blue, green, orange, red, purple, gray-dark

# ... rest of your action configuration
EOF
"@
        } else {
            if (-not $metadata.HasName) {
                $issue.ManualFixCommand += "`n# Add 'name' property to $($metadata.ActionFilePath)"
            }
            if (-not $metadata.HasDescription) {
                $issue.ManualFixCommand += "`n# Add 'description' property to $($metadata.ActionFilePath)"
            }
            if (-not $metadata.HasBrandingIcon -or -not $metadata.HasBrandingColor) {
                $issue.ManualFixCommand += @"

# Add branding section to $($metadata.ActionFilePath):
branding:
  icon: 'check-circle'  # See: https://feathericons.com/
  color: 'blue'         # Options: white, yellow, blue, green, orange, red, purple, gray-dark
"@
            }
        }
        
        if (-not $metadata.ReadmeExists) {
            $issue.ManualFixCommand += @"

# Create README.md in the repository root with documentation for your action
"@
        }
        
        return $issue
    }
}

# Export the rule
$Rule_ActionMetadataRequired
