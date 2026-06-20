#region Module Information
# Name: Infrastructure.Mock
# Purpose: Offline mock infrastructure provider for development and testing.
# Dependencies: Core.ServiceRegistry, Hybrid.Models recommended.
# Exports: Initialize-HybridMockProvider, Search-HybridMockUser, Get-HybridMockUser, Get-HybridMockUserGroups, Get-HybridMockUserMailbox, Get-HybridMockUserDevices, Get-HybridMockUserLicenses
#endregion

Set-StrictMode -Version Latest

$script:State = @{
    Users     = @()
    Groups    = @{}
    Mailboxes = @{}
    Devices   = @{}
    Licenses  = @{}
}

#region Private
function New-MockHybridUserRecord {
    param(
        [string]$DisplayName,
        [string]$GivenName,
        [string]$Surname,
        [string]$SamAccountName,
        [string]$Department,
        [string]$Title,
        [string]$Manager,
        [string]$ManagerSam,
        [string]$EmployeeId,
        [string]$BadgeId,
        [bool]$Enabled = $true,
        [bool]$LockedOut = $false
    )

    $upn = '{0}@atlas-tech.com' -f $SamAccountName

    New-HybridUser `
        -Id ([guid]::NewGuid().ToString()) `
        -DisplayName $DisplayName `
        -GivenName $GivenName `
        -Surname $Surname `
        -SamAccountName $SamAccountName `
        -UserPrincipalName $upn `
        -Mail $upn `
        -Department $Department `
        -Title $Title `
        -Manager $Manager `
        -ManagerSamAccountName $ManagerSam `
        -EmployeeId $EmployeeId `
        -BadgeId $BadgeId `
        -Enabled $Enabled `
        -LockedOut $LockedOut `
        -Company 'Atlas Tech' `
        -Office 'Hybrid Admin Lab' `
        -Source 'Mock'
}

