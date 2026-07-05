Set-StrictMode -Version Latest

$script:HybridDeviceManagementState = @{
    Initialized = $false
    UserService = $null
    DirectoryProvider = $null
    MicrosoftGraphProvider = $null
    LastError = $null
}

function Invoke-HybridDeviceProviderOperation {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Provider,
        [Parameter(Mandatory=$true)][string[]]$OperationNames,
        [object[]]$Arguments = @()
    )

    if ($null -eq $Provider) { return @() }
    $providerPropertyNames = @($Provider.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($operationName in $OperationNames) {
        if ($providerPropertyNames -contains $operationName) {
            $operation = $Provider.$operationName
            if ($operation -is [scriptblock]) { return @(& $operation @Arguments) }
            if ($null -ne $operation -and $operation.PSObject.Methods.Name -contains 'Invoke') { return @($operation.Invoke($Arguments)) }
        }
    }
    return @()
}

function Get-HybridDeviceObjectValue {
    param(
        [AllowNull()][object]$InputObject,
        [string[]]$Names,
        [object]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($name in $Names) {
            if ($InputObject.Contains($name)) { return $InputObject[$name] }
        }
        return $Default
    }
    $propertyNames = @($InputObject.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($name in $Names) {
        if ($propertyNames -contains $name) { return $InputObject.$name }
    }
    return $Default
}

function ConvertTo-HybridManagedDevice {
    [CmdletBinding()]
    param([AllowNull()][object]$Device)

    if ($null -eq $Device) { return $null }
    if ($Device.PSObject.TypeNames -contains 'Hybrid.Device') { return $Device }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.Device'
        Id = [string](Get-HybridDeviceObjectValue -InputObject $Device -Names @('Id','id','DeviceId','deviceId','AzureAdDeviceId','azureAdDeviceId') -Default '')
        Name = [string](Get-HybridDeviceObjectValue -InputObject $Device -Names @('Name','DisplayName','displayName','DeviceName','deviceName') -Default '')
        OperatingSystem = [string](Get-HybridDeviceObjectValue -InputObject $Device -Names @('OperatingSystem','operatingSystem','OS') -Default '')
        ComplianceState = [string](Get-HybridDeviceObjectValue -InputObject $Device -Names @('ComplianceState','complianceState','ManagementState','managementState') -Default 'Unknown')
        PrimaryUser = [string](Get-HybridDeviceObjectValue -InputObject $Device -Names @('PrimaryUser','primaryUser','UserPrincipalName','userPrincipalName','RegisteredOwner','registeredOwner') -Default '')
        LastCheckInUtc = Get-HybridDeviceObjectValue -InputObject $Device -Names @('LastCheckInUtc','lastSyncDateTime','LastSyncDateTime','approximateLastSignInDateTime') -Default ([datetime]::MinValue)
        Source = [string](Get-HybridDeviceObjectValue -InputObject $Device -Names @('Source','source') -Default 'DeviceManagement')
        Attributes = @{ RawDevice = $Device }
        CreatedUtc = [datetime]::UtcNow
    }
}

function Initialize-HybridDeviceManagementService {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$UserService,
        [AllowNull()][object]$DirectoryProvider,
        [AllowNull()][object]$MicrosoftGraphProvider
    )

    $script:HybridDeviceManagementState.UserService = $UserService
    $script:HybridDeviceManagementState.DirectoryProvider = $DirectoryProvider
    $script:HybridDeviceManagementState.MicrosoftGraphProvider = $MicrosoftGraphProvider
    $script:HybridDeviceManagementState.LastError = $null
    $script:HybridDeviceManagementState.Initialized = $true

    [pscustomobject]@{
        PSTypeName = 'Hybrid.DeviceManagement.Service'
        Name = 'DeviceManagementService'
        Initialized = $true
        GetDevicesForUser = ({ param([string]$Identity) Get-HybridManagedDevicesForUser -Identity $Identity }).GetNewClosure()
        SearchDevices = ({ param([string]$Query) Search-HybridManagedDevices -Query $Query }).GetNewClosure()
        GetDevice = ({ param([string]$Identity) Search-HybridManagedDevices -Query $Identity }).GetNewClosure()
        GetSummaryForUser = ({ param([string]$Identity) Get-HybridManagedDeviceSummary -Identity $Identity }).GetNewClosure()
    }
}

