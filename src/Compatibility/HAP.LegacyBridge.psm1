Set-StrictMode -Version Latest

$script:HapLegacyBridgeVersion = '0.1.0'

function Resolve-HapLegacyBridgeRoot {
    [CmdletBinding()]
    param([string]$RepositoryRoot = '')

    if (-not [string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return (Resolve-Path -LiteralPath $RepositoryRoot -ErrorAction Stop).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..') -ErrorAction Stop).Path
}

function Import-HapLegacyBridgeModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RepositoryRoot,
        [Parameter(Mandatory=$true)][string]$RelativePath
    )

    $modulePath = Join-Path $RepositoryRoot $RelativePath
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

function New-HapLegacyBridgeEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$CorrelationId,
        [Parameter(Mandatory=$true)][string]$Operation,
        [Parameter(Mandatory=$true)][bool]$Succeeded,
        [AllowNull()][object]$Data = $null,
        [object[]]$Warnings = @(),
        [object[]]$Errors = @(),
        [string]$Status = ''
    )

    if ([string]::IsNullOrWhiteSpace($Status)) {
        $Status = if ($Succeeded) { 'Completed' } else { 'Failed' }
    }

    [pscustomobject]@{
        ProtocolVersion = '1.0'
        BridgeVersion = $script:HapLegacyBridgeVersion
        CorrelationId = $CorrelationId
        Operation = $Operation
        Succeeded = $Succeeded
        Status = $Status
        Data = $Data
        Warnings = @($Warnings)
        Errors = @($Errors)
    }
}

function New-HapLegacyBridgeError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Target = '',
        [string]$DiagnosticDetail = ''
    )

    [pscustomobject]@{
        Code = $Code
        Message = $Message
        Target = $Target
        DiagnosticDetail = $DiagnosticDetail
    }
}

function ConvertTo-HapRuntimeProfileSummaryDto {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Profile)

    [pscustomobject]@{
        Name = [string]$Profile.Name
        ProfileName = [string]$Profile.ProfileName
        FolderName = [string]$Profile.FolderName
        FileName = [string]$Profile.FileName
        Path = [string]$Profile.Path
        ProfileRoot = [string]$Profile.ProfileRoot
        RuntimeMode = [string]$Profile.RuntimeMode
        CloudEnvironment = [string]$Profile.CloudEnvironment
        Organization = [string]$Profile.Organization
        Environment = [string]$Profile.Environment
        IsValid = [bool]$Profile.IsValid
        IsDefault = [bool]$Profile.IsDefault
        IsLastUsed = [bool]$Profile.IsLastUsed
        EnabledProviders = @($Profile.EnabledProviders | ForEach-Object { [string]$_ })
        EnabledProviderCount = [int]$Profile.EnabledProviderCount
        Warnings = @($Profile.Warnings | ForEach-Object { [string]$_ })
        ErrorMessage = [string]$Profile.ErrorMessage
        HealthLabel = [string]$Profile.HealthLabel
        BadgeText = [string]$Profile.BadgeText
    }
}

function Get-HapLegacyObjectValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory=$true)][string[]]$Names,
        [AllowNull()][object]$Default = $null
    )

    foreach ($name in $Names) {
        if ($null -eq $InputObject) { continue }
        if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($name)) {
            $value = $InputObject[$name]
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return $value }
        }
        if ($InputObject.PSObject.Properties.Name -contains $name) {
            $value = $InputObject.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return $value }
        }
    }

    return $Default
}

function ConvertTo-HapProviderHealthDto {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()][object]$ProviderRecord = $null
    )

    $health = Get-HapLegacyObjectValue -InputObject $ProviderRecord -Names @('Health') -Default $null
    [pscustomobject]@{
        Name = $Name
        Mode = [string](Get-HapLegacyObjectValue -InputObject $ProviderRecord -Names @('Mode') -Default '')
        Enabled = [bool](Get-HapLegacyObjectValue -InputObject $ProviderRecord -Names @('Enabled') -Default $false)
        Required = [bool](Get-HapLegacyObjectValue -InputObject $ProviderRecord -Names @('Required') -Default $false)
        Status = [string](Get-HapLegacyObjectValue -InputObject $ProviderRecord -Names @('Status') -Default 'Unknown')
        Message = [string](Get-HapLegacyObjectValue -InputObject $ProviderRecord -Names @('Message') -Default '')
        Available = [bool](Get-HapLegacyObjectValue -InputObject $health -Names @('Available','ProviderAvailable','Initialized') -Default $false)
        Connected = [bool](Get-HapLegacyObjectValue -InputObject $health -Names @('Connected','ProviderConnected','Available') -Default $false)
        LastError = [string](Get-HapLegacyObjectValue -InputObject $health -Names @('LastError','Error','ErrorMessage') -Default '')
    }
}

