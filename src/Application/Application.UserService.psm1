#region Module Information
# Name: Application.UserService
# Purpose: Provider-agnostic user service API for the Hybrid Administration Platform.
# Dependencies: Core.ServiceRegistry, Hybrid.Models, a registered Directory service.
# Exports: Initialize-HybridUserService, Search-HybridUser, Get-HybridUser, Get-HybridUserOverview, Get-HybridUserGroups, Get-HybridUserMailbox, Get-HybridUserDevices, Get-HybridUserLicenses
#endregion

Set-StrictMode -Version Latest

$script:State = @{
    Initialized = $false
}

#region Private
function Get-HybridDirectoryServiceOrThrow {
    $service = Get-HybridService -Name 'Directory'

    if ($null -eq $service) {
        throw 'Directory service is not registered. Initialize application services before using the user service.'
    }

    return $service
}

function Invoke-HybridServiceScriptBlock {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock,
        [object[]]$Arguments = @()
    )

    return & $ScriptBlock @Arguments
}

function Write-HybridUserServiceLog {
    param(
        [string]$Level = 'Information',
        [string]$Message,
        $Exception
    )

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        if ($PSBoundParameters.ContainsKey('Exception')) {
            Write-HybridLog -Level $Level -Module 'Application.UserService' -Message $Message -Exception $Exception | Out-Null
        }
        else {
            Write-HybridLog -Level $Level -Module 'Application.UserService' -Message $Message | Out-Null
        }
    }
}
#endregion

#region Public
function Initialize-HybridUserService {
    <#
    .SYNOPSIS
    Registers the provider-agnostic user service.

    .DESCRIPTION
    The user service is the application-facing API for user reads. It delegates actual data access to the currently registered Directory service, allowing the same UI/workflow code to use Mock, Active Directory, Graph, or future providers without changing the caller.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Context
    )

    $userService = [pscustomobject]@{
        PSTypeName  = 'Hybrid.UserService'
        SearchUser  = { param([string]$Query, [switch]$IncludeRelated) Search-HybridUser -Query $Query -IncludeRelated:$IncludeRelated }
        GetUser     = { param([string]$Identity, [switch]$IncludeRelated) Get-HybridUser -Identity $Identity -IncludeRelated:$IncludeRelated }
        GetOverview = { param([string]$Identity) Get-HybridUserOverview -Identity $Identity }
        GetGroups   = { param([string]$Identity) Get-HybridUserGroups -Identity $Identity }
        GetMailbox  = { param([string]$Identity) Get-HybridUserMailbox -Identity $Identity }
        GetDevices  = { param([string]$Identity) Get-HybridUserDevices -Identity $Identity }
        GetLicenses = { param([string]$Identity) Get-HybridUserLicenses -Identity $Identity }
    }

    Register-HybridService -Name 'User' -Instance $userService -Description 'Provider-agnostic user application service.' -Provider 'Application' -Force | Out-Null

    $script:State.Initialized = $true
    Write-HybridUserServiceLog -Level Information -Message 'User service initialized.'

    return $userService
}

function Search-HybridUser {
    <#
    .SYNOPSIS
    Searches users through the registered Directory provider.

    .PARAMETER Query
    Name, SAM account name, UPN, email, department, employee ID, badge ID, or provider-supported search text.

    .PARAMETER IncludeRelated
    Requests group, mailbox, device, and license data when the provider supports it.
    #>
    [CmdletBinding()]
    param(
        [string]$Query = '',
        [switch]$IncludeRelated
    )

    try {
        $directory = Get-HybridDirectoryServiceOrThrow

        if ($null -eq $directory.SearchUser) {
            throw 'Directory service does not implement SearchUser.'
        }

        return @(Invoke-HybridServiceScriptBlock -ScriptBlock $directory.SearchUser -Arguments @($Query, $IncludeRelated))
    }
    catch {
        Write-HybridUserServiceLog -Level Error -Message "User search failed for query '$Query'." -Exception $_
        throw
    }
}

