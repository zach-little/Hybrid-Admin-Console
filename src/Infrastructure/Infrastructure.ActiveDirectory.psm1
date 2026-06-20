#region Module Information
# Name: Infrastructure.ActiveDirectory
# Purpose: Active Directory provider for the Hybrid Administration Platform.
# Dependencies: Core.ServiceRegistry, Hybrid.Models, ActiveDirectory PowerShell module at runtime.
# Exports: Initialize-HybridActiveDirectoryProvider, Test-HybridActiveDirectoryProviderAvailable,
#          Search-HybridADUser, Get-HybridADUser, Get-HybridADUserGroups,
#          Get-HybridADUserManager, Get-HybridADUserDirectReports,
#          Reset-HybridADUserPassword, Set-HybridADUserEnabled,
#          Unlock-HybridADUser, Move-HybridADUserOU, ConvertTo-HybridADUser
#endregion

Set-StrictMode -Version Latest

$script:State = @{
    Initialized       = $false
    Registered        = $false
    DomainController  = ''
    SearchBase        = ''
    Credential        = $null
    ProviderAvailable = $false
}

#region Private helpers
function Write-HybridADLog {
    param(
        [string]$Level = 'Information',
        [string]$Message,
        $Exception
    )

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        if ($PSBoundParameters.ContainsKey('Exception')) {
            Write-HybridLog -Level $Level -Module 'Infrastructure.ActiveDirectory' -Message $Message -Exception $Exception | Out-Null
        }
        else {
            Write-HybridLog -Level $Level -Module 'Infrastructure.ActiveDirectory' -Message $Message | Out-Null
        }
    }
}

