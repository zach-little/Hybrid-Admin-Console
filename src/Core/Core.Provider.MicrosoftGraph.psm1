#region Module Information
# Name: Core.Provider.MicrosoftGraph
# Purpose: Provider-facing Microsoft Graph service wrapper for the Hybrid Administration Platform.
# Dependencies: Core.ProviderBase, Core.Authentication.Manager, Core.Authentication, Core.TenantContext, Graph.Models
# Exports: New-HybridMicrosoftGraphProviderContext, Initialize-HybridMicrosoftGraphProvider,
#          Get-HybridMicrosoftGraphProviderHealth, Get-HybridMicrosoftGraphProviderCapabilities,
#          Test-HybridMicrosoftGraphProviderCapability, Search-HybridMicrosoftGraphUser,
#          Get-HybridMicrosoftGraphUser, Clear-HybridMicrosoftGraphProviderCache
#endregion

Set-StrictMode -Version Latest

$script:HybridMicrosoftGraphCapabilities = @(
    'AuthenticationSession',
    'Users',
    'SearchUser',
    'GetUser',
    'MockGraphData',
    'ProviderHealth',
    'CapabilityDiscovery',
    'Caching',
    'Lifecycle'
)

$script:HybridMicrosoftGraphProviderState = if (Get-Command New-HybridProviderState -ErrorAction SilentlyContinue) {
    New-HybridProviderState -Name 'MicrosoftGraph' -Module 'Core.Provider.MicrosoftGraph' -Capabilities $script:HybridMicrosoftGraphCapabilities -CacheBuckets @('Users')
}
else {
    [pscustomobject]@{
        PSTypeName       = 'Hybrid.ProviderState'
        Name             = 'MicrosoftGraph'
        Module           = 'Core.Provider.MicrosoftGraph'
        Initialized      = $false
        Available        = $false
        Connected        = $false
        LastError        = $null
        LastInitialized  = $null
        LastCommand      = $null
        Version          = '0.6.0'
        Capabilities     = @($script:HybridMicrosoftGraphCapabilities)
        CommandHistory   = @()
        Cache            = @{ Users = @{} }
    }
}

$script:HybridMicrosoftGraphState = @{
    Initialized               = $false
    TenantContext             = $null
    AuthenticationRequest     = $null
    AuthenticationMethod      = 'Interactive'
    Scopes                    = @('User.Read.All')
    MockUsers                 = @()
    LastAuthenticationSession = $null
    Cache                     = @{ Users = @{} }
}

$script:HybridMicrosoftGraphProviderState.Cache = $script:HybridMicrosoftGraphState.Cache

function Get-HybridMicrosoftGraphObjectValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory=$true)][string[]]$Names,
        [AllowNull()][object]$Default = $null
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

function New-HybridMicrosoftGraphProviderContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$TenantContext,
        [string]$AuthenticationMethod = 'Interactive',
        [string[]]$Scopes = @('User.Read.All'),
        [hashtable]$Attributes = @{}
    )

    if ($TenantContext.PSObject.Properties.Name -notcontains 'TenantId') {
        throw 'Microsoft Graph provider context requires a TenantContext with a TenantId property.'
    }

    if ($TenantContext.PSObject.Properties.Name -notcontains 'CloudEnvironment') {
        throw 'Microsoft Graph provider context requires a TenantContext with a CloudEnvironment property.'
    }

    [pscustomobject]@{
        PSTypeName            = 'Hybrid.MicrosoftGraphProviderContext'
        TenantContext         = $TenantContext
        AuthenticationMethod  = $AuthenticationMethod
        Scopes                = @($Scopes)
        Attributes            = @{} + $Attributes
        CreatedOn             = [datetime]::UtcNow
    }
}

function New-HybridMicrosoftGraphAuthenticationRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Context
    )

    if ($Context.PSObject.Properties.Name -contains 'AuthenticationRequest' -and $null -ne $Context.AuthenticationRequest) {
        return $Context.AuthenticationRequest
    }

    $tenantContext = Get-HybridMicrosoftGraphObjectValue -InputObject $Context -Names @('TenantContext')
    $methodName = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $Context -Names @('AuthenticationMethod','MethodName','Method') -Default 'Interactive')
    $scopes = @((Get-HybridMicrosoftGraphObjectValue -InputObject $Context -Names @('Scopes','RequiredScopes') -Default @('User.Read.All')))
    $attributes = Get-HybridMicrosoftGraphObjectValue -InputObject $Context -Names @('Attributes') -Default @{}
    $clientId = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $Context -Names @('ClientId') -Default (Get-HybridMicrosoftGraphObjectValue -InputObject $attributes -Names @('ClientId') -Default ''))

    if (-not (Get-Command New-HybridAuthenticationRequest -ErrorAction SilentlyContinue)) {
        throw 'Core.Authentication is required to create a Microsoft Graph authentication request.'
    }

    return New-HybridAuthenticationRequest -TenantContext $tenantContext -MethodName $methodName -ClientId $clientId -Scopes $scopes -Attributes $attributes
}

function Get-HybridMicrosoftGraphAuthenticationSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$AuthenticationRequest,
        [switch]$ForceRefresh
    )

    if (-not (Get-Command Get-HybridAuthenticationSession -ErrorAction SilentlyContinue)) {
        throw 'Core.Authentication.Manager is required before using the Microsoft Graph provider.'
    }

    $session = Get-HybridAuthenticationSession -Request $AuthenticationRequest -ForceRefresh:$ForceRefresh
    $script:HybridMicrosoftGraphState.LastAuthenticationSession = $session
    return $session
}

function ConvertTo-HybridMicrosoftGraphUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$GraphUser
    )

    if (Get-Command ConvertFrom-HybridGraphUser -ErrorAction SilentlyContinue) {
        return ConvertFrom-HybridGraphUser -GraphUser $GraphUser
    }

    [pscustomobject]@{
        PSTypeName          = 'Hybrid.User'
        Id                  = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('id','Id') -Default '')
        DisplayName         = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('displayName','DisplayName') -Default '')
        UserPrincipalName   = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('userPrincipalName','UserPrincipalName') -Default '')
        Mail                = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('mail','Mail') -Default '')
        Source              = 'MicrosoftGraph'
        Attributes          = @{ GraphObject = $GraphUser }
    }
}

function Get-HybridMicrosoftGraphEndpoint {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$TenantContext)

    $cloud = Get-HybridMicrosoftGraphObjectValue -InputObject $TenantContext -Names @('CloudEnvironment') -Default $null
    $endpoints = Get-HybridMicrosoftGraphObjectValue -InputObject $cloud -Names @('Endpoints') -Default $null
    $graphEndpoint = Get-HybridMicrosoftGraphObjectValue -InputObject $endpoints -Names @('Graph') -Default 'https://graph.microsoft.com'
    return ([string]$graphEndpoint).TrimEnd('/')
}

function Invoke-HybridMicrosoftGraphUserRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][object]$Session
    )

    $token = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $Session -Names @('AccessToken') -Default '')
    if ([string]::IsNullOrWhiteSpace($token)) { throw 'Microsoft Graph authentication session did not include an access token.' }

    $tenantContext = $script:HybridMicrosoftGraphState.TenantContext
    $graphEndpoint = Get-HybridMicrosoftGraphEndpoint -TenantContext $tenantContext
    $escapedIdentity = [System.Uri]::EscapeDataString($Identity)
    $select = 'id,displayName,userPrincipalName,mail,userType,preferredLanguage,usageLocation'
    $uri = ('{0}/v1.0/users/{1}?$select={2}' -f $graphEndpoint, $escapedIdentity, $select)
    $headers = @{ Authorization = ('Bearer {0}' -f $token) }

    return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
}

function Invoke-HybridMicrosoftGraphUserSearchRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Query,
        [Parameter(Mandatory=$true)][object]$Session
    )

    $token = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $Session -Names @('AccessToken') -Default '')
    if ([string]::IsNullOrWhiteSpace($token)) { throw 'Microsoft Graph authentication session did not include an access token.' }

    $tenantContext = $script:HybridMicrosoftGraphState.TenantContext
    $graphEndpoint = Get-HybridMicrosoftGraphEndpoint -TenantContext $tenantContext
    $escapedQuery = $Query.Replace("'", "''")
    $filter = [System.Uri]::EscapeDataString("startswith(displayName,'$escapedQuery') or startswith(userPrincipalName,'$escapedQuery') or startswith(mail,'$escapedQuery')")
    $select = 'id,displayName,userPrincipalName,mail,userType,preferredLanguage,usageLocation'
    $uri = ('{0}/v1.0/users?$top=25&$select={1}&$filter={2}' -f $graphEndpoint, $select, $filter)
    $headers = @{ Authorization = ('Bearer {0}' -f $token) }

    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
    $values = Get-HybridMicrosoftGraphObjectValue -InputObject $response -Names @('value','Value') -Default @()
    return @($values)
}

