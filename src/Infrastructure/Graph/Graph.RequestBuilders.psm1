#region Module Information
# Name: Graph.RequestBuilders
# Purpose: Reusable Microsoft Graph request builders for common resources.
# Dependencies: Graph.Client, Graph.Query
# Exports: New-HybridGraphUsersRequest, New-HybridGraphGroupsRequest, New-HybridGraphOrganizationRequest
#endregion

Set-StrictMode -Version Latest

function New-HybridGraphUsersRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Client,
        [string]$Id = '',
        [string[]]$Select = @(),
        [string]$Filter = '',
        [string]$Search = '',
        [Nullable[int]]$Top = $null
    )

    $path = if ([string]::IsNullOrWhiteSpace($Id)) { 'users' } else { 'users/' + $Id.Trim() }
    $query = New-HybridGraphQuery -Select $Select -Filter $Filter -Search $Search -Top $Top
    return New-HybridGraphRequest -Client $Client -Path $path -Method GET -QueryString $query.QueryString -Headers @{ ConsistencyLevel = 'eventual' } -Metadata @{ Resource = 'Users'; Operation = if ($Id) { 'Get' } else { 'Search' }; Query = $query }
}

function New-HybridGraphGroupsRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Client,
        [string]$Id = '',
        [string[]]$Select = @(),
        [string]$Filter = '',
        [string]$Search = '',
        [Nullable[int]]$Top = $null
    )

    $path = if ([string]::IsNullOrWhiteSpace($Id)) { 'groups' } else { 'groups/' + $Id.Trim() }
    $query = New-HybridGraphQuery -Select $Select -Filter $Filter -Search $Search -Top $Top
    return New-HybridGraphRequest -Client $Client -Path $path -Method GET -QueryString $query.QueryString -Headers @{ ConsistencyLevel = 'eventual' } -Metadata @{ Resource = 'Groups'; Operation = if ($Id) { 'Get' } else { 'Search' }; Query = $query }
}

function New-HybridGraphOrganizationRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Client,
        [string[]]$Select = @()
    )

    $query = New-HybridGraphQuery -Select $Select
    return New-HybridGraphRequest -Client $Client -Path 'organization' -Method GET -QueryString $query.QueryString -Metadata @{ Resource = 'Organization'; Operation = 'Get'; Query = $query }
}

Export-ModuleMember -Function @(
    'New-HybridGraphUsersRequest',
    'New-HybridGraphGroupsRequest',
    'New-HybridGraphOrganizationRequest'
)