function Get-DefaultHybridMockData {
    $users = @(
        New-MockHybridUserRecord -DisplayName 'Alex Morgan' -GivenName 'Alex' -Surname 'Morgan' -SamAccountName 'amorgan' -Department 'Information Technology' -Title 'Systems Administrator' -Manager 'Morgan Rivera' -ManagerSam 'mrivera' -EmployeeId '10001' -BadgeId 'A1001'
        New-MockHybridUserRecord -DisplayName 'Jordan Lee' -GivenName 'Jordan' -Surname 'Lee' -SamAccountName 'jlee' -Department 'Operations' -Title 'Project Manager' -Manager 'Morgan Rivera' -ManagerSam 'mrivera' -EmployeeId '10002' -BadgeId 'A1002'
        New-MockHybridUserRecord -DisplayName 'Taylor Smith' -GivenName 'Taylor' -Surname 'Smith' -SamAccountName 'tsmith' -Department 'Security' -Title 'Security Analyst' -Manager 'Alex Morgan' -ManagerSam 'amorgan' -EmployeeId '10003' -BadgeId 'A1003'
        New-MockHybridUserRecord -DisplayName 'Morgan Rivera' -GivenName 'Morgan' -Surname 'Rivera' -SamAccountName 'mrivera' -Department 'Information Technology' -Title 'IT Manager' -Manager 'Casey Director' -ManagerSam 'cdirector' -EmployeeId '10004' -BadgeId 'A1004'
        New-MockHybridUserRecord -DisplayName 'Disabled Sample' -GivenName 'Disabled' -Surname 'Sample' -SamAccountName 'dsample' -Department 'Former Employees' -Title 'Former User' -Manager 'Morgan Rivera' -ManagerSam 'mrivera' -EmployeeId '19999' -BadgeId 'A9999' -Enabled:$false
    )

    $groups = @{
        amorgan = @(
            New-HybridGroup -Name 'Domain Users' -SamAccountName 'Domain Users' -Type 'Security' -Scope 'Global' -IsDefault:$true -Source 'Mock'
            New-HybridGroup -Name 'IT Admins' -SamAccountName 'IT Admins' -Type 'Security' -Scope 'Global' -Source 'Mock'
            New-HybridGroup -Name 'VPN Users' -SamAccountName 'VPN Users' -Type 'Security' -Scope 'Global' -Source 'Mock'
            New-HybridGroup -Name 'M365 E5 License Assignment' -SamAccountName 'M365 E5 License Assignment' -Type 'Security' -Scope 'Universal' -Source 'Mock'
        )
        jlee = @(
            New-HybridGroup -Name 'Domain Users' -SamAccountName 'Domain Users' -Type 'Security' -Scope 'Global' -IsDefault:$true -Source 'Mock'
            New-HybridGroup -Name 'Operations Staff' -SamAccountName 'Operations Staff' -Type 'Security' -Scope 'Global' -Source 'Mock'
            New-HybridGroup -Name 'Project Managers' -SamAccountName 'Project Managers' -Type 'Distribution' -Scope 'Universal' -Source 'Mock'
        )
        tsmith = @(
            New-HybridGroup -Name 'Domain Users' -SamAccountName 'Domain Users' -Type 'Security' -Scope 'Global' -IsDefault:$true -Source 'Mock'
            New-HybridGroup -Name 'Security Team' -SamAccountName 'Security Team' -Type 'Security' -Scope 'Global' -Source 'Mock'
            New-HybridGroup -Name 'Privileged Access Workstations' -SamAccountName 'Privileged Access Workstations' -Type 'Security' -Scope 'Global' -Source 'Mock'
        )
        mrivera = @(
            New-HybridGroup -Name 'Domain Users' -SamAccountName 'Domain Users' -Type 'Security' -Scope 'Global' -IsDefault:$true -Source 'Mock'
            New-HybridGroup -Name 'IT Managers' -SamAccountName 'IT Managers' -Type 'Security' -Scope 'Global' -Source 'Mock'
        )
        dsample = @(
            New-HybridGroup -Name 'Domain Users' -SamAccountName 'Domain Users' -Type 'Security' -Scope 'Global' -IsDefault:$true -Source 'Mock'
        )
    }

    $mailboxes = @{
        amorgan = New-HybridMailbox -Identity 'amorgan' -PrimarySmtpAddress 'amorgan@atlas-tech.com' -RecipientType 'UserMailbox' -Aliases @('alex.morgan@atlas-tech.com') -FullAccess @('IT Admins') -Source 'Mock'
        jlee = New-HybridMailbox -Identity 'jlee' -PrimarySmtpAddress 'jlee@atlas-tech.com' -RecipientType 'UserMailbox' -Aliases @('jordan.lee@atlas-tech.com') -Source 'Mock'
        tsmith = New-HybridMailbox -Identity 'tsmith' -PrimarySmtpAddress 'tsmith@atlas-tech.com' -RecipientType 'UserMailbox' -Aliases @('taylor.smith@atlas-tech.com') -Source 'Mock'
        mrivera = New-HybridMailbox -Identity 'mrivera' -PrimarySmtpAddress 'mrivera@atlas-tech.com' -RecipientType 'UserMailbox' -Aliases @('morgan.rivera@atlas-tech.com') -Source 'Mock'
        dsample = New-HybridMailbox -Identity 'dsample' -PrimarySmtpAddress 'dsample@atlas-tech.com' -RecipientType 'UserMailbox' -HiddenFromAddressLists:$true -Exists:$true -Source 'Mock'
    }

    $devices = @{
        amorgan = @(
            New-HybridDevice -Id 'mock-device-001' -Name 'GOV-100-ADMIN' -OperatingSystem 'Windows 11 Enterprise' -ComplianceState 'Compliant' -PrimaryUser 'amorgan@atlas-tech.com' -LastCheckInUtc ([datetime]::UtcNow.AddHours(-2)) -Source 'Mock'
        )
        jlee = @(
            New-HybridDevice -Id 'mock-device-002' -Name 'GOV-101-PM' -OperatingSystem 'Windows 11 Enterprise' -ComplianceState 'Compliant' -PrimaryUser 'jlee@atlas-tech.com' -LastCheckInUtc ([datetime]::UtcNow.AddHours(-5)) -Source 'Mock'
        )
        tsmith = @(
            New-HybridDevice -Id 'mock-device-003' -Name 'GOV-102-SEC' -OperatingSystem 'Windows 11 Enterprise' -ComplianceState 'NonCompliant' -PrimaryUser 'tsmith@atlas-tech.com' -LastCheckInUtc ([datetime]::UtcNow.AddDays(-3)) -Source 'Mock'
        )
        mrivera = @()
        dsample = @()
    }

    $licenses = @{
        amorgan = @(
            New-HybridLicense -SkuId 'mock-e5' -SkuPartNumber 'SPE_E5' -DisplayName 'Microsoft 365 E5' -AssignmentSource 'Group' -AssignedByGroup 'M365 E5 License Assignment' -Source 'Mock'
        )
        jlee = @(
            New-HybridLicense -SkuId 'mock-e3' -SkuPartNumber 'SPE_E3' -DisplayName 'Microsoft 365 E3' -AssignmentSource 'Group' -AssignedByGroup 'Operations Staff' -Source 'Mock'
        )
        tsmith = @(
            New-HybridLicense -SkuId 'mock-e5' -SkuPartNumber 'SPE_E5' -DisplayName 'Microsoft 365 E5' -AssignmentSource 'Direct' -Source 'Mock'
        )
        mrivera = @(
            New-HybridLicense -SkuId 'mock-e5' -SkuPartNumber 'SPE_E5' -DisplayName 'Microsoft 365 E5' -AssignmentSource 'Group' -AssignedByGroup 'IT Managers' -Source 'Mock'
        )
        dsample = @()
    }

    [pscustomobject]@{
        Users     = $users
        Groups    = $groups
        Mailboxes = $mailboxes
        Devices   = $devices
        Licenses  = $licenses
    }
}

