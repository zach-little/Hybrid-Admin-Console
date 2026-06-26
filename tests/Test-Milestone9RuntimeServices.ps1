$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

function Assert-ContainsText {
    param([string]$Content, [string]$Needle, [string]$Message)
    if ($Content -notlike "*$Needle*") { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$eventModule = Join-Path $repoRoot 'src\Core\Core.RuntimeEvents.psm1'
$servicesModule = Join-Path $repoRoot 'src\Core\Core.RuntimeServices.psm1'
$runtimeModule = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'

Import-Module $eventModule -Force
Import-Module $servicesModule -Force

Initialize-HybridRuntimeEventBus -MaxHistory 50 | Out-Null
$receivedEvents = New-Object System.Collections.Generic.List[string]
Register-HybridRuntimeEventSubscriber -EventName '*' -Name 'RuntimeServicesTestSubscriber' -Action {
    param($Event)
    $receivedEvents.Add($Event.EventName) | Out-Null
}.GetNewClosure() | Out-Null

$providerRegistry = @{
    MicrosoftGraph = [pscustomobject]@{
        Name = 'MicrosoftGraph'
        Status = 'Deferred'
        Service = [pscustomobject]@{
            GetProviderHealth = { [pscustomobject]@{ Status = 'Connected'; Connected = $true } }.GetNewClosure()
        }
    }
}

$orchestrator = Initialize-HybridRuntimeServiceOrchestrator -ProviderRegistry $providerRegistry
Assert-True ($orchestrator.Initialized -and $orchestrator.ProviderRegistry.ContainsKey('MicrosoftGraph')) 'Runtime service orchestrator initializes with provider registry'

$schedule = Register-HybridRuntimeProviderRefreshSchedule -ProviderName 'MicrosoftGraph' -IntervalSeconds 1 -Enabled
Assert-True ($schedule.Enabled -and $schedule.IntervalSeconds -eq 1) 'Provider refresh schedule can be registered'

$refresh = Invoke-HybridRuntimeProviderRefresh -ProviderName 'MicrosoftGraph'
Assert-True ($refresh.Status -eq 'Connected' -and $providerRegistry.MicrosoftGraph.Status -eq 'Connected') 'Provider refresh updates status from provider health'
Assert-True ($receivedEvents -contains 'Runtime.ProviderRefreshStarted' -and $receivedEvents -contains 'Runtime.ProviderRefreshCompleted') 'Provider refresh publishes lifecycle events'
Assert-True ($receivedEvents -contains 'Runtime.ProviderStatusChanged') 'Provider refresh publishes status synchronization event'

$dueSchedule = Get-HybridRuntimeProviderRefreshSchedules -ProviderName 'MicrosoftGraph'
$dueSchedule.NextRefreshUtc = [datetime]::UtcNow.AddSeconds(-1)
$dueRefreshes = @(Invoke-HybridRuntimeDueProviderRefreshes)
Assert-True ($dueRefreshes.Count -eq 1 -and $dueRefreshes[0].ProviderName -eq 'MicrosoftGraph') 'Due provider refresh scheduling invokes due refreshes'

$invalidation = Invoke-HybridRuntimeCacheInvalidation -Scope 'HybridUser' -Reason 'ProfileChanged'
Assert-True ($invalidation.Scope -eq 'HybridUser' -and $receivedEvents -contains 'Runtime.CacheInvalidated') 'Cache invalidation publishes runtime event'

$task = Start-HybridRuntimeTask -Name 'SuccessfulTask' -InputObject 2 -ScriptBlock { param($InputObject, $Task) $InputObject + 3 }
Assert-True ($task.Status -eq 'Completed' -and $task.Result -eq 5) 'Runtime task tracks successful completion'

$failedTask = Start-HybridRuntimeTask -Name 'FailedTask' -ScriptBlock { throw 'task failed' }
Assert-True ($failedTask.Status -eq 'Failed' -and $failedTask.Error -eq 'task failed') 'Runtime task tracks failure state'

$cancelledTask = Start-HybridRuntimeTask -Name 'CancelledTask' -ScriptBlock {
    param($InputObject, $Task)
    $Task.CancellationRequested = $true
    return 'cancelled'
}
Assert-True ($cancelledTask.Status -eq 'Cancelled') 'Runtime task supports cooperative cancellation state'
Assert-True (@(Get-HybridRuntimeTasks).Count -ge 3) 'Runtime task history is queryable'

$servicesText = Get-Content -LiteralPath $servicesModule -Raw
$runtimeText = Get-Content -LiteralPath $runtimeModule -Raw
Assert-ContainsText $servicesText 'Runtime.RefreshScheduled' 'Runtime services publish refresh scheduling events'
Assert-ContainsText $servicesText 'Runtime.CacheInvalidated' 'Runtime services publish cache invalidation events'
Assert-ContainsText $servicesText 'Runtime.TaskStarted' 'Runtime services publish task lifecycle events'
Assert-ContainsText $runtimeText 'Core.RuntimeServices.psm1' 'Runtime bootstrap imports runtime services module'
Assert-ContainsText $runtimeText "Register-HybridService -Name 'RuntimeServices'" 'Runtime bootstrap registers runtime services'
Assert-ContainsText $runtimeText 'Register-HybridRuntimeProviderRefreshSchedule' 'Runtime bootstrap registers provider refresh schedules'

Write-Host 'Milestone 9 runtime services tests passed.'
