#region Module Information
# Name: Core.HttpPipeline
# Purpose: Shared HTTP request pipeline for HAP cloud providers.
# Dependencies: Core.Authentication, Core.HttpResponse, Core.HttpRetry
# Exports: New-HybridHttpRequest, New-HybridHttpPipeline, Invoke-HybridHttpPipeline,
#          New-HybridHttpPipelineDiagnostic, New-HybridHttpPaginationState
#endregion

Set-StrictMode -Version Latest

function New-HybridHttpRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [ValidateSet('GET','POST','PUT','PATCH','DELETE')][string]$Method = 'GET',
        [hashtable]$Headers = @{},
        [object]$Body = $null,
        [string]$ContentType = 'application/json',
        [string]$CorrelationId = '',
        [object]$AuthenticationSession = $null,
        [hashtable]$Metadata = @{}
    )

    if ([string]::IsNullOrWhiteSpace($Uri)) { throw 'HTTP request URI cannot be empty.' }

    if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
        $CorrelationId = [guid]::NewGuid().ToString()
    }

    [pscustomobject]@{
        PSTypeName            = 'Hybrid.HttpRequest'
        Uri                   = $Uri
        Method                = $Method.ToUpperInvariant()
        Headers               = @{} + $Headers
        Body                  = $Body
        ContentType           = $ContentType
        CorrelationId         = $CorrelationId
        AuthenticationSession = $AuthenticationSession
        Metadata              = @{} + $Metadata
        CreatedOn             = [datetime]::UtcNow
    }
}

function New-HybridHttpPipelineDiagnostic {
    [CmdletBinding()]
    param(
        [string]$CorrelationId = '',
        [string]$RequestUri = '',
        [string]$Method = 'GET',
        [int]$AttemptCount = 0,
        [timespan]$Duration = [timespan]::Zero,
        [string]$State = 'Created',
        [hashtable]$Metadata = @{}
    )

    [pscustomobject]@{
        PSTypeName    = 'Hybrid.HttpPipelineDiagnostic'
        CorrelationId = $CorrelationId
        RequestUri    = $RequestUri
        Method        = $Method
        AttemptCount  = $AttemptCount
        Duration      = $Duration
        State         = $State
        Metadata      = @{} + $Metadata
        CreatedOn     = [datetime]::UtcNow
    }
}

function New-HybridHttpPaginationState {
    [CmdletBinding()]
    param(
        [string]$NextLink = '',
        [string]$DeltaLink = '',
        [bool]$HasMore = $false,
        [int]$PageNumber = 1
    )

    [pscustomobject]@{
        PSTypeName = 'Hybrid.HttpPaginationState'
        NextLink   = $NextLink
        DeltaLink  = $DeltaLink
        HasMore    = $HasMore
        PageNumber = $PageNumber
    }
}

function New-HybridHttpPipeline {
    [CmdletBinding()]
    param(
        [object]$AuthenticationSession = $null,
        [object]$RetryPolicy = $null,
        [scriptblock]$Transport = $null,
        [string]$UserAgent = 'Hybrid-Admin-Console/0.5',
        [hashtable]$DefaultHeaders = @{}
    )

    if ($null -eq $RetryPolicy -and (Get-Command -Name New-HybridHttpRetryPolicy -ErrorAction SilentlyContinue)) {
        $RetryPolicy = New-HybridHttpRetryPolicy
    }

    [pscustomobject]@{
        PSTypeName             = 'Hybrid.HttpPipeline'
        AuthenticationSession = $AuthenticationSession
        RetryPolicy           = $RetryPolicy
        Transport             = $Transport
        UserAgent             = $UserAgent
        DefaultHeaders        = @{} + $DefaultHeaders
        CreatedOn             = [datetime]::UtcNow
    }
}

function Add-HybridHttpAuthenticationHeaders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][hashtable]$Headers,
        [object]$Session
    )

    if ($null -eq $Session) { return $Headers }

    $accessToken = $null
    $tokenType = 'Bearer'

    if ($Session.PSObject.Properties.Name -contains 'TokenDescriptor' -and $null -ne $Session.TokenDescriptor) {
        if ($Session.TokenDescriptor.PSObject.Properties.Name -contains 'AccessToken') {
            $accessToken = $Session.TokenDescriptor.AccessToken
        }
        if ($Session.TokenDescriptor.PSObject.Properties.Name -contains 'TokenType') {
            $tokenType = $Session.TokenDescriptor.TokenType
        }
    }
    elseif ($Session.PSObject.Properties.Name -contains 'AccessToken') {
        $accessToken = $Session.AccessToken
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$accessToken)) {
        $Headers['Authorization'] = "$tokenType $accessToken"
    }

    return $Headers
}

