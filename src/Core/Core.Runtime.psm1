#region Module Information
# Name: Core.Runtime
# Purpose: Runtime bootstrap engine for profile-driven Hybrid Admin Console startup.
# Dependencies: Core.RuntimeProfile, Core.ServiceRegistry, provider/application modules loaded on demand.
# Exports: Initialize-HybridRuntime, Get-HybridRuntime, Reset-HybridRuntime, Get-HybridRuntimeProviderRegistration, Get-HybridRuntimeProviderModeSummary, Get-HybridRuntimeDiagnostics, Test-HybridRuntimeDiagnostics
#endregion

Set-StrictMode -Version Latest

$script:HybridRuntimeState = @{
    Runtime = $null
}

function New-HybridRuntimeTypedObject {
    param(
        [Parameter(Mandatory=$true)][string]$TypeName,
        [Parameter(Mandatory=$true)][hashtable]$Properties
    )

    $object = [pscustomobject]$Properties
    if ($object.PSObject.TypeNames[0] -ne $TypeName) {
        $object.PSObject.TypeNames.Insert(0, $TypeName)
    }
    if ($object.PSObject.Properties.Name -notcontains 'PSTypeName') {
        $object | Add-Member -MemberType NoteProperty -Name PSTypeName -Value $TypeName -Force
    }
    else { $object.PSTypeName = $TypeName }
    return $object
}

function Add-HybridRuntimeMember {
    param(
        [Parameter(Mandatory=$true)][object]$InputObject,
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()][object]$Value
    )

    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        try {
            $InputObject.$Name = $Value
        }
        catch [System.ArgumentException] {
            $InputObject.PSObject.Properties.Remove($Name)
            $InputObject | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
        }
    }
    else { $InputObject | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force }
}

function Resolve-HybridRuntimeRootPath {
    param([string]$RootPath = '')

    if (-not [string]::IsNullOrWhiteSpace($RootPath)) { return (Resolve-Path -LiteralPath $RootPath).Path }
    return (Get-Location).Path
}

function Import-HybridRuntimeModule {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)][string]$RelativePath,
        [switch]$Required
    )

    $path = Join-Path $RootPath $RelativePath
    if (Test-Path -LiteralPath $path) {
        Import-Module $path -Force -Global -ErrorAction Stop
        return $true
    }
    if ($Required) { throw "Required runtime module '$RelativePath' was not found." }
    return $false
}

function Write-HybridRuntimeLog {
    param(
        [string]$Level = 'Information',
        [string]$Message,
        $Exception
    )

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        if ($PSBoundParameters.ContainsKey('Exception')) {
            Write-HybridLog -Level $Level -Module 'Core.Runtime' -Message $Message -Exception $Exception | Out-Null
        }
        else {
            Write-HybridLog -Level $Level -Module 'Core.Runtime' -Message $Message | Out-Null
        }
    }
}


function Write-HybridRuntimePersistentDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [string]$Level = 'Information',
        [string]$Message = '',
        [AllowNull()][object]$Data = $null
    )

    try {
        $logRoot = Join-Path $RootPath 'logs'
        if (-not (Test-Path -LiteralPath $logRoot)) { New-Item -Path $logRoot -ItemType Directory -Force | Out-Null }
        $logPath = Join-Path $logRoot 'runtime-diagnostics.log'
        $entry = [ordered]@{
            TimestampUtc = ([datetime]::UtcNow.ToString('o'))
            Level = $Level
            Component = 'Core.Runtime'
            Message = $Message
            Data = $Data
        }
        ($entry | ConvertTo-Json -Depth 10 -Compress) | Add-Content -LiteralPath $logPath -Encoding UTF8
    }
    catch { }
}

function New-HybridRuntimeBootstrapRecord {
    param(
        [string]$Name,
        [string]$Kind,
        [string]$Status = 'Pending',
        [string]$Message = ''
    )

    New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeBootstrapRecord' -Properties @{
        Name = $Name
        Kind = $Kind
        Status = $Status
        Message = $Message
        TimestampUtc = [datetime]::UtcNow
    }
}


function New-HybridRuntimeDiagnosticCheck {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Category = 'General',
        [string]$Target = '',
        [string]$Severity = 'Info',
        [string]$Status = 'Passed',
        [string]$Message = '',
        [hashtable]$Data = @{}
    )

    New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeDiagnosticCheck' -Properties @{
        Name = $Name
        Category = $Category
        Target = $Target
        Severity = $Severity
        Status = $Status
        Message = $Message
        Data = $Data
        TimestampUtc = [datetime]::UtcNow
    }
}

