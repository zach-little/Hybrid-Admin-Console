#region Module Information
# Name: Graph.Client
# Purpose: Microsoft Graph client foundation built on the shared HAP HTTP pipeline.
# Dependencies: Core.CloudEnvironment, Core.TenantContext, Core.Authentication, Core.HttpPipeline
# Exports: New-HybridGraphClient, New-HybridGraphRequest, Invoke-HybridGraphRequest,
#          Resolve-HybridGraphUri, Test-HybridGraphClient
#endregion

Set-StrictMode -Version Latest

function Resolve-HybridGraphUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Client,
        [Parameter(Mandatory=$true)][string]$Path,
        [hashtable]$Query = @{},
        [string]$QueryString = ''
    )

    foreach ($propertyName in @('BaseUri', 'ApiVersion')) {
        if ($Client.PSObject.Properties.Name -notcontains $propertyName) {
            throw "Invalid Graph client. Missing $propertyName property."
        }
    }

    if (Get-Command -Name New-HybridGraphResourceUri -ErrorAction SilentlyContinue) {
        return New-HybridGraphResourceUri -Client $Client -Path $Path -Query $Query -QueryString $QueryString
    }

    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Graph request path cannot be empty.' }

    $base = ([string]$Client.BaseUri).TrimEnd('/')
    $apiVersion = ([string]$Client.ApiVersion).Trim('/')
    $requestPath = $Path.TrimStart('/')

    if ($requestPath -match '^(v1\.0|beta)/') {
        $uri = "$base/$requestPath"
    }
    else {
        $uri = "$base/$apiVersion/$requestPath"
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

function New-HybridGraphClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$TenantContext,
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$AuthenticationSession,
        [object]$Pipeline = $null,
        [scriptblock]$Transport = $null,
        [object]$RetryPolicy = $null,
        [string]$ApiVersion = 'v1.0',
        [string]$BaseUri = '',
        [hashtable]$DefaultHeaders = @{},
        [hashtable]$Attributes = @{}
    )

    foreach ($propertyName in @('TenantId', 'CloudEnvironment')) {
        if ($TenantContext.PSObject.Properties.Name -notcontains $propertyName) {
            throw "Invalid tenant context. Missing $propertyName property."
        }
    }

    foreach ($propertyName in @('SessionId', 'TenantContext', 'CloudEnvironment')) {
        if ($AuthenticationSession.PSObject.Properties.Name -notcontains $propertyName) {
            throw "Invalid authentication session. Missing $propertyName property."
        }
    }

    $resolvedBaseUri = $BaseUri
    if ([string]::IsNullOrWhiteSpace($resolvedBaseUri)) {
        if (Get-Command -Name Resolve-HybridGraphEndpoint -ErrorAction SilentlyContinue) {
            $resolvedBaseUri = Resolve-HybridGraphEndpoint -TenantContext $TenantContext
        }
        else {
            if ($TenantContext.CloudEnvironment.PSObject.Properties.Name -notcontains 'Endpoints' -or -not $TenantContext.CloudEnvironment.Endpoints.ContainsKey('Graph')) {
                throw "Tenant cloud environment '$($TenantContext.CloudEnvironment.Name)' does not define a Graph endpoint."
            }
            $resolvedBaseUri = [string]$TenantContext.CloudEnvironment.Endpoints['Graph']
        }
    }

    $resolvedHeaders = @{
        'Accept' = 'application/json'
        'SdkVersion' = 'Hybrid-Admin-Console/0.5 GraphFoundation'
    }
    foreach ($key in $DefaultHeaders.Keys) { $resolvedHeaders[$key] = $DefaultHeaders[$key] }

    $resolvedPipeline = $Pipeline
    if ($null -eq $resolvedPipeline) {
        if (-not (Get-Command -Name New-HybridHttpPipeline -ErrorAction SilentlyContinue)) {
            throw 'Core.HttpPipeline is required to create a Graph client pipeline.'
        }
        $resolvedPipeline = New-HybridHttpPipeline -AuthenticationSession $AuthenticationSession -RetryPolicy $RetryPolicy -Transport $Transport -UserAgent 'Hybrid-Admin-Console-Graph/0.5' -DefaultHeaders $resolvedHeaders
    }

    $scopes = @()
    if ($AuthenticationSession.PSObject.Properties.Name -contains 'Scopes') { $scopes = @($AuthenticationSession.Scopes) }
    $state = if (Get-Command -Name New-HybridGraphProviderState -ErrorAction SilentlyContinue) {
        New-HybridGraphProviderState -Cloud $TenantContext.CloudEnvironment.Name -TenantId $TenantContext.TenantId -Authenticated $true -ApiVersion $ApiVersion -Scopes $scopes -Transport $(if ($null -ne $Transport) { 'Mock' } else { 'Default' })
    } else { $null }

    [pscustomobject]@{
        PSTypeName            = 'Hybrid.GraphClient'
        TenantContext         = $TenantContext
        CloudEnvironment      = $TenantContext.CloudEnvironment
        AuthenticationSession = $AuthenticationSession
        Pipeline              = $resolvedPipeline
        BaseUri               = $resolvedBaseUri.TrimEnd('/')
        ApiVersion            = $ApiVersion.Trim('/')
        DefaultHeaders        = $resolvedHeaders
        State                 = $state
        Attributes            = $Attributes
        CreatedOn             = [datetime]::UtcNow
    }
}