function ConvertTo-HapRuntimeSessionDto {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Runtime)

    $providerHealth = @()
    if ($null -ne $Runtime.ProviderRegistry) {
        foreach ($providerName in @($Runtime.ProviderRegistry.Keys | Sort-Object)) {
            $providerHealth += ConvertTo-HapProviderHealthDto -Name ([string]$providerName) -ProviderRecord $Runtime.ProviderRegistry[$providerName]
        }
    }

    [pscustomobject]@{
        ProfileName = [string](Get-HapLegacyObjectValue -InputObject $Runtime.Profile -Names @('ProfileName','Name') -Default '')
        RuntimeMode = [string](Get-HapLegacyObjectValue -InputObject $Runtime -Names @('RuntimeMode','Mode') -Default '')
        CloudEnvironment = [string](Get-HapLegacyObjectValue -InputObject $Runtime -Names @('CloudEnvironment','Cloud') -Default '')
        InitializedUtc = [string](Get-HapLegacyObjectValue -InputObject $Runtime -Names @('InitializedUtc') -Default '')
        DurationMs = [int](Get-HapLegacyObjectValue -InputObject $Runtime -Names @('DurationMs') -Default 0)
        OverallStatus = [string](Get-HapLegacyObjectValue -InputObject $Runtime.Diagnostics -Names @('OverallStatus','Status') -Default 'Unknown')
        HasErrors = [bool](Get-HapLegacyObjectValue -InputObject $Runtime.Diagnostics -Names @('HasErrors') -Default $false)
        HasWarnings = [bool](Get-HapLegacyObjectValue -InputObject $Runtime.Diagnostics -Names @('HasWarnings') -Default $false)
        ProviderHealth = $providerHealth
    }
}

function Get-HapRuntimeProfiles {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot = '',
        [string]$CorrelationId = ''
    )

    $operation = 'Get-HapRuntimeProfiles'
    if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = [guid]::NewGuid().ToString('N') }

    try {
        $root = Resolve-HapLegacyBridgeRoot -RepositoryRoot $RepositoryRoot
        Import-HapLegacyBridgeModule -RepositoryRoot $root -RelativePath 'src\Application\Application.RuntimeProfileManager.psm1'
        $profiles = @(Get-HybridRuntimeProfileSummary -RepositoryRoot $root | ForEach-Object { ConvertTo-HapRuntimeProfileSummaryDto -Profile $_ })

        return New-HapLegacyBridgeEnvelope -CorrelationId $CorrelationId -Operation $operation -Succeeded $true -Data ([pscustomobject]@{
            RepositoryRoot = $root
            Profiles = $profiles
        })
    }
    catch {
        $errorRecord = New-HapLegacyBridgeError -Code 'LegacyBridge.GetRuntimeProfilesFailed' -Message 'Failed to get runtime profiles from the legacy bridge.' -DiagnosticDetail $_.Exception.Message
        return New-HapLegacyBridgeEnvelope -CorrelationId $CorrelationId -Operation $operation -Succeeded $false -Errors @($errorRecord)
    }
}

function Start-HapRuntimeSession {
    [CmdletBinding(DefaultParameterSetName='ByName')]
    param(
        [string]$RepositoryRoot = '',
        [Parameter(ParameterSetName='ByName')][string]$ProfileName = 'Simulation',
        [Parameter(ParameterSetName='ByPath')][string]$ProfilePath,
        [string]$CorrelationId = ''
    )

    $operation = 'Start-HapRuntimeSession'
    if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = [guid]::NewGuid().ToString('N') }

    try {
        $root = Resolve-HapLegacyBridgeRoot -RepositoryRoot $RepositoryRoot
        Import-HapLegacyBridgeModule -RepositoryRoot $root -RelativePath 'src\Core\Core.Runtime.psm1'
        $runtime = if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
            Initialize-HybridRuntime -RootPath $root -ProfilePath $ProfilePath -Force
        }
        else {
            Initialize-HybridRuntime -RootPath $root -ProfileName $ProfileName -Force
        }

        return New-HapLegacyBridgeEnvelope -CorrelationId $CorrelationId -Operation $operation -Succeeded $true -Data (ConvertTo-HapRuntimeSessionDto -Runtime $runtime)
    }
    catch {
        $errorRecord = New-HapLegacyBridgeError -Code 'LegacyBridge.StartRuntimeSessionFailed' -Message 'Failed to start runtime session from the legacy bridge.' -DiagnosticDetail $_.Exception.Message
        return New-HapLegacyBridgeEnvelope -CorrelationId $CorrelationId -Operation $operation -Succeeded $false -Errors @($errorRecord)
    }
}

function Stop-HapRuntimeSession {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot = '',
        [string]$CorrelationId = ''
    )

    $operation = 'Stop-HapRuntimeSession'
    if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = [guid]::NewGuid().ToString('N') }

    try {
        $root = Resolve-HapLegacyBridgeRoot -RepositoryRoot $RepositoryRoot
        Import-HapLegacyBridgeModule -RepositoryRoot $root -RelativePath 'src\Core\Core.Runtime.psm1'
        Reset-HybridRuntime | Out-Null
        return New-HapLegacyBridgeEnvelope -CorrelationId $CorrelationId -Operation $operation -Succeeded $true -Data ([pscustomobject]@{
            Shutdown = $true
            RepositoryRoot = $root
        })
    }
    catch {
        $errorRecord = New-HapLegacyBridgeError -Code 'LegacyBridge.StopRuntimeSessionFailed' -Message 'Failed to stop runtime session from the legacy bridge.' -DiagnosticDetail $_.Exception.Message
        return New-HapLegacyBridgeEnvelope -CorrelationId $CorrelationId -Operation $operation -Succeeded $false -Errors @($errorRecord)
    }
}

Export-ModuleMember -Function Get-HapRuntimeProfiles, Start-HapRuntimeSession, Stop-HapRuntimeSession
