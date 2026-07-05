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
    RequestTimeoutSeconds     = 12
    OptionalRequestTimeoutSeconds = 4
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


function Get-HybridMicrosoftGraphCollectionCount {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return 0 }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return 0 }
        return 1
    }

    try {
        if ($Value.PSObject.Properties.Name -contains 'Count') {
            $countValue = $Value.Count
            if ($null -ne $countValue) { return [int]$countValue }
        }
    }
    catch { }

    try { return @($Value).Count } catch { return 1 }
}

function ConvertTo-HybridMicrosoftGraphArray {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @($Value)
    }
    return @($Value)
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
    $licenses = @(Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('Licenses','AssignedLicenses','assignedLicenses') -Default @())
    $licenseAssignmentStates = @(Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('LicenseAssignmentStates','licenseAssignmentStates') -Default @())
    $pimRoles = @(Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('PimRoles','PIMRoles','PrivilegedIdentityRoles','DirectoryRoles','AzureRoles') -Default @())
    $graphDiagnostics = @(Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('GraphDiagnostics','Diagnostics') -Default @())
    $licenseDiagnostic = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('LicenseDiagnostic','LicenseDiagnostics') -Default '')
    $pimRoleDiagnostic = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('PimRoleDiagnostic','PimRoleDiagnostics','PimDiagnostics','RoleDiagnostic','RoleDiagnostics') -Default '')
    $businessPhones = @(Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('businessPhones','BusinessPhones') -Default @())
    $phoneNumber = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('PhoneNumber','TelephoneNumber','mobilePhone','MobilePhone') -Default '')
    if ([string]::IsNullOrWhiteSpace($phoneNumber) -and (Get-HybridMicrosoftGraphCollectionCount $businessPhones) -gt 0) { $phoneNumber = [string]$businessPhones[0] }

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
        Licenses            = @($licenses)
        AssignedLicenses    = @($licenses)
        LicenseAssignmentStates = @($licenseAssignmentStates)
        PimRoles            = @($pimRoles)
        DirectoryRoles      = @($pimRoles)
        GraphDiagnostics    = @($graphDiagnostics)
        LicenseDiagnostic   = $licenseDiagnostic
        LicenseDiagnostics  = $licenseDiagnostic
        PimRoleDiagnostic   = $pimRoleDiagnostic
        PimRoleDiagnostics  = $pimRoleDiagnostic
        PimDiagnostics      = $pimRoleDiagnostic
        DefaultMethod       = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('DefaultMethod','DefaultAuthenticationMethod') -Default $(if ((Get-HybridMicrosoftGraphCollectionCount $methods) -gt 0) { [string]$methods[0] } else { '' }))
        MfaRegistered       = [bool](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('MfaRegistered','MfaEnabled','IsMfaRegistered') -Default ((Get-HybridMicrosoftGraphCollectionCount $methods) -gt 1))
        MfaCapable          = [bool](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('MfaCapable','IsMfaCapable') -Default ((Get-HybridMicrosoftGraphCollectionCount $methods) -gt 0))
        PasswordlessRegistered = [bool](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('PasswordlessRegistered','IsPasswordlessRegistered') -Default (@($methods | Where-Object { $_ -match 'passwordless|fido|windows hello|temporary access pass' }).Count -gt 0))
        AuthenticationStrength = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $GraphUser -Names @('AuthenticationStrength','StrongAuthenticationRequirement') -Default $(if ((Get-HybridMicrosoftGraphCollectionCount $methods) -gt 1) { 'Multi-factor capable' } else { 'Single-factor' }))
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

    $user = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec ([int]$script:HybridMicrosoftGraphState.RequestTimeoutSeconds) -ErrorAction Stop
    $profileSelects = @(
        'companyName,officeLocation,employeeId,mobilePhone,businessPhones',
        'assignedLicenses,licenseAssignmentStates',
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
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = ('Bearer {0}' -f $token) } -TimeoutSec ([int]$script:HybridMicrosoftGraphState.OptionalRequestTimeoutSeconds) -ErrorAction Stop
    }
    catch {
        return $null
    }
}


