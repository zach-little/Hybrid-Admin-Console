#region Module Information
# Name: Application.UserAdministrationService
# Purpose: Command surface for selected-user administration workflows.
# Exports: Initialize-HybridUserAdministrationService, Get-HybridUserEditableSnapshot,
#          Set-HybridUserDirectoryAttributes, Set-HybridUserManager,
#          Move-HybridUserDirectReports, Set-HybridUserMailboxForwarding,
#          Set-HybridUserHiddenFromAddressLists, Get-HybridUserDistributionGroups,
#          Search-HybridUserDistributionGroups, Add-HybridUserMailboxDelegation,
#          Remove-HybridUserMailboxDelegation, Add-HybridUserDistributionGroupMembership,
#          Remove-HybridUserDistributionGroupMembership, Clear-HybridUserAdministrationService
#endregion

Set-StrictMode -Version Latest

$script:HybridUserAdministrationState = @{
    Initialized = $false
    ActiveDirectory = $null
    ExchangeOnline = $null
    MicrosoftGraph = $null
    LastError = $null
}

function New-HybridUserAdministrationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Action,
        [Parameter(Mandatory=$true)][string]$Identity,
        [ValidateSet('Completed','Unsupported','Failed')][string]$Status,
        [string]$Message = '',
        [AllowNull()][object]$Data = $null
    )

    [pscustomobject]@{
        PSTypeName = 'Hybrid.UserAdministrationResult'
        Action = $Action
        Identity = $Identity
        Status = $Status
        Message = $Message
        Data = $Data
        CompletedOn = [datetime]::UtcNow
    }
}

function Get-HybridUserAdminObjectValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory=$true)][string[]]$Names,
        [AllowNull()][object]$Default = $null
    )

    foreach ($name in $Names) {
        if ($null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains $name) {
            $value = $InputObject.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return $value }
        }
    }
    return $Default
}

function Invoke-HybridUserAdminProviderOperation {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Provider,
        [Parameter(Mandatory=$true)][string[]]$OperationNames,
        [object[]]$Arguments = @()
    )

    if ($null -eq $Provider) { return $null }

    $providerPropertyNames = @($Provider.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($operationName in $OperationNames) {
        if ($providerPropertyNames -contains $operationName) {
            $operation = $Provider.$operationName
            if ($operation -is [scriptblock]) { return & $operation @Arguments }
            if ($null -ne $operation -and $operation.PSObject.Methods.Name -contains 'Invoke') { return $operation.Invoke($Arguments) }
        }
    }

    return $null
}

function Test-HybridUserAdminProviderOperation {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Provider,
        [Parameter(Mandatory=$true)][string[]]$OperationNames
    )

    if ($null -eq $Provider) { return $false }
    $providerPropertyNames = @($Provider.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($operationName in $OperationNames) {
        if ($providerPropertyNames -contains $operationName) { return $true }
    }
    return $false
}

