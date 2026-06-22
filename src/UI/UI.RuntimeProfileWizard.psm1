Set-StrictMode -Version Latest

function New-HybridRuntimeProfileDraft {
    [CmdletBinding()]
    param(
        [string]$ProfileName,
        [string]$Organization = 'Atlas',
        [string]$Cloud = 'Commercial',
        [string]$Mode = 'Simulation'
    )

    return [pscustomobject]@{
        PSTypeName    = 'Hybrid.RuntimeProfileDraft'
        ProfileName   = $ProfileName
        Organization  = $Organization
        Cloud         = $Cloud
        Mode          = $Mode
        IsValid       = -not [string]::IsNullOrWhiteSpace($ProfileName)
    }
}

Export-ModuleMember -Function @('New-HybridRuntimeProfileDraft')