function Get-HybridMicrosoftGraphSubscribedSkuMap {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Session)

    $tenantContext = $script:HybridMicrosoftGraphState.TenantContext
    $graphEndpoint = Get-HybridMicrosoftGraphEndpoint -TenantContext $tenantContext
    $map = @{}
    $response = Invoke-HybridMicrosoftGraphOptionalRequest -Uri ('{0}/v1.0/subscribedSkus?$select=skuId,skuPartNumber,consumedUnits,prepaidUnits' -f $graphEndpoint) -Session $Session
    foreach ($sku in @(Get-HybridMicrosoftGraphObjectValue -InputObject $response -Names @('value','Value') -Default @())) {
        $skuId = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $sku -Names @('skuId','SkuId') -Default '')
        $skuPartNumber = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $sku -Names @('skuPartNumber','SkuPartNumber') -Default '')
        if (-not [string]::IsNullOrWhiteSpace($skuId) -and -not [string]::IsNullOrWhiteSpace($skuPartNumber)) {
            $map[$skuId] = $skuPartNumber
            $map[$skuId.ToLowerInvariant()] = $skuPartNumber
        }
    }

    return $map
}


function ConvertTo-HybridMicrosoftGraphSkuFriendlyName {
    [CmdletBinding()]
    param([AllowNull()][string]$SkuPartNumber)

    if ([string]::IsNullOrWhiteSpace($SkuPartNumber)) { return '' }
    $key = $SkuPartNumber.Trim()
    $map = @{
        'AAD_PREMIUM' = 'Microsoft Entra ID P1'
        'AAD_PREMIUM_P2' = 'Microsoft Entra ID P2'
        'ATP_ENTERPRISE' = 'Microsoft Defender for Office 365 Plan 1'
        'ATP_ENTERPRISE_FACULTY' = 'Microsoft Defender for Office 365 Plan 1'
        'DESKLESSPACK' = 'Office 365 F3'
        'EMSPREMIUM' = 'Enterprise Mobility + Security E5'
        'EMS' = 'Enterprise Mobility + Security E3'
        'ENTERPRISEPACK' = 'Office 365 E3'
        'ENTERPRISEPREMIUM' = 'Office 365 E5'
        'EXCHANGEENTERPRISE' = 'Exchange Online Plan 2'
        'EXCHANGESTANDARD' = 'Exchange Online Plan 1'
        'FLOW_FREE' = 'Power Automate Free'
        'INTUNE_A' = 'Microsoft Intune Plan 1'
        'M365EDU_A3_FACULTY' = 'Microsoft 365 A3 Faculty'
        'M365EDU_A5_FACULTY' = 'Microsoft 365 A5 Faculty'
        'M365_F1' = 'Microsoft 365 F1'
        'M365_F3' = 'Microsoft 365 F3'
        'M365_G3_GOV' = 'Microsoft 365 G3 GCC/GCC High'
        'M365_G5_GOV' = 'Microsoft 365 G5 GCC/GCC High'
        'MCOSTANDARD' = 'Microsoft Teams'
        'O365_BUSINESS_ESSENTIALS' = 'Microsoft 365 Business Basic'
        'O365_BUSINESS_PREMIUM' = 'Microsoft 365 Business Standard'
        'POWER_BI_PRO' = 'Power BI Pro'
        'POWER_BI_STANDARD' = 'Power BI Free'
        'PROJECTESSENTIALS' = 'Project Online Essentials'
        'PROJECTPREMIUM' = 'Project Plan 5'
        'PROJECTPROFESSIONAL' = 'Project Plan 3'
        'SPE_E3' = 'Microsoft 365 E3'
        'SPE_E5' = 'Microsoft 365 E5'
        'STANDARDPACK' = 'Office 365 E1'
        'VISIOCLIENT' = 'Visio Plan 2'
        'VISIOONLINE_PLAN1' = 'Visio Plan 1'
        'WIN10_PRO_ENT_SUB' = 'Windows Enterprise E3'
        'WIN_DEF_ATP' = 'Microsoft Defender for Endpoint'
        'SPE_E5_SEC' = 'Microsoft 365 E5 Security'
        'IDENTITY_THREAT_PROTECTION' = 'Microsoft 365 E5 Security'
        'THREAT_INTELLIGENCE' = 'Microsoft Defender for Office 365 Plan 2'
        'RIGHTSMANAGEMENT' = 'Azure Information Protection Plan 1'
        'POWERAPPS_PER_USER' = 'Power Apps Premium'
        'EXCHANGE_S_ENTERPRISE_GOV' = 'Exchange Online Plan 2 GCC/GCC High'
        'EXCHANGE_S_STANDARD_GOV' = 'Exchange Online Plan 1 GCC/GCC High'
    }

    if ($map.ContainsKey($key)) { return [string]$map[$key] }
    $upperKey = $key.ToUpperInvariant()
    if ($map.ContainsKey($upperKey)) { return [string]$map[$upperKey] }

    $fallback = ($key -replace '_GOV$', ' GCC/GCC High') -replace '_', ' '
    return (Get-Culture).TextInfo.ToTitleCase($fallback.ToLowerInvariant())
}