function New-HybridRuntimeDiagnosticSummary {
    param([Parameter(Mandatory=$true)][object[]]$Checks)

    $errorCount = @($Checks | Where-Object { [string]$_.Severity -eq 'Error' -or [string]$_.Status -eq 'Failed' }).Count
    $warningCount = @($Checks | Where-Object { [string]$_.Severity -eq 'Warning' -and [string]$_.Status -ne 'Failed' }).Count
    $passedCount = @($Checks | Where-Object { [string]$_.Status -eq 'Passed' }).Count
    $deferredCount = @($Checks | Where-Object { [string]$_.Status -eq 'Deferred' }).Count
    $skippedCount = @($Checks | Where-Object { [string]$_.Status -eq 'Skipped' }).Count

    $overallStatus = 'Healthy'
    if ($errorCount -gt 0) { $overallStatus = 'Failed' }
    elseif ($warningCount -gt 0 -or $deferredCount -gt 0) { $overallStatus = 'Warning' }

    New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeDiagnosticSummary' -Properties @{
        OverallStatus = $overallStatus
        TotalChecks = @($Checks).Count
        Passed = $passedCount
        Warnings = $warningCount
        Errors = $errorCount
        Deferred = $deferredCount
        Skipped = $skippedCount
        HasErrors = ($errorCount -gt 0)
        HasWarnings = ($warningCount -gt 0 -or $deferredCount -gt 0)
        CreatedUtc = [datetime]::UtcNow
    }
}

function Invoke-HybridRuntimeDiagnosticsInternal {
    param([Parameter(Mandatory=$true)][object]$Runtime)

    $checks = New-Object System.Collections.Generic.List[object]

    if ($null -ne $Runtime.Profile) {
        $checks.Add((New-HybridRuntimeDiagnosticCheck -Name 'RuntimeProfileLoaded' -Category 'Profile' -Target ([string]$Runtime.Profile.ProfileName) -Severity 'Info' -Status 'Passed' -Message 'Runtime profile loaded successfully.')) | Out-Null
    }
    else {
        $checks.Add((New-HybridRuntimeDiagnosticCheck -Name 'RuntimeProfileLoaded' -Category 'Profile' -Target 'RuntimeProfile' -Severity 'Error' -Status 'Failed' -Message 'Runtime profile was not loaded.')) | Out-Null
    }

    if (@('Simulation','Live','Hybrid') -contains [string]$Runtime.RuntimeMode) {
        $checks.Add((New-HybridRuntimeDiagnosticCheck -Name 'RuntimeModeSupported' -Category 'Core' -Target ([string]$Runtime.RuntimeMode) -Severity 'Info' -Status 'Passed' -Message 'Runtime mode is supported.')) | Out-Null
    }
    else {
        $checks.Add((New-HybridRuntimeDiagnosticCheck -Name 'RuntimeModeSupported' -Category 'Core' -Target ([string]$Runtime.RuntimeMode) -Severity 'Error' -Status 'Failed' -Message 'Runtime mode is not supported.')) | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Runtime.CloudEnvironment)) {
        $checks.Add((New-HybridRuntimeDiagnosticCheck -Name 'CloudEnvironmentDeclared' -Category 'Profile' -Target ([string]$Runtime.CloudEnvironment) -Severity 'Info' -Status 'Passed' -Message 'Runtime cloud environment is declared.')) | Out-Null
    }
    else {
        $checks.Add((New-HybridRuntimeDiagnosticCheck -Name 'CloudEnvironmentDeclared' -Category 'Profile' -Target 'CloudEnvironment' -Severity 'Warning' -Status 'Skipped' -Message 'Runtime cloud environment is not declared.')) | Out-Null
    }

    $authStatus = 'Deferred'
    if ($null -ne $Runtime.Authentication -and $Runtime.Authentication.ContainsKey('Status')) { $authStatus = [string]$Runtime.Authentication.Status }
    $checks.Add((New-HybridRuntimeDiagnosticCheck -Name 'AuthenticationBootstrap' -Category 'Authentication' -Target 'Authentication' -Severity 'Info' -Status $authStatus -Message 'Authentication remains deferred during runtime bootstrap.')) | Out-Null

    foreach ($providerName in @($Runtime.ProviderRegistry.Keys | Sort-Object)) {
        $provider = $Runtime.ProviderRegistry[$providerName]
        $severity = 'Info'
        $status = [string]$provider.Status
        $message = [string]$provider.Message
        if ($status -eq 'Failed') { $severity = 'Error' }
        elseif ($status -eq 'Deferred') { $severity = 'Warning' }
        elseif ($status -eq 'Skipped') { $severity = 'Info' }
        if ([string]::IsNullOrWhiteSpace($message)) { $message = "Provider $providerName has status $status." }
        $checks.Add((New-HybridRuntimeDiagnosticCheck -Name 'ProviderRegistration' -Category 'Provider' -Target $providerName -Severity $severity -Status $status -Message $message -Data @{ Mode = [string]$provider.Mode; Required = [bool]$provider.Required; Authentication = [string]$provider.Authentication })) | Out-Null
    }

    foreach ($serviceName in @('HybridUser','GraphProfile','AuthenticationProfile','UserAggregation')) {
        if ($Runtime.ServiceRegistry.ContainsKey($serviceName) -and $null -ne $Runtime.ServiceRegistry[$serviceName]) {
            $checks.Add((New-HybridRuntimeDiagnosticCheck -Name 'ServiceRegistration' -Category 'Service' -Target $serviceName -Severity 'Info' -Status 'Passed' -Message "Application service '$serviceName' is registered.")) | Out-Null
        }
        else {
            $checks.Add((New-HybridRuntimeDiagnosticCheck -Name 'ServiceRegistration' -Category 'Service' -Target $serviceName -Severity 'Error' -Status 'Failed' -Message "Application service '$serviceName' is not registered.")) | Out-Null
        }
    }

    $checkArray = [object[]]$checks.ToArray()
    $summary = New-HybridRuntimeDiagnosticSummary -Checks $checkArray
    $report = New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeDiagnosticReport' -Properties @{
        OverallStatus = $summary.OverallStatus
        Summary = $summary
        Checks = $checkArray
        HasErrors = $summary.HasErrors
        HasWarnings = $summary.HasWarnings
        GeneratedUtc = [datetime]::UtcNow
    }

    return $report
}


