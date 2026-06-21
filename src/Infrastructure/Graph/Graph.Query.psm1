#region Module Information
# Name: Graph.Query
# Purpose: Reusable OData query construction for Microsoft Graph requests.
# Dependencies: None
# Exports: New-HybridGraphQuery, ConvertTo-HybridGraphQueryString
#endregion

Set-StrictMode -Version Latest

function ConvertTo-HybridGraphQueryString {
    [CmdletBinding()]
    param(
        [string[]]$Select = @(),
        [string]$Filter = '',
        [string[]]$Expand = @(),
        [string[]]$OrderBy = @(),
        [Nullable[int]]$Top = $null,
        [string]$Search = '',
        [hashtable]$AdditionalParameters = @{}
    )

    $pairs = New-Object System.Collections.Generic.List[string]
    if ($Select.Count -gt 0) { $pairs.Add('$select=' + [System.Uri]::EscapeDataString(($Select -join ','))) }
    if (-not [string]::IsNullOrWhiteSpace($Filter)) { $pairs.Add('$filter=' + [System.Uri]::EscapeDataString($Filter)) }
    if ($Expand.Count -gt 0) { $pairs.Add('$expand=' + [System.Uri]::EscapeDataString(($Expand -join ','))) }
    if ($OrderBy.Count -gt 0) { $pairs.Add('$orderby=' + [System.Uri]::EscapeDataString(($OrderBy -join ','))) }
    if ($null -ne $Top) { $pairs.Add('$top=' + [System.Uri]::EscapeDataString([string]$Top)) }
    if (-not [string]::IsNullOrWhiteSpace($Search)) { $pairs.Add('$search=' + [System.Uri]::EscapeDataString($Search)) }

    if ($null -ne $AdditionalParameters) {
        foreach ($key in ($AdditionalParameters.Keys | Sort-Object)) {
            $name = [string]$key
            if (-not $name.StartsWith('$')) { $name = '$' + $name }
            $pairs.Add($name + '=' + [System.Uri]::EscapeDataString([string]$AdditionalParameters[$key]))
        }
    }

    return ($pairs -join '&')
}

function New-HybridGraphQuery {
    [CmdletBinding()]
    param(
        [string[]]$Select = @(),
        [string]$Filter = '',
        [string[]]$Expand = @(),
        [string[]]$OrderBy = @(),
        [Nullable[int]]$Top = $null,
        [string]$Search = '',
        [hashtable]$AdditionalParameters = @{}
    )

    $queryString = ConvertTo-HybridGraphQueryString -Select $Select -Filter $Filter -Expand $Expand -OrderBy $OrderBy -Top $Top -Search $Search -AdditionalParameters $AdditionalParameters

    [pscustomobject]@{
        PSTypeName           = 'Hybrid.GraphQuery'
        Select               = @($Select)
        Filter               = $Filter
        Expand               = @($Expand)
        OrderBy              = @($OrderBy)
        Top                  = $Top
        Search               = $Search
        AdditionalParameters = @{} + $AdditionalParameters
        QueryString          = $queryString
    }
}

Export-ModuleMember -Function @(
    'New-HybridGraphQuery',
    'ConvertTo-HybridGraphQueryString'
)
