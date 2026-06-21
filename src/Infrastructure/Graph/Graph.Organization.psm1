#region Module Information
# Name: Graph.Organization
# Purpose: Initial Microsoft Graph organization request wrapper.
# Dependencies: Graph.Client, Graph.Models
# Exports: Get-HybridGraphOrganization
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

function Get-HybridGraphOrganization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Client
    )

    $request = New-HybridGraphRequest -Client $Client -Path 'organization' -Method GET -Metadata @{ Resource = 'Organization'; Operation = 'Get' }
    $response = Invoke-HybridGraphRequest -Client $Client -GraphRequest $request

    if ($response.Succeeded -ne $true) { return $response }

    $items = @(Get-HybridGraphCollectionValue -Body $response.Body)
    if ($items.Count -eq 0) { return $null }

    return ConvertFrom-HybridGraphOrganization -GraphOrganization $items[0]
}

Export-ModuleMember -Function @('Get-HybridGraphOrganization')
