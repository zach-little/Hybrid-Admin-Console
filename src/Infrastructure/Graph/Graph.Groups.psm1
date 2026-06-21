#region Module Information
# Name: Graph.Groups
# Purpose: Initial Microsoft Graph group request wrappers.
# Dependencies: Graph.Client, Graph.Models
# Exports: Search-HybridGraphGroup, Get-HybridGraphGroup
#endregion

Set-StrictMode -Version Latest

function Get-HybridGraphCollectionValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][AllowNull()][object]$Body
    )

    if ($null -eq $Body) { return @() }

    if ($Body -is [System.Collections.IDictionary]) {
        if ($Body.Contains('value')) { return @($Body['value']) }
        return @()
    }

    if ($Body.PSObject.Properties.Name -contains 'value') {
        return @($Body.value)
    }

    return @()
}

function Search-HybridGraphGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Client,
        [string]$Search = '',
        [int]$Top = 25
    )

    $query = @{ '$top' = $Top }
    if (-not [string]::IsNullOrWhiteSpace($Search)) { $query['$search'] = '"displayName:' + $Search + '"' }

    $request = New-HybridGraphRequest -Client $Client -Path 'groups' -Method GET -Query $query -Headers @{ ConsistencyLevel = 'eventual' } -Metadata @{ Resource = 'Groups'; Operation = 'Search' }
    $response = Invoke-HybridGraphRequest -Client $Client -GraphRequest $request

    if ($response.Succeeded -ne $true) { return $response }

    $items = @(Get-HybridGraphCollectionValue -Body $response.Body)
    if ($items.Count -eq 0) { return @() }

    return @($items | ForEach-Object { ConvertFrom-HybridGraphGroup -GraphGroup $_ })
}

function Get-HybridGraphGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Client,
        [Parameter(Mandatory=$true)][string]$Id
    )

    if ([string]::IsNullOrWhiteSpace($Id)) { throw 'Graph group id cannot be empty.' }
    $request = New-HybridGraphRequest -Client $Client -Path ("groups/$($Id.Trim())") -Method GET -Metadata @{ Resource = 'Groups'; Operation = 'Get' }
    $response = Invoke-HybridGraphRequest -Client $Client -GraphRequest $request

    if ($response.Succeeded -ne $true) { return $response }
    return ConvertFrom-HybridGraphGroup -GraphGroup $response.Body
}

Export-ModuleMember -Function @(
    'Search-HybridGraphGroup',
    'Get-HybridGraphGroup'
)
