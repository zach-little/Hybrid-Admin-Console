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

    if (-not $ForceRefresh -and $null -ne $script:HybridMicrosoftGraphState.LastAuthenticationSession) {
        $session = $script:HybridMicrosoftGraphState.LastAuthenticationSession
        $expiresOn = Get-HybridMicrosoftGraphObjectValue -InputObject $session -Names @('ExpiresOn','ExpiresAt','Expires') -Default $null
        $accessToken = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $session -Names @('AccessToken') -Default '')
        if (-not [string]::IsNullOrWhiteSpace($accessToken) -and $null -ne $expiresOn -and ([datetime]$expiresOn) -gt (Get-Date).AddMinutes(5)) {
            return $session
        }
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

    $signInActivity = Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('signInActivity','SignInActivity') -Default $null
    $lastSignIn = Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('LastSignInDateTime','LastSignIn') -Default (Get-HybridMicrosoftGraphObjectValue -InputObject $signInActivity -Names @('lastSignInDateTime','LastSignInDateTime') -Default $null)
    $lastNonInteractive = Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('LastNonInteractiveSignInDateTime','LastNonInteractiveSignIn') -Default (Get-HybridMicrosoftGraphObjectValue -InputObject $signInActivity -Names @('lastNonInteractiveSignInDateTime','LastNonInteractiveSignInDateTime') -Default $null)
    $passwordChanged = Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('lastPasswordChangeDateTime','PasswordLastChangedDateTime','LastPasswordChange','PasswordLastChanged') -Default $null
    $methods = @(Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('AuthenticationMethods','Methods') -Default @())
    $businessPhones = @(Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('businessPhones','BusinessPhones') -Default @())
    $phoneNumber = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('PhoneNumber','TelephoneNumber','mobilePhone','MobilePhone') -Default '')
    if ([string]::IsNullOrWhiteSpace($phoneNumber) -and $businessPhones.Count -gt 0) { $phoneNumber = [string]$businessPhones[0] }

    [pscustomobject]@{
        PSTypeName          = 'Hybrid.User'
        Id                  = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('id','Id') -Default '')
        DisplayName         = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('displayName','DisplayName') -Default '')
        UserPrincipalName   = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('userPrincipalName','UserPrincipalName') -Default '')
        Mail                = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('mail','Mail') -Default '')
        UserType            = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('userType','UserType') -Default 'Member')
        PreferredLanguage   = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('preferredLanguage','PreferredLanguage') -Default '')
        UsageLocation       = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('usageLocation','UsageLocation') -Default '')
        CompanyName         = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('companyName','CompanyName','Company') -Default '')
        OfficeLocation      = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('officeLocation','OfficeLocation','Office') -Default '')
        EmployeeId          = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('employeeId','EmployeeId','EmployeeID') -Default '')
        BadgeId             = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('BadgeId','employeeNumber','EmployeeNumber','extensionAttribute1') -Default '')
        State               = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('state','State') -Default '')
        PhoneNumber         = $phoneNumber
        MobilePhone         = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('mobilePhone','MobilePhone') -Default '')
        BusinessPhones      = @($businessPhones)
        AuthenticationMethods = @($methods)
        DefaultMethod       = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('DefaultMethod','DefaultAuthenticationMethod') -Default $(if ($methods.Count -gt 0) { [string]$methods[0] } else { '' }))
        MfaRegistered       = [bool](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('MfaRegistered','MfaEnabled','IsMfaRegistered') -Default ($methods.Count -gt 1))
        MfaCapable          = [bool](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('MfaCapable','IsMfaCapable') -Default ($methods.Count -gt 0))
        PasswordlessRegistered = [bool](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('PasswordlessRegistered','IsPasswordlessRegistered') -Default (@($methods | Where-Object { $_ -match 'passwordless|fido|windows hello|temporary access pass' }).Count -gt 0))
        AuthenticationStrength = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('AuthenticationStrength','StrongAuthenticationRequirement') -Default $(if ($methods.Count -gt 1) { 'Multi-factor capable' } else { 'Single-factor' }))
        LastSignInDateTime  = $lastSignIn
        LastNonInteractiveSignInDateTime = $lastNonInteractive
        PasswordLastChangedDateTime = $passwordChanged
        RiskState           = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('RiskState','UserRiskState','riskState') -Default 'not loaded')
        SignInRiskState     = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('SignInRiskState','RiskState','UserRiskState','riskState') -Default 'not loaded')
        ConditionalAccessState = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('ConditionalAccessState','ConditionalAccess','conditionalAccessStatus') -Default 'Not loaded')
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

