#region Module Information
# Name: Core.RuntimeServices
# Purpose: Milestone 9 runtime service orchestration for refresh schedules, task tracking, and cache invalidation.
#endregion

Set-StrictMode -Version Latest

$script:HybridRuntimeServicesState = @{
    Initialized = $false
    ProviderRegistry = $null
    RefreshSchedules = @{}
    Tasks = @{}
}

function Publish-HybridRuntimeServiceEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$EventName,
        [AllowNull()][object]$Data = $null
    )

    if (Get-Command Publish-HybridRuntimeEvent -ErrorAction SilentlyContinue) {
        try { Publish-HybridRuntimeEvent -EventName $EventName -Source 'Core.RuntimeServices' -Data $Data | Out-Null } catch { }
    }
}

function Initialize-HybridRuntimeServiceOrchestrator {
    [CmdletBinding()]
    param([AllowNull()][hashtable]$ProviderRegistry = $null)

    $script:HybridRuntimeServicesState.Initialized = $true
    $script:HybridRuntimeServicesState.ProviderRegistry = $ProviderRegistry
    $script:HybridRuntimeServicesState.RefreshSchedules = @{}
    $script:HybridRuntimeServicesState.Tasks = @{}

    $service = [pscustomobject]@{
        PSTypeName = 'Hybrid.RuntimeServiceOrchestrator'
        Initialized = $true
        ProviderRegistry = $ProviderRegistry
        CreatedUtc = [datetime]::UtcNow
    }
    Publish-HybridRuntimeServiceEvent -EventName 'Runtime.ServicesInitialized' -Data ([pscustomobject]@{ ProviderCount = if ($null -eq $ProviderRegistry) { 0 } else { $ProviderRegistry.Count } })
    return $service
}

function Assert-HybridRuntimeServiceOrchestratorInitialized {
    if (-not [bool]$script:HybridRuntimeServicesState.Initialized) {
        Initialize-HybridRuntimeServiceOrchestrator | Out-Null
    }
}

function Register-HybridRuntimeProviderRefreshSchedule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProviderName,
        [int]$IntervalSeconds = 300,
        [switch]$Enabled
    )

    Assert-HybridRuntimeServiceOrchestratorInitialized
    if ($IntervalSeconds -lt 1) { $IntervalSeconds = 1 }
    $now = [datetime]::UtcNow
    $schedule = [pscustomobject]@{
        PSTypeName = 'Hybrid.RuntimeProviderRefreshSchedule'
        ProviderName = $ProviderName
        IntervalSeconds = $IntervalSeconds
        Enabled = [bool]$Enabled
        LastRefreshUtc = [Nullable[datetime]]$null
        NextRefreshUtc = $now.AddSeconds($IntervalSeconds)
        RegisteredUtc = $now
    }
    $script:HybridRuntimeServicesState.RefreshSchedules[$ProviderName] = $schedule
    Publish-HybridRuntimeServiceEvent -EventName 'Runtime.RefreshScheduled' -Data $schedule
    return $schedule
}

function Get-HybridRuntimeProviderRefreshSchedules {
    [CmdletBinding()]
    param([string]$ProviderName = '')

    Assert-HybridRuntimeServiceOrchestratorInitialized
    if (-not [string]::IsNullOrWhiteSpace($ProviderName)) {
        if ($script:HybridRuntimeServicesState.RefreshSchedules.ContainsKey($ProviderName)) {
            return $script:HybridRuntimeServicesState.RefreshSchedules[$ProviderName]
        }
        return $null
    }

    return @($script:HybridRuntimeServicesState.RefreshSchedules.Values)
}

function Get-HybridRuntimeProviderRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProviderName)

    $registry = $script:HybridRuntimeServicesState.ProviderRegistry
    if ($null -eq $registry -or -not $registry.ContainsKey($ProviderName)) { return $null }
    return $registry[$ProviderName]
}