function Register-HybridRuntimeProviderRecord {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Registry,
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Mode = 'Disabled',
        [bool]$Enabled = $false,
        [bool]$Required = $false,
        [string]$Authentication = 'None',
        [string]$Status = 'Skipped',
        [AllowNull()][object]$Service = $null,
        [string]$Message = ''
    )

    $record = New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeProviderRegistration' -Properties @{
        Name = $Name
        Mode = $Mode
        Enabled = $Enabled
        Required = $Required
        Authentication = $Authentication
        Status = $Status
        Service = $Service
        Message = $Message
        RegisteredUtc = [datetime]::UtcNow
    }
    $Registry[$Name] = $record
    return $record
}


function New-HybridRuntimeProviderModeSummary {
    param([Parameter(Mandatory=$true)][hashtable]$ProviderRegistry)

    $modes = @{}
    $liveProviders = New-Object System.Collections.Generic.List[string]
    $simulationProviders = New-Object System.Collections.Generic.List[string]
    $disabledProviders = New-Object System.Collections.Generic.List[string]
    $deferredProviders = New-Object System.Collections.Generic.List[string]
    $initializedProviders = New-Object System.Collections.Generic.List[string]

    foreach ($name in @($ProviderRegistry.Keys | Sort-Object)) {
        $registration = $ProviderRegistry[$name]
        $mode = [string]$registration.Mode
        $status = [string]$registration.Status
        $modes[$name] = $mode
        if ($mode -eq 'Live') { $liveProviders.Add($name) | Out-Null }
        elseif ($mode -eq 'Simulation') { $simulationProviders.Add($name) | Out-Null }
        elseif ($mode -eq 'Disabled') { $disabledProviders.Add($name) | Out-Null }
        if ($status -eq 'Deferred') { $deferredProviders.Add($name) | Out-Null }
        if ($status -eq 'Initialized') { $initializedProviders.Add($name) | Out-Null }
    }

    return New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeProviderModeSummary' -Properties @{
        Modes = $modes
        LiveProviders = [string[]]$liveProviders.ToArray()
        SimulationProviders = [string[]]$simulationProviders.ToArray()
        DisabledProviders = [string[]]$disabledProviders.ToArray()
        DeferredProviders = [string[]]$deferredProviders.ToArray()
        InitializedProviders = [string[]]$initializedProviders.ToArray()
        CreatedUtc = [datetime]::UtcNow
    }
}

function Get-HybridRuntimeProviderSettingsByName {
    param(
        [Parameter(Mandatory=$true)][object[]]$Providers,
        [Parameter(Mandatory=$true)][string]$Name
    )

    return @($Providers | Where-Object { [string]$_.Name -eq $Name } | Select-Object -First 1)
}

function Initialize-HybridRuntimeProviderFromSimulator {
    param(
        [Parameter(Mandatory=$true)][hashtable]$ProviderRegistry,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][object]$ProviderSettings,
        [AllowNull()][object]$Service,
        [Parameter(Mandatory=$true)][System.Collections.Generic.List[object]]$Records,
        [string]$Message = ''
    )

    if ([string]::IsNullOrWhiteSpace($Message)) { $Message = "Simulation $Name provider registered." }
    Register-HybridRuntimeProviderRecord -Registry $ProviderRegistry -Name $Name -Mode 'Simulation' -Enabled $true -Required ([bool]$ProviderSettings.Required) -Authentication ([string]$ProviderSettings.Authentication) -Status 'Initialized' -Service $Service -Message $Message | Out-Null
    $Records.Add((New-HybridRuntimeBootstrapRecord -Name $Name -Kind 'Provider' -Status 'Initialized' -Message $Message)) | Out-Null
}

