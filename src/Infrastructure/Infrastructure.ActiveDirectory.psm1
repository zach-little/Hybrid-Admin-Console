#region Module Information
# Name: Infrastructure.ActiveDirectory
# Purpose: Active Directory provider for the Hybrid Administration Platform.
# Dependencies: Core.ProviderBase, Core.ServiceRegistry, Hybrid.Models, ActiveDirectory PowerShell module at runtime.
# Exports: Initialize-HybridActiveDirectoryProvider, Initialize-HybridActiveDirectoryRuntime, Test-HybridActiveDirectoryProviderAvailable,
#          Search-HybridADUser, Get-HybridADUser, Get-HybridADUserGroups,
#          Get-HybridADUserManager, Get-HybridADUserDirectReports,
#          Reset-HybridADUserPassword, Set-HybridADUserEnabled,
#          Unlock-HybridADUser, Move-HybridADUserOU, Clear-HybridADProviderCache, ConvertTo-HybridADUser,
#          Get-HybridADProviderHealth, Test-HybridADProviderCapability, Get-HybridADProviderCapabilities
#endregion

Set-StrictMode -Version Latest

$script:ProviderCapabilities = @(
    'Search',
    'GetUser',
    'Groups',
    'Manager',
    'DirectReports',
    'PasswordReset',
    'EnableDisable',
    'Unlock',
    'OrganizationalUnits',
    'Caching',
    'CommandWrapper',
    'StructuredErrors',
    'ProviderHealth',
    'CapabilityDiscovery',
    'Lifecycle'
)

$script:ProviderState = if (Get-Command New-HybridProviderState -ErrorAction SilentlyContinue) {
    New-HybridProviderState -Name 'ActiveDirectory' -Module 'Infrastructure.ActiveDirectory' -Capabilities $script:ProviderCapabilities -CacheBuckets @('Users','Groups','Managers','DirectReports','OUs')
}
else {
    [pscustomobject]@{
        PSTypeName      = 'Hybrid.ProviderState'
        Name            = 'ActiveDirectory'
        Module          = 'Infrastructure.ActiveDirectory'
        Initialized     = $false
        Available       = $false
        Connected       = $false
        LastError       = $null
        LastInitialized = $null
        LastCommand     = $null
        Version         = '0.1.0'
        Capabilities    = @($script:ProviderCapabilities)
        CommandHistory  = @()
        Cache           = @{
            Users         = @{}
            Groups        = @{}
            Managers      = @{}
            DirectReports = @{}
            OUs           = @{}
        }
    }
}

$script:State = @{
    Initialized       = $false
    Registered        = $false
    DomainController  = ''
    SearchBase        = ''
    Credential        = $null
    ProviderAvailable = $false
    NoNet             = $false
    RuntimeDiagnosticsPath = ''
    CommandHistory    = @()
    Cache             = @{
        Users         = @{}
        Groups        = @{}
        Managers      = @{}
        DirectReports = @{}
        OUs           = @{}
    }
}

$script:ProviderState.Cache = $script:State.Cache

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


function Write-HybridADRuntimeDiagnostic {
    [CmdletBinding()]
    param(
        [string]$Level = 'Information',
        [string]$Message = '',
        [AllowNull()][object]$Data = $null
    )

    try {
        $logPath = $script:State.RuntimeDiagnosticsPath
        if ([string]::IsNullOrWhiteSpace($logPath)) {
            $logRoot = Join-Path (Get-Location).Path 'logs'
            $logPath = Join-Path $logRoot 'ad-runtime-diagnostics.log'
        }

        $parent = Split-Path -Parent $logPath
        if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }

        $entry = [ordered]@{
            TimestampUtc = ([datetime]::UtcNow.ToString('o'))
            Level = $Level
            Component = 'Infrastructure.ActiveDirectory'
            Message = $Message
            Data = $Data
        }
        ($entry | ConvertTo-Json -Depth 8 -Compress) | Add-Content -LiteralPath $logPath -Encoding UTF8
    }
    catch { }
}

