#region Module Information
# Name: Application.HybridUserService
# Purpose: Vertical-slice service layer for unified Hybrid.User search and enriched user details.
# Dependencies: Provider services supplied by caller.
# Exports: Initialize-HybridUserService, Search-HybridUser, Get-HybridUser, Get-HybridUserDetails, Get-HybridUserMailboxDetails, Get-HybridUserServiceHealth, Clear-HybridUserService
#endregion

Set-StrictMode -Version Latest

$script:HybridUserServiceState = @{
    Initialized      = $false
    ActiveDirectory  = $null
    MicrosoftGraph   = $null
    ExchangeOnline   = $null
    Cache            = @{}
    DetailCache      = @{}
    MailboxCache     = @{}
    LastQuery        = $null
    LastResult       = $null
    LastError        = $null
}

function Get-HybridObjectValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory=$true)][string[]]$Names,
        [AllowNull()][object]$Default = $null
    )

    foreach ($name in $Names) {
        if ($null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains $name) {
            $value = $InputObject.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                return $value
            }
        }
    }

    return $Default
}

function Invoke-HybridServiceOperation {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Service,
        [Parameter(Mandatory=$true)][string[]]$OperationNames,
        [object[]]$Arguments = @()
    )

    if ($null -eq $Service) { return @() }

    foreach ($operationName in $OperationNames) {
        if ($Service.PSObject.Properties.Name -contains $operationName) {
            $operation = $Service.$operationName
            if ($operation -is [scriptblock]) {
                return @(& $operation @Arguments)
            }
            if ($null -ne $operation -and $operation.PSObject.Methods.Name -contains 'Invoke') {
                return @($operation.Invoke($Arguments))
            }
        }
    }

    return @()
}

function Get-HybridProviderHealthSnapshot {
    [CmdletBinding()]
    param([AllowNull()][object]$Service)

    $health = @(Invoke-HybridServiceOperation -Service $Service -OperationNames @('GetHealth','GetProviderHealth') -Arguments @() | Select-Object -First 1)
    if ($health.Count -gt 0) { return $health[0] }

    if ($null -eq $Service) {
        return [pscustomobject]@{
            PSTypeName = 'Hybrid.ProviderHealth.ApplicationSnapshot'
            Initialized = $false
            Available = $false
            Connected = $false
            LastError = $null
        }
    }

    return [pscustomobject]@{
        PSTypeName = 'Hybrid.ProviderHealth.ApplicationSnapshot'
        Initialized = $true
        Available = [bool](Get-HybridObjectValue -InputObject $Service -Names @('ProviderAvailable','Available') -Default $true)
        Connected = [bool](Get-HybridObjectValue -InputObject $Service -Names @('ProviderConnected','Connected','ProviderAvailable','Available') -Default $true)
        LastError = Get-HybridObjectValue -InputObject $Service -Names @('LastError','Error','ErrorMessage') -Default $null
    }
}

function ConvertTo-HybridSourceStatus {
    [CmdletBinding()]
    param(
        [string]$Name,
        [AllowNull()][object]$Object,
        [AllowNull()][object]$ProviderHealth
    )

    $available = ($null -ne $Object)
    $connected = $available
    $lastError = $null

    if ($null -ne $ProviderHealth) {
        $available = [bool](Get-HybridObjectValue -InputObject $ProviderHealth -Names @('Available','ProviderAvailable','Initialized') -Default $available)
        $connected = [bool](Get-HybridObjectValue -InputObject $ProviderHealth -Names @('Connected','ProviderConnected','Available') -Default $available)
        $lastError = Get-HybridObjectValue -InputObject $ProviderHealth -Names @('LastError','Error','ErrorMessage') -Default $null
    }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.UserSourceStatus'
        Name       = $Name
        Available  = $available
        Connected  = $connected
        LastError  = $lastError
        Object     = $Object
        Health     = $ProviderHealth
    }
}

function ConvertTo-HybridUserOrganizationalUnit {
    [CmdletBinding()]
    param([AllowNull()][string]$DistinguishedName)

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { return '' }

    $ouParts = @($DistinguishedName -split ',' | Where-Object { $_ -like 'OU=*' } | ForEach-Object { $_.Substring(3) })
    if ($ouParts.Count -eq 0) { return '' }

    [array]::Reverse($ouParts)
    return ($ouParts -join ' / ')
}