function Get-HybridManagedDevicesForUser {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not $script:HybridDeviceManagementState.Initialized) { throw 'Device Management service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'User identity is required for device lookup.' }

    $devices = @()
    $devices += @(Invoke-HybridDeviceProviderOperation -Provider $script:HybridDeviceManagementState.DirectoryProvider -OperationNames @('GetUserDevices','GetDevices','GetManagedDevices') -Arguments @($Identity))
    $devices += @(Invoke-HybridDeviceProviderOperation -Provider $script:HybridDeviceManagementState.MicrosoftGraphProvider -OperationNames @('GetUserDevices','GetManagedDevices','GetIntuneDevices') -Arguments @($Identity))

    if ($devices.Count -eq 0 -and $null -ne $script:HybridDeviceManagementState.UserService) {
        $user = @(Invoke-HybridDeviceProviderOperation -Provider $script:HybridDeviceManagementState.UserService -OperationNames @('GetUser','GetUserDetails') -Arguments @($Identity) | Select-Object -First 1)
        if ($user.Count -gt 0 -and $null -ne $user[0] -and $user[0].PSObject.Properties.Name -contains 'Devices') {
            $devices += @($user[0].Devices)
        }
    }

    return @($devices | ForEach-Object { ConvertTo-HybridManagedDevice -Device $_ } | Where-Object { $null -ne $_ } | Sort-Object Name -Unique)
}

function Search-HybridManagedDevices {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Query)

    if (-not $script:HybridDeviceManagementState.Initialized) { throw 'Device Management service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Query)) { throw 'Device identity is required for device lookup.' }

    $devices = @()
    $devices += @(Get-HybridManagedDevicesForUser -Identity $Query)
    $devices += @(Invoke-HybridDeviceProviderOperation -Provider $script:HybridDeviceManagementState.DirectoryProvider -OperationNames @('SearchDevices','SearchDevice','GetDevice','GetComputer','SearchComputer','GetManagedDevice') -Arguments @($Query))
    $devices += @(Invoke-HybridDeviceProviderOperation -Provider $script:HybridDeviceManagementState.MicrosoftGraphProvider -OperationNames @('SearchDevices','SearchDevice','GetDevice','GetManagedDevice','GetManagedDevices','GetIntuneDevices') -Arguments @($Query))

    $needle = $Query.Trim()
    return @($devices |
        ForEach-Object { ConvertTo-HybridManagedDevice -Device $_ } |
        Where-Object {
            $null -ne $_ -and (
                [string]::IsNullOrWhiteSpace($needle) -or
                $_.Name -like "*$needle*" -or
                $_.Id -like "*$needle*" -or
                $_.PrimaryUser -like "*$needle*"
            )
        } |
        Sort-Object Name, Id -Unique)
}

function Get-HybridManagedDeviceSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $devices = @(Search-HybridManagedDevices -Query $Identity)
    $nonCompliant = @($devices | Where-Object { $_.ComplianceState -and $_.ComplianceState -notin @('Compliant','Unknown') })
    $stale = @($devices | Where-Object {
        $lastCheckIn = $_.LastCheckInUtc
        $lastCheckIn -is [datetime] -and $lastCheckIn -gt [datetime]::MinValue -and $lastCheckIn -lt ([datetime]::UtcNow.AddDays(-7))
    })

    [pscustomobject]@{
        PSTypeName = 'Hybrid.DeviceManagement.Summary'
        Identity = $Identity
        DeviceCount = $devices.Count
        NonCompliantCount = $nonCompliant.Count
        StaleCheckInCount = $stale.Count
        Status = if ($nonCompliant.Count -gt 0 -or $stale.Count -gt 0) { 'Warning' } elseif ($devices.Count -gt 0) { 'Ready' } else { 'No devices' }
        Devices = @($devices)
    }
}

Export-ModuleMember -Function @(
    'Initialize-HybridDeviceManagementService',
    'ConvertTo-HybridManagedDevice',
    'Get-HybridManagedDevicesForUser',
    'Search-HybridManagedDevices',
    'Get-HybridManagedDeviceSummary'
)