function Test-HybridADCommand {
    param([Parameter(Mandatory=$true)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Import-HybridActiveDirectoryModule {
    if (Get-Module -Name ActiveDirectory) { return $true }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-HybridADRuntimeDiagnostic -Level Information -Message 'ActiveDirectory module imported into provider runtime session.'
        return $true
    }
    catch {
        Write-HybridADLog -Level Warning -Message 'ActiveDirectory module is not available.' -Exception $_
        Write-HybridADRuntimeDiagnostic -Level Warning -Message 'ActiveDirectory module import failed in provider runtime session.' -Data @{ Error = $_.Exception.Message; PSModulePath = $env:PSModulePath }
        return $false
    }
}

function Initialize-HybridActiveDirectoryRuntime {
    <#
    .SYNOPSIS
    Validates the ActiveDirectory module inside the current HAP provider runtime session.
    #>
    [CmdletBinding()]
    param(
        [string[]]$RequiredCommands = @('Get-ADUser','Get-ADDomain','Get-ADPrincipalGroupMembership'),
        [switch]$ThrowOnFailure
    )

    $result = [pscustomobject]@{
        PSTypeName = 'Hybrid.ActiveDirectoryRuntimeReadiness'
        Available = $false
        Connected = $false
        ModuleLoaded = $false
        RequiredCommands = @($RequiredCommands)
        MissingCommands = @()
        DomainAvailable = $false
        ErrorMessage = ''
        CheckedUtc = [datetime]::UtcNow
        PSModulePath = $env:PSModulePath
    }
    $result.PSObject.TypeNames.Insert(0, 'Hybrid.ActiveDirectoryRuntimeReadiness')

    if ($script:State.NoNet) {
        $result.ErrorMessage = 'Active Directory runtime readiness skipped because provider is initialized in NoNet mode.'
        Write-HybridADRuntimeDiagnostic -Level Information -Message $result.ErrorMessage -Data $result
        if ($ThrowOnFailure) { throw $result.ErrorMessage }
        return $result
    }

    try {
        if (-not (Import-HybridActiveDirectoryModule)) {
            throw 'ActiveDirectory module could not be imported into the HAP provider runtime session.'
        }

        $result.ModuleLoaded = $true
        $missing = @()
        foreach ($requiredCommand in @($RequiredCommands)) {
            if (-not (Get-Command -Name $requiredCommand -ErrorAction SilentlyContinue)) {
                $missing += $requiredCommand
            }
        }
        $result.MissingCommands = @($missing)
        if ($missing.Count -gt 0) {
            throw ('ActiveDirectory module loaded, but required command(s) are unavailable in this session: {0}' -f ($missing -join ', '))
        }

        try {
            $domainParams = New-HybridADCommonParameters
            $null = Invoke-HybridADCommand -CommandName 'Get-ADDomain' -Parameters $domainParams -Operation 'Runtime readiness domain check'
            $result.DomainAvailable = $true
        }
        catch {
            throw "ActiveDirectory module is loaded, but the domain check failed in this HAP runtime session: $($_.Exception.Message)"
        }

        $result.Available = $true
        $result.Connected = $true
        $script:State.ProviderAvailable = $true
        $script:ProviderState.Available = $true
        $script:ProviderState.Connected = $true
        $script:ProviderState.LastError = $null
        Write-HybridADRuntimeDiagnostic -Level Information -Message 'Active Directory runtime readiness succeeded inside provider runtime session.' -Data $result
        return $result
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
        $script:State.ProviderAvailable = $false
        $script:ProviderState.Available = $false
        $script:ProviderState.Connected = $false
        $script:ProviderState.LastError = $result.ErrorMessage
        Write-HybridADLog -Level Warning -Message 'Active Directory runtime readiness failed.' -Exception $_
        Write-HybridADRuntimeDiagnostic -Level Warning -Message 'Active Directory runtime readiness failed inside provider runtime session.' -Data $result
        if ($ThrowOnFailure) { throw $result.ErrorMessage }
        return $result
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
        'BadgeID',
        'employeeNumber',
        'extensionAttribute1',
        'st',
        'telephoneNumber',
        'mobile',
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
    if (-not $script:State.ProviderAvailable -and -not $script:State.NoNet) {
        Initialize-HybridActiveDirectoryRuntime -ThrowOnFailure | Out-Null
    }

    if (-not $script:State.ProviderAvailable) {
        throw 'Active Directory provider is not available in the current HAP runtime session. Install RSAT Active Directory tools, confirm the workstation can contact the domain, or review logs\ad-runtime-diagnostics.log.'
    }
}

function ConvertTo-HybridArrayValue {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [array]) { return @($Value) }
    return @($Value)
}


function New-HybridADProviderException {
    param(
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)][string]$Message,
        [object]$InnerException = $null
    )

    $exception = [System.InvalidOperationException]::new("[$Code] $Message")
    $exception.Data['HybridErrorCode'] = $Code
    if ($null -ne $InnerException) {
        $exception.Data['InnerException'] = $InnerException
    }
    return $exception
}