function Initialize-HybridRuntimeServiceRegistry {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)][object]$Context
    )

    Import-HybridRuntimeModule -RootPath $RootPath -RelativePath 'src\Core\Core.ServiceRegistry.psm1' -Required | Out-Null
    Initialize-HybridServiceRegistry -Context $Context | Out-Null
}

function Initialize-HybridRuntimeProfileInternal {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [string]$ProfileName = 'Simulation',
        [string]$ProfilePath = '',
        [Parameter(Mandatory=$true)][object]$Context
    )

    Import-HybridRuntimeModule -RootPath $RootPath -RelativePath 'src\Core\Core.RuntimeProfile.psm1' -Required | Out-Null
    if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
        return Initialize-HybridRuntimeProfile -Name $ProfileName -RootPath $RootPath -Context $Context
    }
    return Initialize-HybridRuntimeProfile -Path $ProfilePath -RootPath $RootPath -Context $Context
}

function Initialize-HybridRuntimeSimulationProviders {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)][hashtable]$ProviderRegistry,
        [Parameter(Mandatory=$true)][object]$ProviderSettings,
        [Parameter(Mandatory=$true)][object[]]$ProfileProviders,
        [Parameter(Mandatory=$true)][string]$RuntimeMode,
        [Parameter(Mandatory=$true)][System.Collections.Generic.List[object]]$Records
    )

    Import-HybridRuntimeModule -RootPath $RootPath -RelativePath 'src\Infrastructure\Mock\Infrastructure.DirectorySimulator.psm1' -Required | Out-Null
    $simulator = New-HybridDirectorySimulator
    $providers = $simulator.Providers

    Register-HybridRuntimeProviderRecord -Registry $ProviderRegistry -Name 'DirectorySimulator' -Mode 'Simulation' -Enabled $true -Required ([bool]$ProviderSettings.Required) -Authentication ([string]$ProviderSettings.Authentication) -Status 'Initialized' -Service $providers -Message 'Directory Simulator initialized.' | Out-Null
    $Records.Add((New-HybridRuntimeBootstrapRecord -Name 'DirectorySimulator' -Kind 'Provider' -Status 'Initialized' -Message 'Directory Simulator providers created.')) | Out-Null

    $logicalProviders = @('ActiveDirectory','MicrosoftGraph','ExchangeOnline')
    foreach ($logicalProviderName in $logicalProviders) {
        if ($ProviderRegistry.ContainsKey($logicalProviderName)) { continue }
        $logicalSettings = @(Get-HybridRuntimeProviderSettingsByName -Providers $ProfileProviders -Name $logicalProviderName)
        $shouldRegisterSimulationProvider = $false

        if ([string]$RuntimeMode -eq 'Simulation') {
            # Backward-compatible Phase 2 behavior: a pure simulation profile exposes all existing simulator-backed vertical providers.
            $shouldRegisterSimulationProvider = $true
        }
        elseif ($logicalSettings.Count -gt 0 -and [bool]$logicalSettings[0].Enabled -and [string]$logicalSettings[0].Mode -eq 'Simulation') {
            $shouldRegisterSimulationProvider = $true
        }

        if ($shouldRegisterSimulationProvider) {
            $settings = if ($logicalSettings.Count -gt 0) { $logicalSettings[0] } else { $ProviderSettings }
            $service = $null
            if ($logicalProviderName -eq 'ActiveDirectory') { $service = $providers.ActiveDirectory }
            elseif ($logicalProviderName -eq 'MicrosoftGraph') { $service = $providers.MicrosoftGraph }
            elseif ($logicalProviderName -eq 'ExchangeOnline') { $service = $providers.ExchangeOnline }
            Initialize-HybridRuntimeProviderFromSimulator -ProviderRegistry $ProviderRegistry -Name $logicalProviderName -ProviderSettings $settings -Service $service -Records $Records -Message "Simulation $logicalProviderName provider registered."
        }
    }

    return $providers
}