function Add-HybridMicrosoftGraphObjectProperties {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Target,
        [AllowNull()][object]$Source,
        [string[]]$PropertyNames = @()
    )

    if ($null -eq $Source) { return $Target }
    foreach ($propertyName in $PropertyNames) {
        if ($Source.PSObject.Properties.Name -contains $propertyName) {
            $Target | Add-Member -NotePropertyName $propertyName -NotePropertyValue $Source.$propertyName -Force
        }
    }

    return $Target
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

    $user = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
    $profileSelects = @(
        'companyName,officeLocation,employeeId,mobilePhone,businessPhones',
        'state',
        'lastPasswordChangeDateTime',
        'signInActivity'
    )
    foreach ($profileSelect in $profileSelects) {
        $profileUri = ('{0}/v1.0/users/{1}?$select={2}' -f $graphEndpoint, $escapedIdentity, $profileSelect)
        $profileResponse = Invoke-HybridMicrosoftGraphOptionalRequest -Uri $profileUri -Session $Session
        $user = Add-HybridMicrosoftGraphObjectProperties -Target $user -Source $profileResponse -PropertyNames @($profileSelect -split ',')
    }

    return Add-HybridMicrosoftGraphUserSecurityEnrichment -GraphUser $user -Session $Session
}

function Invoke-HybridMicrosoftGraphOptionalRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][object]$Session
    )

    $token = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $Session -Names @('AccessToken') -Default '')
    if ([string]::IsNullOrWhiteSpace($token)) { return $null }

    try {
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = ('Bearer {0}' -f $token) } -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function ConvertTo-HybridMicrosoftGraphAuthenticationMethodName {
    [CmdletBinding()]
    param([AllowNull()][object]$Method)

    $odataType = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $Method -Names @('@odata.type','odata.type') -Default '')
    switch -Regex ($odataType) {
        'microsoftAuthenticatorAuthenticationMethod' { return 'Microsoft Authenticator' }
        'phoneAuthenticationMethod' { return 'Phone' }
        'fido2AuthenticationMethod' { return 'FIDO2 security key' }
        'windowsHelloForBusinessAuthenticationMethod' { return 'Windows Hello for Business' }
        'emailAuthenticationMethod' { return 'Email' }
        'temporaryAccessPassAuthenticationMethod' { return 'Temporary Access Pass' }
        'passwordAuthenticationMethod' { return 'Password' }
        'softwareOathAuthenticationMethod' { return 'Software OATH' }
        default {
            $displayName = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $Method -Names @('displayName','DisplayName') -Default '')
            if (-not [string]::IsNullOrWhiteSpace($displayName)) { return $displayName }
            if (-not [string]::IsNullOrWhiteSpace($odataType)) { return ($odataType -replace '^#microsoft\.graph\.', '') }
            return 'Authentication method'
        }
    }
}