function Test-HybridGraphClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Client,
        [switch]$Detailed
    )

    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($propertyName in @('TenantContext', 'CloudEnvironment', 'AuthenticationSession', 'Pipeline', 'BaseUri', 'ApiVersion')) {
        if ($Client.PSObject.Properties.Name -notcontains $propertyName) { $errors.Add("Missing required property: $propertyName") }
    }

    $result = [pscustomobject]@{
        PSTypeName = 'Hybrid.GraphClientValidationResult'
        IsValid    = ($errors.Count -eq 0)
        Errors     = @($errors)
    }

    if ($Detailed) { return $result }
    return [bool]$result.IsValid
}

function New-HybridGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Client,
        [Parameter(Mandatory=$true)][string]$Path,
        [ValidateSet('GET','POST','PUT','PATCH','DELETE')][string]$Method = 'GET',
        [hashtable]$Query = @{},
        [string]$QueryString = '',
        [hashtable]$Headers = @{},
        [object]$Body = $null,
        [hashtable]$Metadata = @{}
    )

    $uri = Resolve-HybridGraphUri -Client $Client -Path $Path -Query $Query -QueryString $QueryString

    [pscustomobject]@{
        PSTypeName   = 'Hybrid.GraphRequest'
        Client       = $Client
        Uri          = $uri
        Path         = $Path
        Method       = $Method.ToUpperInvariant()
        Query        = @{} + $Query
        QueryString  = $QueryString
        Headers      = @{} + $Headers
        Body         = $Body
        Metadata     = @{} + $Metadata
    }
}

function Invoke-HybridGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Client,
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$GraphRequest
    )

    foreach ($propertyName in @('Uri', 'Method', 'Headers')) {
        if ($GraphRequest.PSObject.Properties.Name -notcontains $propertyName) {
            throw "Invalid Graph request. Missing $propertyName property."
        }
    }

    if (-not (Get-Command -Name New-HybridHttpRequest -ErrorAction SilentlyContinue) -or -not (Get-Command -Name Invoke-HybridHttpPipeline -ErrorAction SilentlyContinue)) {
        throw 'Core.HttpPipeline is required to invoke Graph requests.'
    }

    $request = New-HybridHttpRequest -Uri $GraphRequest.Uri -Method $GraphRequest.Method -Headers $GraphRequest.Headers -Body $GraphRequest.Body -AuthenticationSession $Client.AuthenticationSession -Metadata $GraphRequest.Metadata
    $response = Invoke-HybridHttpPipeline -Pipeline $Client.Pipeline -Request $request

    if ($Client.PSObject.Properties.Name -contains 'State' -and $null -ne $Client.State) {
        $Client.State.LastRequest = $GraphRequest
        $Client.State.LastRequestOn = [datetime]::UtcNow
        if (Get-Command -Name New-HybridGraphDiagnostic -ErrorAction SilentlyContinue) {
            $requestId = ''
            if ($response.PSObject.Properties.Name -contains 'Headers' -and $response.Headers -is [System.Collections.IDictionary] -and $response.Headers.Contains('request-id')) { $requestId = [string]$response.Headers['request-id'] }
            $correlationId = ''
            if ($request.PSObject.Properties.Name -contains 'CorrelationId') { $correlationId = [string]$request.CorrelationId }
            $duration = if ($response.PSObject.Properties.Name -contains 'Duration') { $response.Duration } else { [timespan]::Zero }
            $attemptCount = if ($response.PSObject.Properties.Name -contains 'AttemptCount') { [int]$response.AttemptCount } else { 1 }
            $Client.State.LastDiagnostic = New-HybridGraphDiagnostic -RequestId $requestId -CorrelationId $correlationId -ServiceRoot $Client.BaseUri -ApiVersion $Client.ApiVersion -RetryCount ([Math]::Max(0, $attemptCount - 1)) -Duration $duration -State $(if ($response.Succeeded) { 'Completed' } else { 'Failed' })
        }
    }

    return $response
}

Export-ModuleMember -Function @(
    'New-HybridGraphClient',
    'New-HybridGraphRequest',
    'Invoke-HybridGraphRequest',
    'Resolve-HybridGraphUri',
    'Test-HybridGraphClient'
)