function Initialize-HybridRuntimeLiveActiveDirectoryProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)][hashtable]$ProviderRegistry,
        [Parameter(Mandatory=$true)][object]$ProviderSettings,
        [Parameter(Mandatory=$true)][object]$Context,
        [Parameter(Mandatory=$true)][System.Collections.Generic.List[object]]$Records
    )

    $providerName = [string]$ProviderSettings.Name
    $diagnosticPath = Join-Path (Join-Path $RootPath 'logs') 'ad-runtime-diagnostics.log'
    try {
        Import-HybridRuntimeModule -RootPath $RootPath -RelativePath 'src\Core\Core.ProviderBase.psm1' -Required | Out-Null
        Import-HybridRuntimeModule -RootPath $RootPath -RelativePath 'src\Domain\Hybrid.Models.psm1' -Required | Out-Null
        Import-HybridRuntimeModule -RootPath $RootPath -RelativePath 'src\Infrastructure\Infrastructure.ActiveDirectory.psm1' -Required | Out-Null

        $service = Initialize-HybridActiveDirectoryProvider -Context $Context -RuntimeDiagnosticsPath $diagnosticPath
        $health = $null
        if ($null -ne $service) {
            $health = @(& $service.GetHealth | Select-Object -First 1)
        }
        if ($health -is [array]) { $health = $health | Select-Object -First 1 }

        $status = 'Unavailable'
        $message = 'Active Directory provider initialized, but live connectivity is unavailable. Review logs\ad-runtime-diagnostics.log.'
        if ($null -ne $health -and [bool]$health.Available -and [bool]$health.Connected) {
            $status = 'Connected'
            $message = 'Active Directory provider connected using the current HAP runtime session.'
        }
        elseif ($null -ne $health -and $health.PSObject.Properties.Name -contains 'LastError' -and -not [string]::IsNullOrWhiteSpace([string]$health.LastError)) {
            $message = 'Active Directory provider unavailable: ' + [string]$health.LastError
        }

        Register-HybridRuntimeProviderRecord -Registry $ProviderRegistry -Name $providerName -Mode ([string]$ProviderSettings.Mode) -Enabled ([bool]$ProviderSettings.Enabled) -Required ([bool]$ProviderSettings.Required) -Authentication ([string]$ProviderSettings.Authentication) -Status $status -Service $service -Message $message | Out-Null
        $Records.Add((New-HybridRuntimeBootstrapRecord -Name $providerName -Kind 'Provider' -Status $status -Message $message)) | Out-Null
        Write-HybridRuntimePersistentDiagnostic -RootPath $RootPath -Level $(if ($status -eq 'Connected') { 'Information' } else { 'Warning' }) -Message 'Live Active Directory runtime binding completed.' -Data @{ Status = $status; Message = $message; Health = $health }
    }
    catch {
        $message = 'Active Directory provider failed during runtime binding: ' + $_.Exception.Message
        Register-HybridRuntimeProviderRecord -Registry $ProviderRegistry -Name $providerName -Mode ([string]$ProviderSettings.Mode) -Enabled ([bool]$ProviderSettings.Enabled) -Required ([bool]$ProviderSettings.Required) -Authentication ([string]$ProviderSettings.Authentication) -Status 'Failed' -Service $null -Message $message | Out-Null
        $Records.Add((New-HybridRuntimeBootstrapRecord -Name $providerName -Kind 'Provider' -Status 'Failed' -Message $message)) | Out-Null
        Write-HybridRuntimePersistentDiagnostic -RootPath $RootPath -Level Error -Message $message -Data @{ Error = $_.Exception.Message; Provider = $providerName }
    }
}

function Register-HybridRuntimeDeferredProvider {
    param(
        [Parameter(Mandatory=$true)][hashtable]$ProviderRegistry,
        [Parameter(Mandatory=$true)][object]$ProviderSettings,
        [Parameter(Mandatory=$true)][System.Collections.Generic.List[object]]$Records
    )

    $message = 'Provider registration deferred. Runtime bootstrap does not perform live authentication or connectivity checks.'
    Register-HybridRuntimeProviderRecord -Registry $ProviderRegistry -Name ([string]$ProviderSettings.Name) -Mode ([string]$ProviderSettings.Mode) -Enabled ([bool]$ProviderSettings.Enabled) -Required ([bool]$ProviderSettings.Required) -Authentication ([string]$ProviderSettings.Authentication) -Status 'Deferred' -Service $null -Message $message | Out-Null
    $Records.Add((New-HybridRuntimeBootstrapRecord -Name ([string]$ProviderSettings.Name) -Kind 'Provider' -Status 'Deferred' -Message $message)) | Out-Null
}