function Get-HybridRuntimeProviderHealthFromRecord {
    [CmdletBinding()]
    param([AllowNull()][object]$Record)

    if ($null -eq $Record) { return $null }
    $service = if ($Record.PSObject.Properties.Name -contains 'Service') { $Record.Service } else { $null }
    if ($null -eq $service) { return $null }
    foreach ($operationName in @('GetProviderHealth','GetHealth')) {
        if ($service.PSObject.Properties.Name -contains $operationName -and $service.$operationName -is [scriptblock]) {
            return @(& $service.$operationName | Select-Object -First 1)
        }
    }
    return $null
}

function Invoke-HybridRuntimeProviderRefresh {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProviderName)

    Assert-HybridRuntimeServiceOrchestratorInitialized
    $schedule = Get-HybridRuntimeProviderRefreshSchedules -ProviderName $ProviderName
    $record = Get-HybridRuntimeProviderRecord -ProviderName $ProviderName
    $started = [datetime]::UtcNow
    Publish-HybridRuntimeServiceEvent -EventName 'Runtime.ProviderRefreshStarted' -Data ([pscustomobject]@{ ProviderName = $ProviderName; StartedUtc = $started })

    try {
        $health = Get-HybridRuntimeProviderHealthFromRecord -Record $record
        $status = if ($null -ne $health -and $health.PSObject.Properties.Name -contains 'Status') { [string]$health.Status } elseif ($null -ne $record -and $record.PSObject.Properties.Name -contains 'Status') { [string]$record.Status } else { 'Unknown' }
        if ($null -ne $record -and $record.PSObject.Properties.Name -contains 'Status' -and -not [string]::IsNullOrWhiteSpace($status)) { $record.Status = $status }
        if ($null -ne $schedule) {
            $schedule.LastRefreshUtc = [datetime]::UtcNow
            $schedule.NextRefreshUtc = $schedule.LastRefreshUtc.AddSeconds([int]$schedule.IntervalSeconds)
        }

        $result = [pscustomobject]@{
            PSTypeName = 'Hybrid.RuntimeProviderRefreshResult'
            ProviderName = $ProviderName
            Status = $status
            Health = $health
            StartedUtc = $started
            CompletedUtc = [datetime]::UtcNow
        }
        Publish-HybridRuntimeServiceEvent -EventName 'Runtime.ProviderStatusChanged' -Data $result
        Publish-HybridRuntimeServiceEvent -EventName 'Runtime.ProviderRefreshCompleted' -Data $result
        return $result
    }
    catch {
        $result = [pscustomobject]@{
            PSTypeName = 'Hybrid.RuntimeProviderRefreshResult'
            ProviderName = $ProviderName
            Status = 'Failed'
            Error = $_.Exception.Message
            StartedUtc = $started
            CompletedUtc = [datetime]::UtcNow
        }
        Publish-HybridRuntimeServiceEvent -EventName 'Runtime.ProviderRefreshFailed' -Data $result
        return $result
    }
}

function Invoke-HybridRuntimeDueProviderRefreshes {
    [CmdletBinding()]
    param([datetime]$AsOfUtc = [datetime]::UtcNow)

    Assert-HybridRuntimeServiceOrchestratorInitialized
    $results = New-Object System.Collections.ArrayList
    foreach ($schedule in @($script:HybridRuntimeServicesState.RefreshSchedules.Values)) {
        if (-not [bool]$schedule.Enabled) { continue }
        if ([datetime]$schedule.NextRefreshUtc -le $AsOfUtc) {
            $results.Add((Invoke-HybridRuntimeProviderRefresh -ProviderName ([string]$schedule.ProviderName))) | Out-Null
        }
    }
    return @($results)
}