function ConvertTo-HybridDisplayNameFromDn {
    [CmdletBinding()]
    param([AllowNull()][string]$DistinguishedName)

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { return '' }
    $firstPart = ($DistinguishedName -split ',' | Select-Object -First 1)
    if ($firstPart -like 'CN=*') { return $firstPart.Substring(3) }
    return $DistinguishedName
}

function New-HybridCompositeUser {
    [CmdletBinding()]
    param(
        [string]$Identity,
        [AllowNull()][object]$ActiveDirectoryUser,
        [AllowNull()][object]$GraphUser,
        [AllowNull()][object]$Mailbox,
        [AllowNull()][object]$ActiveDirectoryHealth,
        [AllowNull()][object]$GraphHealth,
        [AllowNull()][object]$ExchangeHealth
    )

    $displayName = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('DisplayName','Name') -Default $null
    if ($null -eq $displayName) {
        $displayName = Get-HybridObjectValue -InputObject $GraphUser -Names @('DisplayName','Name') -Default $Identity
    }

    $upn = Get-HybridObjectValue -InputObject $GraphUser -Names @('UserPrincipalName','UPN') -Default $null
    if ($null -eq $upn) {
        $upn = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('UserPrincipalName','UPN') -Default $Identity
    }

    $mail = Get-HybridObjectValue -InputObject $Mailbox -Names @('PrimarySmtpAddress','Mail','EmailAddress') -Default $null
    if ($null -eq $mail) { $mail = Get-HybridObjectValue -InputObject $GraphUser -Names @('Mail','EmailAddress') -Default $null }
    if ($null -eq $mail) { $mail = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Mail','EmailAddress') -Default $null }

    $distinguishedName = [string](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('DistinguishedName','DN') -Default '')
    $manager = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Manager') -Default $null

    $user = [pscustomobject]@{
        PSTypeName            = 'Hybrid.User'
        Identity              = $Identity
        DisplayName           = [string]$displayName
        UserPrincipalName     = [string]$upn
        SamAccountName        = [string](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('SamAccountName','SAMAccountName') -Default '')
        Mail                  = [string]$mail
        Department            = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('Department') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Department') -Default ''))
        Title                 = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('JobTitle','Title') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Title') -Default ''))
        Company               = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('CompanyName','Company') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Company','CompanyName') -Default ''))
        Office                = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('OfficeLocation','Office') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Office','PhysicalDeliveryOfficeName','OfficeLocation') -Default ''))
        EmployeeId            = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('EmployeeId','EmployeeID') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('EmployeeId','EmployeeID') -Default ''))
        Manager               = $manager
        ManagerDisplayName    = ConvertTo-HybridDisplayNameFromDn -DistinguishedName ([string]$manager)
        DistinguishedName     = $distinguishedName
        OrganizationalUnit    = ConvertTo-HybridUserOrganizationalUnit -DistinguishedName $distinguishedName
        Enabled               = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Enabled','AccountEnabled') -Default $null
        LockedOut             = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('LockedOut','IsLockedOut') -Default $null
        Groups                = @()
        DirectReports         = @()
        Mailbox               = $Mailbox
        MailboxDetails        = $null
        ExchangeLoaded        = $false
        ExchangeRetrievedOn   = $null
        Sources               = @(
            ConvertTo-HybridSourceStatus -Name 'ActiveDirectory' -Object $ActiveDirectoryUser -ProviderHealth $ActiveDirectoryHealth
            ConvertTo-HybridSourceStatus -Name 'MicrosoftGraph' -Object $GraphUser -ProviderHealth $GraphHealth
            ConvertTo-HybridSourceStatus -Name 'ExchangeOnline' -Object $Mailbox -ProviderHealth $ExchangeHealth
        )
        Source                = 'HybridUserService'
        RetrievedOn           = [datetime]::UtcNow
        DetailsLoaded         = $false
        DetailRetrievedOn     = $null
    }

    $user.PSObject.TypeNames.Insert(0, 'Hybrid.User.VerticalSlice')
    return $user
}