function Invoke-HybridHttpPipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Pipeline,
        [Parameter(Mandatory=$true)][object]$Request
    )

    foreach ($propertyName in @('Uri', 'Method', 'Headers', 'CorrelationId')) {
        if ($Request.PSObject.Properties.Name -notcontains $propertyName) {
            throw "Invalid HTTP request. Missing $propertyName property."
        }
    }

    $session = $Request.AuthenticationSession
    if ($null -eq $session -and $Pipeline.PSObject.Properties.Name -contains 'AuthenticationSession') {
        $session = $Pipeline.AuthenticationSession
    }

    $headers = @{}

    if ($Pipeline.PSObject.Properties.Name -contains 'DefaultHeaders' -and $null -ne $Pipeline.DefaultHeaders) {
        foreach ($key in $Pipeline.DefaultHeaders.Keys) { $headers[$key] = $Pipeline.DefaultHeaders[$key] }
    }

    foreach ($key in $Request.Headers.Keys) { $headers[$key] = $Request.Headers[$key] }

    if (-not $headers.ContainsKey('User-Agent')) {
        $headers['User-Agent'] = $Pipeline.UserAgent
    }

    if (-not $headers.ContainsKey('x-ms-client-request-id')) {
        $headers['x-ms-client-request-id'] = $Request.CorrelationId
    }

    $headers = Add-HybridHttpAuthenticationHeaders -Headers $headers -Session $session

    $preparedRequest = [pscustomobject]@{
        PSTypeName            = 'Hybrid.PreparedHttpRequest'
        Uri                   = $Request.Uri
        Method                = $Request.Method
        Headers               = $headers
        Body                  = $Request.Body
        ContentType           = $Request.ContentType
        CorrelationId         = $Request.CorrelationId
        AuthenticationSession = $session
        Metadata              = $Request.Metadata
    }

    $transport = $Pipeline.Transport
    if ($null -eq $transport) {
        throw 'No HTTP transport is configured. Phase 5 supports mock transport only.'
    }

    $attemptCounter = 0
    $script:__HybridHttpPipelineAttempt = 0
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $operation = {
        param($Attempt)
        $script:__HybridHttpPipelineAttempt = $Attempt
        return & $transport $preparedRequest $Attempt
    }

    if ($null -ne $Pipeline.RetryPolicy -and (Get-Command -Name Invoke-HybridHttpRetry -ErrorAction SilentlyContinue)) {
        $rawResponse = Invoke-HybridHttpRetry -Operation $operation -Policy $Pipeline.RetryPolicy
        $attemptCounter = [int]$script:__HybridHttpPipelineAttempt
    }
    else {
        $attemptCounter = 1
        $rawResponse = & $transport $preparedRequest 1
    }

    $stopwatch.Stop()

    if ($null -eq $rawResponse) {
        $errorObject = $null
        if (Get-Command -Name New-HybridHttpError -ErrorAction SilentlyContinue) {
            $errorObject = New-HybridHttpError -Code 'NullResponse' -Message 'HTTP transport returned null.' -StatusCode 0
        }
        return New-HybridHttpResponse -StatusCode 0 -Headers @{} -Error $errorObject -CorrelationId $Request.CorrelationId -Duration $stopwatch.Elapsed -AttemptCount $attemptCounter -RequestUri $Request.Uri -Method $Request.Method
    }

    $statusCode = 200
    $responseHeaders = @{}
    $body = $rawResponse
    $errorObject = $null

    if ($rawResponse.PSObject.Properties.Name -contains 'StatusCode') { $statusCode = [int]$rawResponse.StatusCode }
    if ($rawResponse.PSObject.Properties.Name -contains 'Headers' -and $null -ne $rawResponse.Headers) { $responseHeaders = $rawResponse.Headers }
    if ($rawResponse.PSObject.Properties.Name -contains 'Body') { $body = $rawResponse.Body }
    if ($rawResponse.PSObject.Properties.Name -contains 'Error') { $errorObject = $rawResponse.Error }

    if ($statusCode -ge 400 -and $null -eq $errorObject -and (Get-Command -Name New-HybridHttpError -ErrorAction SilentlyContinue)) {
        $errorObject = New-HybridHttpError -Code "HTTP$statusCode" -Message "HTTP request failed with status code $statusCode." -StatusCode $statusCode -RawError $rawResponse
    }

    return New-HybridHttpResponse -StatusCode $statusCode -Headers $responseHeaders -Body $body -Error $errorObject -CorrelationId $Request.CorrelationId -Duration $stopwatch.Elapsed -AttemptCount $attemptCounter -RequestUri $Request.Uri -Method $Request.Method -RawResponse $rawResponse
}

Export-ModuleMember -Function @(
    'New-HybridHttpRequest',
    'New-HybridHttpPipeline',
    'Invoke-HybridHttpPipeline',
    'New-HybridHttpPipelineDiagnostic',
    'New-HybridHttpPaginationState'
)
