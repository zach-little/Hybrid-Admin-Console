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
        [hashtable]$Query = @{}
    )

    foreach ($propertyName in @('BaseUri', 'ApiVersion')) {
        if ($Client.PSObject.Properties.Name -notcontains $propertyName) {
            throw "Invalid Graph client. Missing $propertyName property."
        }
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

    if ($null -ne $Query -and $Query.Count -gt 0) {
        $pairs = New-Object System.Collections.Generic.List[string]
        foreach ($key in ($Query.Keys | Sort-Object)) {
            $encodedKey = [System.Uri]::EscapeDataString([string]$key)
            $encodedValue = [System.Uri]::EscapeDataString([string]$Query[$key])
            $pairs.Add("$encodedKey=$encodedValue")
        }
        $uri = $uri + '?' + ($pairs -join '&')
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
        if ($TenantContext.CloudEnvironment.PSObject.Properties.Name -notcontains 'Endpoints' -or -not $TenantContext.CloudEnvironment.Endpoints.ContainsKey('Graph')) {
            throw "Tenant cloud environment '$($TenantContext.CloudEnvironment.Name)' does not define a Graph endpoint."
        }
        $resolvedBaseUri = [string]$TenantContext.CloudEnvironment.Endpoints['Graph']
    }

    $resolvedHeaders = @{
        'Accept' = 'application/json'
    }
    foreach ($key in $DefaultHeaders.Keys) { $resolvedHeaders[$key] = $DefaultHeaders[$key] }

    $resolvedPipeline = $Pipeline
    if ($null -eq $resolvedPipeline) {
        if (-not (Get-Command -Name New-HybridHttpPipeline -ErrorAction SilentlyContinue)) {
            throw 'Core.HttpPipeline is required to create a Graph client pipeline.'
        }
        $resolvedPipeline = New-HybridHttpPipeline -AuthenticationSession $AuthenticationSession -RetryPolicy $RetryPolicy -Transport $Transport -UserAgent 'Hybrid-Admin-Console-Graph/0.5' -DefaultHeaders $resolvedHeaders
    }

    [pscustomobject]@{
        PSTypeName            = 'Hybrid.GraphClient'
        TenantContext         = $TenantContext
        CloudEnvironment      = $TenantContext.CloudEnvironment
        AuthenticationSession = $AuthenticationSession
        Pipeline              = $resolvedPipeline
        BaseUri               = $resolvedBaseUri.TrimEnd('/')
        ApiVersion            = $ApiVersion.Trim('/')
        DefaultHeaders        = $resolvedHeaders
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
        [hashtable]$Headers = @{},
        [object]$Body = $null,
        [hashtable]$Metadata = @{}
    )

    $uri = Resolve-HybridGraphUri -Client $Client -Path $Path -Query $Query

    [pscustomobject]@{
        PSTypeName = 'Hybrid.GraphRequest'
        Client     = $Client
        Uri        = $uri
        Path       = $Path
        Method     = $Method.ToUpperInvariant()
        Query      = @{} + $Query
        Headers    = @{} + $Headers
        Body       = $Body
        Metadata   = @{} + $Metadata
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
    return Invoke-HybridHttpPipeline -Pipeline $Client.Pipeline -Request $request
}

Export-ModuleMember -Function @(
    'New-HybridGraphClient',
    'New-HybridGraphRequest',
    'Invoke-HybridGraphRequest',
    'Resolve-HybridGraphUri',
    'Test-HybridGraphClient'
)
