Set-StrictMode -Version Latest

function Get-HybridMsalObjectValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string[]]$Names,
        $Default = $null
    )

    foreach ($name in $Names) {
        if ($null -ne $InputObject -and $InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($name)) {
            return $InputObject[$name]
        }
        if ($null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains $name) {
            return $InputObject.$name
        }
    }

    return $Default
}

function New-HybridMsalAuthenticationAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Interactive','InteractiveBrowser','AppOnly','AppOnlyClientCredentials','ManagedIdentity')]
        [string]$MethodName,

        [ValidateSet('Contract','Live','Auto')]
        [string]$RuntimeMode = 'Contract'
    )

    [pscustomobject]@{
        PSTypeName   = 'Hybrid.MsalAuthenticationAdapter'
        Name         = $MethodName
        Runtime      = 'MSAL'
        RuntimeMode  = $RuntimeMode
        SupportsMock = $true
        Status       = if ($RuntimeMode -eq 'Contract') { 'ContractOnly' } else { 'LiveCapable' }
    }
}

function Test-HybridMsalRuntimeAvailable {
    [CmdletBinding()]
    param()

    $getMsalToken = Get-Command -Name 'Get-MsalToken' -ErrorAction SilentlyContinue

    [pscustomobject]@{
        PSTypeName      = 'Hybrid.MsalRuntimeStatus'
        Runtime         = 'MSAL'
        IsAvailable     = ($null -ne $getMsalToken)
        CommandName     = if ($null -ne $getMsalToken) { $getMsalToken.Name } else { '' }
        ModuleName      = if ($null -ne $getMsalToken) { [string]$getMsalToken.ModuleName } else { '' }
        SupportsLiveRun = ($null -ne $getMsalToken)
    }
}

function New-HybridMsalTokenRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$AuthenticationRequest,

        [Parameter(Mandatory)]
        [ValidateSet('Interactive','InteractiveBrowser','AppOnly','AppOnlyClientCredentials','ManagedIdentity')]
        [string]$MethodName
    )

    foreach ($propertyName in @('TenantContext','CloudEnvironment','Authority','Scopes')) {
        if ($AuthenticationRequest.PSObject.Properties.Name -notcontains $propertyName) {
            throw "Invalid authentication request. Missing $propertyName property."
        }
    }

    $tenantContext = $AuthenticationRequest.TenantContext
    $cloudEnvironment = $AuthenticationRequest.CloudEnvironment
    $clientId = [string](Get-HybridMsalObjectValue -InputObject $AuthenticationRequest -Names @('ClientId') -Default '')
    $scopes = @((Get-HybridMsalObjectValue -InputObject $AuthenticationRequest -Names @('Scopes','RequiredScopes') -Default @()))
    $tenantId = [string](Get-HybridMsalObjectValue -InputObject $tenantContext -Names @('TenantId','Id') -Default '')
    $cloudName = [string](Get-HybridMsalObjectValue -InputObject $cloudEnvironment -Names @('Name') -Default '')

    if ([string]::IsNullOrWhiteSpace($tenantId)) {
        throw 'Authentication request tenant context is missing TenantId.'
    }

    $mode = switch ($MethodName) {
        { $_ -in @('AppOnly','AppOnlyClientCredentials') } { 'Application' }
        'ManagedIdentity' { 'ManagedIdentity' }
        default           { 'Delegated' }
    }

    [pscustomobject]@{
        PSTypeName           = 'Hybrid.MsalTokenRequest'
        AuthenticationRequest = $AuthenticationRequest
        MethodName           = $MethodName
        Mode                 = $mode
        TenantId             = $tenantId
        ClientId             = $clientId
        Scopes               = @($scopes)
        Authority            = [string]$AuthenticationRequest.Authority
        CloudEnvironment     = $cloudEnvironment
        CloudEnvironmentName = $cloudName
        IsInteractive        = ($MethodName -in @('Interactive','InteractiveBrowser'))
        Attributes           = if ($AuthenticationRequest.PSObject.Properties.Name -contains 'Attributes') { $AuthenticationRequest.Attributes } else { @{} }
    }
}

