#region Module Information
# Name: Graph.Error
# Purpose: Translates Microsoft Graph error responses into HAP platform error objects.
# Dependencies: Core.HttpResponse
# Exports: ConvertFrom-HybridGraphError, New-HybridGraphError
#endregion

Set-StrictMode -Version Latest

function Get-HybridGraphValue {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

function New-HybridGraphError {
    [CmdletBinding()]
    param(
        [string]$Code = 'GraphError',
        [string]$Message = '',
        [int]$StatusCode = 0,
        [string]$RequestId = '',
        [string]$ClientRequestId = '',
        [string]$CorrelationId = '',
        [string]$RetryAfter = '',
        [object]$InnerError = $null,
        [object]$RawError = $null
    )

    [pscustomobject]@{
        PSTypeName      = 'Hybrid.GraphError'
        Code            = $Code
        Message         = $Message
        StatusCode      = $StatusCode
        RequestId       = $RequestId
        ClientRequestId = $ClientRequestId
        CorrelationId   = $CorrelationId
        RetryAfter      = $RetryAfter
        InnerError      = $InnerError
        RawError        = $RawError
    }
}

function ConvertFrom-HybridGraphError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$HttpResponse
    )

    $body = if ($HttpResponse.PSObject.Properties.Name -contains 'Body') { $HttpResponse.Body } else { $null }
    $headers = if ($HttpResponse.PSObject.Properties.Name -contains 'Headers') { $HttpResponse.Headers } else { @{} }
    $status = if ($HttpResponse.PSObject.Properties.Name -contains 'StatusCode') { [int]$HttpResponse.StatusCode } else { 0 }

    $errorNode = Get-HybridGraphValue -Object $body -Name 'error'
    if ($null -eq $errorNode) { $errorNode = $body }

    $inner = Get-HybridGraphValue -Object $errorNode -Name 'innerError'
    $requestId = Get-HybridGraphValue -Object $inner -Name 'request-id'
    if ([string]::IsNullOrWhiteSpace([string]$requestId)) { $requestId = Get-HybridGraphValue -Object $inner -Name 'requestId' }
    if ([string]::IsNullOrWhiteSpace([string]$requestId) -and $headers -is [System.Collections.IDictionary] -and $headers.Contains('request-id')) { $requestId = $headers['request-id'] }

    $clientRequestId = Get-HybridGraphValue -Object $inner -Name 'client-request-id'
    if ([string]::IsNullOrWhiteSpace([string]$clientRequestId)) { $clientRequestId = Get-HybridGraphValue -Object $inner -Name 'clientRequestId' }
    if ([string]::IsNullOrWhiteSpace([string]$clientRequestId) -and $headers -is [System.Collections.IDictionary] -and $headers.Contains('client-request-id')) { $clientRequestId = $headers['client-request-id'] }

    $retryAfter = ''
    if ($headers -is [System.Collections.IDictionary] -and $headers.Contains('Retry-After')) { $retryAfter = [string]$headers['Retry-After'] }

    return New-HybridGraphError -Code ([string](Get-HybridGraphValue -Object $errorNode -Name 'code')) -Message ([string](Get-HybridGraphValue -Object $errorNode -Name 'message')) -StatusCode $status -RequestId ([string]$requestId) -ClientRequestId ([string]$clientRequestId) -CorrelationId ([string]$clientRequestId) -RetryAfter $retryAfter -InnerError $inner -RawError $body
}

Export-ModuleMember -Function @(
    'ConvertFrom-HybridGraphError',
    'New-HybridGraphError'
)
