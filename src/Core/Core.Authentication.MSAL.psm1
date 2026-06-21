Set-StrictMode -Version Latest

function Get-HybridMsalObjectValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string[]]$Names,
        $Default = $null
    )

    foreach ($name in $Names) {
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
        [ValidateSet('Interactive','InteractiveBrowser','AppOnly','ManagedIdentity')]
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
        [ValidateSet('Interactive','InteractiveBrowser','AppOnly','ManagedIdentity')]
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
        'AppOnly'         { 'Application' }
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
        [ValidateSet('Interactive','InteractiveBrowser','AppOnly','ManagedIdentity')]
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

    foreach ($method in 'Interactive','InteractiveBrowser','AppOnly','ManagedIdentity') {
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