function ConvertTo-HybridADProviderErrorCode {
    param([object]$ErrorRecord)

    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match 'access is denied|insufficient access|unauthorized|permission') { return 'AccessDenied' }
    if ($message -match 'cannot find|not found|does not exist') { return 'ObjectNotFound' }
    if ($message -match 'server is not operational|domain.*unavailable|unable to contact') { return 'DomainUnavailable' }
    if ($message -match 'already exists|duplicate') { return 'ObjectAlreadyExists' }
    if ($message -match 'constraint|violat') { return 'ConstraintViolation' }
    return 'ActiveDirectoryCommandFailed'
}

function Invoke-HybridADCommand {
    param(
        [Parameter(Mandatory=$true)][string]$CommandName,
        [Parameter(Mandatory=$true)][hashtable]$Parameters,
        [string]$Operation = $CommandName
    )

    $started = Get-Date
    Write-HybridADLog -Level Debug -Message "AD operation '$Operation' starting."

    try {
        $command = Get-Command $CommandName -ErrorAction Stop
        $result = & $command @Parameters
        $elapsed = [int]((Get-Date) - $started).TotalMilliseconds
        $commandRecord = [pscustomobject]@{
            CommandName = $CommandName
            Operation   = $Operation
            Success     = $true
            DurationMs  = $elapsed
            Timestamp   = Get-Date
        }
        $script:State.CommandHistory += $commandRecord
        $script:ProviderState.CommandHistory += $commandRecord
        $script:ProviderState.LastCommand = $Operation
        Write-HybridADLog -Level Debug -Message "AD operation '$Operation' completed in $elapsed ms."
        return $result
    }
    catch {
        $elapsed = [int]((Get-Date) - $started).TotalMilliseconds
        $code = ConvertTo-HybridADProviderErrorCode -ErrorRecord $_
        $commandRecord = [pscustomobject]@{
            CommandName = $CommandName
            Operation   = $Operation
            Success     = $false
            DurationMs  = $elapsed
            Timestamp   = Get-Date
            ErrorCode   = $code
        }
        $script:State.CommandHistory += $commandRecord
        $script:ProviderState.CommandHistory += $commandRecord
        $script:ProviderState.LastCommand = $Operation
        $script:ProviderState.LastError = $code
        Write-HybridADLog -Level Error -Message "AD operation '$Operation' failed with $code." -Exception $_
        throw (New-HybridADProviderException -Code $code -Message "Active Directory operation '$Operation' failed: $($_.Exception.Message)" -InnerException $_.Exception)
    }
}

function Get-HybridADCacheKey {
    param([string]$Prefix, [string]$Value)
    return "$Prefix::$($Value.ToLowerInvariant())"
}

function Get-HybridADCacheValue {
    param([string]$Bucket, [string]$Key)
    if ($script:State.Cache.ContainsKey($Bucket) -and $script:State.Cache[$Bucket].ContainsKey($Key)) {
        return $script:State.Cache[$Bucket][$Key]
    }
    return $null
}