function Test-HybridADCommand {
    param([Parameter(Mandatory=$true)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Import-HybridActiveDirectoryModule {
    if (Get-Module -Name ActiveDirectory) { return $true }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    }
    catch {
        Write-HybridADLog -Level Warning -Message 'ActiveDirectory module is not available.' -Exception $_
        return $false
    }
}

function New-HybridADCommonParameters {
    $parameters = @{}

    if (-not [string]::IsNullOrWhiteSpace($script:State.DomainController)) {
        $parameters.Server = $script:State.DomainController
    }

    if ($null -ne $script:State.Credential) {
        $parameters.Credential = $script:State.Credential
    }

    return $parameters
}

function Get-HybridADDefaultUserProperties {
    return @(
        'mail',
        'department',
        'title',
        'company',
        'physicalDeliveryOfficeName',
        'manager',
        'employeeID',
        'employeeNumber',
        'extensionAttribute1',
        'directReports',
        'lockedOut',
        'enabled',
        'distinguishedName',
        'objectGUID'
    )
}

function Resolve-HybridADIdentityFilter {
    param([Parameter(Mandatory=$true)][string]$Identity)

    $escaped = $Identity.Replace("'", "''")
    return "SamAccountName -eq '$escaped' -or UserPrincipalName -eq '$escaped' -or mail -eq '$escaped' -or employeeID -eq '$escaped' -or Name -eq '$escaped'"
}

function Assert-HybridADProviderAvailable {
    if (-not $script:State.ProviderAvailable) {
        throw 'Active Directory provider is not available. Install RSAT Active Directory tools or initialize without -NoNet on a domain-joined/admin workstation.'
    }
}

function ConvertTo-HybridArrayValue {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [array]) { return @($Value) }
    return @($Value)
}
#endregion

#region Public provider lifecycle
function Test-HybridActiveDirectoryProviderAvailable {
    <#
    .SYNOPSIS
    Returns true when the ActiveDirectory PowerShell module is available.
    #>
    [CmdletBinding()]
    param()

    if (Get-Module -Name ActiveDirectory) { return $true }
    return $null -ne (Get-Module -ListAvailable -Name ActiveDirectory)
}

function Initialize-HybridActiveDirectoryProvider {
    <#
    .SYNOPSIS
    Initializes the Active Directory provider.

    .DESCRIPTION
    The provider is safe to import and initialize in offline development. Use -NoNet to avoid importing RSAT or touching the domain. Use -RegisterAsDirectory to replace the current Directory service with Active Directory when available.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Context,

        [string]$DomainController = '',
        [string]$SearchBase = '',
        [pscredential]$Credential = $null,
        [switch]$NoNet,
        [switch]$RegisterAsDirectory
    )

    $script:State.DomainController = $DomainController
    $script:State.SearchBase = $SearchBase
    $script:State.Credential = $Credential
    $script:State.ProviderAvailable = $false

    if (-not $NoNet) {
        $script:State.ProviderAvailable = Import-HybridActiveDirectoryModule
    }

    $directoryService = [pscustomobject]@{
        PSTypeName           = 'Hybrid.ActiveDirectoryService'
        ProviderName         = 'ActiveDirectory'
        ProviderAvailable    = $script:State.ProviderAvailable
        SearchUser           = { param([string]$Query, [switch]$IncludeRelated) Search-HybridADUser -Query $Query -IncludeRelated:$IncludeRelated }
        GetUser              = { param([string]$Identity, [switch]$IncludeRelated) Get-HybridADUser -Identity $Identity -IncludeRelated:$IncludeRelated }
        GetUserGroups        = { param([string]$Identity) Get-HybridADUserGroups -Identity $Identity }
        GetUserManager       = { param([string]$Identity) Get-HybridADUserManager -Identity $Identity }
        GetUserDirectReports = { param([string]$Identity) Get-HybridADUserDirectReports -Identity $Identity }
        ResetPassword        = { param([string]$Identity, [securestring]$NewPassword, [switch]$ChangeAtLogon) Reset-HybridADUserPassword -Identity $Identity -NewPassword $NewPassword -ChangeAtLogon:$ChangeAtLogon }
        SetEnabled           = { param([string]$Identity, [bool]$Enabled) Set-HybridADUserEnabled -Identity $Identity -Enabled $Enabled }
        UnlockUser           = { param([string]$Identity) Unlock-HybridADUser -Identity $Identity }
        MoveUserOU           = { param([string]$Identity, [string]$TargetPath) Move-HybridADUserOU -Identity $Identity -TargetPath $TargetPath }
        SetUserManager       = { param([string]$Identity, [string]$ManagerIdentity) Set-HybridADUserManager -Identity $Identity -ManagerIdentity $ManagerIdentity }
        AddUserToGroup       = { param([string]$Identity, [string]$GroupIdentity) Add-HybridADUserGroupMembership -Identity $Identity -GroupIdentity $GroupIdentity }
        RemoveUserFromGroup  = { param([string]$Identity, [string]$GroupIdentity) Remove-HybridADUserGroupMembership -Identity $Identity -GroupIdentity $GroupIdentity }
        SearchOU             = { param([string]$Query) Search-HybridADOrganizationalUnit -Query $Query }
    }

    if ($RegisterAsDirectory) {
        if (-not (Get-Command Register-HybridService -ErrorAction SilentlyContinue)) {
            throw 'Core.ServiceRegistry is required before registering the Active Directory provider.'
        }

        if (-not $script:State.ProviderAvailable -and -not $NoNet) {
            throw 'Active Directory provider cannot be registered because the ActiveDirectory module is unavailable.'
        }

        Register-HybridService -Name 'Directory' -Instance $directoryService -Description 'Active Directory directory service provider.' -Provider 'ActiveDirectory' -Force | Out-Null
        $script:State.Registered = $true
    }

    $script:State.Initialized = $true
    Write-HybridADLog -Level Information -Message 'Active Directory provider initialized.'
    return $directoryService
}
#endregion