function Add-HybridUserDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$User)

    $identityCandidates = @(
        (Get-HybridObjectValue -InputObject $User -Names @('UserPrincipalName') -Default $null),
        (Get-HybridObjectValue -InputObject $User -Names @('SamAccountName') -Default $null),
        (Get-HybridObjectValue -InputObject $User -Names @('Identity') -Default $null)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    $identity = [string]($identityCandidates | Select-Object -First 1)

    $groups = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('GetUserGroups','GetGroups','GetADUserGroups') -Arguments @($identity))
    $directReports = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('GetUserDirectReports','GetDirectReports','GetADUserDirectReports') -Arguments @($identity))
    $managerObject = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('GetUserManager','GetManager','GetADUserManager') -Arguments @($identity) | Select-Object -First 1)

    if ($User.PSObject.Properties.Name -notcontains 'Groups') { Add-Member -InputObject $User -NotePropertyName Groups -NotePropertyValue @() }
    if ($User.PSObject.Properties.Name -notcontains 'DirectReports') { Add-Member -InputObject $User -NotePropertyName DirectReports -NotePropertyValue @() }
    if ($User.PSObject.Properties.Name -notcontains 'ManagerObject') { Add-Member -InputObject $User -NotePropertyName ManagerObject -NotePropertyValue $null }
    if ($User.PSObject.Properties.Name -notcontains 'DetailsLoaded') { Add-Member -InputObject $User -NotePropertyName DetailsLoaded -NotePropertyValue $false }
    if ($User.PSObject.Properties.Name -notcontains 'DetailRetrievedOn') { Add-Member -InputObject $User -NotePropertyName DetailRetrievedOn -NotePropertyValue $null }

    $User.Groups = @($groups)
    $User.DirectReports = @($directReports)
    $User.ManagerObject = ($managerObject | Select-Object -First 1)

    if ($null -ne $User.ManagerObject) {
        $managerName = Get-HybridObjectValue -InputObject $User.ManagerObject -Names @('DisplayName','Name','SamAccountName','UserPrincipalName') -Default $null
        if ($null -ne $managerName -and $User.PSObject.Properties.Name -contains 'ManagerDisplayName') {
            $User.ManagerDisplayName = [string]$managerName
        }
    }

    $User.DetailsLoaded = $true
    $User.DetailRetrievedOn = [datetime]::UtcNow
    return $User
}

function Add-HybridUserMailboxDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$User)

    $identityCandidates = @(
        (Get-HybridObjectValue -InputObject $User -Names @('UserPrincipalName') -Default $null),
        (Get-HybridObjectValue -InputObject $User -Names @('Mail') -Default $null),
        (Get-HybridObjectValue -InputObject $User -Names @('SamAccountName') -Default $null),
        (Get-HybridObjectValue -InputObject $User -Names @('Identity') -Default $null)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    $identity = [string]($identityCandidates | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($identity)) { return $User }

    $mailbox = $User.Mailbox
    if ($null -eq $mailbox) {
        $mailbox = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetMailbox','GetUserMailbox','Get') -Arguments @($identity) | Select-Object -First 1)
        $mailbox = ($mailbox | Select-Object -First 1)
    }

    $statistics = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetMailboxStatistics','GetMailboxStats','GetStatistics') -Arguments @($identity) | Select-Object -First 1)
    $delegations = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetMailboxDelegations','GetDelegations','GetMailboxPermissions','GetPermissions') -Arguments @($identity))
    $distributionGroups = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetDistributionGroups','GetOwnedDistributionGroups','GetRecipientGroups') -Arguments @($identity))
    $forwarding = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetMailboxForwarding','GetForwarding') -Arguments @($identity) | Select-Object -First 1)

    $mailboxDetails = [pscustomobject]@{
        PSTypeName = 'Hybrid.UserMailboxDetails'
        Mailbox = $mailbox
        PrimarySmtpAddress = [string](Get-HybridObjectValue -InputObject $mailbox -Names @('PrimarySmtpAddress','Mail','EmailAddress') -Default '')
        RecipientTypeDetails = [string](Get-HybridObjectValue -InputObject $mailbox -Names @('RecipientTypeDetails','RecipientType','Type') -Default '')
        HiddenFromAddressListsEnabled = Get-HybridObjectValue -InputObject $mailbox -Names @('HiddenFromAddressListsEnabled') -Default $null
        LitigationHoldEnabled = Get-HybridObjectValue -InputObject $mailbox -Names @('LitigationHoldEnabled') -Default $null
        ForwardingSmtpAddress = Get-HybridObjectValue -InputObject $forwarding -Names @('ForwardingSmtpAddress','ForwardingAddress') -Default (Get-HybridObjectValue -InputObject $mailbox -Names @('ForwardingSmtpAddress','ForwardingAddress') -Default $null)
        DeliverToMailboxAndForward = Get-HybridObjectValue -InputObject $forwarding -Names @('DeliverToMailboxAndForward') -Default (Get-HybridObjectValue -InputObject $mailbox -Names @('DeliverToMailboxAndForward') -Default $null)
        Statistics = ($statistics | Select-Object -First 1)
        Delegations = @($delegations)
        DistributionGroups = @($distributionGroups)
        RetrievedOn = [datetime]::UtcNow
    }

    if ($User.PSObject.Properties.Name -notcontains 'Mailbox') { Add-Member -InputObject $User -NotePropertyName Mailbox -NotePropertyValue $mailbox }
    if ($User.PSObject.Properties.Name -notcontains 'MailboxDetails') { Add-Member -InputObject $User -NotePropertyName MailboxDetails -NotePropertyValue $mailboxDetails }
    if ($User.PSObject.Properties.Name -notcontains 'ExchangeLoaded') { Add-Member -InputObject $User -NotePropertyName ExchangeLoaded -NotePropertyValue $false }
    if ($User.PSObject.Properties.Name -notcontains 'ExchangeRetrievedOn') { Add-Member -InputObject $User -NotePropertyName ExchangeRetrievedOn -NotePropertyValue $null }

    $User.Mailbox = $mailbox
    $User.MailboxDetails = $mailboxDetails
    $User.ExchangeLoaded = $true
    $User.ExchangeRetrievedOn = [datetime]::UtcNow
    return $User
}

