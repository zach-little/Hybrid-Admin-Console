#region Module Information
# Name: Application.HybridUserService
# Purpose: Milestone 7 vertical-slice service layer for unified Hybrid.User search and user detail enrichment.
# Exports: Initialize-HybridUserService, Search-HybridUser, Get-HybridUser, Get-HybridUserDetails, Get-HybridUserServiceHealth, Clear-HybridUserService
#endregion

Set-StrictMode -Version Latest

$script:HybridUserServiceState = @{
    Initialized     = $false
    ActiveDirectory = $null
    MicrosoftGraph  = $null
    ExchangeOnline  = $null
    Cache           = @{}
    DetailCache     = @{}
    LastQuery       = $null
    LastResult      = $null
    LastError       = $null
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
            if ($operation -is [scriptblock]) { return @(& $operation @Arguments) }
            if ($null -ne $operation -and $operation.PSObject.Methods.Name -contains 'Invoke') { return @($operation.Invoke($Arguments)) }
        }
    }

    return @()
}

function Get-HybridProviderHealth {
    [CmdletBinding()]
    param(
        [string]$Name,
        [AllowNull()][object]$Provider
    )

    $health = @(Invoke-HybridServiceOperation -Service $Provider -OperationNames @('GetHealth','GetProviderHealth','Health') | Select-Object -First 1)
    if ($health.Count -gt 0) { return $health[0] }

    return [pscustomobject]@{
        PSTypeName  = 'Hybrid.ProviderHealth'
        Name        = $Name
        Initialized = ($null -ne $Provider)
        Available   = ($null -ne $Provider)
        Connected   = ($null -ne $Provider)
        LastError   = $null
    }
}

function ConvertTo-HybridSourceStatus {
    [CmdletBinding()]
    param(
        [string]$Name,
        [AllowNull()][object]$Object,
        [AllowNull()][object]$Provider
    )

    $health = Get-HybridProviderHealth -Name $Name -Provider $Provider

    [pscustomobject]@{
        PSTypeName = 'Hybrid.UserSourceStatus'
        Name       = $Name
        Available  = ($null -ne $Object)
        Connected  = [bool](Get-HybridObjectValue -InputObject $health -Names @('Connected','Available','Initialized') -Default ($null -ne $Object))
        Health     = $health
        Object     = $Object
    }
}

function Get-HybridOrganizationalUnitFromDistinguishedName {
    [CmdletBinding()]
    param([AllowNull()][string]$DistinguishedName)

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { return '' }

    $ous = @($DistinguishedName -split ',' | Where-Object { $_ -like 'OU=*' } | ForEach-Object { $_.Substring(3) })
    if ($ous.Count -eq 0) { return '' }

    # Distinguished names list the closest OU first. For UI display, show the
    # path from the domain side toward the user container so nested locations
    # read naturally: Users / Service Desk.
    [array]::Reverse($ous)
    return ($ous -join ' / ')
}