function ConvertTo-HybridMicrosoftGraphFriendlyLicenseName {
    [CmdletBinding()]
    param([AllowNull()][string]$SkuPartNumber)

    if ([string]::IsNullOrWhiteSpace($SkuPartNumber)) { return '' }
    $key = $SkuPartNumber.Trim()
    $upperKey = $key.ToUpperInvariant()
    $map = @{
        'AAD_PREMIUM' = 'Microsoft Entra ID P1'; 'AAD_PREMIUM_P2' = 'Microsoft Entra ID P2'; 'ATP_ENTERPRISE' = 'Microsoft Defender for Office 365 Plan 1'
        'DESKLESSPACK' = 'Office 365 F3'; 'EMS' = 'Enterprise Mobility + Security E3'; 'EMSPREMIUM' = 'Enterprise Mobility + Security E5'
        'ENTERPRISEPACK' = 'Office 365 E3'; 'ENTERPRISEPREMIUM' = 'Office 365 E5'; 'ENTERPRISEPREMIUM_NOPSTNCONF' = 'Office 365 E5 without Audio Conferencing'
        'EXCHANGEENTERPRISE' = 'Exchange Online Plan 2'; 'EXCHANGESTANDARD' = 'Exchange Online Plan 1'; 'FLOW_FREE' = 'Power Automate Free'
        'IDENTITY_THREAT_PROTECTION' = 'Microsoft 365 E5 Security'; 'INTUNE_A' = 'Microsoft Intune Plan 1'
        'M365_F1' = 'Microsoft 365 F1'; 'M365_F3' = 'Microsoft 365 F3'; 'M365_G3_GOV' = 'Microsoft 365 G3 GCC/GCC High'; 'M365_G5_GOV' = 'Microsoft 365 G5 GCC/GCC High'
        'MCOSTANDARD' = 'Microsoft Teams'; 'MEETING_ROOM' = 'Microsoft Teams Rooms Standard'
        'O365_BUSINESS' = 'Microsoft 365 Apps for business'; 'O365_BUSINESS_ESSENTIALS' = 'Microsoft 365 Business Basic'; 'O365_BUSINESS_PREMIUM' = 'Microsoft 365 Business Standard'
        'POWER_BI_PRO' = 'Power BI Pro'; 'POWERAPPS_PER_USER' = 'Power Apps Premium'; 'PROJECTESSENTIALS' = 'Project Plan 1'; 'PROJECTPREMIUM' = 'Project Plan 5'; 'PROJECTPROFESSIONAL' = 'Project Plan 3'
        'RIGHTSMANAGEMENT' = 'Azure Information Protection Plan 1'; 'SPE_E3' = 'Microsoft 365 E3'; 'SPE_E5' = 'Microsoft 365 E5'; 'SPE_F1' = 'Microsoft 365 F3'
        'STANDARDPACK' = 'Office 365 E1'; 'STANDARDWOFFPACK' = 'Office 365 E2'; 'STREAM' = 'Microsoft Stream'; 'TEAMS_EXPLORATORY' = 'Microsoft Teams Exploratory'
        'VISIOCLIENT' = 'Visio Plan 2'; 'VISIOONLINE_PLAN1' = 'Visio Plan 1'; 'WIN10_PRO_ENT_SUB' = 'Windows Enterprise E3'; 'WIN_DEF_ATP' = 'Microsoft Defender for Endpoint'
        'SPE_E5_SEC' = 'Microsoft 365 E5 Security'
        'THREAT_INTELLIGENCE' = 'Microsoft Defender for Office 365 Plan 2'
        'EXCHANGE_S_ENTERPRISE_GOV' = 'Exchange Online Plan 2 GCC/GCC High'
        'EXCHANGE_S_STANDARD_GOV' = 'Exchange Online Plan 1 GCC/GCC High'
    }
    if ($map.ContainsKey($key)) { return [string]$map[$key] }
    if ($map.ContainsKey($upperKey)) { return [string]$map[$upperKey] }
    if ($upperKey -match '^[A-Z0-9_]+$') {
        $fallback = $key -replace '_GOV$', ' GCC/GCC High' -replace '_GCCHIGH$', ' GCC High' -replace '_DOD$', ' DoD' -replace '^SPE_', 'Microsoft 365 ' -replace '_', ' '
        return (Get-Culture).TextInfo.ToTitleCase($fallback.ToLowerInvariant())
    }
    return $key
}

