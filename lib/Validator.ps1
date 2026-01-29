#############################################################################
# Validator.ps1 - Validation Module for SemVer Checker
#############################################################################
# This module implements a pipeline-based validation system that extracts
# validation logic from main.ps1 into reusable, testable validators.
#
# Each validator:
# - Implements a specific validation rule
# - Returns ValidationIssue objects
# - Can be tested independently
# - Supports auto-fix capability
#############################################################################

#############################################################################
# Base Validator Class
#############################################################################

class ValidatorBase {
    [string]$Name
    [string]$Description
    
    ValidatorBase([string]$name, [string]$description) {
        $this.Name = $name
        $this.Description = $description
    }
    
    # Override this method in derived classes
    [ValidationIssue[]] Validate([RepositoryState]$state, [hashtable]$config) {
        throw "Validate method must be implemented by derived class"
    }
}

#############################################################################
# Floating Version Validator
# Validates that floating versions (vX, vX.Y) have corresponding patch versions
#############################################################################

class FloatingVersionValidator : ValidatorBase {
    FloatingVersionValidator() : base("FloatingVersion", "Validates that floating versions have corresponding patch versions") {
    }
    
    [ValidationIssue[]] Validate([RepositoryState]$state, [hashtable]$config) {
        $issues = @()
        $allVersions = $state.Tags + $state.Branches
        
        Write-Host "::debug::[$($this.Name)] Validating floating versions. Total versions: $($allVersions.Count) (tags: $($state.Tags.Count), branches: $($state.Branches.Count))"
        
        foreach ($version in $allVersions) {
            Write-Host "::debug::[$($this.Name)] Checking version $($version.Version) - isMajor:$($version.IsMajor) isMinor:$($version.IsMinor) isPatch:$($version.IsPatch)"
            
            if ($version.IsMajor) {
                # Check if any patch versions exist for this major version
                $patchVersionsExist = $allVersions | Where-Object { 
                    $_.IsPatch -and $_.Major -eq $version.Major 
                }
                
                Write-Host "::debug::[$($this.Name)] Major version $($version.Version) - found $($patchVersionsExist.Count) patch versions"
                
                # Note: Missing patch versions will be detected by VersionConsistencyValidator
                # This validator just logs debug information
            }
            elseif ($version.IsMinor) {
                # Check if any patch versions exist for this minor version
                $patchVersionsExist = $allVersions | Where-Object { 
                    $_.IsPatch -and 
                    $_.Major -eq $version.Major -and 
                    $_.Minor -eq $version.Minor 
                }
                
                Write-Host "::debug::[$($this.Name)] Minor version $($version.Version) - found $($patchVersionsExist.Count) patch versions"
            }
        }
        
        return $issues
    }
}

#############################################################################
# Release Validator
# Validates that patch versions have corresponding GitHub Releases
#############################################################################

class ReleaseValidator : ValidatorBase {
    ReleaseValidator() : base("Release", "Validates that patch versions have GitHub Releases") {
    }
    
    [ValidationIssue[]] Validate([RepositoryState]$state, [hashtable]$config) {
        $issues = @()
        
        # Check if release validation is disabled
        if ($config.checkReleases -eq "none") {
            return $issues
        }
        
        # Get list of versions to ignore
        $ignoreVersions = $config.ContainsKey('ignoreVersions') ? $config.ignoreVersions : @()
        
        $releaseTagNames = $state.Releases | ForEach-Object { $_.TagName }
        $messageType = ($config.checkReleases -eq "error") ? "error" : "warning"
        
        foreach ($tag in $state.Tags) {
            # Skip if version should be ignored
            if ($ignoreVersions -contains $tag.Version) {
                Write-Host "::debug::[$($this.Name)] Skipping ignored version $($tag.Version)"
                continue
            }
            
            # Only check patch versions (vX.Y.Z format) - floating versions don't need releases
            if ($tag.IsPatch) {
                $hasRelease = $releaseTagNames -contains $tag.Version
                
                if (-not $hasRelease) {
                    $issue = [ValidationIssue]::new("missing_release", $messageType, "Version $($tag.Version) does not have a GitHub Release")
                    $issue.Version = $tag.Version
                    $issue.ManualFixCommand = "gh release create $($tag.Version) --draft --title `"$($tag.Version)`" --notes `"Release $($tag.Version)`""
                    $issues += $issue
                }
            }
        }
        
        return $issues
    }
}

#############################################################################
# Release Immutability Validator
# Validates that releases are immutable (not draft, properly attested)
#############################################################################

class ReleaseImmutabilityValidator : ValidatorBase {
    ReleaseImmutabilityValidator() : base("ReleaseImmutability", "Validates that releases are immutable") {
    }
    
    [ValidationIssue[]] Validate([RepositoryState]$state, [hashtable]$config) {
        $issues = @()
        
        # Check if immutability validation is disabled
        if ($config.checkReleaseImmutability -eq "none") {
            return $issues
        }
        
        # Get list of versions to ignore
        $ignoreVersions = $config.ContainsKey('ignoreVersions') ? $config.ignoreVersions : @()
        
        $messageType = ($config.checkReleaseImmutability -eq "error") ? "error" : "warning"
        
        foreach ($release in $state.Releases) {
            # Skip if version should be ignored
            if ($ignoreVersions -contains $release.TagName) {
                Write-Host "::debug::[$($this.Name)] Skipping ignored version $($release.TagName)"
                continue
            }
            
            # Only check releases for patch versions (vX.Y.Z format)
            if ($release.TagName -match "^v\d+\.\d+\.\d+$") {
                if ($release.IsDraft) {
                    $issue = [ValidationIssue]::new("draft_release", $messageType, "Release $($release.TagName) is still in draft status, making it mutable")
                    $issue.Version = $release.TagName
                    $issue.ManualFixCommand = "gh release edit $($release.TagName) --draft=false"
                    $issues += $issue
                }
            }
        }
        
        return $issues
    }
}