function ConvertTo-HybridMsalBase64Url {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]]$Bytes)

    return ([Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','-').Replace('/','_'))
}

function Get-HybridMsalCertificate {
    [CmdletBinding()]
    param(
        [string]$Thumbprint = '',
        [string]$CertificatePath = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($Thumbprint)) {
        $normalizedThumbprint = ([regex]::Replace($Thumbprint.Trim(), '[^0-9A-Fa-f]', '')).ToUpperInvariant()
        foreach ($storeName in @('Cert:\CurrentUser\My','Cert:\LocalMachine\My')) {
            $certificate = @(Get-ChildItem -Path $storeName -ErrorAction SilentlyContinue | Where-Object {
                ([regex]::Replace(([string]$_.Thumbprint), '[^0-9A-Fa-f]', '')).ToUpperInvariant() -eq $normalizedThumbprint
            } | Select-Object -First 1)
            if ($certificate.Count -gt 0 -and $null -ne $certificate[0]) { return $certificate[0] }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($CertificatePath) -and (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath)
    }

    return $null
}

function New-HybridMsalCertificateClientAssertion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$TokenEndpoint,
        [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    $now = [DateTimeOffset]::UtcNow
    $header = @{
        alg = 'RS256'
        typ = 'JWT'
        x5t = ConvertTo-HybridMsalBase64Url -Bytes $Certificate.GetCertHash()
    }
    $payload = @{
        aud = $TokenEndpoint
        iss = $ClientId
        sub = $ClientId
        jti = [guid]::NewGuid().ToString()
        nbf = [int]$now.ToUnixTimeSeconds()
        exp = [int]$now.AddMinutes(10).ToUnixTimeSeconds()
    }

    $headerJson = $header | ConvertTo-Json -Compress
    $payloadJson = $payload | ConvertTo-Json -Compress
    $unsignedToken = '{0}.{1}' -f (ConvertTo-HybridMsalBase64Url -Bytes ([Text.Encoding]::UTF8.GetBytes($headerJson))), (ConvertTo-HybridMsalBase64Url -Bytes ([Text.Encoding]::UTF8.GetBytes($payloadJson)))
    $rsa = $Certificate.GetRSAPrivateKey()
    if ($null -eq $rsa) { throw 'Certificate does not expose an RSA private key for app-only authentication.' }
    $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($unsignedToken), [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    return '{0}.{1}' -f $unsignedToken, (ConvertTo-HybridMsalBase64Url -Bytes $signature)
}

function Invoke-HybridMsalCertificateClientCredentials {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$TokenRequest)

    $attributes = Get-HybridMsalObjectValue -InputObject $TokenRequest -Names @('Attributes') -Default @{}
    $clientId = [string](Get-HybridMsalObjectValue -InputObject $TokenRequest -Names @('ClientId') -Default '')
    $tenantId = [string](Get-HybridMsalObjectValue -InputObject $TokenRequest -Names @('TenantId') -Default '')
    $authority = [string](Get-HybridMsalObjectValue -InputObject $TokenRequest -Names @('Authority') -Default '')
    $thumbprint = [string](Get-HybridMsalObjectValue -InputObject $attributes -Names @('CertificateThumbprint') -Default '')
    $certificatePath = [string](Get-HybridMsalObjectValue -InputObject $attributes -Names @('CertificatePath') -Default '')

    if ([string]::IsNullOrWhiteSpace($clientId)) { throw 'App-only Microsoft Graph authentication requires ClientId.' }
    if ([string]::IsNullOrWhiteSpace($tenantId) -and [string]::IsNullOrWhiteSpace($authority)) { throw 'App-only Microsoft Graph authentication requires TenantId or Authority.' }

    $certificate = Get-HybridMsalCertificate -Thumbprint $thumbprint -CertificatePath $certificatePath
    if ($null -eq $certificate) { throw 'App-only Microsoft Graph authentication could not find the configured certificate.' }
    if (-not $certificate.HasPrivateKey) { throw 'App-only Microsoft Graph authentication certificate does not include a private key.' }

    if ([string]::IsNullOrWhiteSpace($authority)) { $authority = 'https://login.microsoftonline.com/{0}' -f $tenantId }
    $tokenEndpoint = $authority.TrimEnd('/') + '/oauth2/v2.0/token'
    $assertion = New-HybridMsalCertificateClientAssertion -ClientId $clientId -TokenEndpoint $tokenEndpoint -Certificate $certificate
    $body = @{
        client_id = $clientId
        scope = (@($TokenRequest.Scopes) -join ' ')
        grant_type = 'client_credentials'
        client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        client_assertion = $assertion
    }

    $response = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
    $expiresIn = [int](Get-HybridMsalObjectValue -InputObject $response -Names @('expires_in','ExpiresIn') -Default 3600)
    [pscustomobject]@{
        PSTypeName = 'Hybrid.MsalCertificateClientCredentialsTokenResult'
        AccessToken = [string](Get-HybridMsalObjectValue -InputObject $response -Names @('access_token','AccessToken') -Default '')
        TokenType = [string](Get-HybridMsalObjectValue -InputObject $response -Names @('token_type','TokenType') -Default 'Bearer')
        ExpiresOn = [datetime]::UtcNow.AddSeconds($expiresIn)
        RuntimeMode = 'CertificateClientCredentials'
    }
}

function Invoke-HybridMsalLoopbackInteractive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$TokenRequest)

    $clientId = [string](Get-HybridMsalObjectValue -InputObject $TokenRequest -Names @('ClientId') -Default '')
    $authority = [string](Get-HybridMsalObjectValue -InputObject $TokenRequest -Names @('Authority') -Default '')
    if ([string]::IsNullOrWhiteSpace($clientId)) { throw 'Delegated Microsoft Graph authentication requires ClientId.' }
    if ([string]::IsNullOrWhiteSpace($authority)) { throw 'Delegated Microsoft Graph authentication requires Authority.' }

    $listener = $null
    $redirectUri = ''
    foreach ($port in 8400..8499) {
        try {
            $candidate = "http://localhost:$port/"
            $listener = [System.Net.HttpListener]::new()
            $listener.Prefixes.Add($candidate)
            $listener.Start()
            $redirectUri = $candidate
            break
        }
        catch {
            if ($null -ne $listener) { $listener.Close() }
            $listener = $null
        }
    }
    if ($null -eq $listener) { throw 'Delegated Microsoft Graph authentication could not open a localhost callback listener.' }

    $state = [guid]::NewGuid().ToString('N')
    $scopeText = (@($TokenRequest.Scopes) + 'offline_access') | Select-Object -Unique
    $authorizeUri = '{0}/oauth2/v2.0/authorize?client_id={1}&response_type=code&redirect_uri={2}&response_mode=query&scope={3}&state={4}&prompt=select_account' -f `
        $authority.TrimEnd('/'),
        [System.Uri]::EscapeDataString($clientId),
        [System.Uri]::EscapeDataString($redirectUri),
        [System.Uri]::EscapeDataString(($scopeText -join ' ')),
        [System.Uri]::EscapeDataString($state)

    try {
        Start-Process $authorizeUri | Out-Null
        $async = $listener.BeginGetContext($null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne([TimeSpan]::FromMinutes(5))) {
            throw 'Delegated Microsoft Graph sign-in timed out waiting for browser callback.'
        }
        $context = $listener.EndGetContext($async)
        $request = $context.Request
        $code = [string]$request.QueryString['code']
        $returnedState = [string]$request.QueryString['state']
        $error = [string]$request.QueryString['error']
        $errorDescription = [string]$request.QueryString['error_description']
        $message = if ([string]::IsNullOrWhiteSpace($error)) { 'Hybrid Admin Platform sign-in complete. You can close this browser window.' } else { "Hybrid Admin Platform sign-in failed: $error $errorDescription" }
        $bytes = [Text.Encoding]::UTF8.GetBytes("<html><body><h2>$message</h2></body></html>")
        $context.Response.ContentType = 'text/html'
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.Close()

        if (-not [string]::IsNullOrWhiteSpace($error)) { throw "Delegated Microsoft Graph sign-in failed: $error $errorDescription" }
        if ([string]::IsNullOrWhiteSpace($code)) { throw 'Delegated Microsoft Graph sign-in did not return an authorization code.' }
        if ($returnedState -ne $state) { throw 'Delegated Microsoft Graph sign-in returned an invalid state value.' }

        $tokenEndpoint = $authority.TrimEnd('/') + '/oauth2/v2.0/token'
        $body = @{
            client_id = $clientId
            scope = ($scopeText -join ' ')
            code = $code
            redirect_uri = $redirectUri
            grant_type = 'authorization_code'
        }
        $response = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        $expiresIn = [int](Get-HybridMsalObjectValue -InputObject $response -Names @('expires_in','ExpiresIn') -Default 3600)
        [pscustomobject]@{
            PSTypeName = 'Hybrid.MsalLoopbackInteractiveTokenResult'
            AccessToken = [string](Get-HybridMsalObjectValue -InputObject $response -Names @('access_token','AccessToken') -Default '')
            TokenType = [string](Get-HybridMsalObjectValue -InputObject $response -Names @('token_type','TokenType') -Default 'Bearer')
            ExpiresOn = [datetime]::UtcNow.AddSeconds($expiresIn)
            RuntimeMode = 'LoopbackInteractive'
        }
    }
    finally {
        if ($null -ne $listener) { $listener.Close() }
    }
}

function ConvertTo-HybridMsalTokenDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$TokenResult,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$TokenRequest
    )

    $accessToken = [string](Get-HybridMsalObjectValue -InputObject $TokenResult -Names @('AccessToken','Token') -Default '')
    if ([string]::IsNullOrWhiteSpace($accessToken)) {
        throw 'MSAL token acquisition did not return an access token.'
    }

    $expiresOn = Get-HybridMsalObjectValue -InputObject $TokenResult -Names @('ExpiresOn','ExpiresAt','Expires') -Default ([datetime]::UtcNow.AddHours(1))
    $tokenType = [string](Get-HybridMsalObjectValue -InputObject $TokenResult -Names @('TokenType') -Default 'Bearer')
    $claims = Get-HybridMsalObjectValue -InputObject $TokenResult -Names @('Claims') -Default @{}

    New-HybridTokenDescriptor `
        -AccessToken $accessToken `
        -TokenType $tokenType `
        -ExpiresOn ([datetime]$expiresOn) `
        -Scopes @($TokenRequest.Scopes) `
        -Claims $claims
}

