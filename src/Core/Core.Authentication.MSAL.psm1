Set-StrictMode -Version Latest

function New-HybridMsalAuthenticationAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Interactive','InteractiveBrowser','AppOnly','ManagedIdentity')]
        [string]$MethodName
    )

    [pscustomobject]@{
        PSTypeName   = 'Hybrid.MsalAuthenticationAdapter'
        Name         = $MethodName
        Runtime      = 'MSAL'
        SupportsMock = $true
        Status       = 'ContractOnly'
    }
}

function Register-HybridMsalAuthenticationAdapters {
    [CmdletBinding()]
    param([switch]$Force)

    foreach ($method in 'Interactive','InteractiveBrowser','AppOnly','ManagedIdentity') {
        Register-HybridAuthenticationAdapter `
            -Name $method `
            -AcquireSession {
                param($Request)

                New-HybridAuthenticationSession `
                    -TenantContext $Request.TenantContext `
                    -CloudEnvironment $Request.CloudEnvironment `
                    -MethodName $Request.MethodName `
                    -AccessToken ('msal-contract-token-{0}' -f ([guid]::NewGuid().ToString('N'))) `
                    -Scopes $Request.Scopes `
                    -ExpiresOn (Get-Date).AddHours(1)
            } `
            -RefreshSession {
                param($Request, $ExistingSession)

                New-HybridAuthenticationSession `
                    -TenantContext $Request.TenantContext `
                    -CloudEnvironment $Request.CloudEnvironment `
                    -MethodName $Request.MethodName `
                    -AccessToken ('msal-contract-refresh-{0}' -f ([guid]::NewGuid().ToString('N'))) `
                    -Scopes $Request.Scopes `
                    -ExpiresOn (Get-Date).AddHours(1)
            } `
            -Force:$Force | Out-Null
    }

    Get-HybridAuthenticationAdapterNames
}

Export-ModuleMember -Function New-HybridMsalAuthenticationAdapter,Register-HybridMsalAuthenticationAdapters