function New-HybridHydratedUserCopy {
    param([Parameter(Mandatory=$true)][object]$User)

    $groups = @(Get-HybridUserGroups -Identity $User.SamAccountName)
    $mailbox = Get-HybridUserMailbox -Identity $User.SamAccountName
    $devices = @(Get-HybridUserDevices -Identity $User.SamAccountName)
    $licenses = @(Get-HybridUserLicenses -Identity $User.SamAccountName)

    return New-HybridUser `
        -Id $User.Id `
        -DisplayName $User.DisplayName `
        -GivenName $User.GivenName `
        -Surname $User.Surname `
        -SamAccountName $User.SamAccountName `
        -UserPrincipalName $User.UserPrincipalName `
        -Mail $User.Mail `
        -EmployeeId $User.EmployeeId `
        -BadgeId $User.BadgeId `
        -Department $User.Department `
        -Title $User.Title `
        -Company $User.Company `
        -Office $User.Office `
        -Manager $User.Manager `
        -ManagerSamAccountName $User.ManagerSamAccountName `
        -Enabled $User.Enabled `
        -LockedOut $User.LockedOut `
        -Source $User.Source `
        -Groups $groups `
        -Mailbox $mailbox `
        -Devices $devices `
        -Licenses $licenses `
        -Hydration @{
            Groups   = $true
            Mailbox  = ($null -ne $mailbox)
            Devices  = $true
            Licenses = $true
        } `
        -Attributes $User.Attributes
}

function Get-HybridUser {
    <#
    .SYNOPSIS
    Gets one user by identity through the registered Directory provider.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Identity,
        [switch]$IncludeRelated
    )

    try {
        $directory = Get-HybridDirectoryServiceOrThrow

        if ($null -eq $directory.GetUser) {
            throw 'Directory service does not implement GetUser.'
        }

        # Always fetch the base user first. When IncludeRelated is requested,
        # hydrate through the explicit provider contracts below instead of relying
        # on positional switch forwarding through nested scriptblocks. This keeps
        # Milestone 3 behavior stable across mock, AD, Graph, and future providers.
        $user = Invoke-HybridServiceScriptBlock -ScriptBlock $directory.GetUser -Arguments @($Identity, $false)

        if ($null -eq $user) {
            return $null
        }

        if ($IncludeRelated) {
            return New-HybridHydratedUserCopy -User $user
        }

        return $user
    }
    catch {
        Write-HybridUserServiceLog -Level Error -Message "Get user failed for identity '$Identity'." -Exception $_
        throw
    }
}

function Get-HybridUserOverview {
    <#
    .SYNOPSIS
    Gets a card-ready overview for one fully hydrated user.

    .DESCRIPTION
    This application-layer composition keeps UI rendering separate from infrastructure reads while giving the UI a stable overview model.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Identity
    )

    try {
        $user = Get-HybridUser -Identity $Identity -IncludeRelated

        if ($null -eq $user) {
            return $null
        }

        return New-HybridUserOverview -User $user -Metadata @{
            IdentityRequested = $Identity
            Source            = $user.Source
            HydratedUtc       = [datetime]::UtcNow
        }
    }
    catch {
        Write-HybridUserServiceLog -Level Error -Message "Get user overview failed for identity '$Identity'." -Exception $_
        throw
    }
}

function Get-HybridUserGroups {
    <#
    .SYNOPSIS
    Gets group memberships for one user.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $directory = Get-HybridDirectoryServiceOrThrow
    if ($null -eq $directory.GetUserGroups) { return @() }

    return @(Invoke-HybridServiceScriptBlock -ScriptBlock $directory.GetUserGroups -Arguments @($Identity))
}

function Get-HybridUserMailbox {
    <#
    .SYNOPSIS
    Gets mailbox details for one user.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $directory = Get-HybridDirectoryServiceOrThrow
    if ($null -eq $directory.GetUserMailbox) { return $null }

    return Invoke-HybridServiceScriptBlock -ScriptBlock $directory.GetUserMailbox -Arguments @($Identity)
}

function Get-HybridUserDevices {
    <#
    .SYNOPSIS
    Gets devices associated with one user.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $directory = Get-HybridDirectoryServiceOrThrow
    if ($null -eq $directory.GetUserDevices) { return @() }

    return @(Invoke-HybridServiceScriptBlock -ScriptBlock $directory.GetUserDevices -Arguments @($Identity))
}

function Get-HybridUserLicenses {
    <#
    .SYNOPSIS
    Gets license assignments for one user.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $directory = Get-HybridDirectoryServiceOrThrow
    if ($null -eq $directory.GetUserLicenses) { return @() }

    return @(Invoke-HybridServiceScriptBlock -ScriptBlock $directory.GetUserLicenses -Arguments @($Identity))
}
#endregion

#region Initialization
Export-ModuleMember -Function @(
    'Initialize-HybridUserService',
    'Search-HybridUser',
    'Get-HybridUser',
    'Get-HybridUserOverview',
    'Get-HybridUserGroups',
    'Get-HybridUserMailbox',
    'Get-HybridUserDevices',
    'Get-HybridUserLicenses'
)
#endregion
