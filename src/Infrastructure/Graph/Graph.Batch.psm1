#region Module Information
# Name: Graph.Batch
# Purpose: Microsoft Graph batch request and response contracts.
# Dependencies: None
# Exports: New-HybridGraphBatchRequest, Add-HybridGraphBatchStep, New-HybridGraphBatchResponse
#endregion

Set-StrictMode -Version Latest

function New-HybridGraphBatchRequest {
    [CmdletBinding()]
    param(
        [string]$BatchId = ([guid]::NewGuid().ToString()),
        [object[]]$Steps = @()
    )

    $list = New-Object System.Collections.Generic.List[object]
    foreach ($step in @($Steps)) { $list.Add($step) }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.GraphBatchRequest'
        BatchId    = $BatchId
        Steps      = $list
        CreatedOn  = [datetime]::UtcNow
    }
}

function Add-HybridGraphBatchStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$BatchRequest,
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][ValidateSet('GET','POST','PUT','PATCH','DELETE')][string]$Method,
        [Parameter(Mandatory=$true)][string]$Url,
        [hashtable]$Headers = @{},
        [object]$Body = $null
    )

    if ($BatchRequest.PSObject.Properties.Name -notcontains 'Steps') { throw 'Invalid batch request. Missing Steps property.' }
    $step = [pscustomobject]@{
        PSTypeName = 'Hybrid.GraphBatchStep'
        Id         = $Id
        Method     = $Method.ToUpperInvariant()
        Url        = $Url
        Headers    = @{} + $Headers
        Body       = $Body
    }
    $BatchRequest.Steps.Add($step) | Out-Null
    return $BatchRequest
}

function New-HybridGraphBatchResponse {
    [CmdletBinding()]
    param(
        [string]$BatchId = '',
        [object[]]$Responses = @(),
        [bool]$Succeeded = $true
    )

    [pscustomobject]@{
        PSTypeName = 'Hybrid.GraphBatchResponse'
        BatchId    = $BatchId
        Responses  = @($Responses)
        Succeeded  = $Succeeded
        CreatedOn  = [datetime]::UtcNow
    }
}

Export-ModuleMember -Function @(
    'New-HybridGraphBatchRequest',
    'Add-HybridGraphBatchStep',
    'New-HybridGraphBatchResponse'
)