function Initialize-HybridUserAdministrationService {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$ActiveDirectoryProvider,
        [AllowNull()][object]$ExchangeOnlineProvider,
        [AllowNull()][object]$MicrosoftGraphProvider
    )

    $script:HybridUserAdministrationState.ActiveDirectory = $ActiveDirectoryProvider
    $script:HybridUserAdministrationState.ExchangeOnline = $ExchangeOnlineProvider
    $script:HybridUserAdministrationState.MicrosoftGraph = $MicrosoftGraphProvider
    $script:HybridUserAdministrationState.LastError = $null
    $script:HybridUserAdministrationState.Initialized = $true

    [pscustomobject]@{
        PSTypeName = 'Hybrid.UserAdministrationService'
        Name = 'UserAdministrationService'
        Initialized = $true
        ActiveDirectoryProvider = ($null -ne $ActiveDirectoryProvider)
        ExchangeOnlineProvider = ($null -ne $ExchangeOnlineProvider)
        MicrosoftGraphProvider = ($null -ne $MicrosoftGraphProvider)
        GetEditableSnapshot = ({ param([object]$User) Get-HybridUserEditableSnapshot -User $User }).GetNewClosure()
        SetDirectoryAttributes = ({ param([string]$Identity, [hashtable]$Attributes) Set-HybridUserDirectoryAttributes -Identity $Identity -Attributes $Attributes }).GetNewClosure()
        SetManager = ({ param([string]$Identity, [string]$ManagerIdentity) Set-HybridUserManager -Identity $Identity -ManagerIdentity $ManagerIdentity }).GetNewClosure()
        MoveDirectReports = ({ param([string]$Identity, [string]$NewManagerIdentity, [object[]]$DirectReports) Move-HybridUserDirectReports -Identity $Identity -NewManagerIdentity $NewManagerIdentity -DirectReports $DirectReports }).GetNewClosure()
        SetMailboxForwarding = ({ param([string]$Identity, [string]$ForwardingSmtpAddress, [bool]$DeliverToMailboxAndForward) Set-HybridUserMailboxForwarding -Identity $Identity -ForwardingSmtpAddress $ForwardingSmtpAddress -DeliverToMailboxAndForward $DeliverToMailboxAndForward }).GetNewClosure()
        SetHiddenFromAddressLists = ({ param([string]$Identity, [bool]$Hidden) Set-HybridUserHiddenFromAddressLists -Identity $Identity -Hidden $Hidden }).GetNewClosure()
        GetDistributionGroups = ({ param([string]$Identity) Get-HybridUserDistributionGroups -Identity $Identity }).GetNewClosure()
        SearchDistributionGroups = ({ param([string]$Query) Search-HybridUserDistributionGroups -Query $Query }).GetNewClosure()
        AddMailboxDelegation = ({ param([string]$Identity, [string]$Trustee, [string[]]$AccessRights) Add-HybridUserMailboxDelegation -Identity $Identity -Trustee $Trustee -AccessRights $AccessRights }).GetNewClosure()
        RemoveMailboxDelegation = ({ param([string]$Identity, [string]$Trustee, [string[]]$AccessRights) Remove-HybridUserMailboxDelegation -Identity $Identity -Trustee $Trustee -AccessRights $AccessRights }).GetNewClosure()
        AddDistributionGroupMembership = ({ param([string]$Identity, [string]$GroupIdentity) Add-HybridUserDistributionGroupMembership -Identity $Identity -GroupIdentity $GroupIdentity }).GetNewClosure()
        RemoveDistributionGroupMembership = ({ param([string]$Identity, [string]$GroupIdentity) Remove-HybridUserDistributionGroupMembership -Identity $Identity -GroupIdentity $GroupIdentity }).GetNewClosure()
    }
}

function Get-HybridUserEditableSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$User)

    if (-not $script:HybridUserAdministrationState.Initialized) { throw 'Hybrid user administration service has not been initialized.' }

    $identity = [string](Get-HybridUserAdminObjectValue -InputObject $User -Names @('SamAccountName','UserPrincipalName','Identity','Mail') -Default '')
    $directoryUser = $User
    if (-not [string]::IsNullOrWhiteSpace($identity)) {
        $hydrated = Invoke-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ActiveDirectory -OperationNames @('GetUser') -Arguments @($identity, $true)
        if ($null -ne $hydrated) { $directoryUser = $hydrated }
    }

    $attributes = [ordered]@{
        displayName = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('DisplayName','Name') -Default ''
        givenName = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('GivenName') -Default ''
        sn = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('Surname','sn') -Default ''
        userPrincipalName = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('UserPrincipalName','UPN') -Default ''
        sAMAccountName = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('SamAccountName','SAMAccountName') -Default ''
        mail = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('Mail','PrimarySmtpAddress') -Default ''
        telephoneNumber = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('PhoneNumber','TelephoneNumber','OfficePhone') -Default ''
        title = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('Title','JobTitle') -Default ''
        department = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('Department') -Default ''
        company = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('Company','CompanyName') -Default ''
        physicalDeliveryOfficeName = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('Office','OfficeLocation','PhysicalDeliveryOfficeName') -Default ''
        employeeID = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('EmployeeId','EmployeeID') -Default ''
        badgeID = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('BadgeId','BadgeID','extensionAttribute15') -Default ''
        st = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('State','st') -Default ''
        mobile = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('Mobile','MobilePhone','mobile') -Default ''
        manager = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('ManagerDisplayName','ManagerName','Manager') -Default ''
        distinguishedName = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('DistinguishedName','DN') -Default ''
        enabled = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('Enabled') -Default ''
    }

    $rawAttributes = @{}
    if (-not [string]::IsNullOrWhiteSpace($identity)) {
        $raw = Invoke-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ActiveDirectory -OperationNames @('GetUserRawAttributes','GetRawAttributes') -Arguments @($identity)
        if ($raw -is [hashtable]) { foreach ($key in $raw.Keys) { $rawAttributes[[string]$key] = $raw[$key] } }
    }

    if ($rawAttributes.Count -eq 0 -and $directoryUser.PSObject.Properties.Name -contains 'Attributes' -and $null -ne $directoryUser.Attributes) {
        if ($directoryUser.Attributes -is [hashtable]) {
            foreach ($key in $directoryUser.Attributes.Keys) { $rawAttributes[[string]$key] = $directoryUser.Attributes[$key] }
        }
        else {
            foreach ($property in $directoryUser.Attributes.PSObject.Properties) { $rawAttributes[$property.Name] = $property.Value }
        }
    }
    elseif ($rawAttributes.Count -eq 0) {
        foreach ($property in $directoryUser.PSObject.Properties) { $rawAttributes[$property.Name] = $property.Value }
    }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.UserEditableSnapshot'
        Identity = $identity
        Attributes = $attributes
        RawAttributes = $rawAttributes
        DirectReports = @(Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('DirectReports') -Default @())
        Manager = Get-HybridUserAdminObjectValue -InputObject $directoryUser -Names @('ManagerObject','Manager') -Default $null
    }
}