function Initialize-HybridRuntimeApplicationServices {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)][hashtable]$ProviderRegistry,
        [Parameter(Mandatory=$true)][hashtable]$ServiceRegistry,
        [Parameter(Mandatory=$true)][System.Collections.Generic.List[object]]$Records
    )

    Import-HybridRuntimeModule -RootPath $RootPath -RelativePath 'src\Application\Application.HybridUserService.psm1' -Required | Out-Null
    Import-HybridRuntimeModule -RootPath $RootPath -RelativePath 'src\Application\Application.GraphProfileService.psm1' -Required | Out-Null
    Import-HybridRuntimeModule -RootPath $RootPath -RelativePath 'src\Application\Application.AuthenticationProfileService.psm1' -Required | Out-Null
    Import-HybridRuntimeModule -RootPath $RootPath -RelativePath 'src\Application\Application.HybridUserAggregationService.psm1' -Required | Out-Null

    $adProvider = $null
    $graphProvider = $null
    $exchangeProvider = $null
    if ($ProviderRegistry.ContainsKey('ActiveDirectory')) { $adProvider = $ProviderRegistry['ActiveDirectory'].Service }
    if ($ProviderRegistry.ContainsKey('MicrosoftGraph')) { $graphProvider = $ProviderRegistry['MicrosoftGraph'].Service }
    if ($ProviderRegistry.ContainsKey('ExchangeOnline')) { $exchangeProvider = $ProviderRegistry['ExchangeOnline'].Service }

    $userService = Initialize-HybridUserService -ActiveDirectoryProvider $adProvider -MicrosoftGraphProvider $graphProvider -ExchangeOnlineProvider $exchangeProvider
    Register-HybridService -Name 'HybridUser' -Instance $userService -Description 'Unified hybrid user application service.' -Provider 'Application' -Force | Out-Null

    $graphService = Initialize-HybridGraphProfileService -MicrosoftGraphProvider $graphProvider
    Register-HybridService -Name 'GraphProfile' -Instance $graphService -Description 'Microsoft Graph profile application service.' -Provider 'Application' -Force | Out-Null

    $authService = Initialize-HybridAuthenticationProfileService -MicrosoftGraphProvider $graphProvider
    Register-HybridService -Name 'AuthenticationProfile' -Instance $authService -Description 'Authentication posture application service.' -Provider 'Application' -Force | Out-Null

    $aggregationService = Initialize-HybridUserAggregationService
    Register-HybridService -Name 'UserAggregation' -Instance $aggregationService -Description 'Hybrid user aggregation application service.' -Provider 'Application' -Force | Out-Null

    $ServiceRegistry['HybridUser'] = $userService
    $ServiceRegistry['GraphProfile'] = $graphService
    $ServiceRegistry['AuthenticationProfile'] = $authService
    $ServiceRegistry['UserAggregation'] = $aggregationService

    $Records.Add((New-HybridRuntimeBootstrapRecord -Name 'ApplicationServices' -Kind 'Service' -Status 'Initialized' -Message 'Application services initialized in dependency order.')) | Out-Null
}

