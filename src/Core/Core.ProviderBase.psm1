#region Module Information
# Name: Core.ProviderBase
# Purpose: Shared provider contract helpers for the Hybrid Administration Platform.
# Dependencies: None.
# Exports: New-HybridProviderState, New-HybridProviderService, Get-HybridProviderCapabilities,
#          Test-HybridProviderCapability, Get-HybridProviderHealth, Initialize-HybridProvider,
#          Stop-HybridProvider, Invoke-HybridProviderCommand, Clear-HybridProviderCache
#endregion

Set-StrictMode -Version Latest

function New-HybridProviderState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Module,
        [string[]]$Capabilities = @(),
        [string[]]$CacheBuckets = @()
    )

    $cache = @{}
    foreach ($bucket in $CacheBuckets) { $cache[$bucket] = @{} }

    [pscustomobject]@{
        PSTypeName       = 'Hybrid.ProviderState'
        Name             = $Name
        Module           = $Module
        Initialized      = $false
        Available        = $false
        Connected        = $false
        LastError        = $null
        LastInitialized  = $null
        LastCommand      = $null
        Version          = '0.1.0'
        Capabilities     = @($Capabilities)
        CommandHistory   = @()
        Cache            = $cache
    }
}

function Initialize-HybridProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$ProviderState,
        [bool]$Available = $false,
        [bool]$Connected = $false,
        [string]$Version = ''
    )

    $ProviderState.Initialized = $true
    $ProviderState.Available = $Available
    $ProviderState.Connected = $Connected
    $ProviderState.LastInitialized = Get-Date
    if (-not [string]::IsNullOrWhiteSpace($Version)) { $ProviderState.Version = $Version }
    return $ProviderState
}

function Stop-HybridProvider {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$ProviderState)

    $ProviderState.Connected = $false
    return $ProviderState
}

function Get-HybridProviderCapabilities {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$ProviderState)

    return @($ProviderState.Capabilities)
}

function Test-HybridProviderCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$ProviderState,
        [Parameter(Mandatory=$true)][string]$Capability
    )

    return @($ProviderState.Capabilities) -contains $Capability
}

function Get-HybridProviderCacheEntryCount {
    param([Parameter(Mandatory=$true)][object]$ProviderState)

    $count = 0
    foreach ($bucket in $ProviderState.Cache.Keys) {
        $count += $ProviderState.Cache[$bucket].Count
    }
    return $count
}

function Clear-HybridProviderCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$ProviderState,
        [string]$Bucket = ''
    )

    if ([string]::IsNullOrWhiteSpace($Bucket)) {
        foreach ($key in @($ProviderState.Cache.Keys)) { $ProviderState.Cache[$key].Clear() }
    }
    elseif ($ProviderState.Cache.ContainsKey($Bucket)) {
        $ProviderState.Cache[$Bucket].Clear()
    }

    return $ProviderState
}

function Get-HybridProviderHealth {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$ProviderState)

    $lastCommand = $null
    if (@($ProviderState.CommandHistory).Count -gt 0) {
        $lastCommand = @($ProviderState.CommandHistory)[-1]
    }

    $responseTime = $null
    if ($null -ne $lastCommand -and $lastCommand.PSObject.Properties.Name -contains 'DurationMs') {
        $responseTime = $lastCommand.DurationMs
    }

    [pscustomobject]@{
        PSTypeName      = 'Hybrid.ProviderHealth'
        Name            = [string]$ProviderState.Name
        Module          = [string]$ProviderState.Module
        Initialized     = [bool]$ProviderState.Initialized
        Available       = [bool]$ProviderState.Available
        Connected       = [bool]$ProviderState.Connected
        LastError       = $ProviderState.LastError
        Version         = [string]$ProviderState.Version
        Capabilities    = @($ProviderState.Capabilities)
        CacheEntries    = Get-HybridProviderCacheEntryCount -ProviderState $ProviderState
        CommandCount    = @($ProviderState.CommandHistory).Count
        LastCommand     = $lastCommand
        ResponseTimeMs  = $responseTime
    }
}

function Invoke-HybridProviderCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$ProviderState,
        [Parameter(Mandatory=$true)][string]$CommandName,
        [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock,
        [string]$Operation = $CommandName
    )

    $started = Get-Date
    try {
        $result = & $ScriptBlock
        $elapsed = [int]((Get-Date) - $started).TotalMilliseconds
        $ProviderState.LastCommand = $Operation
        $ProviderState.CommandHistory += [pscustomobject]@{
            CommandName = $CommandName
            Operation   = $Operation
            Success     = $true
            DurationMs  = $elapsed
            Timestamp   = Get-Date
        }
        return $result
    }
    catch {
        $elapsed = [int]((Get-Date) - $started).TotalMilliseconds
        $ProviderState.LastError = $_.Exception.Message
        $ProviderState.CommandHistory += [pscustomobject]@{
            CommandName = $CommandName
            Operation   = $Operation
            Success     = $false
            DurationMs  = $elapsed
            Timestamp   = Get-Date
            Error       = $_.Exception.Message
        }
        throw
    }
}

function New-HybridProviderService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$ProviderState,
        [Parameter(Mandatory=$true)][hashtable]$Operations
    )

    $service = [ordered]@{
        PSTypeName        = 'Hybrid.ProviderService'
        ProviderName      = [string]$ProviderState.Name
        ProviderModule    = [string]$ProviderState.Module
        ProviderAvailable = [bool]$ProviderState.Available
        ProviderConnected = [bool]$ProviderState.Connected
        Capabilities      = @($ProviderState.Capabilities)
        Initialize        = ({ Initialize-HybridProvider -ProviderState $ProviderState | Out-Null }).GetNewClosure()
        Dispose           = ({ Stop-HybridProvider -ProviderState $ProviderState | Out-Null }).GetNewClosure()
        GetHealth         = ({ Get-HybridProviderHealth -ProviderState $ProviderState }).GetNewClosure()
        Supports          = ({ param([string]$Capability) Test-HybridProviderCapability -ProviderState $ProviderState -Capability $Capability }).GetNewClosure()
        GetCapabilities   = ({ Get-HybridProviderCapabilities -ProviderState $ProviderState }).GetNewClosure()
        ClearCache        = ({ Clear-HybridProviderCache -ProviderState $ProviderState | Out-Null }).GetNewClosure()
    }

    foreach ($key in $Operations.Keys) { $service[$key] = $Operations[$key] }

    $object = [pscustomobject]$service
    $object.PSObject.TypeNames.Insert(0, 'Hybrid.ProviderService')
    return $object
}

Export-ModuleMember -Function @(
    'New-HybridProviderState',
    'New-HybridProviderService',
    'Get-HybridProviderCapabilities',
    'Test-HybridProviderCapability',
    'Get-HybridProviderHealth',
    'Initialize-HybridProvider',
    'Stop-HybridProvider',
    'Invoke-HybridProviderCommand',
    'Clear-HybridProviderCache'
)
