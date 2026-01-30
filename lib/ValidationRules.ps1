#############################################################################
# ValidationRules.ps1 - Rule engine and helper functions
#############################################################################

. "$PSScriptRoot/StateModel.ps1"

class ValidationRule {
    [string]$Name            # Unique identifier (e.g., "patch_release_required")
    [string]$Description     # Human-readable description
    [int]$Priority           # Lower values run first
    [string]$Category        # Grouping category (ref_type, version_tracking, releases, etc.)
    [scriptblock]$Condition  # Returns items to validate
    [scriptblock]$Check      # Returns $true when the item is already valid
    [scriptblock]$CreateIssue # Creates a ValidationIssue when the item is invalid
}

function Get-AllValidationRules {
    param(
        [string]$RulesPath = (Join-Path -Path $PSScriptRoot -ChildPath "rules")
    )

    if (-not (Test-Path $RulesPath)) {
        return @()
    }

    $rules = @()
    $ruleFiles = Get-ChildItem -Path $RulesPath -Recurse -Filter "*.ps1" |
        Where-Object { $_.Name -notmatch '\.Tests\.ps1$' }

    foreach ($file in $ruleFiles) {
        $loaded = . $file.FullName
        if ($loaded -is [ValidationRule]) {
            $rules += $loaded
        }
    }

    return $rules | Sort-Object -Property Priority, Name
}

function Get-ValidationRules {
    param(
        [hashtable]$Config = @{},
        [string]$RulesPath
    )

    $pathToUse = if ($RulesPath) { $RulesPath } else { Join-Path -Path $PSScriptRoot -ChildPath "rules" }
    return Get-AllValidationRules -RulesPath $pathToUse
}

function Invoke-ValidationRules {
    param(
        [Parameter(Mandatory)]
        [RepositoryState]$State,
        [hashtable]$Config = @{},
        [ValidationRule[]]$Rules
    )

    $rulesToRun = if ($Rules) { $Rules } else { Get-ValidationRules -Config $Config }
    if (-not $rulesToRun -or $rulesToRun.Count -eq 0) {
        return @()
    }

    $addedIssues = @()

    foreach ($rule in ($rulesToRun | Sort-Object -Property Priority, Name)) {
        if (-not ($rule -is [ValidationRule])) { continue }
        if (-not $rule.Condition) { throw "Rule '$($rule.Name)' is missing a Condition scriptblock." }
        if (-not $rule.Check) { throw "Rule '$($rule.Name)' is missing a Check scriptblock." }
        if (-not $rule.CreateIssue) { throw "Rule '$($rule.Name)' is missing a CreateIssue scriptblock." }

        $items = & $rule.Condition $State $Config
        if ($null -eq $items) { continue }

        foreach ($item in @($items)) {
            $isValid = & $rule.Check $item $State $Config
            if (-not $isValid) {
                $issue = & $rule.CreateIssue $item $State $Config
                if ($issue -is [ValidationIssue]) {
                    $State.AddIssue($issue)
                    $addedIssues += $issue
                }
            }
        }
    }

    return $addedIssues
}

# Helper function to check if a version is a prerelease by looking up its Release
function Test-IsPrerelease {
    param(
        [Parameter(Mandatory)][RepositoryState]$State,
        [Parameter(Mandatory)][VersionRef]$VersionRef
    )
    
    # Look up the release for this version
    $release = $State.Releases | Where-Object { $_.TagName -eq $VersionRef.Version } | Select-Object -First 1
    
    # If no release exists, it's not a prerelease
    if (-not $release) { return $false }
    
    return $release.IsPrerelease
}

function Get-HighestPatchForMajor {
    param(
        [Parameter(Mandatory)][RepositoryState]$State,
        [Parameter(Mandatory)][int]$Major,
        [bool]$ExcludePrereleases = $false
    )

    $patches = ($State.Tags + $State.Branches) | Where-Object {
        $_.IsPatch -and
        -not $_.IsIgnored -and
        $_.Major -eq $Major -and
        (-not $ExcludePrereleases -or -not (Test-IsPrerelease -State $State -VersionRef $_))
    }

    return $patches | Sort-Object -Property Major, Minor, Patch -Descending | Select-Object -First 1
}

function Get-HighestPatchForMinor {
    param(
        [Parameter(Mandatory)][RepositoryState]$State,
        [Parameter(Mandatory)][int]$Major,
        [Parameter(Mandatory)][int]$Minor,
        [bool]$ExcludePrereleases = $false
    )

    $patches = ($State.Tags + $State.Branches) | Where-Object {
        $_.IsPatch -and
        -not $_.IsIgnored -and
        $_.Major -eq $Major -and
        $_.Minor -eq $Minor -and
        (-not $ExcludePrereleases -or -not (Test-IsPrerelease -State $State -VersionRef $_))
    }

    return $patches | Sort-Object -Property Major, Minor, Patch -Descending | Select-Object -First 1
}

function Get-HighestMinorForMajor {
    param(
        [Parameter(Mandatory)][RepositoryState]$State,
        [Parameter(Mandatory)][int]$Major,
        [bool]$ExcludePrereleases = $false
    )

    $candidates = ($State.Tags + $State.Branches) | Where-Object {
        -not $_.IsIgnored -and
        $_.Major -eq $Major -and
        (-not $ExcludePrereleases -or -not (Test-IsPrerelease -State $State -VersionRef $_))
    }

    if (-not $candidates) { return $null }

    $patchCandidates = $candidates | Where-Object { $_.IsPatch }
    if ($patchCandidates) {
        return $patchCandidates | Sort-Object -Property Minor, Patch -Descending | Select-Object -First 1
    }

    $minorCandidates = $candidates | Where-Object { $_.IsMinor }
    return $minorCandidates | Sort-Object -Property Minor -Descending | Select-Object -First 1
}