function Initialize-HybridRuntime {
    [CmdletBinding(DefaultParameterSetName='ByName')]
    param(
        [Parameter(ParameterSetName='ByName')][string]$ProfileName = 'Simulation',
        [Parameter(ParameterSetName='ByPath')][string]$ProfilePath,
        [string]$RootPath = '',
        [switch]$Force
    )

    if ($null -ne $script:HybridRuntimeState.Runtime -and -not $Force) {
        return $script:HybridRuntimeState.Runtime
    }

    if ($Force) { Reset-HybridRuntime | Out-Null }

    $started = Get-Date
    $resolvedRoot = Resolve-HybridRuntimeRootPath -RootPath $RootPath
    $records = New-Object System.Collections.Generic.List[object]
    $providerRegistry = @{}
    $serviceRegistry = @{}
    $diagnostics = New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeDiagnostics' -Properties @{
        Status = 'Initializing'
        OverallStatus = 'Initializing'
        Summary = $null
        Checks = $null
        Records = $null
        Errors = $null
        HasErrors = $false
        HasWarnings = $false
    }

    $context = New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeContext' -Properties @{
        Version = 'v0.8.5'
        RootPath = $resolvedRoot
        Paths = @{ Root = $resolvedRoot }
        Profile = $null
        RuntimeProfile = $null
        RuntimeMode = ''
        Mode = ''
        CloudEnvironment = ''
        Authentication = @{ Initialized = $false; Status = 'Deferred'; Message = 'Authentication is not invoked during runtime bootstrap.' }
        ProviderRegistry = $providerRegistry
        Providers = $providerRegistry
        ServiceRegistry = $serviceRegistry
        Services = $serviceRegistry
        Diagnostics = $diagnostics
        BootstrapPlan = $null
        StartupTime = $started
        StartupTimeUtc = [datetime]::UtcNow
        InitializedUtc = $null
        DurationMs = 0
        IsSimulation = $false
        ProviderModes = $null
    }

    try {
        Initialize-HybridRuntimeServiceRegistry -RootPath $resolvedRoot -Context $context
        $records.Add((New-HybridRuntimeBootstrapRecord -Name 'ServiceRegistry' -Kind 'Core' -Status 'Initialized' -Message 'Core service registry initialized.')) | Out-Null

        $profile = if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
            Initialize-HybridRuntimeProfileInternal -RootPath $resolvedRoot -ProfilePath $ProfilePath -Context $context
        }
        else {
            Initialize-HybridRuntimeProfileInternal -RootPath $resolvedRoot -ProfileName $ProfileName -Context $context
        }
        $plan = New-HybridRuntimeBootstrapPlan -Profile $profile

        Add-HybridRuntimeMember -InputObject $context -Name Profile -Value $profile
        Add-HybridRuntimeMember -InputObject $context -Name RuntimeProfile -Value $profile
        Add-HybridRuntimeMember -InputObject $context -Name RuntimeMode -Value ([string]$profile.Mode)
        Add-HybridRuntimeMember -InputObject $context -Name Mode -Value ([string]$profile.Mode)
        Add-HybridRuntimeMember -InputObject $context -Name CloudEnvironment -Value ([string]$profile.Cloud)
        Add-HybridRuntimeMember -InputObject $context -Name BootstrapPlan -Value $plan
        Add-HybridRuntimeMember -InputObject $context -Name IsSimulation -Value ([string]$profile.Mode -eq 'Simulation')
        $records.Add((New-HybridRuntimeBootstrapRecord -Name 'RuntimeProfile' -Kind 'Core' -Status 'Loaded' -Message "Runtime profile '$($profile.ProfileName)' loaded.")) | Out-Null

        foreach ($provider in @($profile.Providers)) {
            if (-not [bool]$provider.Enabled) {
                if ($providerRegistry.ContainsKey([string]$provider.Name)) { continue }
                Register-HybridRuntimeProviderRecord -Registry $providerRegistry -Name ([string]$provider.Name) -Mode 'Disabled' -Enabled $false -Required ([bool]$provider.Required) -Authentication ([string]$provider.Authentication) -Status 'Skipped' -Service $null -Message 'Provider disabled by runtime profile.' | Out-Null
                continue
            }

            if ($providerRegistry.ContainsKey([string]$provider.Name)) { continue }

            if ([string]$provider.Name -eq 'DirectorySimulator' -and [string]$provider.Mode -eq 'Simulation') {
                Initialize-HybridRuntimeSimulationProviders -RootPath $resolvedRoot -ProviderRegistry $providerRegistry -ProviderSettings $provider -ProfileProviders @($profile.Providers) -RuntimeMode ([string]$profile.Mode) -Records $records | Out-Null
            }
            elseif ([string]$provider.Mode -eq 'Simulation') {
                $directorySimulatorSettings = @(Get-HybridRuntimeProviderSettingsByName -Providers @($profile.Providers) -Name 'DirectorySimulator')
                if ($directorySimulatorSettings.Count -gt 0 -and [bool]$directorySimulatorSettings[0].Enabled -and [string]$directorySimulatorSettings[0].Mode -eq 'Simulation') {
                    Initialize-HybridRuntimeSimulationProviders -RootPath $resolvedRoot -ProviderRegistry $providerRegistry -ProviderSettings $directorySimulatorSettings[0] -ProfileProviders @($profile.Providers) -RuntimeMode ([string]$profile.Mode) -Records $records | Out-Null
                }
                else {
                    Register-HybridRuntimeProviderRecord -Registry $providerRegistry -Name ([string]$provider.Name) -Mode 'Simulation' -Enabled $true -Required ([bool]$provider.Required) -Authentication ([string]$provider.Authentication) -Status 'Failed' -Service $null -Message 'Simulation provider requested but DirectorySimulator is not enabled.' | Out-Null
                    $records.Add((New-HybridRuntimeBootstrapRecord -Name ([string]$provider.Name) -Kind 'Provider' -Status 'Failed' -Message 'Simulation provider requested but DirectorySimulator is not enabled.')) | Out-Null
                }
            }
            elseif ([string]$provider.Name -eq 'ActiveDirectory' -and [string]$provider.Mode -eq 'Live') {
                Initialize-HybridRuntimeLiveActiveDirectoryProvider -RootPath $resolvedRoot -ProviderRegistry $providerRegistry -ProviderSettings $provider -Context $context -Records $records
            }
            else {
                Register-HybridRuntimeDeferredProvider -ProviderRegistry $providerRegistry -ProviderSettings $provider -Records $records
            }
        }

        Initialize-HybridRuntimeApplicationServices -RootPath $resolvedRoot -ProviderRegistry $providerRegistry -ServiceRegistry $serviceRegistry -Records $records

        $elapsed = [int]((Get-Date) - $started).TotalMilliseconds
        Add-HybridRuntimeMember -InputObject $context -Name InitializedUtc -Value ([datetime]::UtcNow)
        Add-HybridRuntimeMember -InputObject $context -Name DurationMs -Value $elapsed
        Add-HybridRuntimeMember -InputObject $context -Name ProviderModes -Value (New-HybridRuntimeProviderModeSummary -ProviderRegistry $providerRegistry)
        $diagnosticReport = Invoke-HybridRuntimeDiagnosticsInternal -Runtime $context
        $diagnostics.Status = 'Initialized'
        Add-HybridRuntimeMember -InputObject $diagnostics -Name OverallStatus -Value ([string]$diagnosticReport.OverallStatus)
        Add-HybridRuntimeMember -InputObject $diagnostics -Name Summary -Value $diagnosticReport.Summary
        Add-HybridRuntimeMember -InputObject $diagnostics -Name Checks -Value ([object[]]$diagnosticReport.Checks)
        Add-HybridRuntimeMember -InputObject $diagnostics -Name HasErrors -Value ([bool]$diagnosticReport.HasErrors)
        Add-HybridRuntimeMember -InputObject $diagnostics -Name HasWarnings -Value ([bool]$diagnosticReport.HasWarnings)
        Add-HybridRuntimeMember -InputObject $diagnostics -Name Records -Value ([object[]]$records.ToArray())
        $script:HybridRuntimeState.Runtime = $context
        Write-HybridRuntimeLog -Message "Hybrid runtime initialized with profile '$($profile.ProfileName)' in $elapsed ms."
        return $context
    }
    catch {
        $diagnostics.Status = 'Failed'
        Add-HybridRuntimeMember -InputObject $diagnostics -Name OverallStatus -Value 'Failed'
        Add-HybridRuntimeMember -InputObject $diagnostics -Name HasErrors -Value $true
        Add-HybridRuntimeMember -InputObject $diagnostics -Name Errors -Value ([object[]]@($_.Exception.Message))
        Add-HybridRuntimeMember -InputObject $diagnostics -Name Records -Value ([object[]]$records.ToArray())
        Write-HybridRuntimeLog -Level Error -Message 'Hybrid runtime initialization failed.' -Exception $_.Exception
        throw
    }
}