function Resolve-HybridMockSamAccountName {
    param([Parameter(Mandatory=$true)][string]$Identity)

    $user = Get-HybridMockUser -Identity $Identity
    if ($null -eq $user) { return $null }
    return $user.SamAccountName
}

function Add-HybridMockUserHydration {
    param([Parameter(Mandatory=$true)][object]$User)

    $sam = $User.SamAccountName
    $User.Groups = @(Get-HybridMockUserGroups -Identity $sam)
    $User.Mailbox = Get-HybridMockUserMailbox -Identity $sam
    $User.Devices = @(Get-HybridMockUserDevices -Identity $sam)
    $User.Licenses = @(Get-HybridMockUserLicenses -Identity $sam)
    return $User
}
#endregion

#region Public
function Initialize-HybridMockProvider {
    <#.SYNOPSIS Registers mock services for offline development.#>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Context)

    $data = Get-DefaultHybridMockData
    $script:State.Users = @($data.Users)
    $script:State.Groups = $data.Groups
    $script:State.Mailboxes = $data.Mailboxes
    $script:State.Devices = $data.Devices
    $script:State.Licenses = $data.Licenses

    $directoryService = [pscustomobject]@{
        PSTypeName = 'Hybrid.MockDirectoryService'
        SearchUser = {
            param([string]$Query, [switch]$IncludeRelated)
            Search-HybridMockUser -Query $Query -IncludeRelated:$IncludeRelated
        }
        GetUser = {
            param([string]$Identity, [switch]$IncludeRelated)
            Get-HybridMockUser -Identity $Identity -IncludeRelated:$IncludeRelated
        }
        GetUserGroups = {
            param([string]$Identity)
            Get-HybridMockUserGroups -Identity $Identity
        }
        GetUserMailbox = {
            param([string]$Identity)
            Get-HybridMockUserMailbox -Identity $Identity
        }
        GetUserDevices = {
            param([string]$Identity)
            Get-HybridMockUserDevices -Identity $Identity
        }
        GetUserLicenses = {
            param([string]$Identity)
            Get-HybridMockUserLicenses -Identity $Identity
        }
    }

    if (Get-Command Register-HybridService -ErrorAction SilentlyContinue) {
        Register-HybridService -Name 'Directory' -Instance $directoryService -Description 'Mock directory service for offline development.' -Provider 'Mock' -Force | Out-Null
    }

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        Write-HybridLog -Level Information -Module 'Infrastructure.Mock' -Message 'Mock provider initialized.' | Out-Null
    }

    return $directoryService
}

