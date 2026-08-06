$sdkPath = Join-Path $PSScriptRoot '..\..\HAP.ProviderSdk.psm1'
Import-Module -Name $sdkPath -Force

function Invoke-HapProviderOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProviderId,
        [Parameter(Mandatory=$true)][string]$CapabilityId,
        [Parameter(Mandatory=$true)][string]$Operation,
        [string]$PayloadJson = '{}'
    )

    if ($ProviderId -ne 'contoso.identity') {
        return New-HapProviderResult -Errors @(
            New-HapProviderError -Code 'Contoso.ProviderMismatch' -Message 'Provider ID does not match this sample provider.'
        )
    }

    switch ($Operation) {
        'TestConnection' {
            return New-HapProviderResult -Succeeded -Data ([pscustomobject]@{
                status = 'Healthy'
                providerId = $ProviderId
            })
        }
        'GetSampleUser' {
            $payload = $PayloadJson | ConvertFrom-Json
            return New-HapProviderResult -Succeeded -Data ([pscustomobject]@{
                userPrincipalName = [string]$payload.UserPrincipalName
                displayName = 'Ada Lovelace'
                source = 'Contoso.Identity.Sample'
                capabilityId = $CapabilityId
            })
        }
        default {
            return New-HapProviderResult -Errors @(
                New-HapProviderError -Code 'Contoso.OperationUnsupported' -Message "Operation '$Operation' is not supported." -Target $Operation
            )
        }
    }
}

Export-ModuleMember -Function Invoke-HapProviderOperation