function Get-HybridMicrosoftGraphUserCacheKey {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Value)

    return ('user::{0}' -f $Value.ToLowerInvariant())
}

function Clear-HybridMicrosoftGraphProviderCache {
    [CmdletBinding()]
    param()

    foreach ($bucket in @($script:HybridMicrosoftGraphState.Cache.Keys)) {
        $script:HybridMicrosoftGraphState.Cache[$bucket].Clear()
    }

    return $true
}

function Search-HybridMicrosoftGraphUser {
    [CmdletBinding()]
    param(
        [string]$Query = '',
        [switch]$ForceRefresh
    )

    $operation = {
        $session = Get-HybridMicrosoftGraphAuthenticationSession -AuthenticationRequest $script:HybridMicrosoftGraphState.AuthenticationRequest -ForceRefresh:$ForceRefresh
        $null = $session

        $users = @($script:HybridMicrosoftGraphState.MockUsers)
        if (-not [string]::IsNullOrWhiteSpace($Query)) {
            $needle = $Query.Trim()
            $users = @($users | Where-Object {
                ([string](Get-HybridMicrosoftGraphObjectValue -InputObject $_ -Names @('displayName','DisplayName') -Default '') -like "*$needle*") -or
                ([string](Get-HybridMicrosoftGraphObjectValue -InputObject $_ -Names @('userPrincipalName','UserPrincipalName') -Default '') -like "*$needle*") -or
                ([string](Get-HybridMicrosoftGraphObjectValue -InputObject $_ -Names @('mail','Mail') -Default '') -like "*$needle*") -or
                ([string](Get-HybridMicrosoftGraphObjectValue -InputObject $_ -Names @('id','Id') -Default '') -like "*$needle*")
            })
        }

        if ($users.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Query)) {
            $users = @(Invoke-HybridMicrosoftGraphUserSearchRequest -Query $Query -Session $session)
        }

        return @($users | ForEach-Object { ConvertTo-HybridMicrosoftGraphUser -GraphUser $_ })
    }

    if (Get-Command Invoke-HybridProviderCommand -ErrorAction SilentlyContinue) {
        return Invoke-HybridProviderCommand -ProviderState $script:HybridMicrosoftGraphProviderState -CommandName 'Search-HybridMicrosoftGraphUser' -Operation 'SearchUser' -ScriptBlock $operation
    }

    return & $operation
}

function Get-HybridMicrosoftGraphUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [switch]$ForceRefresh
    )

    if ([string]::IsNullOrWhiteSpace($Identity)) {
        throw 'Microsoft Graph user identity cannot be empty.'
    }

    $operation = {
        $session = Get-HybridMicrosoftGraphAuthenticationSession -AuthenticationRequest $script:HybridMicrosoftGraphState.AuthenticationRequest -ForceRefresh:$ForceRefresh
        $null = $session

        $cacheKey = Get-HybridMicrosoftGraphUserCacheKey -Value $Identity
        if (-not $ForceRefresh -and $script:HybridMicrosoftGraphState.Cache.Users.ContainsKey($cacheKey)) {
            return $script:HybridMicrosoftGraphState.Cache.Users[$cacheKey]
        }

        $match = @($script:HybridMicrosoftGraphState.MockUsers | Where-Object {
            ([string](Get-HybridMicrosoftGraphObjectValue -InputObject $_ -Names @('id','Id') -Default '') -ieq $Identity) -or
            ([string](Get-HybridMicrosoftGraphObjectValue -InputObject $_ -Names @('userPrincipalName','UserPrincipalName') -Default '') -ieq $Identity) -or
            ([string](Get-HybridMicrosoftGraphObjectValue -InputObject $_ -Names @('mail','Mail') -Default '') -ieq $Identity)
        } | Select-Object -First 1)

        if ($match.Count -eq 0) {
            $liveUser = Invoke-HybridMicrosoftGraphUserRequest -Identity $Identity -Session $session
            $user = ConvertTo-HybridMicrosoftGraphUser -GraphUser $liveUser
            $script:HybridMicrosoftGraphState.Cache.Users[$cacheKey] = $user
            return $user
        }

        $user = ConvertTo-HybridMicrosoftGraphUser -GraphUser $match[0]
        $script:HybridMicrosoftGraphState.Cache.Users[$cacheKey] = $user
        return $user
    }

    if (Get-Command Invoke-HybridProviderCommand -ErrorAction SilentlyContinue) {
        return Invoke-HybridProviderCommand -ProviderState $script:HybridMicrosoftGraphProviderState -CommandName 'Get-HybridMicrosoftGraphUser' -Operation 'GetUser' -ScriptBlock $operation
    }

    return & $operation
}