function Set-HybridUserDirectoryAttributes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][hashtable]$Attributes
    )

    try {
        $result = Invoke-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ActiveDirectory -OperationNames @('SetUserAttributes','SetDirectoryAttributes','UpdateUser','SetUser') -Arguments @($Identity, $Attributes)
        if ($null -eq $result) {
            return New-HybridUserAdministrationResult -Action 'SetDirectoryAttributes' -Identity $Identity -Status Unsupported -Message 'Active Directory provider does not expose editable attribute updates.'
        }
        return New-HybridUserAdministrationResult -Action 'SetDirectoryAttributes' -Identity $Identity -Status Completed -Message "Updated directory attributes for '$Identity'." -Data $result
    }
    catch {
        $script:HybridUserAdministrationState.LastError = $_.Exception.Message
        return New-HybridUserAdministrationResult -Action 'SetDirectoryAttributes' -Identity $Identity -Status Failed -Message $_.Exception.Message
    }
}

function Set-HybridUserManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][string]$ManagerIdentity
    )

    try {
        $result = Invoke-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ActiveDirectory -OperationNames @('SetUserManager','SetManager','SetADUserManager') -Arguments @($Identity, $ManagerIdentity)
        if ($null -eq $result) {
            return New-HybridUserAdministrationResult -Action 'SetManager' -Identity $Identity -Status Unsupported -Message 'Active Directory provider does not expose manager updates.'
        }
        return New-HybridUserAdministrationResult -Action 'SetManager' -Identity $Identity -Status Completed -Message "Manager for '$Identity' set to '$ManagerIdentity'." -Data $result
    }
    catch {
        $script:HybridUserAdministrationState.LastError = $_.Exception.Message
        return New-HybridUserAdministrationResult -Action 'SetManager' -Identity $Identity -Status Failed -Message $_.Exception.Message
    }
}

function Move-HybridUserDirectReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][string]$NewManagerIdentity,
        [object[]]$DirectReports = @()
    )

    try {
        if ($DirectReports.Count -eq 0) {
            $DirectReports = @(Invoke-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ActiveDirectory -OperationNames @('GetUserDirectReports','GetDirectReports') -Arguments @($Identity))
        }

        if ($DirectReports.Count -eq 0) {
            return New-HybridUserAdministrationResult -Action 'MoveDirectReports' -Identity $Identity -Status Completed -Message "No direct reports found for '$Identity'." -Data @()
        }

        if (-not (Test-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ActiveDirectory -OperationNames @('SetUserManager','SetManager','SetADUserManager'))) {
            return New-HybridUserAdministrationResult -Action 'MoveDirectReports' -Identity $Identity -Status Unsupported -Message 'Active Directory provider does not expose manager updates.'
        }

        $results = @()
        foreach ($report in @($DirectReports)) {
            $reportIdentity = [string](Get-HybridUserAdminObjectValue -InputObject $report -Names @('DistinguishedName','SamAccountName','UserPrincipalName','Identity') -Default ([string]$report))
            if ([string]::IsNullOrWhiteSpace($reportIdentity)) { continue }
            $results += (Set-HybridUserManager -Identity $reportIdentity -ManagerIdentity $NewManagerIdentity)
        }

        $failed = @($results | Where-Object { $_.Status -eq 'Failed' })
        $status = if ($failed.Count -gt 0) { 'Failed' } else { 'Completed' }
        $message = if ($failed.Count -gt 0) { "Moved some direct reports for '$Identity'; $($failed.Count) failed." } else { "Moved $($results.Count) direct report(s) for '$Identity'." }
        return New-HybridUserAdministrationResult -Action 'MoveDirectReports' -Identity $Identity -Status $status -Message $message -Data @($results)
    }
    catch {
        $script:HybridUserAdministrationState.LastError = $_.Exception.Message
        return New-HybridUserAdministrationResult -Action 'MoveDirectReports' -Identity $Identity -Status Failed -Message $_.Exception.Message
    }
}

