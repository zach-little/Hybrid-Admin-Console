#region Module Information
# Name: Graph.Diagnostics
# Purpose: Microsoft Graph diagnostics and provider runtime state contracts.
# Dependencies: None
# Exports: New-HybridGraphDiagnostic, New-HybridGraphProviderState
#endregion

Set-StrictMode -Version Latest

function New-HybridGraphDiagnostic {
    [CmdletBinding()]
    param(
        [string]$RequestId = '',
        [string]$ClientRequestId = '',
        [string]$CorrelationId = '',
        [string]$ServiceRoot = '',
        [string]$ApiVersion = 'v1.0',
        [int]$RetryCount = 0,
        [timespan]$Duration = [timespan]::Zero,
        [string]$State = 'Created'
    )

    [pscustomobject]@{
        PSTypeName      = 'Hybrid.GraphDiagnostic'
        RequestId       = $RequestId
        ClientRequestId = $ClientRequestId
        CorrelationId   = $CorrelationId
        ServiceRoot     = $ServiceRoot
        ApiVersion      = $ApiVersion
        RetryCount      = $RetryCount
        Duration        = $Duration
        State           = $State
        CreatedOn       = [datetime]::UtcNow
    }
}

function New-HybridGraphProviderState {
    [CmdletBinding()]
    param(
        [string]$Cloud = '',
        [string]$TenantId = '',
        [bool]$Authenticated = $false,
        [string]$ApiVersion = 'v1.0',
        [string[]]$Scopes = @(),
        [string]$Transport = 'Default',
        [object]$LastRequest = $null,
        [object]$LastDiagnostic = $null
    )

    [pscustomobject]@{
        PSTypeName      = 'Hybrid.GraphProviderState'
        Cloud           = $Cloud
        TenantId        = $TenantId
        Authenticated   = $Authenticated
        ApiVersion      = $ApiVersion
        Scopes          = @($Scopes)
        Transport       = $Transport
        LastRequest     = $LastRequest
        LastDiagnostic  = $LastDiagnostic
        LastRequestOn   = $null
    }
}

Export-ModuleMember -Function @(
    'New-HybridGraphDiagnostic',
    'New-HybridGraphProviderState'
)
