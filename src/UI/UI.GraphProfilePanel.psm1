#region Module Information
# Name: UI.GraphProfilePanel
# Purpose: Reusable Microsoft Graph vertical card helpers for the desktop UI.
#endregion

Set-StrictMode -Version Latest

function Format-HybridGraphUiDate {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '—' }
    try { return ([datetime]$Value).ToLocalTime().ToString('g') } catch { return [string]$Value }
}

function Format-HybridGraphUiBool {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'Unknown' }
    if ([bool]$Value) { return 'Yes' }
    return 'No'
}

function ConvertTo-HybridGraphProfileDisplayRows {
    [CmdletBinding()]
    param([AllowNull()][object]$GraphProfile)

    if ($null -eq $GraphProfile) {
        return @(
            [pscustomobject]@{ Label = 'Microsoft Graph'; Value = 'No Graph profile loaded.' }
        )
    }

    @(
        [pscustomobject]@{ Label = 'Graph Object ID'; Value = $GraphProfile.ObjectId }
        [pscustomobject]@{ Label = 'User Type'; Value = $GraphProfile.UserType }
        [pscustomobject]@{ Label = 'Preferred Language'; Value = $GraphProfile.PreferredLanguage }
        [pscustomobject]@{ Label = 'Usage Location'; Value = $GraphProfile.UsageLocation }
        [pscustomobject]@{ Label = 'Last Sign-In'; Value = (Format-HybridGraphUiDate $GraphProfile.LastSignInDateTime) }
        [pscustomobject]@{ Label = 'Last Non-Interactive Sign-In'; Value = (Format-HybridGraphUiDate $GraphProfile.LastNonInteractiveSignInDateTime) }
        [pscustomobject]@{ Label = 'Password Last Changed'; Value = (Format-HybridGraphUiDate $GraphProfile.PasswordLastChangedDateTime) }
        [pscustomobject]@{ Label = 'Authentication Methods'; Value = (@($GraphProfile.AuthenticationMethods) -join ', ') }
        [pscustomobject]@{ Label = 'MFA Registered'; Value = (Format-HybridGraphUiBool $GraphProfile.MfaRegistered) }
        [pscustomobject]@{ Label = 'MFA Capable'; Value = (Format-HybridGraphUiBool $GraphProfile.MfaCapable) }
        [pscustomobject]@{ Label = 'Risk State'; Value = $GraphProfile.RiskState }
    )
}

Export-ModuleMember -Function @(
    'Format-HybridGraphUiDate',
    'Format-HybridGraphUiBool',
    'ConvertTo-HybridGraphProfileDisplayRows'
)
