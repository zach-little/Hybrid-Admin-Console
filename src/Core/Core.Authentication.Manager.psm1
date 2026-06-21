Set-StrictMode -Version Latest

$script:HybridAuthenticationAdapters = @{}
$script:HybridAuthenticationSessionCache = @{}

function Get-HybridAuthenticationObjectValue {
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

function New-HybridAuthenticationManagerCacheKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Request)

    $command = Get-Command New-HybridAuthenticationCacheKey -ErrorAction SilentlyContinue

    if ($null -ne $command) {
        try {
            if ($command.Parameters.ContainsKey('AuthenticationRequest')) {
                $keyObject = New-HybridAuthenticationCacheKey -AuthenticationRequest $Request

                if ($null -ne $keyObject -and $keyObject.PSObject.Properties.Name -contains 'Key') {
                    return [string]$keyObject.Key
                }

                if ($null -ne $keyObject) {
                    return [string]$keyObject
                }
            }
        }
        catch {
            # Fall back to deterministic manager key below.
        }
    }

    $tenantContext = Get-HybridAuthenticationObjectValue -InputObject $Request -Names @('TenantContext','Tenant')
    $cloudEnvironment = Get-HybridAuthenticationObjectValue -InputObject $Request -Names @('CloudEnvironment','Cloud')
    $methodName = [string](Get-HybridAuthenticationObjectValue -InputObject $Request -Names @('MethodName','AuthenticationMethod','Method') -Default 'Interactive')
    $scopes = @((Get-HybridAuthenticationObjectValue -InputObject $Request -Names @('Scopes','RequiredScopes') -Default @()))

    if ($null -ne $command) {
        $params = @{}

        if ($command.Parameters.ContainsKey('TenantContext')) {
            $params['TenantContext'] = $tenantContext
        }
        elseif ($command.Parameters.ContainsKey('Tenant')) {
            $params['Tenant'] = $tenantContext
        }
        elseif ($command.Parameters.ContainsKey('TenantId')) {
            $params['TenantId'] = [string](Get-HybridAuthenticationObjectValue -InputObject $tenantContext -Names @('TenantId','Id') -Default '')
        }

        if ($command.Parameters.ContainsKey('CloudEnvironment')) {
            $params['CloudEnvironment'] = $cloudEnvironment
        }
        elseif ($command.Parameters.ContainsKey('Cloud')) {
            $params['Cloud'] = $cloudEnvironment
        }
        elseif ($command.Parameters.ContainsKey('CloudEnvironmentName')) {
            $params['CloudEnvironmentName'] = [string](Get-HybridAuthenticationObjectValue -InputObject $cloudEnvironment -Names @('Name') -Default '')
        }
        elseif ($command.Parameters.ContainsKey('CloudName')) {
            $params['CloudName'] = [string](Get-HybridAuthenticationObjectValue -InputObject $cloudEnvironment -Names @('Name') -Default '')
        }

        if ($command.Parameters.ContainsKey('MethodName')) {
            $params['MethodName'] = $methodName
        }
        elseif ($command.Parameters.ContainsKey('AuthenticationMethod')) {
            $params['AuthenticationMethod'] = $methodName
        }
        elseif ($command.Parameters.ContainsKey('Method')) {
            $params['Method'] = $methodName
        }

        if ($command.Parameters.ContainsKey('Scopes')) {
            $params['Scopes'] = $scopes
        }
        elseif ($command.Parameters.ContainsKey('RequiredScopes')) {
            $params['RequiredScopes'] = $scopes
        }

        if ($params.Count -gt 0) {
            try {
                $keyObject = New-HybridAuthenticationCacheKey @params

                if ($null -ne $keyObject -and $keyObject.PSObject.Properties.Name -contains 'Key') {
                    return [string]$keyObject.Key
                }

                if ($null -ne $keyObject) {
                    return [string]$keyObject
                }
            }
            catch {
                # Fall back to deterministic manager key below.
            }
        }
    }

    $tenantId = [string](Get-HybridAuthenticationObjectValue -InputObject $tenantContext -Names @('TenantId','Id') -Default '')
    $cloudName = [string](Get-HybridAuthenticationObjectValue -InputObject $cloudEnvironment -Names @('Name') -Default '')
    $scopeText = (@($scopes) | Sort-Object) -join ','

    return ('{0}|{1}|{2}|{3}' -f $tenantId,$cloudName,$methodName,$scopeText).ToLowerInvariant()
}

function New-HybridAuthenticationManagerTokenDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AccessToken,
        [string]$TokenType = 'Bearer',
        [string[]]$Scopes = @(),
        [datetime]$ExpiresOn = (Get-Date).AddHours(1),
        [hashtable]$Claims = @{}
    )

    $command = Get-Command New-HybridTokenDescriptor -ErrorAction SilentlyContinue

    if ($null -eq $command) {
        return [pscustomobject]@{
            PSTypeName   = 'Hybrid.TokenDescriptor'
            AccessToken  = $AccessToken
            TokenType    = $TokenType
            Scopes       = @($Scopes)
            ExpiresOn    = $ExpiresOn
            Claims       = $Claims
        }
    }

    $params = @{}

    if ($command.Parameters.ContainsKey('AccessToken')) { $params['AccessToken'] = $AccessToken }
    elseif ($command.Parameters.ContainsKey('Token')) { $params['Token'] = $AccessToken }

    if ($command.Parameters.ContainsKey('TokenType')) { $params['TokenType'] = $TokenType }
    if ($command.Parameters.ContainsKey('Scopes')) { $params['Scopes'] = @($Scopes) }
    elseif ($command.Parameters.ContainsKey('RequiredScopes')) { $params['RequiredScopes'] = @($Scopes) }
    if ($command.Parameters.ContainsKey('ExpiresOn')) { $params['ExpiresOn'] = $ExpiresOn }
    elseif ($command.Parameters.ContainsKey('ExpiresAt')) { $params['ExpiresAt'] = $ExpiresOn }
    if ($command.Parameters.ContainsKey('Claims')) { $params['Claims'] = $Claims }

    return New-HybridTokenDescriptor @params
}

function New-HybridAuthenticationManagerSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][string]$AccessToken,
        [datetime]$ExpiresOn = (Get-Date).AddHours(1)
    )

    $tenantContext = Get-HybridAuthenticationObjectValue -InputObject $Request -Names @('TenantContext','Tenant')
    $cloudEnvironment = Get-HybridAuthenticationObjectValue -InputObject $Request -Names @('CloudEnvironment','Cloud')
    $methodName = [string](Get-HybridAuthenticationObjectValue -InputObject $Request -Names @('MethodName','AuthenticationMethod','Method') -Default 'Interactive')
    $scopes = @((Get-HybridAuthenticationObjectValue -InputObject $Request -Names @('Scopes','RequiredScopes') -Default @()))

    $command = Get-Command New-HybridAuthenticationSession -ErrorAction Stop
    $params = @{}

    if ($command.Parameters.ContainsKey('AuthenticationRequest')) {
        $params['AuthenticationRequest'] = $Request
    }

    if ($command.Parameters.ContainsKey('TenantContext')) {
        $params['TenantContext'] = $tenantContext
    }
    elseif ($command.Parameters.ContainsKey('Tenant')) {
        $params['Tenant'] = $tenantContext
    }
    elseif ($command.Parameters.ContainsKey('TenantId')) {
        $params['TenantId'] = [string](Get-HybridAuthenticationObjectValue -InputObject $tenantContext -Names @('TenantId','Id') -Default '')
    }

    if ($command.Parameters.ContainsKey('CloudEnvironment')) {
        $params['CloudEnvironment'] = $cloudEnvironment
    }
    elseif ($command.Parameters.ContainsKey('Cloud')) {
        $params['Cloud'] = $cloudEnvironment
    }
    elseif ($command.Parameters.ContainsKey('CloudEnvironmentName')) {
        $params['CloudEnvironmentName'] = [string](Get-HybridAuthenticationObjectValue -InputObject $cloudEnvironment -Names @('Name') -Default '')
    }

    if ($command.Parameters.ContainsKey('MethodName')) {
        $params['MethodName'] = $methodName
    }
    elseif ($command.Parameters.ContainsKey('AuthenticationMethod')) {
        $params['AuthenticationMethod'] = $methodName
    }
    elseif ($command.Parameters.ContainsKey('Method')) {
        $params['Method'] = $methodName
    }

    if ($command.Parameters.ContainsKey('AccessToken')) {
        $params['AccessToken'] = $AccessToken
    }
    elseif ($command.Parameters.ContainsKey('Token')) {
        $params['Token'] = $AccessToken
    }

    if ($command.Parameters.ContainsKey('Scopes')) {
        $params['Scopes'] = @($scopes)
    }
    elseif ($command.Parameters.ContainsKey('RequiredScopes')) {
        $params['RequiredScopes'] = @($scopes)
    }

    if ($command.Parameters.ContainsKey('ExpiresOn')) {
        $params['ExpiresOn'] = $ExpiresOn
    }
    elseif ($command.Parameters.ContainsKey('ExpiresAt')) {
        $params['ExpiresAt'] = $ExpiresOn
    }

    if ($command.Parameters.ContainsKey('TokenDescriptor')) {
        $params['TokenDescriptor'] = New-HybridAuthenticationManagerTokenDescriptor -AccessToken $AccessToken -Scopes $scopes -ExpiresOn $ExpiresOn
    }

    return New-HybridAuthenticationSession @params
}