function Set-HybridADCacheValue {
    param([string]$Bucket, [string]$Key, [object]$Value)
    if (-not $script:State.Cache.ContainsKey($Bucket)) { $script:State.Cache[$Bucket] = @{} }
    $script:State.Cache[$Bucket][$Key] = $Value
}

function Clear-HybridADProviderCache {
    [CmdletBinding()]
    param([string]$Identity = '')

    foreach ($bucket in @('Users','Groups','Managers','DirectReports','OUs')) {
        if ($script:State.Cache.ContainsKey($bucket)) { $script:State.Cache[$bucket].Clear() }
    }

    Write-HybridADLog -Level Debug -Message $(if ([string]::IsNullOrWhiteSpace($Identity)) { 'AD provider cache cleared.' } else { "AD provider cache cleared after write involving '$Identity'." })
}
#endregion

#region Public provider lifecycle

function Get-HybridADProviderCapabilities {
    [CmdletBinding()]
    param()

    if (Get-Command Get-HybridProviderCapabilities -ErrorAction SilentlyContinue) {
        return Get-HybridProviderCapabilities -ProviderState $script:ProviderState
    }

    return @($script:ProviderState.Capabilities)
}

function Test-HybridADProviderCapability {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Capability)

    if (Get-Command Test-HybridProviderCapability -ErrorAction SilentlyContinue) {
        return Test-HybridProviderCapability -ProviderState $script:ProviderState -Capability $Capability
    }

    return @($script:ProviderState.Capabilities) -contains $Capability
}

