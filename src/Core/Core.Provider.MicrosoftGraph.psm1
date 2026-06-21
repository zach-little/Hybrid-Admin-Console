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

    if (-not (Get-Command New-HybridAuthenticationRequest -ErrorAction SilentlyContinue)) {
        throw 'Core.Authentication is required to create a Microsoft Graph authentication request.'
    }

    return New-HybridAuthenticationRequest -TenantContext $tenantContext -MethodName $methodName -Scopes $scopes
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
            return $null
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