#############################################################################
# Floating Version Release Validator
# Validates that floating versions (v1, v1.0) do not have releases
#############################################################################

class FloatingVersionReleaseValidator : ValidatorBase {
    FloatingVersionReleaseValidator() : base("FloatingVersionRelease", "Validates that floating versions do not have releases") {
    }
    
    [ValidationIssue[]] Validate([RepositoryState]$state, [hashtable]$config) {
        $issues = @()
        
        # Check if release validation is disabled
        if ($config.checkReleases -eq "none" -and $config.checkReleaseImmutability -eq "none") {
            return $issues
        }
        
        # Get list of versions to ignore
        $ignoreVersions = $config.ContainsKey('ignoreVersions') ? $config.ignoreVersions : @()
        
        $messageType = (($config.checkReleaseImmutability -eq "error") -or ($config.checkReleases -eq "error")) ? "error" : "warning"
        
        foreach ($release in $state.Releases) {
            # Skip if version should be ignored
            if ($ignoreVersions -contains $release.TagName) {
                Write-Host "::debug::[$($this.Name)] Skipping ignored version $($release.TagName)"
                continue
            }
            
            # Check if this is a floating version (vX, vX.Y, or "latest")
            $isFloatingVersion = $release.TagName -match "^v\d+$" -or $release.TagName -match "^v\d+\.\d+$" -or $release.TagName -eq "latest"
            
            if ($isFloatingVersion) {
                # Check if the release is truly immutable
                $isImmutable = $release.IsImmutable
                
                if ($isImmutable) {
                    # Immutable release on a floating version - this is unfixable
                    $issue = [ValidationIssue]::new("immutable_floating_release", $messageType, "Floating version $($release.TagName) has an immutable release")
                    $issue.Version = $release.TagName
                    $issue.Status = "unfixable"
                    $issue.ManualFixCommand = "# WARNING: Cannot delete immutable release for $($release.TagName). Floating versions should not have releases."
                    $issues += $issue
                }
                else {
                    # Mutable release (draft or not immutable) on a floating version - can be auto-fixed
                    $issue = [ValidationIssue]::new("mutable_floating_release", "warning", "Floating version $($release.TagName) has a mutable release")
                    $issue.Version = $release.TagName
                    $issue.ManualFixCommand = "gh release delete $($release.TagName) --yes"
                    $issues += $issue
                }
            }
        }
        
        return $issues
    }
}

#############################################################################
# Version Consistency Validator
# Validates that floating versions point to the correct patch versions
#############################################################################

class VersionConsistencyValidator : ValidatorBase {
    VersionConsistencyValidator() : base("VersionConsistency", "Validates that floating versions point to correct patch versions") {
    }
    
    [ValidationIssue[]] Validate([RepositoryState]$state, [hashtable]$config) {
        $issues = @()
        
        # This validator is complex and handles the main version consistency logic
        # It will be populated in the next phase
        # For now, return empty array - the existing logic in main.ps1 will continue to work
        
        return $issues
    }
}

#############################################################################
# Validator Pipeline
#############################################################################

class ValidatorPipeline {
    [ValidatorBase[]]$Validators
    
    ValidatorPipeline() {
        $this.Validators = @()
    }
    
    [void] AddValidator([ValidatorBase]$validator) {
        $this.Validators += $validator
    }
    
    [ValidationIssue[]] RunValidations([RepositoryState]$state, [hashtable]$config) {
        $allIssues = @()
        
        Write-Host ""
        Write-Host "=============================================================================" -ForegroundColor Cyan
        Write-Host " Running Validation Pipeline ($($this.Validators.Count) validators)" -ForegroundColor Cyan
        Write-Host "=============================================================================" -ForegroundColor Cyan
        Write-Host ""
        
        foreach ($validator in $this.Validators) {
            Write-Host "Running validator: $($validator.Name) - $($validator.Description)" -ForegroundColor Yellow
            
            try {
                $issues = $validator.Validate($state, $config)
                $allIssues += $issues
                
                if ($issues.Count -gt 0) {
                    Write-Host "  Found $($issues.Count) issue(s)" -ForegroundColor Yellow
                } else {
                    Write-Host "  ✓ No issues found" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "::error::Validator $($validator.Name) failed: $_"
                Write-Host "::debug::$($_.ScriptStackTrace)"
            }
        }
        
        Write-Host ""
        Write-Host "=============================================================================" -ForegroundColor Cyan
        Write-Host " Validation Complete: $($allIssues.Count) total issue(s) found" -ForegroundColor Cyan
        Write-Host "=============================================================================" -ForegroundColor Cyan
        Write-Host ""
        
        return $allIssues
    }
}

#############################################################################
# Helper Function: Create Default Pipeline
#############################################################################

function New-DefaultValidatorPipeline {
    param()
    
    $pipeline = [ValidatorPipeline]::new()
    
    # Add validators in execution order
    $pipeline.AddValidator([FloatingVersionValidator]::new())
    $pipeline.AddValidator([ReleaseValidator]::new())
    $pipeline.AddValidator([ReleaseImmutabilityValidator]::new())
    $pipeline.AddValidator([FloatingVersionReleaseValidator]::new())
    # Note: VersionConsistencyValidator is not added yet - it's complex and will be migrated later
    
    return $pipeline
}