function Invoke-HybridRuntimeCacheInvalidation {
    [CmdletBinding()]
    param(
        [string]$Scope = 'Runtime',
        [string]$Reason = 'Requested'
    )

    Assert-HybridRuntimeServiceOrchestratorInitialized
    $eventData = [pscustomobject]@{
        PSTypeName = 'Hybrid.RuntimeCacheInvalidation'
        Scope = $Scope
        Reason = $Reason
        InvalidatedUtc = [datetime]::UtcNow
    }
    Publish-HybridRuntimeServiceEvent -EventName 'Runtime.CacheInvalidated' -Data $eventData
    return $eventData
}

function Start-HybridRuntimeTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock,
        [AllowNull()][object]$InputObject = $null
    )

    Assert-HybridRuntimeServiceOrchestratorInitialized
    $task = [pscustomobject]@{
        PSTypeName = 'Hybrid.RuntimeTask'
        Id = [guid]::NewGuid().ToString('N')
        Name = $Name
        Status = 'Running'
        InputObject = $InputObject
        Result = $null
        Error = $null
        CancellationRequested = $false
        StartedUtc = [datetime]::UtcNow
        CompletedUtc = $null
    }
    $script:HybridRuntimeServicesState.Tasks[$task.Id] = $task
    Publish-HybridRuntimeServiceEvent -EventName 'Runtime.TaskStarted' -Data $task

    try {
        $task.Result = & $ScriptBlock $InputObject $task
        if ([bool]$task.CancellationRequested) {
            $task.Status = 'Cancelled'
            Publish-HybridRuntimeServiceEvent -EventName 'Runtime.TaskCancelled' -Data $task
        }
        else {
            $task.Status = 'Completed'
            Publish-HybridRuntimeServiceEvent -EventName 'Runtime.TaskCompleted' -Data $task
        }
    }
    catch {
        $task.Status = 'Failed'
        $task.Error = $_.Exception.Message
        Publish-HybridRuntimeServiceEvent -EventName 'Runtime.TaskFailed' -Data $task
    }
    finally {
        $task.CompletedUtc = [datetime]::UtcNow
    }

    return $task
}

function Stop-HybridRuntimeTask {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$TaskId)

    Assert-HybridRuntimeServiceOrchestratorInitialized
    if (-not $script:HybridRuntimeServicesState.Tasks.ContainsKey($TaskId)) { return $false }
    $task = $script:HybridRuntimeServicesState.Tasks[$TaskId]
    $task.CancellationRequested = $true
    if ($task.Status -eq 'Running') { $task.Status = 'Cancelling' }
    Publish-HybridRuntimeServiceEvent -EventName 'Runtime.TaskCancellationRequested' -Data $task
    return $true
}

function Get-HybridRuntimeTasks {
    [CmdletBinding()]
    param([string]$TaskId = '')

    Assert-HybridRuntimeServiceOrchestratorInitialized
    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        if ($script:HybridRuntimeServicesState.Tasks.ContainsKey($TaskId)) { return $script:HybridRuntimeServicesState.Tasks[$TaskId] }
        return $null
    }
    return @($script:HybridRuntimeServicesState.Tasks.Values)
}

function Clear-HybridRuntimeServiceOrchestrator {
    [CmdletBinding()]
    param()

    $script:HybridRuntimeServicesState.Initialized = $false
    $script:HybridRuntimeServicesState.ProviderRegistry = $null
    $script:HybridRuntimeServicesState.RefreshSchedules = @{}
    $script:HybridRuntimeServicesState.Tasks = @{}
    return $true
}

Export-ModuleMember -Function `
    Initialize-HybridRuntimeServiceOrchestrator,`
    Register-HybridRuntimeProviderRefreshSchedule,`
    Get-HybridRuntimeProviderRefreshSchedules,`
    Invoke-HybridRuntimeProviderRefresh,`
    Invoke-HybridRuntimeDueProviderRefreshes,`
    Invoke-HybridRuntimeCacheInvalidation,`
    Start-HybridRuntimeTask,`
    Stop-HybridRuntimeTask,`
    Get-HybridRuntimeTasks,`
    Clear-HybridRuntimeServiceOrchestrator