function New-HybridCompositeUser {
    [CmdletBinding()]
    param(
        [string]$Identity,
        [AllowNull()][object]$ActiveDirectoryUser,
        [AllowNull()][object]$GraphUser,
        [AllowNull()][object]$Mailbox
    )

    $displayName = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('DisplayName','Name') -Default $null
    if ($null -eq $displayName) { $displayName = Get-HybridObjectValue -InputObject $GraphUser -Names @('DisplayName','Name') -Default $Identity }

    $upn = Get-HybridObjectValue -InputObject $GraphUser -Names @('UserPrincipalName','UPN') -Default $null
    if ($null -eq $upn) { $upn = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('UserPrincipalName','UPN') -Default $Identity }

    $mail = Get-HybridObjectValue -InputObject $Mailbox -Names @('PrimarySmtpAddress','Mail','EmailAddress') -Default $null
    if ($null -eq $mail) { $mail = Get-HybridObjectValue -InputObject $GraphUser -Names @('Mail','EmailAddress') -Default $null }
    if ($null -eq $mail) { $mail = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Mail','EmailAddress') -Default $null }

    $distinguishedName = [string](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('DistinguishedName','DN') -Default '')

    $user = [pscustomobject]@{
        PSTypeName          = 'Hybrid.User'
        Identity            = $Identity
        DisplayName         = [string]$displayName
        UserPrincipalName   = [string]$upn
        SamAccountName      = [string](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('SamAccountName','SAMAccountName') -Default '')
        Mail                = [string]$mail
        Department          = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('Department') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Department') -Default ''))
        Title               = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('JobTitle','Title') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Title') -Default ''))
        Company             = [string](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Company') -Default (Get-HybridObjectValue -InputObject $GraphUser -Names @('CompanyName','Company') -Default ''))
        Office              = [string](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Office','PhysicalDeliveryOfficeName') -Default (Get-HybridObjectValue -InputObject $GraphUser -Names @('OfficeLocation','Office') -Default ''))
        EmployeeId          = [string](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('EmployeeId','EmployeeID') -Default (Get-HybridObjectValue -InputObject $GraphUser -Names @('EmployeeId','EmployeeID') -Default ''))
        DistinguishedName   = $distinguishedName
        OrganizationalUnit  = (Get-HybridOrganizationalUnitFromDistinguishedName -DistinguishedName $distinguishedName)
        Enabled             = [bool](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Enabled','AccountEnabled') -Default $true)
        LockedOut           = [bool](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('LockedOut','IsLockedOut') -Default $false)
        Manager             = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Manager') -Default $null
        ManagerDisplayName  = ''
        Groups              = @()
        DirectReports       = @()
        DetailsLoaded       = $false
        Mailbox             = $Mailbox
        Sources             = @(
            ConvertTo-HybridSourceStatus -Name 'ActiveDirectory' -Object $ActiveDirectoryUser -Provider $script:HybridUserServiceState.ActiveDirectory
            ConvertTo-HybridSourceStatus -Name 'MicrosoftGraph' -Object $GraphUser -Provider $script:HybridUserServiceState.MicrosoftGraph
            ConvertTo-HybridSourceStatus -Name 'ExchangeOnline' -Object $Mailbox -Provider $script:HybridUserServiceState.ExchangeOnline
        )
        Source              = 'HybridUserService'
        RetrievedOn         = [datetime]::UtcNow
    }

    $user.PSObject.TypeNames.Insert(0, 'Hybrid.User.VerticalSlice')
    return $user
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

    [pscustomobject]@{
        PSTypeName   = 'Hybrid.UserService'
        Name         = 'HybridUserService'
        Initialized  = $true
        Providers    = @{
            ActiveDirectory = ($null -ne $ActiveDirectoryProvider)
            MicrosoftGraph  = ($null -ne $MicrosoftGraphProvider)
            ExchangeOnline  = ($null -ne $ExchangeOnlineProvider)
        }
        SearchUser   = ({ param([string]$Query) Search-HybridUser -Query $Query }).GetNewClosure()
        GetUser      = ({ param([string]$Identity) Get-HybridUser -Identity $Identity }).GetNewClosure()
        GetDetails   = ({ param([string]$Identity) Get-HybridUserDetails -Identity $Identity }).GetNewClosure()
        GetHealth    = ({ Get-HybridUserServiceHealth }).GetNewClosure()
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
    if ($script:HybridUserServiceState.Cache.ContainsKey($cacheKey)) { return $script:HybridUserServiceState.Cache[$cacheKey] }

    $adUser = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('GetUser','GetADUser','Get') -Arguments @($Identity) | Select-Object -First 1)
    $graphUser = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.MicrosoftGraph -OperationNames @('GetUser','GetGraphUser','Get') -Arguments @($Identity) | Select-Object -First 1)
    $mailbox = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetMailbox','GetUserMailbox','Get') -Arguments @($Identity) | Select-Object -First 1)

    $user = New-HybridCompositeUser -Identity $Identity -ActiveDirectoryUser ($adUser | Select-Object -First 1) -GraphUser ($graphUser | Select-Object -First 1) -Mailbox ($mailbox | Select-Object -First 1)
    $script:HybridUserServiceState.Cache[$cacheKey] = $user
    return $user
}

function Get-HybridUserDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not $script:HybridUserServiceState.Initialized) { throw 'Hybrid user service has not been initialized.' }

    $cacheKey = $Identity.ToLowerInvariant()
    if ($script:HybridUserServiceState.DetailCache.ContainsKey($cacheKey)) { return $script:HybridUserServiceState.DetailCache[$cacheKey] }

    $user = Get-HybridUser -Identity $Identity

    $manager = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('GetManager','GetUserManager') -Arguments @($Identity) | Select-Object -First 1)
    if ($manager.Count -gt 0) {
        $user.ManagerDisplayName = [string](Get-HybridObjectValue -InputObject $manager[0] -Names @('DisplayName','Name') -Default $user.Manager)
    }
    elseif ($null -ne $user.Manager) {
        $user.ManagerDisplayName = [string]$user.Manager
    }

    $groups = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('GetGroups','GetUserGroups','GetGroupMembership') -Arguments @($Identity))
    $directReports = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('GetDirectReports','GetUserDirectReports') -Arguments @($Identity))

    $user.Groups = @($groups)
    $user.DirectReports = @($directReports)
    $user.DetailsLoaded = $true

    $script:HybridUserServiceState.DetailCache[$cacheKey] = $user
    return $user
}

function Get-HybridUserServiceHealth {
    [CmdletBinding()]
    param()

    $providerHealth = @{
        ActiveDirectory = Get-HybridProviderHealth -Name 'ActiveDirectory' -Provider $script:HybridUserServiceState.ActiveDirectory
        MicrosoftGraph  = Get-HybridProviderHealth -Name 'MicrosoftGraph' -Provider $script:HybridUserServiceState.MicrosoftGraph
        ExchangeOnline  = Get-HybridProviderHealth -Name 'ExchangeOnline' -Provider $script:HybridUserServiceState.ExchangeOnline
    }

    [pscustomobject]@{
        PSTypeName      = 'Hybrid.UserServiceHealth'
        Initialized     = [bool]$script:HybridUserServiceState.Initialized
        Providers       = @{
            ActiveDirectory = ($null -ne $script:HybridUserServiceState.ActiveDirectory)
            MicrosoftGraph  = ($null -ne $script:HybridUserServiceState.MicrosoftGraph)
            ExchangeOnline  = ($null -ne $script:HybridUserServiceState.ExchangeOnline)
        }
        ProviderHealth  = $providerHealth
        CacheEntries    = $script:HybridUserServiceState.Cache.Count
        DetailCacheEntries = $script:HybridUserServiceState.DetailCache.Count
        LastQuery       = $script:HybridUserServiceState.LastQuery
        LastError       = $script:HybridUserServiceState.LastError
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
    'Get-HybridUserServiceHealth',
    'Clear-HybridUserService'
)