function Set-HybridUserMailboxForwarding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [AllowNull()][string]$ForwardingSmtpAddress,
        [bool]$DeliverToMailboxAndForward = $false
    )

    try {
        $result = Invoke-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ExchangeOnline -OperationNames @('SetMailboxForwarding','SetForwarding','UpdateMailboxForwarding') -Arguments @($Identity, $ForwardingSmtpAddress, $DeliverToMailboxAndForward)
        if ($null -eq $result) {
            return New-HybridUserAdministrationResult -Action 'SetMailboxForwarding' -Identity $Identity -Status Unsupported -Message 'Exchange Online provider does not expose mailbox forwarding updates yet.'
        }
        return New-HybridUserAdministrationResult -Action 'SetMailboxForwarding' -Identity $Identity -Status Completed -Message "Updated mailbox forwarding for '$Identity'." -Data $result
    }
    catch {
        $script:HybridUserAdministrationState.LastError = $_.Exception.Message
        return New-HybridUserAdministrationResult -Action 'SetMailboxForwarding' -Identity $Identity -Status Failed -Message $_.Exception.Message
    }
}

function Set-HybridUserHiddenFromAddressLists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [bool]$Hidden
    )

    try {
        $result = Invoke-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ExchangeOnline -OperationNames @('SetHiddenFromAddressLists','SetMailboxVisibility','SetMailboxHiddenFromAddressLists') -Arguments @($Identity, $Hidden)
        if ($null -eq $result) {
            return New-HybridUserAdministrationResult -Action 'SetHiddenFromAddressLists' -Identity $Identity -Status Unsupported -Message 'Exchange Online provider does not expose GAL visibility updates yet.'
        }
        return New-HybridUserAdministrationResult -Action 'SetHiddenFromAddressLists' -Identity $Identity -Status Completed -Message "Updated GAL visibility for '$Identity'." -Data $result
    }
    catch {
        $script:HybridUserAdministrationState.LastError = $_.Exception.Message
        return New-HybridUserAdministrationResult -Action 'SetHiddenFromAddressLists' -Identity $Identity -Status Failed -Message $_.Exception.Message
    }
}

function Get-HybridUserDistributionGroups {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    try {
        $groups = @(Invoke-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ExchangeOnline -OperationNames @('GetDistributionGroups','GetUserDistributionGroups') -Arguments @($Identity))
        return New-HybridUserAdministrationResult -Action 'GetDistributionGroups' -Identity $Identity -Status Completed -Message "Loaded $($groups.Count) distribution group(s)." -Data @($groups)
    }
    catch {
        $script:HybridUserAdministrationState.LastError = $_.Exception.Message
        return New-HybridUserAdministrationResult -Action 'GetDistributionGroups' -Identity $Identity -Status Failed -Message $_.Exception.Message
    }
}

function Search-HybridUserDistributionGroups {
    [CmdletBinding()]
    param([string]$Query = '')

    try {
        $groups = @(Invoke-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ExchangeOnline -OperationNames @('SearchDistributionGroups','FindDistributionGroups','SearchGroups') -Arguments @($Query))
        if ($groups.Count -eq 0 -and -not (Test-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ExchangeOnline -OperationNames @('SearchDistributionGroups','FindDistributionGroups','SearchGroups'))) {
            return New-HybridUserAdministrationResult -Action 'SearchDistributionGroups' -Identity $Query -Status Unsupported -Message 'Exchange Online provider does not expose distribution group lookup yet.'
        }
        return New-HybridUserAdministrationResult -Action 'SearchDistributionGroups' -Identity $Query -Status Completed -Message "Found $($groups.Count) distribution group(s)." -Data @($groups)
    }
    catch {
        $script:HybridUserAdministrationState.LastError = $_.Exception.Message
        return New-HybridUserAdministrationResult -Action 'SearchDistributionGroups' -Identity $Query -Status Failed -Message $_.Exception.Message
    }
}

function Add-HybridUserMailboxDelegation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][string]$Trustee,
        [string[]]$AccessRights = @('FullAccess')
    )

    try {
        $result = Invoke-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ExchangeOnline -OperationNames @('AddMailboxDelegation','AddMailboxPermission') -Arguments @($Identity, $Trustee, $AccessRights)
        if ($null -eq $result) {
            return New-HybridUserAdministrationResult -Action 'AddMailboxDelegation' -Identity $Identity -Status Unsupported -Message 'Exchange Online provider does not expose mailbox delegation updates yet.'
        }
        return New-HybridUserAdministrationResult -Action 'AddMailboxDelegation' -Identity $Identity -Status Completed -Message "Added mailbox delegation for '$Trustee'." -Data $result
    }
    catch {
        $script:HybridUserAdministrationState.LastError = $_.Exception.Message
        return New-HybridUserAdministrationResult -Action 'AddMailboxDelegation' -Identity $Identity -Status Failed -Message $_.Exception.Message
    }
}