#region Public mapping
function ConvertTo-HybridADUser {
    <#
    .SYNOPSIS
    Converts an AD user object into the canonical Hybrid.User model.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [object]$InputObject
    )

    process {
        $managerDn = ''
        if ($InputObject.PSObject.Properties.Name -contains 'Manager' -and $null -ne $InputObject.Manager) {
            $managerDn = [string]$InputObject.Manager
        }

        $employeeId = ''
        if ($InputObject.PSObject.Properties.Name -contains 'EmployeeID' -and $null -ne $InputObject.EmployeeID) {
            $employeeId = [string]$InputObject.EmployeeID
        }

        $badgeId = ''
        if ($InputObject.PSObject.Properties.Name -contains 'extensionAttribute1' -and $null -ne $InputObject.extensionAttribute1) {
            $badgeId = [string]$InputObject.extensionAttribute1
        }
        elseif ($InputObject.PSObject.Properties.Name -contains 'EmployeeNumber' -and $null -ne $InputObject.EmployeeNumber) {
            $badgeId = [string]$InputObject.EmployeeNumber
        }

        $objectId = ''
        if ($InputObject.PSObject.Properties.Name -contains 'ObjectGUID' -and $null -ne $InputObject.ObjectGUID) {
            $objectId = [string]$InputObject.ObjectGUID
        }

        $mail = ''
        if ($InputObject.PSObject.Properties.Name -contains 'Mail' -and $null -ne $InputObject.Mail) {
            $mail = [string]$InputObject.Mail
        }

        New-HybridUser `
            -Id $objectId `
            -DisplayName ([string]$InputObject.Name) `
            -GivenName ([string]$InputObject.GivenName) `
            -Surname ([string]$InputObject.Surname) `
            -SamAccountName ([string]$InputObject.SamAccountName) `
            -UserPrincipalName ([string]$InputObject.UserPrincipalName) `
            -Mail $mail `
            -EmployeeId $employeeId `
            -BadgeId $badgeId `
            -Department ([string]$InputObject.Department) `
            -Title ([string]$InputObject.Title) `
            -Company ([string]$InputObject.Company) `
            -Office ([string]$InputObject.physicalDeliveryOfficeName) `
            -Manager $managerDn `
            -ManagerSamAccountName '' `
            -Enabled ([bool]$InputObject.Enabled) `
            -LockedOut ([bool]$InputObject.LockedOut) `
            -Source 'ActiveDirectory' `
            -Attributes @{
                DistinguishedName = [string]$InputObject.DistinguishedName
                ManagerDn         = $managerDn
                DirectReportDns   = @(ConvertTo-HybridArrayValue $InputObject.DirectReports)
            }
    }
}
#endregion

#region Public reads
function Search-HybridADUser {
    [CmdletBinding()]
    param(
        [string]$Query = '',
        [switch]$IncludeRelated,
        [int]$ResultSetSize = 50
    )

    Assert-HybridADProviderAvailable

    $adParams = New-HybridADCommonParameters
    $adParams.Properties = Get-HybridADDefaultUserProperties
    $adParams.ResultSetSize = $ResultSetSize

    if (-not [string]::IsNullOrWhiteSpace($script:State.SearchBase)) {
        $adParams.SearchBase = $script:State.SearchBase
    }

    if ([string]::IsNullOrWhiteSpace($Query)) {
        $adParams.Filter = '*'
    }
    else {
        $escaped = $Query.Replace("'", "''")
        $adParams.Filter = "Name -like '*$escaped*' -or SamAccountName -like '*$escaped*' -or UserPrincipalName -like '*$escaped*' -or mail -like '*$escaped*' -or department -like '*$escaped*' -or employeeID -like '*$escaped*'"
    }

    $users = @(Get-ADUser @adParams | ForEach-Object { ConvertTo-HybridADUser -InputObject $_ })

    if ($IncludeRelated) {
        return @($users | ForEach-Object { Get-HybridADUser -Identity $_.SamAccountName -IncludeRelated })
    }

    return $users
}

function Get-HybridADUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Identity,
        [switch]$IncludeRelated
    )

    Assert-HybridADProviderAvailable

    $adParams = New-HybridADCommonParameters
    $adParams.Properties = Get-HybridADDefaultUserProperties
    $adParams.Filter = Resolve-HybridADIdentityFilter -Identity $Identity

    $adUser = Get-ADUser @adParams | Select-Object -First 1
    if ($null -eq $adUser) { return $null }

    $user = ConvertTo-HybridADUser -InputObject $adUser

    if ($IncludeRelated) {
        $user.Groups = @(Get-HybridADUserGroups -Identity $user.SamAccountName)
        $manager = Get-HybridADUserManager -Identity $user.SamAccountName
        if ($null -ne $manager) {
            $user.Manager = $manager.DisplayName
            $user.ManagerSamAccountName = $manager.SamAccountName
            $user.Attributes.Manager = $manager
        }
        $user.Attributes.DirectReports = @(Get-HybridADUserDirectReports -Identity $user.SamAccountName)
    }

    return $user
}

function Get-HybridADUserGroups {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    Assert-HybridADProviderAvailable

    $adParams = New-HybridADCommonParameters
    $adParams.Identity = $Identity

    return @(Get-ADPrincipalGroupMembership @adParams | ForEach-Object {
        New-HybridGroup `
            -Id ([string]$_.ObjectGUID) `
            -Name ([string]$_.Name) `
            -SamAccountName ([string]$_.SamAccountName) `
            -Type 'Security' `
            -Scope ([string]$_.GroupScope) `
            -IsDefault:($_.Name -eq 'Domain Users') `
            -Source 'ActiveDirectory' `
            -Attributes @{ DistinguishedName = [string]$_.DistinguishedName }
    })
}

function Get-HybridADUserManager {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    Assert-HybridADProviderAvailable

    $user = Get-HybridADUser -Identity $Identity
    if ($null -eq $user -or [string]::IsNullOrWhiteSpace($user.Attributes.ManagerDn)) { return $null }

    $adParams = New-HybridADCommonParameters
    $adParams.Identity = $user.Attributes.ManagerDn
    $adParams.Properties = Get-HybridADDefaultUserProperties

    $manager = Get-ADUser @adParams
    if ($null -eq $manager) { return $null }

    return ConvertTo-HybridADUser -InputObject $manager
}

function Get-HybridADUserDirectReports {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    Assert-HybridADProviderAvailable

    $user = Get-HybridADUser -Identity $Identity
    if ($null -eq $user) { return @() }

    $reportDns = @(ConvertTo-HybridArrayValue $user.Attributes.DirectReportDns)
    if ($reportDns.Count -eq 0) { return @() }

    $adParams = New-HybridADCommonParameters
    $adParams.Properties = Get-HybridADDefaultUserProperties

    return @($reportDns | ForEach-Object {
        $adParams.Identity = $_
        $report = Get-ADUser @adParams
        if ($null -ne $report) { ConvertTo-HybridADUser -InputObject $report }
    })
}
#endregion

#region Public write actions
function Reset-HybridADUserPassword {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][securestring]$NewPassword,
        [switch]$ChangeAtLogon
    )

    Assert-HybridADProviderAvailable

    if ($PSCmdlet.ShouldProcess($Identity, 'Reset Active Directory password')) {
        $adParams = New-HybridADCommonParameters
        Set-ADAccountPassword @adParams -Identity $Identity -Reset -NewPassword $NewPassword
        if ($ChangeAtLogon) {
            Set-ADUser @adParams -Identity $Identity -ChangePasswordAtLogon $true
        }
    }

    return New-HybridResult -Success $true -Message "Password reset completed for '$Identity'."
}

function Set-HybridADUserEnabled {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][bool]$Enabled
    )

    Assert-HybridADProviderAvailable

    if ($PSCmdlet.ShouldProcess($Identity, $(if ($Enabled) { 'Enable AD account' } else { 'Disable AD account' }))) {
        $adParams = New-HybridADCommonParameters
        if ($Enabled) { Enable-ADAccount @adParams -Identity $Identity }
        else { Disable-ADAccount @adParams -Identity $Identity }
    }

    return New-HybridResult -Success $true -Message "Enabled state set to '$Enabled' for '$Identity'."
}

function Unlock-HybridADUser {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory=$true)][string]$Identity)

    Assert-HybridADProviderAvailable

    if ($PSCmdlet.ShouldProcess($Identity, 'Unlock AD account')) {
        $adParams = New-HybridADCommonParameters
        Unlock-ADAccount @adParams -Identity $Identity
    }

    return New-HybridResult -Success $true -Message "Account unlocked for '$Identity'."
}


function Set-HybridADUserManager {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][string]$ManagerIdentity
    )

    Assert-HybridADProviderAvailable

    $adParams = New-HybridADCommonParameters
    if ($PSCmdlet.ShouldProcess($Identity, "Set AD manager to $ManagerIdentity")) {
        Set-ADUser @adParams -Identity $Identity -Manager $ManagerIdentity
    }

    return New-HybridResult -Success $true -Message "Manager for '$Identity' set to '$ManagerIdentity'."
}

function Add-HybridADUserGroupMembership {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][string]$GroupIdentity
    )

    Assert-HybridADProviderAvailable

    $adParams = New-HybridADCommonParameters
    if ($PSCmdlet.ShouldProcess($Identity, "Add to AD group $GroupIdentity")) {
        Add-ADGroupMember @adParams -Identity $GroupIdentity -Members $Identity
    }

    return New-HybridResult -Success $true -Message "User '$Identity' added to group '$GroupIdentity'."
}

function Remove-HybridADUserGroupMembership {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][string]$GroupIdentity
    )

    Assert-HybridADProviderAvailable

    $adParams = New-HybridADCommonParameters
    if ($PSCmdlet.ShouldProcess($Identity, "Remove from AD group $GroupIdentity")) {
        Remove-ADGroupMember @adParams -Identity $GroupIdentity -Members $Identity -Confirm:$false
    }

    return New-HybridResult -Success $true -Message "User '$Identity' removed from group '$GroupIdentity'."
}

function Search-HybridADOrganizationalUnit {
    [CmdletBinding()]
    param(
        [string]$Query = '',
        [int]$ResultSetSize = 100
    )

    Assert-HybridADProviderAvailable

    $adParams = New-HybridADCommonParameters
    $adParams.ResultSetSize = $ResultSetSize
    $adParams.Properties = @('description')

    if (-not [string]::IsNullOrWhiteSpace($script:State.SearchBase)) {
        $adParams.SearchBase = $script:State.SearchBase
    }

    if ([string]::IsNullOrWhiteSpace($Query)) {
        $adParams.Filter = '*'
    }
    else {
        $escaped = $Query.Replace("'", "''")
        $adParams.Filter = "Name -like '*$escaped*' -or DistinguishedName -like '*$escaped*'"
    }

    return @(Get-ADOrganizationalUnit @adParams | ForEach-Object {
        [pscustomobject]@{
            PSTypeName         = 'Hybrid.ActiveDirectoryOrganizationalUnit'
            Name               = [string]$_.Name
            DistinguishedName  = [string]$_.DistinguishedName
            Description        = [string]$_.Description
            Source             = 'ActiveDirectory'
        }
    })
}

function Move-HybridADUserOU {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][string]$TargetPath
    )

    Assert-HybridADProviderAvailable

    $adParams = New-HybridADCommonParameters
    $user = Get-ADUser @adParams -Identity $Identity -Properties distinguishedName
    if ($null -eq $user) { throw "AD user '$Identity' was not found." }

    if ($PSCmdlet.ShouldProcess($Identity, "Move AD object to $TargetPath")) {
        Move-ADObject @adParams -Identity $user.DistinguishedName -TargetPath $TargetPath
    }

    return New-HybridResult -Success $true -Message "User '$Identity' moved to '$TargetPath'."
}
#endregion

Export-ModuleMember -Function @(
    'Initialize-HybridActiveDirectoryProvider',
    'Test-HybridActiveDirectoryProviderAvailable',
    'Search-HybridADUser',
    'Get-HybridADUser',
    'Get-HybridADUserGroups',
    'Get-HybridADUserManager',
    'Get-HybridADUserDirectReports',
    'Reset-HybridADUserPassword',
    'Set-HybridADUserEnabled',
    'Unlock-HybridADUser',
    'Move-HybridADUserOU',
    'Set-HybridADUserManager',
    'Add-HybridADUserGroupMembership',
    'Remove-HybridADUserGroupMembership',
    'Search-HybridADOrganizationalUnit',
    'ConvertTo-HybridADUser'
)
