Import-Module -Name (Join-Path $PSScriptRoot '..\HILOP.ProviderSdk.psm1') -Force

function Invoke-HapProviderOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProviderId,
        [Parameter(Mandatory=$true)][string]$CapabilityId,
        [Parameter(Mandatory=$true)][string]$Operation,
        [string]$PayloadJson = '{}'
    )

    switch ($Operation) {
        'TestConnection' {
            return New-HapProviderResult -Succeeded -Data ([pscustomobject]@{ status = 'Healthy' })
        }
        default {
            return New-HapProviderResult -Errors @(
                New-HapProviderError -Code 'Provider.OperationUnsupported' -Message "Operation '$Operation' is not supported." -Target $Operation
            )
        }
    }
}

Export-ModuleMember -Function Invoke-HapProviderOperation