function Invoke-HybridMsalTokenAcquisition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$TokenRequest,

        [ValidateSet('Contract','Live','Auto')]
        [string]$RuntimeMode = 'Contract',

        [scriptblock]$TokenAcquisitionScript
    )

    if ($null -ne $TokenAcquisitionScript) {
        return & $TokenAcquisitionScript $TokenRequest
    }

    $runtime = Test-HybridMsalRuntimeAvailable
    if ($TokenRequest.MethodName -in @('Interactive','InteractiveBrowser')) {
        return Invoke-HybridMsalLoopbackInteractive -TokenRequest $TokenRequest
    }

    if ($TokenRequest.MethodName -in @('AppOnly','AppOnlyClientCredentials')) {
        $attributes = Get-HybridMsalObjectValue -InputObject $TokenRequest -Names @('Attributes') -Default @{}
        $thumbprint = [string](Get-HybridMsalObjectValue -InputObject $attributes -Names @('CertificateThumbprint') -Default '')
        $certificatePath = [string](Get-HybridMsalObjectValue -InputObject $attributes -Names @('CertificatePath') -Default '')
        if (-not [string]::IsNullOrWhiteSpace($thumbprint) -or -not [string]::IsNullOrWhiteSpace($certificatePath)) {
            return Invoke-HybridMsalCertificateClientCredentials -TokenRequest $TokenRequest
        }
    }

    if ($RuntimeMode -eq 'Contract' -or ($RuntimeMode -eq 'Auto' -and -not $runtime.IsAvailable)) {
        return [pscustomobject]@{
            PSTypeName   = 'Hybrid.MsalContractTokenResult'
            AccessToken  = ('msal-contract-token-{0}' -f ([guid]::NewGuid().ToString('N')))
            TokenType    = 'Bearer'
            ExpiresOn    = [datetime]::UtcNow.AddHours(1)
            RuntimeMode  = 'Contract'
        }
    }

    if (-not $runtime.IsAvailable) {
        throw 'MSAL runtime is not available. Install/load an MSAL runtime command or register the adapter with -RuntimeMode Contract for offline tests.'
    }

    $params = @{
        TenantId = $TokenRequest.TenantId
        Scopes   = @($TokenRequest.Scopes)
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$TokenRequest.ClientId)) {
        $params['ClientId'] = [string]$TokenRequest.ClientId
    }

    if ($TokenRequest.MethodName -eq 'InteractiveBrowser') {
        $params['Interactive'] = $true
    }

    Get-MsalToken @params
}

function New-HybridMsalAuthenticationSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$AuthenticationRequest,

        [Parameter(Mandatory)]
        [ValidateSet('Interactive','InteractiveBrowser','AppOnly','AppOnlyClientCredentials','ManagedIdentity')]
        [string]$MethodName,

        [ValidateSet('Contract','Live','Auto')]
        [string]$RuntimeMode = 'Contract',

        [scriptblock]$TokenAcquisitionScript
    )

    $tokenRequest = New-HybridMsalTokenRequest -AuthenticationRequest $AuthenticationRequest -MethodName $MethodName
    $tokenResult = Invoke-HybridMsalTokenAcquisition -TokenRequest $tokenRequest -RuntimeMode $RuntimeMode -TokenAcquisitionScript $TokenAcquisitionScript
    $tokenDescriptor = ConvertTo-HybridMsalTokenDescriptor -TokenResult $tokenResult -TokenRequest $tokenRequest

    New-HybridAuthenticationSession `
        -AuthenticationRequest $AuthenticationRequest `
        -TokenDescriptor $tokenDescriptor `
        -Attributes @{
            Runtime = 'MSAL'
            RuntimeMode = $RuntimeMode
            TokenRequest = $tokenRequest
        }
}

function Register-HybridMsalAuthenticationAdapters {
    [CmdletBinding()]
    param(
        [switch]$Force,

        [ValidateSet('Contract','Live','Auto')]
        [string]$RuntimeMode = 'Contract',

        [scriptblock]$TokenAcquisitionScript
    )

    foreach ($method in 'Interactive','InteractiveBrowser','AppOnly','AppOnlyClientCredentials','ManagedIdentity') {
        $methodName = $method
        $runtimeModeValue = $RuntimeMode
        $tokenScriptValue = $TokenAcquisitionScript

        $acquire = {
            param($Request)
            New-HybridMsalAuthenticationSession `
                -AuthenticationRequest $Request `
                -MethodName $methodName `
                -RuntimeMode $runtimeModeValue `
                -TokenAcquisitionScript $tokenScriptValue
        }.GetNewClosure()

        $refresh = {
            param($Request, $ExistingSession)
            New-HybridMsalAuthenticationSession `
                -AuthenticationRequest $Request `
                -MethodName $methodName `
                -RuntimeMode $runtimeModeValue `
                -TokenAcquisitionScript $tokenScriptValue
        }.GetNewClosure()

        Register-HybridAuthenticationAdapter `
            -Name $methodName `
            -AcquireSession $acquire `
            -RefreshSession $refresh `
            -Force:$Force | Out-Null
    }

    Get-HybridAuthenticationAdapterNames
}

Export-ModuleMember -Function `
    New-HybridMsalAuthenticationAdapter,`
    Test-HybridMsalRuntimeAvailable,`
    New-HybridMsalTokenRequest,`
    ConvertTo-HybridMsalTokenDescriptor,`
    Invoke-HybridMsalTokenAcquisition,`
    New-HybridMsalAuthenticationSession,`
    Register-HybridMsalAuthenticationAdapters
