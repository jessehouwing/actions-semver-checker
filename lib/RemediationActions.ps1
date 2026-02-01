#############################################################################
# RemediationActions.ps1 - Remediation Action Classes Loader
#############################################################################
# This module loads all remediation action classes from their individual files.
# Each action class is defined in its own folder under lib/actions/.
#############################################################################

# Get the directory containing this script
$script:ActionsRoot = Join-Path $PSScriptRoot "actions"

#############################################################################
# Load Base Classes (must load first)
#############################################################################

. (Join-Path $script:ActionsRoot "base/RemediationAction.ps1")
. (Join-Path $script:ActionsRoot "base/ReleaseRemediationAction.ps1")

#############################################################################
# Load Tag Actions
#############################################################################

. (Join-Path $script:ActionsRoot "tags/CreateTagAction/CreateTagAction.ps1")
. (Join-Path $script:ActionsRoot "tags/UpdateTagAction/UpdateTagAction.ps1")
. (Join-Path $script:ActionsRoot "tags/DeleteTagAction/DeleteTagAction.ps1")

#############################################################################
# Load Branch Actions
#############################################################################

. (Join-Path $script:ActionsRoot "branches/CreateBranchAction/CreateBranchAction.ps1")
. (Join-Path $script:ActionsRoot "branches/UpdateBranchAction/UpdateBranchAction.ps1")
. (Join-Path $script:ActionsRoot "branches/DeleteBranchAction/DeleteBranchAction.ps1")

#############################################################################
# Load Release Actions
#############################################################################

. (Join-Path $script:ActionsRoot "releases/CreateReleaseAction/CreateReleaseAction.ps1")
. (Join-Path $script:ActionsRoot "releases/PublishReleaseAction/PublishReleaseAction.ps1")
. (Join-Path $script:ActionsRoot "releases/RepublishReleaseAction/RepublishReleaseAction.ps1")
. (Join-Path $script:ActionsRoot "releases/DeleteReleaseAction/DeleteReleaseAction.ps1")
. (Join-Path $script:ActionsRoot "releases/SetLatestReleaseAction/SetLatestReleaseAction.ps1")

#############################################################################
# Load Conversion Actions
#############################################################################

. (Join-Path $script:ActionsRoot "conversions/ConvertTagToBranchAction/ConvertTagToBranchAction.ps1")
. (Join-Path $script:ActionsRoot "conversions/ConvertBranchToTagAction/ConvertBranchToTagAction.ps1")
