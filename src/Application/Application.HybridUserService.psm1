#region Module Information
# Name: Application.HybridUserService
# Purpose: First vertical-slice service layer for unified Hybrid.User search.
# Dependencies: Provider services supplied by caller.
# Exports: Initialize-HybridUserService, Search-HybridUser, Get-HybridUser, Get-HybridUserServiceHealth, Clear-HybridUserService
#endregion

Set-StrictMode -Version Latest

$script:HybridUserServiceState = @{
    Initialized      = $false
    ActiveDirectory = $null
    MicrosoftGraph  = $null
    ExchangeOnline  = $null
    Cache           = @{}
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

    if ($null -eq $Service) {
        return @()
    }

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

function ConvertTo-HybridSourceStatus {
    [CmdletBinding()]
    param(
        [string]$Name,
        [AllowNull()][object]$Object
    )

    [pscustomobject]@{
        PSTypeName = 'Hybrid.UserSourceStatus'
        Name       = $Name
        Available  = ($null -ne $Object)
        Object     = $Object
    }
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
    if ($null -eq $displayName) {
        $displayName = Get-HybridObjectValue -InputObject $GraphUser -Names @('DisplayName','Name') -Default $Identity
    }

    $upn = Get-HybridObjectValue -InputObject $GraphUser -Names @('UserPrincipalName','UPN') -Default $null
    if ($null -eq $upn) {
        $upn = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('UserPrincipalName','UPN') -Default $Identity
    }

    $mail = Get-HybridObjectValue -InputObject $Mailbox -Names @('PrimarySmtpAddress','Mail','EmailAddress') -Default $null
    if ($null -eq $mail) {
        $mail = Get-HybridObjectValue -InputObject $GraphUser -Names @('Mail','EmailAddress') -Default $null
    }
    if ($null -eq $mail) {
        $mail = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Mail','EmailAddress') -Default $null
    }

    $user = [pscustomobject]@{
        PSTypeName          = 'Hybrid.User'
        Identity            = $Identity
        DisplayName         = [string]$displayName
        UserPrincipalName   = [string]$upn
        SamAccountName      = [string](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('SamAccountName','SAMAccountName') -Default '')
        Mail                = [string]$mail
        Department          = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('Department') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Department') -Default ''))
        Title               = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('JobTitle','Title') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Title') -Default ''))
        Manager             = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Manager') -Default $null
        Mailbox             = $Mailbox
        Sources             = @(
            ConvertTo-HybridSourceStatus -Name 'ActiveDirectory' -Object $ActiveDirectoryUser
            ConvertTo-HybridSourceStatus -Name 'MicrosoftGraph' -Object $GraphUser
            ConvertTo-HybridSourceStatus -Name 'ExchangeOnline' -Object $Mailbox
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

    [pscustomobject]@{
        PSTypeName = 'Hybrid.UserService'
        Name       = 'HybridUserService'
        Initialized = $true
        Providers  = @{
            ActiveDirectory = ($null -ne $ActiveDirectoryProvider)
            MicrosoftGraph  = ($null -ne $MicrosoftGraphProvider)
            ExchangeOnline  = ($null -ne $ExchangeOnlineProvider)
        }
        SearchUser = ({ param([string]$Query) Search-HybridUser -Query $Query }).GetNewClosure()
        GetUser    = ({ param([string]$Identity) Get-HybridUser -Identity $Identity }).GetNewClosure()
        GetHealth  = ({ Get-HybridUserServiceHealth }).GetNewClosure()
    }
}

function Search-HybridUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Query
    )

    if (-not $script:HybridUserServiceState.Initialized) {
        throw 'Hybrid user service has not been initialized.'
    }

    if ([string]::IsNullOrWhiteSpace($Query)) {
        throw 'Search query cannot be empty.'
    }

    try {
        $script:HybridUserServiceState.LastQuery = $Query

        $adUsers = Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('SearchUser','SearchADUser','Search') -Arguments @($Query)
        $graphUsers = Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.MicrosoftGraph -OperationNames @('SearchUser','SearchGraphUser','Search') -Arguments @($Query)

        $primary = @($graphUsers | Select-Object -First 1)
        if ($primary.Count -eq 0) {
            $primary = @($adUsers | Select-Object -First 1)
        }

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
    param(
        [Parameter(Mandatory=$true)][string]$Identity
    )

    if (-not $script:HybridUserServiceState.Initialized) {
        throw 'Hybrid user service has not been initialized.'
    }

    if ([string]::IsNullOrWhiteSpace($Identity)) {
        throw 'User identity cannot be empty.'
    }

    $cacheKey = $Identity.ToLowerInvariant()
    if ($script:HybridUserServiceState.Cache.ContainsKey($cacheKey)) {
        return $script:HybridUserServiceState.Cache[$cacheKey]
    }

    $adUser = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('GetUser','GetADUser','Get') -Arguments @($Identity) | Select-Object -First 1)
    $graphUser = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.MicrosoftGraph -OperationNames @('GetUser','GetGraphUser','Get') -Arguments @($Identity) | Select-Object -First 1)
    $mailbox = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetMailbox','GetUserMailbox','Get') -Arguments @($Identity) | Select-Object -First 1)

    $user = New-HybridCompositeUser `
        -Identity $Identity `
        -ActiveDirectoryUser ($adUser | Select-Object -First 1) `
        -GraphUser ($graphUser | Select-Object -First 1) `
        -Mailbox ($mailbox | Select-Object -First 1)

    $script:HybridUserServiceState.Cache[$cacheKey] = $user
    return $user
}

function Get-HybridUserServiceHealth {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        PSTypeName   = 'Hybrid.UserServiceHealth'
        Initialized  = [bool]$script:HybridUserServiceState.Initialized
        Providers    = @{
            ActiveDirectory = ($null -ne $script:HybridUserServiceState.ActiveDirectory)
            MicrosoftGraph  = ($null -ne $script:HybridUserServiceState.MicrosoftGraph)
            ExchangeOnline  = ($null -ne $script:HybridUserServiceState.ExchangeOnline)
        }
        CacheEntries = $script:HybridUserServiceState.Cache.Count
        LastQuery    = $script:HybridUserServiceState.LastQuery
        LastError    = $script:HybridUserServiceState.LastError
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
    $script:HybridUserServiceState.LastQuery = $null
    $script:HybridUserServiceState.LastResult = $null
    $script:HybridUserServiceState.LastError = $null
    return $true
}

Export-ModuleMember -Function @(
    'Initialize-HybridUserService',
    'Search-HybridUser',
    'Get-HybridUser',
    'Get-HybridUserServiceHealth',
    'Clear-HybridUserService'
)