function ConvertTo-HybridMicrosoftGraphLicenseDisplayObject {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$License,
        [hashtable]$SkuMap = @{}
    )

    if ($null -eq $License) { return $null }
    if ($License -is [string]) {
        $skuString = [string]$License
        return [pscustomobject]@{ PSTypeName = 'Hybrid.MicrosoftGraph.License'; DisplayName = (ConvertTo-HybridMicrosoftGraphSkuFriendlyName -SkuPartNumber $skuString); SkuPartNumber = $skuString; SkuId = ''; Status = ''; AssignmentSource = ''; DisabledPlans = @() }
    }

    $skuId = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $License -Names @('skuId','SkuId') -Default '')
    $skuPartNumber = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $License -Names @('skuPartNumber','SkuPartNumber') -Default '')
    if ([string]::IsNullOrWhiteSpace($skuPartNumber) -and -not [string]::IsNullOrWhiteSpace($skuId)) {
        if ($SkuMap.ContainsKey($skuId)) { $skuPartNumber = [string]$SkuMap[$skuId] }
        elseif ($SkuMap.ContainsKey($skuId.ToLowerInvariant())) { $skuPartNumber = [string]$SkuMap[$skuId.ToLowerInvariant()] }
    }
    if ([string]::IsNullOrWhiteSpace($skuPartNumber)) { $skuPartNumber = $skuId }
    $friendlyName = ConvertTo-HybridMicrosoftGraphFriendlyLicenseName -SkuPartNumber $skuPartNumber

    $state = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $License -Names @('state','State') -Default '')
    $assignmentSource = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $License -Names @('assignedByGroup','AssignedByGroup','AssignmentSource') -Default '')
    $disabledPlans = @(Get-HybridMicrosoftGraphObjectValue -InputObject $License -Names @('disabledPlans','DisabledPlans') -Default @())

    $friendlyName = ConvertTo-HybridMicrosoftGraphSkuFriendlyName -SkuPartNumber $skuPartNumber

    return [pscustomobject]@{
        PSTypeName = 'Hybrid.MicrosoftGraph.License'
        DisplayName = $friendlyName
        SkuPartNumber = $skuPartNumber
        SkuId = $skuId
        Status = $state
        AssignmentSource = $assignmentSource
        DisabledPlans = @($disabledPlans)
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
        if ((Get-HybridMicrosoftGraphCollectionCount $methodValues) -gt 0) {
            $methodNames = @($methodValues | ForEach-Object { ConvertTo-HybridMicrosoftGraphAuthenticationMethodName -Method $_ } | Select-Object -Unique)
            $GraphUser | Add-Member -NotePropertyName AuthenticationMethods -NotePropertyValue @($methodNames) -Force
            $GraphUser | Add-Member -NotePropertyName MfaRegistered -NotePropertyValue ((Get-HybridMicrosoftGraphCollectionCount $methodNames) -gt 1) -Force
            $GraphUser | Add-Member -NotePropertyName MfaCapable -NotePropertyValue ((Get-HybridMicrosoftGraphCollectionCount $methodNames) -gt 0) -Force
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

        $skuMap = Get-HybridMicrosoftGraphSubscribedSkuMap -Session $Session
        $licenseDetailsResponse = Invoke-HybridMicrosoftGraphOptionalRequest -Uri ('{0}/v1.0/users/{1}/licenseDetails' -f $graphEndpoint, $escapedId) -Session $Session
        $licenseDetailValues = @(Get-HybridMicrosoftGraphObjectValue -InputObject $licenseDetailsResponse -Names @('value','Value') -Default @() | ForEach-Object { ConvertTo-HybridMicrosoftGraphLicenseDisplayObject -License $_ -SkuMap $skuMap } | Where-Object { $null -ne $_ })
        $licenseResponse = Invoke-HybridMicrosoftGraphOptionalRequest -Uri ('{0}/v1.0/users/{1}?$select=assignedLicenses,licenseAssignmentStates' -f $graphEndpoint, $escapedId) -Session $Session
        $assignedLicenses = @()
        $licenseAssignmentStates = @()
        if ($null -ne $licenseResponse) {
            $assignedLicenses = @(Get-HybridMicrosoftGraphObjectValue -InputObject $licenseResponse -Names @('assignedLicenses','AssignedLicenses') -Default @() | ForEach-Object { ConvertTo-HybridMicrosoftGraphLicenseDisplayObject -License $_ -SkuMap $skuMap } | Where-Object { $null -ne $_ })
            $licenseAssignmentStates = @(Get-HybridMicrosoftGraphObjectValue -InputObject $licenseResponse -Names @('licenseAssignmentStates','LicenseAssignmentStates') -Default @() | ForEach-Object { ConvertTo-HybridMicrosoftGraphLicenseDisplayObject -License $_ -SkuMap $skuMap } | Where-Object { $null -ne $_ })
        }
        $displayLicenses = if ((Get-HybridMicrosoftGraphCollectionCount $licenseDetailValues) -gt 0) { @($licenseDetailValues) } else { @($assignedLicenses) }
        if ((Get-HybridMicrosoftGraphCollectionCount $displayLicenses) -gt 0) {
            $GraphUser | Add-Member -NotePropertyName Licenses -NotePropertyValue @($displayLicenses) -Force
            $GraphUser | Add-Member -NotePropertyName AssignedLicenses -NotePropertyValue @($displayLicenses) -Force
        }
        elseif ((Get-HybridMicrosoftGraphCollectionCount $licenseAssignmentStates) -gt 0) {
            $GraphUser | Add-Member -NotePropertyName Licenses -NotePropertyValue @($licenseAssignmentStates) -Force
            $GraphUser | Add-Member -NotePropertyName AssignedLicenses -NotePropertyValue @($licenseAssignmentStates) -Force
        }
        if ((Get-HybridMicrosoftGraphCollectionCount $licenseAssignmentStates) -gt 0) {
            $GraphUser | Add-Member -NotePropertyName LicenseAssignmentStates -NotePropertyValue @($licenseAssignmentStates) -Force
        }
        if ((Get-HybridMicrosoftGraphCollectionCount $licenseDetailValues) -eq 0 -and (Get-HybridMicrosoftGraphCollectionCount $assignedLicenses) -eq 0 -and (Get-HybridMicrosoftGraphCollectionCount $licenseAssignmentStates) -eq 0) {
            $licenseMessage = if ($null -eq $licenseDetailsResponse -and $null -eq $licenseResponse) {
                'License lookup did not return data. Verify Directory.Read.All/User.Read.All consent and Graph cloud endpoint.'
            }
            else {
                'Graph returned no licenseDetails, assignedLicenses, or licenseAssignmentStates records for this user.'
            }
            $GraphUser | Add-Member -NotePropertyName LicenseDiagnostic -NotePropertyValue $licenseMessage -Force
            $GraphUser | Add-Member -NotePropertyName LicenseDiagnostics -NotePropertyValue $licenseMessage -Force
        }

        $pimRoles = New-Object System.Collections.Generic.List[object]
        $roleFilter = [System.Uri]::EscapeDataString("principalId eq '$id'")
        $roleRequests = @(
            [pscustomobject]@{ Uri = ('{0}/v1.0/roleManagement/directory/roleAssignments?$filter={1}&$select=id,roleDefinitionId,directoryScopeId' -f $graphEndpoint, $roleFilter); AssignmentType = 'Permanent assignment' },
            [pscustomobject]@{ Uri = ('{0}/beta/roleManagement/directory/roleAssignmentScheduleInstances?$filter={1}' -f $graphEndpoint, $roleFilter); AssignmentType = 'Active assignment' },
            [pscustomobject]@{ Uri = ('{0}/beta/roleManagement/directory/roleEligibilityScheduleInstances?$filter={1}' -f $graphEndpoint, $roleFilter); AssignmentType = 'Eligible assignment' }
        )
        foreach ($roleRequest in $roleRequests) {
            $roleResponse = Invoke-HybridMicrosoftGraphOptionalRequest -Uri $roleRequest.Uri -Session $Session
            foreach ($role in @(Get-HybridMicrosoftGraphObjectValue -InputObject $roleResponse -Names @('value','Value') -Default @())) {
                $roleDefinitionId = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $role -Names @('roleDefinitionId','RoleDefinitionId') -Default '')
                if ([string]::IsNullOrWhiteSpace($roleDefinitionId)) { continue }
                $status = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $role -Names @('status','Status') -Default '')
                if ([string]::IsNullOrWhiteSpace($status)) { $status = [string]$roleRequest.AssignmentType }
                $pimRoles.Add([pscustomobject]@{
                    PSTypeName = 'Hybrid.MicrosoftGraph.PimRole'
                    RoleDefinitionId = $roleDefinitionId
                    DisplayName = $roleDefinitionId
                    RoleDefinitionName = $roleDefinitionId
                    AssignmentType = [string]$roleRequest.AssignmentType
                    Status = $status
                }) | Out-Null
            }
        }
        if ((Get-HybridMicrosoftGraphCollectionCount $pimRoles) -eq 0) {
            foreach ($membershipPath in @('memberOf/microsoft.graph.directoryRole','transitiveMemberOf/microsoft.graph.directoryRole')) {
                $roleMembershipResponse = Invoke-HybridMicrosoftGraphOptionalRequest -Uri ('{0}/v1.0/users/{1}/{2}?$select=id,displayName,roleTemplateId' -f $graphEndpoint, $escapedId, $membershipPath) -Session $Session
                foreach ($roleMembership in @(Get-HybridMicrosoftGraphObjectValue -InputObject $roleMembershipResponse -Names @('value','Value') -Default @())) {
                    $roleName = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $roleMembership -Names @('displayName','DisplayName') -Default '')
                    $roleId = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $roleMembership -Names @('roleTemplateId','RoleTemplateId','id','Id') -Default '')
                    if ([string]::IsNullOrWhiteSpace($roleName) -and [string]::IsNullOrWhiteSpace($roleId)) { continue }
                    if ([string]::IsNullOrWhiteSpace($roleName)) { $roleName = $roleId }
                    $pimRoles.Add([pscustomobject]@{
                        PSTypeName = 'Hybrid.MicrosoftGraph.PimRole'
                        RoleDefinitionId = $roleId
                        DisplayName = $roleName
                        RoleDefinitionName = $roleName
                        AssignmentType = 'Directory role membership'
                        Status = 'Active'
                    }) | Out-Null
                }
                if ((Get-HybridMicrosoftGraphCollectionCount $pimRoles) -gt 0) { break }
            }
        }

        if ((Get-HybridMicrosoftGraphCollectionCount $pimRoles) -gt 0) {
            $definitionResponse = Invoke-HybridMicrosoftGraphOptionalRequest -Uri ('{0}/v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName' -f $graphEndpoint) -Session $Session
            $definitionMap = @{}
            foreach ($definition in @(Get-HybridMicrosoftGraphObjectValue -InputObject $definitionResponse -Names @('value','Value') -Default @())) {
                $definitionId = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $definition -Names @('id','Id') -Default '')
                $definitionName = [string](Get-HybridMicrosoftGraphObjectValue -InputObject $definition -Names @('displayName','DisplayName') -Default '')
                if (-not [string]::IsNullOrWhiteSpace($definitionId) -and -not [string]::IsNullOrWhiteSpace($definitionName)) { $definitionMap[$definitionId] = $definitionName }
            }
            foreach ($role in @($pimRoles)) {
                if (-not [string]::IsNullOrWhiteSpace($role.RoleDefinitionId) -and $definitionMap.ContainsKey($role.RoleDefinitionId)) {
                    $role.DisplayName = $definitionMap[$role.RoleDefinitionId]
                    $role.RoleDefinitionName = $definitionMap[$role.RoleDefinitionId]
                }
            }
            $roleValues = @($pimRoles | Sort-Object DisplayName,AssignmentType -Unique)
            $GraphUser | Add-Member -NotePropertyName PimRoles -NotePropertyValue @($roleValues) -Force
            $GraphUser | Add-Member -NotePropertyName DirectoryRoles -NotePropertyValue @($roleValues) -Force
        }
        else {
            $pimMessage = 'No directory role/PIM assignments returned from roleManagement or directoryRole membership endpoints. Verify RoleManagement.Read.Directory and Directory.Read.All admin consent, and confirm the user has assigned, active, or eligible roles.'
            $GraphUser | Add-Member -NotePropertyName PimRoleDiagnostic -NotePropertyValue $pimMessage -Force
            $GraphUser | Add-Member -NotePropertyName PimRoleDiagnostics -NotePropertyValue $pimMessage -Force
            $GraphUser | Add-Member -NotePropertyName PimDiagnostics -NotePropertyValue $pimMessage -Force
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($upn)) {
        $escapedUpn = $upn.Replace("'", "''")
        $signInFilter = [System.Uri]::EscapeDataString("userPrincipalName eq '$escapedUpn'")
        $signInUri = ('{0}/v1.0/auditLogs/signIns?$top=1&$orderby=createdDateTime%20desc&$filter={1}' -f $graphEndpoint, $signInFilter)
        $signInResponse = Invoke-HybridMicrosoftGraphOptionalRequest -Uri $signInUri -Session $Session
        $signIn = @(Get-HybridMicrosoftGraphObjectValue -InputObject $signInResponse -Names @('value','Value') -Default @() | Select-Object -First 1)
        if ((Get-HybridMicrosoftGraphCollectionCount $signIn) -gt 0 -and $null -ne $signIn[0]) {
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
            if ((Get-HybridMicrosoftGraphCollectionCount $methodsUsed) -gt 0 -and -not ($GraphUser.PSObject.Properties.Name -contains 'AuthenticationMethods')) {
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

    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec ([int]$script:HybridMicrosoftGraphState.RequestTimeoutSeconds) -ErrorAction Stop
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

        if ((Get-HybridMicrosoftGraphCollectionCount $users) -eq 0 -and -not [string]::IsNullOrWhiteSpace($Query)) {
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

        if ((Get-HybridMicrosoftGraphCollectionCount $match) -eq 0) {
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
            CacheEntries    = (Get-HybridMicrosoftGraphCollectionCount $script:HybridMicrosoftGraphState.Cache.Users)
            CommandCount    = (Get-HybridMicrosoftGraphCollectionCount $script:HybridMicrosoftGraphProviderState.CommandHistory)
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
            CacheEntries    = (Get-HybridMicrosoftGraphCollectionCount $script:HybridMicrosoftGraphState.Cache.Users)
            CommandCount    = (Get-HybridMicrosoftGraphCollectionCount $script:HybridMicrosoftGraphProviderState.CommandHistory)
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