function Search-HybridMockUser {
    <#.SYNOPSIS Searches mock users.#>
    [CmdletBinding()]
    param(
        [string]$Query='',
        [switch]$IncludeRelated
    )

    $results = @()

    if ([string]::IsNullOrWhiteSpace($Query)) {
        $results = @($script:State.Users)
    }
    else {
        $results = @($script:State.Users | Where-Object {
            $_.DisplayName -like "*$Query*" -or
            $_.SamAccountName -like "*$Query*" -or
            $_.UserPrincipalName -like "*$Query*" -or
            $_.Mail -like "*$Query*" -or
            $_.Department -like "*$Query*" -or
            $_.EmployeeId -like "*$Query*" -or
            $_.BadgeId -like "*$Query*"
        })
    }

    if ($IncludeRelated) {
        return @($results | ForEach-Object { Add-HybridMockUserHydration -User $_ })
    }

    return @($results)
}

function Get-HybridMockUser {
    <#.SYNOPSIS Gets one mock user by identity.#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [switch]$IncludeRelated
    )

    $user = ($script:State.Users | Where-Object {
        $_.SamAccountName -eq $Identity -or
        $_.UserPrincipalName -eq $Identity -or
        $_.Mail -eq $Identity -or
        $_.DisplayName -eq $Identity -or
        $_.EmployeeId -eq $Identity -or
        $_.BadgeId -eq $Identity
    } | Select-Object -First 1)

    if ($null -ne $user -and $IncludeRelated) {
        return Add-HybridMockUserHydration -User $user
    }

    return $user
}

function Get-HybridMockUserGroups {
    <#.SYNOPSIS Gets mock group memberships for a user.#>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $sam = Resolve-HybridMockSamAccountName -Identity $Identity
    if ([string]::IsNullOrWhiteSpace($sam)) { return @() }
    if (-not $script:State.Groups.ContainsKey($sam)) { return @() }
    return @($script:State.Groups[$sam])
}

function Get-HybridMockUserMailbox {
    <#.SYNOPSIS Gets a mock mailbox for a user.#>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $sam = Resolve-HybridMockSamAccountName -Identity $Identity
    if ([string]::IsNullOrWhiteSpace($sam)) { return $null }
    if (-not $script:State.Mailboxes.ContainsKey($sam)) { return $null }
    return $script:State.Mailboxes[$sam]
}

function Get-HybridMockUserDevices {
    <#.SYNOPSIS Gets mock devices for a user.#>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $sam = Resolve-HybridMockSamAccountName -Identity $Identity
    if ([string]::IsNullOrWhiteSpace($sam)) { return @() }
    if (-not $script:State.Devices.ContainsKey($sam)) { return @() }
    return @($script:State.Devices[$sam])
}

function Get-HybridMockUserLicenses {
    <#.SYNOPSIS Gets mock license assignments for a user.#>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $sam = Resolve-HybridMockSamAccountName -Identity $Identity
    if ([string]::IsNullOrWhiteSpace($sam)) { return @() }
    if (-not $script:State.Licenses.ContainsKey($sam)) { return @() }
    return @($script:State.Licenses[$sam])
}
#endregion

#region Initialization
Export-ModuleMember -Function @(
    'Initialize-HybridMockProvider',
    'Search-HybridMockUser',
    'Get-HybridMockUser',
    'Get-HybridMockUserGroups',
    'Get-HybridMockUserMailbox',
    'Get-HybridMockUserDevices',
    'Get-HybridMockUserLicenses'
)
#endregion
