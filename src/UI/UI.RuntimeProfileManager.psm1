Set-StrictMode -Version Latest

function Get-HybridRuntimeProfileDisplayLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Profile)

    $prefix = '  '
    if ($Profile.IsLastUsed) { $prefix = '> ' }
    elseif ($Profile.IsDefault) { $prefix = '* ' }
    $status = if ($Profile.IsValid) { 'Ready' } else { 'Invalid' }
    return ('{0}{1}  [{2} / {3} / {4}]' -f $prefix, $Profile.ProfileName, $Profile.CloudEnvironment, $Profile.RuntimeMode, $status)
}

function Select-HybridRuntimeProfileSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Profiles,
        [AllowNull()][object]$PreferredSelection,
        [string]$PreferredProfileName = ''
    )

    if ($Profiles.Count -eq 0) { return $null }

    if (-not [string]::IsNullOrWhiteSpace($PreferredProfileName)) {
        $named = @($Profiles | Where-Object { [string]::Equals($_.ProfileName, $PreferredProfileName, [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($_.Name, $PreferredProfileName, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if ($named.Count -gt 0) { return $named[0] }
    }

    if ($null -ne $PreferredSelection -and -not [string]::IsNullOrWhiteSpace([string]$PreferredSelection.Path)) {
        $matched = @($Profiles | Where-Object { [string]::Equals($_.Path, $PreferredSelection.Path, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if ($matched.Count -gt 0) { return $matched[0] }
    }

    $default = @($Profiles | Where-Object { $_.IsDefault -and $_.IsValid } | Select-Object -First 1)
    if ($default.Count -gt 0) { return $default[0] }

    $valid = @($Profiles | Where-Object { $_.IsValid } | Select-Object -First 1)
    if ($valid.Count -gt 0) { return $valid[0] }

    return $Profiles[0]
}

Export-ModuleMember -Function @('Get-HybridRuntimeProfileDisplayLabel','Select-HybridRuntimeProfileSummary')