function Initialize-HybridUserService {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$ActiveDirectoryProvider,
        [AllowNull()][object]$MicrosoftGraphProvider,
        [AllowNull()][object]$ExchangeOnlineProvider
    )

    $script:HybridUserServiceState.ActiveDirectory = $ActiveDirectoryProvider
    $script:HybridUserServiceState.MicrosoftGraph = $MicrosoftGraphProvider
    $script:HybridUserServiceState.ExchangeOnline = $ExchangeOnlineProvider
    $script:HybridUserServiceState.Initialized = $true
    $script:HybridUserServiceState.Cache.Clear()
    $script:HybridUserServiceState.DetailCache.Clear()
    $script:HybridUserServiceState.MailboxCache.Clear()

    [pscustomobject]@{
        PSTypeName = 'Hybrid.UserService'
        Name       = 'HybridUserService'
        Initialized = $true
        Providers  = @{
            ActiveDirectory = ($null -ne $ActiveDirectoryProvider)
            MicrosoftGraph  = ($null -ne $MicrosoftGraphProvider)
            ExchangeOnline  = ($null -ne $ExchangeOnlineProvider)
        }
        SearchUser     = ({ param([string]$Query) Search-HybridUser -Query $Query }).GetNewClosure()
        GetUser        = ({ param([string]$Identity) Get-HybridUser -Identity $Identity }).GetNewClosure()
        GetUserDetails = ({ param([string]$Identity) Get-HybridUserDetails -Identity $Identity }).GetNewClosure()
        GetMailboxDetails = ({ param([string]$Identity) Get-HybridUserMailboxDetails -Identity $Identity }).GetNewClosure()
        GetHealth      = ({ Get-HybridUserServiceHealth }).GetNewClosure()
    }
}

function Search-HybridUser {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Query)

    if (-not $script:HybridUserServiceState.Initialized) { throw 'Hybrid user service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Query)) { throw 'Search query cannot be empty.' }

    try {
        $script:HybridUserServiceState.LastQuery = $Query
        $adUsers = Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('SearchUser','SearchADUser','Search') -Arguments @($Query)
        $graphUsers = Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.MicrosoftGraph -OperationNames @('SearchUser','SearchGraphUser','Search') -Arguments @($Query)

        $primary = @($graphUsers | Select-Object -First 1)
        if ($primary.Count -eq 0) { $primary = @($adUsers | Select-Object -First 1) }
        if ($primary.Count -eq 0) {
            $script:HybridUserServiceState.LastResult = @()
            return @()
        }

        $identity = [string](Get-HybridObjectValue -InputObject $primary[0] -Names @('UserPrincipalName','UPN','SamAccountName','Identity','Mail') -Default $Query)
        $result = Get-HybridUser -Identity $identity
        $script:HybridUserServiceState.LastResult = @($result)
        return @($result)
    }
    catch {
        $script:HybridUserServiceState.LastError = $_.Exception.Message
        throw
    }
}