function Add-HybridMicrosoftGraphUserSecurityEnrichment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$GraphUser,
        [Parameter(Mandatory=$true)][object]$Session
    )

    $tenantContext = $script:HybridMicrosoftGraphState.TenantContext
    $graphEndpoint = Get-HybridMicrosoftGraphEndpoint -TenantContext $tenantContext
    $id = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('id','Id') -Default '')
    $upn = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('userPrincipalName','UserPrincipalName') -Default '')

    if (-not [string]::IsNullOrWhiteSpace($id)) {
        $escapedId = [System.Uri]::EscapeDataString($id)
        $methodsResponse = Invoke-HybridMicrosoftGraphOptionalRequest -Uri ('{0}/v1.0/users/{1}/authentication/methods' -f $graphEndpoint, $escapedId) -Session $Session
        $methodValues = @(Get-HybridMicrosoftGraphObjectValue -InputObject $methodsResponse -Names @('value','Value') -Default @())
        if ($methodValues.Count -gt 0) {
            $methodNames = @($methodValues | ForEach-Object { ConvertTo-HybridMicrosoftGraphAuthenticationMethodName -Method $_ } | Select-Object -Unique)
            $GraphUser | Add-Member -NotePropertyName AuthenticationMethods -NotePropertyValue @($methodNames) -Force
            $GraphUser | Add-Member -NotePropertyName MfaRegistered -NotePropertyValue ($methodNames.Count -gt 1) -Force
            $GraphUser | Add-Member -NotePropertyName MfaCapable -NotePropertyValue ($methodNames.Count -gt 0) -Force
            $GraphUser | Add-Member -NotePropertyName PasswordlessRegistered -NotePropertyValue (@($methodNames | Where-Object { $_ -match 'FIDO2|Windows Hello|Temporary Access Pass' }).Count -gt 0) -Force
        }

        $riskResponse = Invoke-HybridMicrosoftGraphOptionalRequest -Uri ('{0}/v1.0/identityProtection/riskyUsers/{1}' -f $graphEndpoint, $escapedId) -Session $Session
        if ($null -ne $riskResponse) {
            $riskState = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $riskResponse -Names @('riskState','RiskState') -Default '')
            if (-not [string]::IsNullOrWhiteSpace($riskState)) {
                $GraphUser | Add-Member -NotePropertyName RiskState -NotePropertyValue $riskState -Force
                $GraphUser | Add-Member -NotePropertyName SignInRiskState -NotePropertyValue $riskState -Force
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($upn)) {
        $escapedUpn = $upn.Replace("'", "''")
        $signInFilter = [System.Uri]::EscapeDataString("userPrincipalName eq '$escapedUpn'")
        $signInUri = ('{0}/v1.0/auditLogs/signIns?$top=1&$orderby=createdDateTime%20desc&$filter={1}' -f $graphEndpoint, $signInFilter)
        $signInResponse = Invoke-HybridMicrosoftGraphOptionalRequest -Uri $signInUri -Session $Session
        $signIn = @(Get-HybridMicrosoftGraphObjectValue -InputObject $signInResponse -Names @('value','Value') -Default @() | Select-Object -First 1)
        if ($signIn.Count -gt 0 -and $null -ne $signIn[0]) {
            $latest = $signIn[0]
            $created = Get-HybridMicrosoftGraphObjectValue -InputObject $latest -Names @('createdDateTime','CreatedDateTime') -Default $null
            $conditionalAccess = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $latest -Names @('conditionalAccessStatus','ConditionalAccessStatus') -Default '')
            $riskState = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $latest -Names @('riskState','RiskState') -Default '')
            $methodsUsed = @(Get-HybridMicrosoftGraphObjectValue -InputObject $latest -Names @('authenticationMethodsUsed','AuthenticationMethodsUsed') -Default @())

            if ($null -ne $created) { $GraphUser | Add-Member -NotePropertyName LastSignInDateTime -NotePropertyValue $created -Force }
            if (-not [string]::IsNullOrWhiteSpace($conditionalAccess)) { $GraphUser | Add-Member -NotePropertyName ConditionalAccessState -NotePropertyValue $conditionalAccess -Force }
            if (-not [string]::IsNullOrWhiteSpace($riskState)) {
                $GraphUser | Add-Member -NotePropertyName RiskState -NotePropertyValue $riskState -Force
                $GraphUser | Add-Member -NotePropertyName SignInRiskState -NotePropertyValue $riskState -Force
            }
            if ($methodsUsed.Count -gt 0 -and -not ($GraphUser.PSObject.Properties.Name -contains 'AuthenticationMethods')) {
                $GraphUser | Add-Member -NotePropertyName AuthenticationMethods -NotePropertyValue @($methodsUsed) -Force
            }
        }
    }

    return $GraphUser
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
