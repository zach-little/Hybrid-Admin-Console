#region Module Information
# Name: Core.HttpResponse
# Purpose: Standard HTTP response and error contracts for HAP cloud providers.
# Dependencies: None.
# Exports: New-HybridHttpResponse, New-HybridHttpError, Test-HybridHttpResponse
#endregion

Set-StrictMode -Version Latest

function New-HybridHttpError {
    [CmdletBinding()]
    param(
        [string]$Code = '',
        [string]$Message = '',
        [int]$StatusCode = 0,
        [object]$Details = $null,
        [object]$RawError = $null
    )

    [pscustomobject]@{
        PSTypeName  = 'Hybrid.HttpError'
        Code        = $Code
        Message     = $Message
        StatusCode  = $StatusCode
        Details     = $Details
        RawError    = $RawError
        CreatedOn   = [datetime]::UtcNow
    }
}

function New-HybridHttpResponse {
    [CmdletBinding()]
    param(
        [int]$StatusCode = 200,
        [hashtable]$Headers = @{},
        [object]$Body = $null,
        [object]$Error = $null,
        [string]$CorrelationId = '',
        [string]$RequestId = '',
        [timespan]$Duration = [timespan]::Zero,
        [int]$AttemptCount = 1,
        [string]$RequestUri = '',
        [string]$Method = 'GET',
        [object]$RawResponse = $null
    )

    $succeeded = ($StatusCode -ge 200 -and $StatusCode -lt 300 -and $null -eq $Error)

    [pscustomobject]@{
        PSTypeName    = 'Hybrid.HttpResponse'
        Succeeded     = $succeeded
        StatusCode    = $StatusCode
        Headers       = $Headers
        Body          = $Body
        Error         = $Error
        CorrelationId = $CorrelationId
        RequestId     = $RequestId
        Duration      = $Duration
        AttemptCount  = $AttemptCount
        RequestUri    = $RequestUri
        Method        = $Method
        RawResponse   = $RawResponse
        CreatedOn     = [datetime]::UtcNow
    }
}

function Test-HybridHttpResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Response
    )

    if ($null -eq $Response) { return $false }

    foreach ($propertyName in @('Succeeded', 'StatusCode', 'Headers', 'CorrelationId', 'Duration', 'AttemptCount')) {
        if ($Response.PSObject.Properties.Name -notcontains $propertyName) {
            return $false
        }
    }

    return ($Response.StatusCode -ge 100 -and $Response.StatusCode -le 599 -and $Response.AttemptCount -ge 1)
}

Export-ModuleMember -Function @(
    'New-HybridHttpResponse',
    'New-HybridHttpError',
    'Test-HybridHttpResponse'
)