function Register-HybridAuthenticationAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$AcquireSession,
        [scriptblock]$RefreshSession,
        [switch]$Force
    )

    if ($Name -ieq 'DeviceCode') {
        throw 'Device Code Flow is unsupported by project charter.'
    }

    if ($script:HybridAuthenticationAdapters.ContainsKey($Name) -and -not $Force) {
        throw "Authentication adapter '$Name' is already registered."
    }

    $script:HybridAuthenticationAdapters[$Name] = [pscustomobject]@{
        PSTypeName     = 'Hybrid.AuthenticationAdapter'
        Name           = $Name
        AcquireSession = $AcquireSession
        RefreshSession = $RefreshSession
    }

    $script:HybridAuthenticationAdapters[$Name]
}

function Get-HybridAuthenticationAdapter {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    if ($script:HybridAuthenticationAdapters.ContainsKey($Name)) {
        return $script:HybridAuthenticationAdapters[$Name]
    }

    return $null
}

function Get-HybridAuthenticationAdapterNames {
    [CmdletBinding()]
    param()

    @($script:HybridAuthenticationAdapters.Keys | Sort-Object)
}

function Clear-HybridAuthenticationSessionCache {
    [CmdletBinding()]
    param()

    $script:HybridAuthenticationSessionCache.Clear()
}

function Get-HybridCachedAuthenticationSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CacheKey)

    if ($script:HybridAuthenticationSessionCache.ContainsKey($CacheKey)) {
        return $script:HybridAuthenticationSessionCache[$CacheKey]
    }

    return $null
}

function Set-HybridCachedAuthenticationSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CacheKey,
        [Parameter(Mandatory)]$Session
    )

    $script:HybridAuthenticationSessionCache[$CacheKey] = $Session
    return $Session
}

function Test-HybridAuthenticationRefreshRequired {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [int]$RefreshWindowMinutes = 5
    )

    if ($null -eq $Session) { return $true }
    if ($Session.PSObject.Properties.Name -notcontains 'ExpiresOn') { return $true }

    return ([datetime]$Session.ExpiresOn) -le (Get-Date).AddMinutes($RefreshWindowMinutes)
}

function Get-HybridAuthenticationSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [switch]$ForceRefresh
    )

    $methodName = [string](Get-HybridAuthenticationObjectValue -InputObject $Request -Names @('MethodName','AuthenticationMethod','Method') -Default '')

    if ([string]::IsNullOrWhiteSpace($methodName)) {
        throw 'Authentication request is missing MethodName.'
    }

    $cacheKey = New-HybridAuthenticationManagerCacheKey -Request $Request
    $cached = Get-HybridCachedAuthenticationSession -CacheKey $cacheKey

    if (-not $ForceRefresh -and $null -ne $cached -and -not (Test-HybridAuthenticationRefreshRequired -Session $cached)) {
        return $cached
    }

    $adapter = Get-HybridAuthenticationAdapter -Name $methodName
    if ($null -eq $adapter) {
        throw "Authentication adapter '$methodName' is not registered."
    }

    if ($null -ne $cached -and $adapter.RefreshSession -and (Test-HybridAuthenticationRefreshRequired -Session $cached)) {
        $session = & $adapter.RefreshSession $Request $cached
    }
    else {
        $session = & $adapter.AcquireSession $Request
    }

    if ($null -eq $session) {
        throw "Authentication adapter '$methodName' did not return a session."
    }

    Set-HybridCachedAuthenticationSession -CacheKey $cacheKey -Session $session | Out-Null
    return $session
}

function Initialize-HybridMockAuthenticationAdapters {
    [CmdletBinding()]
    param([switch]$Force)

    $acquire = {
        param($Request)

        New-HybridAuthenticationManagerSession `
            -Request $Request `
            -AccessToken ('mock-token-{0}' -f ([guid]::NewGuid().ToString('N'))) `
            -ExpiresOn (Get-Date).AddHours(1)
    }

    $refresh = {
        param($Request, $ExistingSession)

        New-HybridAuthenticationManagerSession `
            -Request $Request `
            -AccessToken ('refreshed-token-{0}' -f ([guid]::NewGuid().ToString('N'))) `
            -ExpiresOn (Get-Date).AddHours(1)
    }

    foreach ($method in 'Interactive','InteractiveBrowser','AppOnly','ManagedIdentity') {
        Register-HybridAuthenticationAdapter -Name $method -AcquireSession $acquire -RefreshSession $refresh -Force:$Force | Out-Null
    }

    Get-HybridAuthenticationAdapterNames
}

Export-ModuleMember -Function `
    Register-HybridAuthenticationAdapter,`
    Get-HybridAuthenticationAdapter,`
    Get-HybridAuthenticationAdapterNames,`
    Clear-HybridAuthenticationSessionCache,`
    Get-HybridCachedAuthenticationSession,`
    Set-HybridCachedAuthenticationSession,`
    Test-HybridAuthenticationRefreshRequired,`
    Get-HybridAuthenticationSession,`
    Initialize-HybridMockAuthenticationAdapters
