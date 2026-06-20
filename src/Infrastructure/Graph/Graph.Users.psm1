#region Module Information
# Name: Graph.Users
# Purpose: Initial Microsoft Graph user request wrappers.
# Dependencies: Graph.Client, Graph.Models
# Exports: Search-HybridGraphUser, Get-HybridGraphUser
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

function Search-HybridGraphUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Client,
        [string]$Search = '',
        [int]$Top = 25
    )

    $query = @{ '$top' = $Top }
    if (-not [string]::IsNullOrWhiteSpace($Search)) { $query['$search'] = '"displayName:' + $Search + '"' }

    $request = New-HybridGraphRequest -Client $Client -Path 'users' -Method GET -Query $query -Headers @{ ConsistencyLevel = 'eventual' } -Metadata @{ Resource = 'Users'; Operation = 'Search' }
    $response = Invoke-HybridGraphRequest -Client $Client -GraphRequest $request

    if ($response.Succeeded -ne $true) { return $response }

    $items = @(Get-HybridGraphCollectionValue -Body $response.Body)
    if ($items.Count -eq 0) { return @() }

    return @($items | ForEach-Object { ConvertFrom-HybridGraphUser -GraphUser $_ })
}

function Get-HybridGraphUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Client,
        [Parameter(Mandatory=$true)][string]$Id
    )

    if ([string]::IsNullOrWhiteSpace($Id)) { throw 'Graph user id cannot be empty.' }
    $request = New-HybridGraphRequest -Client $Client -Path ("users/$($Id.Trim())") -Method GET -Metadata @{ Resource = 'Users'; Operation = 'Get' }
    $response = Invoke-HybridGraphRequest -Client $Client -GraphRequest $request

    if ($response.Succeeded -ne $true) { return $response }
    return ConvertFrom-HybridGraphUser -GraphUser $response.Body
}

Export-ModuleMember -Function @(
    'Search-HybridGraphUser',
    'Get-HybridGraphUser'
)