function Remove-HybridUserMailboxDelegation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][string]$Trustee,
        [string[]]$AccessRights = @('FullAccess')
    )

    try {
        $result = Invoke-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ExchangeOnline -OperationNames @('RemoveMailboxDelegation','RemoveMailboxPermission') -Arguments @($Identity, $Trustee, $AccessRights)
        if ($null -eq $result) {
            return New-HybridUserAdministrationResult -Action 'RemoveMailboxDelegation' -Identity $Identity -Status Unsupported -Message 'Exchange Online provider does not expose mailbox delegation updates yet.'
        }
        return New-HybridUserAdministrationResult -Action 'RemoveMailboxDelegation' -Identity $Identity -Status Completed -Message "Removed mailbox delegation for '$Trustee'." -Data $result
    }
    catch {
        $script:HybridUserAdministrationState.LastError = $_.Exception.Message
        return New-HybridUserAdministrationResult -Action 'RemoveMailboxDelegation' -Identity $Identity -Status Failed -Message $_.Exception.Message
    }
}

function Add-HybridUserDistributionGroupMembership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][string]$GroupIdentity
    )

    try {
        $result = Invoke-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ExchangeOnline -OperationNames @('AddDistributionGroupMembership','AddDistributionGroupMember') -Arguments @($Identity, $GroupIdentity)
        if ($null -eq $result) {
            return New-HybridUserAdministrationResult -Action 'AddDistributionGroupMembership' -Identity $Identity -Status Unsupported -Message 'Exchange Online provider does not expose distribution group membership updates yet.'
        }
        return New-HybridUserAdministrationResult -Action 'AddDistributionGroupMembership' -Identity $Identity -Status Completed -Message "Added '$Identity' to '$GroupIdentity'." -Data $result
    }
    catch {
        $script:HybridUserAdministrationState.LastError = $_.Exception.Message
        return New-HybridUserAdministrationResult -Action 'AddDistributionGroupMembership' -Identity $Identity -Status Failed -Message $_.Exception.Message
    }
}

function Remove-HybridUserDistributionGroupMembership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][string]$GroupIdentity
    )

    try {
        $result = Invoke-HybridUserAdminProviderOperation -Provider $script:HybridUserAdministrationState.ExchangeOnline -OperationNames @('RemoveDistributionGroupMembership','RemoveDistributionGroupMember') -Arguments @($Identity, $GroupIdentity)
        if ($null -eq $result) {
            return New-HybridUserAdministrationResult -Action 'RemoveDistributionGroupMembership' -Identity $Identity -Status Unsupported -Message 'Exchange Online provider does not expose distribution group membership updates yet.'
        }
        return New-HybridUserAdministrationResult -Action 'RemoveDistributionGroupMembership' -Identity $Identity -Status Completed -Message "Removed '$Identity' from '$GroupIdentity'." -Data $result
    }
    catch {
        $script:HybridUserAdministrationState.LastError = $_.Exception.Message
        return New-HybridUserAdministrationResult -Action 'RemoveDistributionGroupMembership' -Identity $Identity -Status Failed -Message $_.Exception.Message
    }
}

function Clear-HybridUserAdministrationService {
    [CmdletBinding()]
    param()

    $script:HybridUserAdministrationState.Initialized = $false
    $script:HybridUserAdministrationState.ActiveDirectory = $null
    $script:HybridUserAdministrationState.ExchangeOnline = $null
    $script:HybridUserAdministrationState.MicrosoftGraph = $null
    $script:HybridUserAdministrationState.LastError = $null
    return $true
}

Export-ModuleMember -Function @(
    'Initialize-HybridUserAdministrationService',
    'Get-HybridUserEditableSnapshot',
    'Set-HybridUserDirectoryAttributes',
    'Set-HybridUserManager',
    'Move-HybridUserDirectReports',
    'Set-HybridUserMailboxForwarding',
    'Set-HybridUserHiddenFromAddressLists',
    'Get-HybridUserDistributionGroups',
    'Search-HybridUserDistributionGroups',
    'Add-HybridUserMailboxDelegation',
    'Remove-HybridUserMailboxDelegation',
    'Add-HybridUserDistributionGroupMembership',
    'Remove-HybridUserDistributionGroupMembership',
    'Clear-HybridUserAdministrationService'
)