function Get-HybridADProviderHealth {
    [CmdletBinding()]
    param()

    if (-not $script:State.NoNet) {
        Initialize-HybridActiveDirectoryRuntime | Out-Null
    }

    $script:ProviderState.Available = [bool]$script:State.ProviderAvailable
    $script:ProviderState.Connected = [bool]$script:State.ProviderAvailable
    $script:ProviderState.Cache = $script:State.Cache

    if (Get-Command Get-HybridProviderHealth -ErrorAction SilentlyContinue) {
        $health = Get-HybridProviderHealth -ProviderState $script:ProviderState
    }
    else {
        $cacheEntries = 0
        foreach ($bucket in $script:State.Cache.Keys) { $cacheEntries += $script:State.Cache[$bucket].Count }
        $health = [pscustomobject]@{
            PSTypeName     = 'Hybrid.ProviderHealth'
            Name           = 'ActiveDirectory'
            Module         = 'Infrastructure.ActiveDirectory'
            Initialized    = [bool]$script:State.Initialized
            Available      = [bool]$script:State.ProviderAvailable
            Connected      = [bool]$script:State.ProviderAvailable
            LastError      = $script:ProviderState.LastError
            Version        = [string]$script:ProviderState.Version
            Capabilities   = @($script:ProviderState.Capabilities)
            CacheEntries   = $cacheEntries
            CommandCount   = @($script:State.CommandHistory).Count
            LastCommand    = $(if (@($script:State.CommandHistory).Count -gt 0) { @($script:State.CommandHistory)[-1] } else { $null })
            ResponseTimeMs = $null
        }
    }

    $health.PSObject.TypeNames.Insert(0, 'Hybrid.ActiveDirectoryProviderHealth')
    return $health
}

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
        [string]$RuntimeDiagnosticsPath = '',
        [switch]$NoNet,
        [switch]$RegisterAsDirectory
    )

    $script:State.DomainController = $DomainController
    $script:State.SearchBase = $SearchBase
    $script:State.Credential = $Credential
    $script:State.ProviderAvailable = $false
    $script:State.NoNet = [bool]$NoNet
    $script:State.RuntimeDiagnosticsPath = $RuntimeDiagnosticsPath
    Clear-HybridADProviderCache

    if (-not $NoNet) {
        $readiness = Initialize-HybridActiveDirectoryRuntime
        $script:State.ProviderAvailable = [bool]$readiness.Available
    }

    $script:ProviderState.Cache = $script:State.Cache
    if (Get-Command Initialize-HybridProvider -ErrorAction SilentlyContinue) {
        Initialize-HybridProvider -ProviderState $script:ProviderState -Available ([bool]$script:State.ProviderAvailable) -Connected ([bool]$script:State.ProviderAvailable) -Version '0.4.0' | Out-Null
    }
    else {
        $script:ProviderState.Initialized = $true
        $script:ProviderState.Available = [bool]$script:State.ProviderAvailable
        $script:ProviderState.Connected = [bool]$script:State.ProviderAvailable
        $script:ProviderState.LastInitialized = Get-Date
    }

    $operations = @{
        ClearCache           = { param([string]$Identity) Clear-HybridADProviderCache -Identity $Identity }
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
        GetHealth            = { Get-HybridADProviderHealth }
        GetProviderHealth    = { Get-HybridADProviderHealth }
        InitializeRuntime    = { Initialize-HybridActiveDirectoryRuntime }
        SupportsCapability   = { param([string]$Capability) Test-HybridADProviderCapability -Capability $Capability }
    }

    if (Get-Command New-HybridProviderService -ErrorAction SilentlyContinue) {
        $directoryService = New-HybridProviderService -ProviderState $script:ProviderState -Operations $operations
        $directoryService.PSObject.TypeNames.Insert(0, 'Hybrid.ActiveDirectoryService')
    }
    else {
        $directoryService = [pscustomobject]@{
            PSTypeName           = 'Hybrid.ActiveDirectoryService'
            ProviderName         = 'ActiveDirectory'
            ProviderModule       = 'Infrastructure.ActiveDirectory'
            ProviderAvailable    = $script:State.ProviderAvailable
            ProviderConnected    = $script:State.ProviderAvailable
            Capabilities         = @($script:ProviderCapabilities)
            GetHealth            = { Get-HybridADProviderHealth }
            GetProviderHealth    = { Get-HybridADProviderHealth }
            InitializeRuntime    = { Initialize-HybridActiveDirectoryRuntime }
            Supports             = { param([string]$Capability) Test-HybridADProviderCapability -Capability $Capability }
            GetCapabilities      = { Get-HybridADProviderCapabilities }
            ClearCache           = $operations.ClearCache
            SearchUser           = $operations.SearchUser
            GetUser              = $operations.GetUser
            GetUserGroups        = $operations.GetUserGroups
            GetUserManager       = $operations.GetUserManager
            GetUserDirectReports = $operations.GetUserDirectReports
            ResetPassword        = $operations.ResetPassword
            SetEnabled           = $operations.SetEnabled
            UnlockUser           = $operations.UnlockUser
            MoveUserOU           = $operations.MoveUserOU
            SetUserManager       = $operations.SetUserManager
            AddUserToGroup       = $operations.AddUserToGroup
            RemoveUserFromGroup  = $operations.RemoveUserFromGroup
            SearchOU             = $operations.SearchOU
        }
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
    $script:ProviderState.Initialized = $true
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
        if ($InputObject.PSObject.Properties.Name -contains 'BadgeID' -and $null -ne $InputObject.BadgeID) {
            $badgeId = [string]$InputObject.BadgeID
        }
        elseif ($InputObject.PSObject.Properties.Name -contains 'BadgeId' -and $null -ne $InputObject.BadgeId) {
            $badgeId = [string]$InputObject.BadgeId
        }
        elseif ($InputObject.PSObject.Properties.Name -contains 'extensionAttribute1' -and $null -ne $InputObject.extensionAttribute1) {
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

        $state = ''
        if ($InputObject.PSObject.Properties.Name -contains 'st' -and $null -ne $InputObject.st) {
            $state = [string]$InputObject.st
        }

        $phoneNumber = ''
        if ($InputObject.PSObject.Properties.Name -contains 'telephoneNumber' -and $null -ne $InputObject.telephoneNumber) {
            $phoneNumber = [string]$InputObject.telephoneNumber
        }

        $mobilePhone = ''
        if ($InputObject.PSObject.Properties.Name -contains 'mobile' -and $null -ne $InputObject.mobile) {
            $mobilePhone = [string]$InputObject.mobile
        }

        $distinguishedName = ''
        if ($InputObject.PSObject.Properties.Name -contains 'DistinguishedName' -and $null -ne $InputObject.DistinguishedName) {
            $distinguishedName = [string]$InputObject.DistinguishedName
        }

        $organizationalUnit = ''
        if (-not [string]::IsNullOrWhiteSpace($distinguishedName)) {
            $ouParts = @($distinguishedName -split ',' | Where-Object { $_ -like 'OU=*' } | ForEach-Object { $_.Substring(3) })
            if ($ouParts.Count -gt 0) {
                [array]::Reverse($ouParts)
                $organizationalUnit = ($ouParts -join ' / ')
            }
        }

        $user = New-HybridUser `
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
                DistinguishedName = $distinguishedName
                ActiveDirectoryDistinguishedName = $distinguishedName
                OrganizationalUnit = $organizationalUnit
                ActiveDirectoryOrganizationalUnit = $organizationalUnit
                ManagerDn         = $managerDn
                State             = $state
                TelephoneNumber   = $phoneNumber
                PhoneNumber       = $phoneNumber
                MobilePhone       = $mobilePhone
                DirectReportDns   = @(ConvertTo-HybridArrayValue $InputObject.DirectReports)
            }

        $user | Add-Member -NotePropertyName DistinguishedName -NotePropertyValue $distinguishedName -Force
        $user | Add-Member -NotePropertyName ActiveDirectoryDistinguishedName -NotePropertyValue $distinguishedName -Force
        $user | Add-Member -NotePropertyName OrganizationalUnit -NotePropertyValue $organizationalUnit -Force
        $user | Add-Member -NotePropertyName ActiveDirectoryOrganizationalUnit -NotePropertyValue $organizationalUnit -Force
        $user | Add-Member -NotePropertyName State -NotePropertyValue $state -Force
        $user | Add-Member -NotePropertyName PhoneNumber -NotePropertyValue $phoneNumber -Force
        $user | Add-Member -NotePropertyName MobilePhone -NotePropertyValue $mobilePhone -Force
        return $user
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

    $users = @(Invoke-HybridADCommand -CommandName 'Get-ADUser' -Parameters $adParams -Operation 'Search users' | ForEach-Object { ConvertTo-HybridADUser -InputObject $_ })

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

    $cacheKey = Get-HybridADCacheKey -Prefix $(if ($IncludeRelated) { 'user:hydrated' } else { 'user' }) -Value $Identity
    $cachedUser = Get-HybridADCacheValue -Bucket 'Users' -Key $cacheKey
    if ($null -ne $cachedUser) { return $cachedUser }

    $adParams = New-HybridADCommonParameters
    $adParams.Properties = Get-HybridADDefaultUserProperties
    $adParams.Filter = Resolve-HybridADIdentityFilter -Identity $Identity

    $adUser = Invoke-HybridADCommand -CommandName 'Get-ADUser' -Parameters $adParams -Operation 'Get user' | Select-Object -First 1
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

    Set-HybridADCacheValue -Bucket 'Users' -Key $cacheKey -Value $user
    return $user
}

function Get-HybridADUserGroups {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    Assert-HybridADProviderAvailable

    $cacheKey = Get-HybridADCacheKey -Prefix 'groups' -Value $Identity
    $cachedGroups = Get-HybridADCacheValue -Bucket 'Groups' -Key $cacheKey
    if ($null -ne $cachedGroups) { return @($cachedGroups) }

    $adParams = New-HybridADCommonParameters
    $adParams.Identity = $Identity

    $groups = @(Invoke-HybridADCommand -CommandName 'Get-ADPrincipalGroupMembership' -Parameters $adParams -Operation 'Get user groups' | ForEach-Object {
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
    Set-HybridADCacheValue -Bucket 'Groups' -Key $cacheKey -Value $groups
    return $groups
}

function Get-HybridADUserManager {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    Assert-HybridADProviderAvailable

    $cacheKey = Get-HybridADCacheKey -Prefix 'manager' -Value $Identity
    $cachedManager = Get-HybridADCacheValue -Bucket 'Managers' -Key $cacheKey
    if ($null -ne $cachedManager) { return $cachedManager }

    $user = Get-HybridADUser -Identity $Identity
    if ($null -eq $user -or [string]::IsNullOrWhiteSpace($user.Attributes.ManagerDn)) { return $null }

    $adParams = New-HybridADCommonParameters
    $adParams.Identity = $user.Attributes.ManagerDn
    $adParams.Properties = Get-HybridADDefaultUserProperties

    $manager = Invoke-HybridADCommand -CommandName 'Get-ADUser' -Parameters $adParams -Operation 'Get user manager'
    if ($null -eq $manager) { return $null }

    $hybridManager = ConvertTo-HybridADUser -InputObject $manager
    Set-HybridADCacheValue -Bucket 'Managers' -Key $cacheKey -Value $hybridManager
    return $hybridManager
}

function Get-HybridADUserDirectReports {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    Assert-HybridADProviderAvailable

    $cacheKey = Get-HybridADCacheKey -Prefix 'reports' -Value $Identity
    $cachedReports = Get-HybridADCacheValue -Bucket 'DirectReports' -Key $cacheKey
    if ($null -ne $cachedReports) { return @($cachedReports) }

    $user = Get-HybridADUser -Identity $Identity
    if ($null -eq $user) { return @() }

    $reportDns = @(ConvertTo-HybridArrayValue $user.Attributes.DirectReportDns)
    if ($reportDns.Count -eq 0) { return @() }

    $adParams = New-HybridADCommonParameters
    $adParams.Properties = Get-HybridADDefaultUserProperties

    $reports = @($reportDns | ForEach-Object {
        $adParams.Identity = $_
        $report = Invoke-HybridADCommand -CommandName 'Get-ADUser' -Parameters $adParams -Operation 'Get direct report'
        if ($null -ne $report) { ConvertTo-HybridADUser -InputObject $report }
    })
    Set-HybridADCacheValue -Bucket 'DirectReports' -Key $cacheKey -Value $reports
    return $reports
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
        $passwordParams = $adParams.Clone()
        $passwordParams.Identity = $Identity
        $passwordParams.Reset = $true
        $passwordParams.NewPassword = $NewPassword
        Invoke-HybridADCommand -CommandName 'Set-ADAccountPassword' -Parameters $passwordParams -Operation 'Reset password' | Out-Null
        if ($ChangeAtLogon) {
            $changeParams = $adParams.Clone()
            $changeParams.Identity = $Identity
            $changeParams.ChangePasswordAtLogon = $true
            Invoke-HybridADCommand -CommandName 'Set-ADUser' -Parameters $changeParams -Operation 'Set change password at logon' | Out-Null
        }
    }

    Clear-HybridADProviderCache -Identity $Identity
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
        $enableParams = $adParams.Clone()
        $enableParams.Identity = $Identity
        if ($Enabled) { Invoke-HybridADCommand -CommandName 'Enable-ADAccount' -Parameters $enableParams -Operation 'Enable account' | Out-Null }
        else { Invoke-HybridADCommand -CommandName 'Disable-ADAccount' -Parameters $enableParams -Operation 'Disable account' | Out-Null }
    }

    Clear-HybridADProviderCache -Identity $Identity
    return New-HybridResult -Success $true -Message "Enabled state set to '$Enabled' for '$Identity'."
}

function Unlock-HybridADUser {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory=$true)][string]$Identity)

    Assert-HybridADProviderAvailable

    if ($PSCmdlet.ShouldProcess($Identity, 'Unlock AD account')) {
        $adParams = New-HybridADCommonParameters
        $unlockParams = $adParams.Clone()
        $unlockParams.Identity = $Identity
        Invoke-HybridADCommand -CommandName 'Unlock-ADAccount' -Parameters $unlockParams -Operation 'Unlock account' | Out-Null
    }

    Clear-HybridADProviderCache -Identity $Identity
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
        $managerParams = $adParams.Clone()
        $managerParams.Identity = $Identity
        $managerParams.Manager = $ManagerIdentity
        Invoke-HybridADCommand -CommandName 'Set-ADUser' -Parameters $managerParams -Operation 'Set user manager' | Out-Null
    }

    Clear-HybridADProviderCache -Identity $Identity
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
        $groupParams = $adParams.Clone()
        $groupParams.Identity = $GroupIdentity
        $groupParams.Members = $Identity
        Invoke-HybridADCommand -CommandName 'Add-ADGroupMember' -Parameters $groupParams -Operation 'Add user to group' | Out-Null
    }

    Clear-HybridADProviderCache -Identity $Identity
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
        $groupParams = $adParams.Clone()
        $groupParams.Identity = $GroupIdentity
        $groupParams.Members = $Identity
        $groupParams.Confirm = $false
        Invoke-HybridADCommand -CommandName 'Remove-ADGroupMember' -Parameters $groupParams -Operation 'Remove user from group' | Out-Null
    }

    Clear-HybridADProviderCache -Identity $Identity
    return New-HybridResult -Success $true -Message "User '$Identity' removed from group '$GroupIdentity'."
}

function Search-HybridADOrganizationalUnit {
    [CmdletBinding()]
    param(
        [string]$Query = '',
        [int]$ResultSetSize = 100
    )

    Assert-HybridADProviderAvailable

    $cacheKey = Get-HybridADCacheKey -Prefix 'ou' -Value "$Query|$ResultSetSize"
    $cachedOUs = Get-HybridADCacheValue -Bucket 'OUs' -Key $cacheKey
    if ($null -ne $cachedOUs) { return @($cachedOUs) }

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

    $ous = @(Invoke-HybridADCommand -CommandName 'Get-ADOrganizationalUnit' -Parameters $adParams -Operation 'Search organizational units' | ForEach-Object {
        [pscustomobject]@{
            PSTypeName         = 'Hybrid.ActiveDirectoryOrganizationalUnit'
            Name               = [string]$_.Name
            DistinguishedName  = [string]$_.DistinguishedName
            Description        = [string]$_.Description
            Source             = 'ActiveDirectory'
        }
    })
    Set-HybridADCacheValue -Bucket 'OUs' -Key $cacheKey -Value $ous
    return $ous
}

function Move-HybridADUserOU {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][string]$TargetPath
    )

    Assert-HybridADProviderAvailable

    $adParams = New-HybridADCommonParameters
    $moveUserParams = $adParams.Clone()
    $moveUserParams.Identity = $Identity
    $moveUserParams.Properties = 'distinguishedName'
    $user = Invoke-HybridADCommand -CommandName 'Get-ADUser' -Parameters $moveUserParams -Operation 'Resolve user for OU move'
    if ($null -eq $user) { throw (New-HybridADProviderException -Code 'ObjectNotFound' -Message "AD user '$Identity' was not found.") }

    if ($PSCmdlet.ShouldProcess($Identity, "Move AD object to $TargetPath")) {
        $moveParams = $adParams.Clone()
        $moveParams.Identity = $user.DistinguishedName
        $moveParams.TargetPath = $TargetPath
        Invoke-HybridADCommand -CommandName 'Move-ADObject' -Parameters $moveParams -Operation 'Move user OU' | Out-Null
    }

    Clear-HybridADProviderCache -Identity $Identity
    return New-HybridResult -Success $true -Message "User '$Identity' moved to '$TargetPath'."
}
#endregion

Export-ModuleMember -Function @(
    'Initialize-HybridActiveDirectoryProvider',
    'Initialize-HybridActiveDirectoryRuntime',
    'Test-HybridActiveDirectoryProviderAvailable',
    'Get-HybridADProviderHealth',
    'Test-HybridADProviderCapability',
    'Get-HybridADProviderCapabilities',
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
    'ConvertTo-HybridADUser',
    'Clear-HybridADProviderCache'
)