function Get-HybridMicrosoftGraphProviderCapabilities {
    [CmdletBinding()]
    param()

    if (Get-Command Get-HybridProviderCapabilities -ErrorAction SilentlyContinue) {
        return Get-HybridProviderCapabilities -ProviderState $script:HybridMicrosoftGraphProviderState
    }

    return @($script:HybridMicrosoftGraphProviderState.Capabilities)
}

function Test-HybridMicrosoftGraphProviderCapability {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Capability)

    if (Get-Command Test-HybridProviderCapability -ErrorAction SilentlyContinue) {
        return Test-HybridProviderCapability -ProviderState $script:HybridMicrosoftGraphProviderState -Capability $Capability
    }

    return @($script:HybridMicrosoftGraphProviderState.Capabilities) -contains $Capability
}

function Get-HybridMicrosoftGraphProviderHealth {
    [CmdletBinding()]
    param()

    $script:HybridMicrosoftGraphProviderState.Available = $true
    $script:HybridMicrosoftGraphProviderState.Connected = ($null -ne $script:HybridMicrosoftGraphState.LastAuthenticationSession)

    $health = if (Get-Command Get-HybridProviderHealth -ErrorAction SilentlyContinue) {
        Get-HybridProviderHealth -ProviderState $script:HybridMicrosoftGraphProviderState
    }
    else {
        [pscustomobject]@{
            PSTypeName      = 'Hybrid.ProviderHealth'
            Name            = 'MicrosoftGraph'
            Module          = 'Core.Provider.MicrosoftGraph'
            Initialized     = [bool]$script:HybridMicrosoftGraphState.Initialized
            Available       = $true
            Connected       = ($null -ne $script:HybridMicrosoftGraphState.LastAuthenticationSession)
            LastError       = $script:HybridMicrosoftGraphProviderState.LastError
            Version         = '0.6.0'
            Capabilities    = @($script:HybridMicrosoftGraphProviderState.Capabilities)
            CacheEntries    = $script:HybridMicrosoftGraphState.Cache.Users.Count
            CommandCount    = @($script:HybridMicrosoftGraphProviderState.CommandHistory).Count
            LastCommand     = $script:HybridMicrosoftGraphProviderState.LastCommand
            ResponseTimeMs  = $null
        }
    }

    $health = @($health) | Select-Object -First 1

    if ($null -eq $health) {
        $health = [pscustomobject]@{
            PSTypeName      = 'Hybrid.ProviderHealth'
            Name            = 'MicrosoftGraph'
            Module          = 'Core.Provider.MicrosoftGraph'
            Initialized     = [bool]$script:HybridMicrosoftGraphState.Initialized
            Available       = $true
            Connected       = ($null -ne $script:HybridMicrosoftGraphState.LastAuthenticationSession)
            LastError       = $script:HybridMicrosoftGraphProviderState.LastError
            Version         = '0.6.0'
            Capabilities    = @($script:HybridMicrosoftGraphProviderState.Capabilities)
            CacheEntries    = $script:HybridMicrosoftGraphState.Cache.Users.Count
            CommandCount    = @($script:HybridMicrosoftGraphProviderState.CommandHistory).Count
            LastCommand     = $script:HybridMicrosoftGraphProviderState.LastCommand
            ResponseTimeMs  = $null
        }
    }

    if ($health.PSObject.TypeNames -notcontains 'Hybrid.MicrosoftGraphProviderHealth') {
        $health.PSObject.TypeNames.Insert(0, 'Hybrid.MicrosoftGraphProviderHealth')
    }

    return $health
}

function Initialize-HybridMicrosoftGraphProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Context,
        [object[]]$MockUsers = @(),
        [switch]$ForceRefresh
    )

    if ($Context.PSObject.Properties.Name -notcontains 'TenantContext') {
        throw 'Initialize-HybridMicrosoftGraphProvider requires a Microsoft Graph provider context.'
    }

    $authenticationRequest = New-HybridMicrosoftGraphAuthenticationRequest -Context $Context

    $script:HybridMicrosoftGraphState.TenantContext = $Context.TenantContext
    $script:HybridMicrosoftGraphState.AuthenticationRequest = $authenticationRequest
    $script:HybridMicrosoftGraphState.AuthenticationMethod = [string]$Context.AuthenticationMethod
    $script:HybridMicrosoftGraphState.Scopes = @($Context.Scopes)
    $script:HybridMicrosoftGraphState.MockUsers = @($MockUsers)
    $script:HybridMicrosoftGraphState.Initialized = $true

    Clear-HybridMicrosoftGraphProviderCache | Out-Null

    $session = Get-HybridMicrosoftGraphAuthenticationSession -AuthenticationRequest $authenticationRequest -ForceRefresh:$ForceRefresh

    if (Get-Command Initialize-HybridProvider -ErrorAction SilentlyContinue) {
        Initialize-HybridProvider -ProviderState $script:HybridMicrosoftGraphProviderState -Available $true -Connected $true -Version '0.6.0' | Out-Null
    }
    else {
        $script:HybridMicrosoftGraphProviderState.Initialized = $true
        $script:HybridMicrosoftGraphProviderState.Available = $true
        $script:HybridMicrosoftGraphProviderState.Connected = $true
        $script:HybridMicrosoftGraphProviderState.LastInitialized = Get-Date
    }

    $operations = @{
        SearchUser = { param([string]$Query) Search-HybridMicrosoftGraphUser -Query $Query }.GetNewClosure()
        GetUser = { param([string]$Identity) Get-HybridMicrosoftGraphUser -Identity $Identity }.GetNewClosure()
        ClearCache = { Clear-HybridMicrosoftGraphProviderCache | Out-Null }.GetNewClosure()
        GetHealth = { Get-HybridMicrosoftGraphProviderHealth }.GetNewClosure()
        GetProviderHealth = { Get-HybridMicrosoftGraphProviderHealth }.GetNewClosure()
        SupportsCapability = { param([string]$Capability) Test-HybridMicrosoftGraphProviderCapability -Capability $Capability }.GetNewClosure()
    }

    $service = if (Get-Command New-HybridProviderService -ErrorAction SilentlyContinue) {
        New-HybridProviderService -ProviderState $script:HybridMicrosoftGraphProviderState -Operations $operations
    }
    else {
        [pscustomobject]@{
            PSTypeName         = 'Hybrid.ProviderService'
            ProviderName       = 'MicrosoftGraph'
            ProviderModule     = 'Core.Provider.MicrosoftGraph'
            ProviderAvailable  = $true
            ProviderConnected  = $true
            Capabilities       = @($script:HybridMicrosoftGraphProviderState.Capabilities)
            SearchUser         = $operations.SearchUser
            GetUser            = $operations.GetUser
            ClearCache         = $operations.ClearCache
            GetHealth          = $operations.GetHealth
            SupportsCapability = $operations.SupportsCapability
        }
    }

    $service.PSObject.TypeNames.Insert(0, 'Hybrid.MicrosoftGraphProviderService')

    if ($service.PSObject.Properties.Name -notcontains 'AuthenticationSession') {
        $service | Add-Member -NotePropertyName AuthenticationSession -NotePropertyValue $session
    }

    return $service
}

Export-ModuleMember -Function @(
    'New-HybridMicrosoftGraphProviderContext',
    'Initialize-HybridMicrosoftGraphProvider',
    'Get-HybridMicrosoftGraphProviderHealth',
    'Get-HybridMicrosoftGraphProviderCapabilities',
    'Test-HybridMicrosoftGraphProviderCapability',
    'Search-HybridMicrosoftGraphUser',
    'Get-HybridMicrosoftGraphUser',
    'Clear-HybridMicrosoftGraphProviderCache'
)