function Get-HybridRuntime {
    [CmdletBinding()]
    param()

    if ($null -eq $script:HybridRuntimeState.Runtime) { throw 'Hybrid runtime has not been initialized.' }
    return $script:HybridRuntimeState.Runtime
}

function Reset-HybridRuntime {
    [CmdletBinding()]
    param()

    $script:HybridRuntimeState.Runtime = $null
    return $true
}


function Get-HybridRuntimeProviderRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()][object]$Runtime = $null
    )

    if ($null -eq $Runtime) { $Runtime = Get-HybridRuntime }
    if ($null -eq $Runtime.ProviderRegistry -or -not $Runtime.ProviderRegistry.ContainsKey($Name)) {
        throw "Runtime provider '$Name' is not registered."
    }
    return $Runtime.ProviderRegistry[$Name]
}

function Get-HybridRuntimeProviderModeSummary {
    [CmdletBinding()]
    param([AllowNull()][object]$Runtime = $null)

    if ($null -eq $Runtime) { $Runtime = Get-HybridRuntime }
    if ($Runtime.PSObject.Properties.Name -contains 'ProviderModes' -and $null -ne $Runtime.ProviderModes) {
        return $Runtime.ProviderModes
    }
    return New-HybridRuntimeProviderModeSummary -ProviderRegistry $Runtime.ProviderRegistry
}


function Get-HybridRuntimeDiagnostics {
    [CmdletBinding()]
    param([AllowNull()][object]$Runtime = $null)

    if ($null -eq $Runtime) { $Runtime = Get-HybridRuntime }
    if ($null -eq $Runtime.Diagnostics) { throw 'Runtime diagnostics are not available.' }
    return $Runtime.Diagnostics
}

function Test-HybridRuntimeDiagnostics {
    [CmdletBinding()]
    param([AllowNull()][object]$Runtime = $null)

    $diagnostics = Get-HybridRuntimeDiagnostics -Runtime $Runtime
    return New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeDiagnosticResult' -Properties @{
        IsHealthy = (-not [bool]$diagnostics.HasErrors)
        OverallStatus = [string]$diagnostics.OverallStatus
        HasErrors = [bool]$diagnostics.HasErrors
        HasWarnings = [bool]$diagnostics.HasWarnings
        Summary = $diagnostics.Summary
        CheckedUtc = [datetime]::UtcNow
    }
}

Export-ModuleMember -Function Initialize-HybridRuntime, Get-HybridRuntime, Reset-HybridRuntime, Get-HybridRuntimeProviderRegistration, Get-HybridRuntimeProviderModeSummary, Get-HybridRuntimeDiagnostics, Test-HybridRuntimeDiagnostics
