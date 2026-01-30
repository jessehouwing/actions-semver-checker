#############################################################################
# RemediationAction.ps1 - Base Remediation Action Class
#############################################################################
# This class provides the base interface for all remediation actions.
# Each concrete action must implement Execute() and GetManualCommands().
#############################################################################

class RemediationAction {
    [string]$Description
    [string]$Version
    [int]$Priority  # Lower number = higher priority (for ordering)
    
    RemediationAction([string]$description, [string]$version) {
        $this.Description = $description
        $this.Version = $version
        $this.Priority = 50  # Default priority
    }
    
    # Execute the auto-fix action
    [bool] Execute([RepositoryState]$state) {
        throw "Execute must be implemented in derived class"
    }
    
    # Get manual fix command(s) - without comments by default
    [string[]] GetManualCommands([RepositoryState]$state) {
        throw "GetManualCommands must be implemented in derived class"
    }
    
    [string] ToString() {
        return "$($this.Description) for $($this.Version)"
    }
}