function Get-HybridUser {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not $script:HybridUserServiceState.Initialized) { throw 'Hybrid user service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'User identity cannot be empty.' }

    $cacheKey = $Identity.ToLowerInvariant()
    if ($script:HybridUserServiceState.Cache.ContainsKey($cacheKey)) {
        return $script:HybridUserServiceState.Cache[$cacheKey]
    }

    $adUser = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('GetUser','GetADUser','Get') -Arguments @($Identity) | Select-Object -First 1)
    $graphUser = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.MicrosoftGraph -OperationNames @('GetUser','GetGraphUser','Get') -Arguments @($Identity) | Select-Object -First 1)
    $mailbox = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetMailbox','GetUserMailbox','Get') -Arguments @($Identity) | Select-Object -First 1)

    $adHealth = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.ActiveDirectory
    $graphHealth = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.MicrosoftGraph
    $exchangeHealth = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.ExchangeOnline

    $user = New-HybridCompositeUser `
        -Identity $Identity `
        -ActiveDirectoryUser ($adUser | Select-Object -First 1) `
        -GraphUser ($graphUser | Select-Object -First 1) `
        -Mailbox ($mailbox | Select-Object -First 1) `
        -ActiveDirectoryHealth $adHealth `
        -GraphHealth $graphHealth `
        -ExchangeHealth $exchangeHealth

    $script:HybridUserServiceState.Cache[$cacheKey] = $user
    return $user
}

function Get-HybridUserDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not $script:HybridUserServiceState.Initialized) { throw 'Hybrid user service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'User identity cannot be empty.' }

    $cacheKey = $Identity.ToLowerInvariant()
    if ($script:HybridUserServiceState.DetailCache.ContainsKey($cacheKey)) {
        return $script:HybridUserServiceState.DetailCache[$cacheKey]
    }

    $user = Get-HybridUser -Identity $Identity
    $detailedUser = Add-HybridUserDetails -User $user
    $script:HybridUserServiceState.DetailCache[$cacheKey] = $detailedUser
    return $detailedUser
}

function Get-HybridUserMailboxDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not $script:HybridUserServiceState.Initialized) { throw 'Hybrid user service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'User identity cannot be empty.' }

    $cacheKey = $Identity.ToLowerInvariant()
    if ($script:HybridUserServiceState.MailboxCache.ContainsKey($cacheKey)) {
        return $script:HybridUserServiceState.MailboxCache[$cacheKey]
    }

    $user = Get-HybridUserDetails -Identity $Identity
    $exchangeUser = Add-HybridUserMailboxDetails -User $user
    $script:HybridUserServiceState.MailboxCache[$cacheKey] = $exchangeUser
    return $exchangeUser
}

function Get-HybridUserServiceHealth {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        PSTypeName    = 'Hybrid.UserServiceHealth'
        Initialized   = [bool]$script:HybridUserServiceState.Initialized
        Providers     = @{
            ActiveDirectory = ($null -ne $script:HybridUserServiceState.ActiveDirectory)
            MicrosoftGraph  = ($null -ne $script:HybridUserServiceState.MicrosoftGraph)
            ExchangeOnline  = ($null -ne $script:HybridUserServiceState.ExchangeOnline)
        }
        ProviderHealth     = @{
            ActiveDirectory = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.ActiveDirectory
            MicrosoftGraph  = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.MicrosoftGraph
            ExchangeOnline  = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.ExchangeOnline
        }
        CacheEntries       = $script:HybridUserServiceState.Cache.Count
        DetailCacheEntries = $script:HybridUserServiceState.DetailCache.Count
        MailboxCacheEntries = $script:HybridUserServiceState.MailboxCache.Count
        LastQuery          = $script:HybridUserServiceState.LastQuery
        LastError          = $script:HybridUserServiceState.LastError
    }
}

function Clear-HybridUserService {
    [CmdletBinding()]
    param()

    $script:HybridUserServiceState.Initialized = $false
    $script:HybridUserServiceState.ActiveDirectory = $null
    $script:HybridUserServiceState.MicrosoftGraph = $null
    $script:HybridUserServiceState.ExchangeOnline = $null
    $script:HybridUserServiceState.Cache.Clear()
    $script:HybridUserServiceState.DetailCache.Clear()
    $script:HybridUserServiceState.MailboxCache.Clear()
    $script:HybridUserServiceState.LastQuery = $null
    $script:HybridUserServiceState.LastResult = $null
    $script:HybridUserServiceState.LastError = $null
    return $true
}

Export-ModuleMember -Function @(
    'Initialize-HybridUserService',
    'Search-HybridUser',
    'Get-HybridUser',
    'Get-HybridUserDetails',
    'Get-HybridUserMailboxDetails',
    'Get-HybridUserServiceHealth',
    'Clear-HybridUserService'
)
