#region Module Information
# Name: Graph.EndpointBuilder
# Purpose: Reusable Microsoft Graph endpoint and resource URI builder.
# Dependencies: Core.CloudEnvironment or Graph.Client objects
# Exports: Resolve-HybridGraphEndpoint, New-HybridGraphResourceUri
#endregion

Set-StrictMode -Version Latest

function Resolve-HybridGraphEndpoint {
    [CmdletBinding(DefaultParameterSetName='Client')]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='Client')][ValidateNotNull()][object]$Client,
        [Parameter(Mandatory=$true, ParameterSetName='Tenant')][ValidateNotNull()][object]$TenantContext,
        [Parameter(Mandatory=$true, ParameterSetName='Cloud')][ValidateNotNull()][object]$CloudEnvironment,
        [string]$EndpointName = 'Graph'
    )

    $environment = $null
    if ($PSCmdlet.ParameterSetName -eq 'Client') {
        if ($Client.PSObject.Properties.Name -contains 'BaseUri' -and -not [string]::IsNullOrWhiteSpace([string]$Client.BaseUri)) {
            return ([string]$Client.BaseUri).TrimEnd('/')
        }
        if ($Client.PSObject.Properties.Name -contains 'CloudEnvironment') { $environment = $Client.CloudEnvironment }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Tenant') {
        if ($TenantContext.PSObject.Properties.Name -notcontains 'CloudEnvironment') { throw 'Tenant context does not include a CloudEnvironment property.' }
        $environment = $TenantContext.CloudEnvironment
    }
    else {
        $environment = $CloudEnvironment
    }

    if ($null -eq $environment) { throw 'Unable to resolve Graph cloud environment.' }
    if ($environment.PSObject.Properties.Name -notcontains 'Endpoints') { throw 'Cloud environment does not include an Endpoints property.' }
    if (-not $environment.Endpoints.ContainsKey($EndpointName)) { throw "Cloud environment '$($environment.Name)' does not define endpoint '$EndpointName'." }

    return ([string]$environment.Endpoints[$EndpointName]).TrimEnd('/')
}

function New-HybridGraphResourceUri {
    [CmdletBinding(DefaultParameterSetName='Client')]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='Client')][ValidateNotNull()][object]$Client,
        [Parameter(Mandatory=$true, ParameterSetName='BaseUri')][string]$BaseUri,
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$ApiVersion = '',
        [hashtable]$Query = @{},
        [string]$QueryString = ''
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Graph resource path cannot be empty.' }

    $resolvedBaseUri = $BaseUri
    $resolvedApiVersion = $ApiVersion
    if ($PSCmdlet.ParameterSetName -eq 'Client') {
        $resolvedBaseUri = Resolve-HybridGraphEndpoint -Client $Client
        if ([string]::IsNullOrWhiteSpace($resolvedApiVersion) -and $Client.PSObject.Properties.Name -contains 'ApiVersion') {
            $resolvedApiVersion = [string]$Client.ApiVersion
        }
    }
    if ([string]::IsNullOrWhiteSpace($resolvedApiVersion)) { $resolvedApiVersion = 'v1.0' }

    $base = ([string]$resolvedBaseUri).TrimEnd('/')
    $version = ([string]$resolvedApiVersion).Trim('/')
    $resourcePath = $Path.TrimStart('/')

    if ($resourcePath -match '^(v1\.0|beta)(/|$)') {
        $uri = "$base/$resourcePath"
    }
    else {
        $uri = "$base/$version/$resourcePath"
    }

    $resolvedQueryString = $QueryString
    if ([string]::IsNullOrWhiteSpace($resolvedQueryString) -and $null -ne $Query -and $Query.Count -gt 0) {
        $pairs = New-Object System.Collections.Generic.List[string]
        foreach ($key in ($Query.Keys | Sort-Object)) {
            $encodedKey = [System.Uri]::EscapeDataString([string]$key)
            $encodedValue = [System.Uri]::EscapeDataString([string]$Query[$key])
            $pairs.Add("$encodedKey=$encodedValue")
        }
        $resolvedQueryString = $pairs -join '&'
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedQueryString)) {
        $uri = $uri + '?' + $resolvedQueryString.TrimStart('?')
    }

    return $uri
}

Export-ModuleMember -Function @(
    'Resolve-HybridGraphEndpoint',
    'New-HybridGraphResourceUri'
)
