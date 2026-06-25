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
$runtimeModule = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'

Import-Module $eventModule -Force

$bus = Initialize-HybridRuntimeEventBus -MaxHistory 2
Assert-True ($bus.Initialized -and $bus.MaxHistory -eq 2) 'Runtime event bus initializes with bounded history'

$received = New-Object System.Collections.Generic.List[object]
$wildcard = New-Object System.Collections.Generic.List[object]
$subscription = Register-HybridRuntimeEventSubscriber -EventName 'Runtime.RefreshRequested' -Name 'RefreshSubscriber' -Action {
    param($Event)
    $received.Add($Event) | Out-Null
}.GetNewClosure()
Register-HybridRuntimeEventSubscriber -EventName '*' -Name 'WildcardSubscriber' -Action {
    param($Event)
    $wildcard.Add($Event.EventName) | Out-Null
}.GetNewClosure() | Out-Null

$event = Publish-HybridRuntimeEvent -EventName 'Runtime.RefreshRequested' -Source 'Test' -Data ([pscustomobject]@{ Provider = 'MicrosoftGraph' }) -CorrelationId 'corr-1'
Assert-True ($event.EventName -eq 'Runtime.RefreshRequested' -and $event.CorrelationId -eq 'corr-1') 'Runtime event publish returns structured event'
Assert-True ($received.Count -eq 1 -and $received[0].Data.Provider -eq 'MicrosoftGraph') 'Runtime event bus invokes named subscribers'
Assert-True ($wildcard.Count -eq 1 -and $wildcard[0] -eq 'Runtime.RefreshRequested') 'Runtime event bus invokes wildcard subscribers'

Register-HybridRuntimeEventSubscriber -EventName 'Runtime.RefreshRequested' -Name 'FailingSubscriber' -Action { throw 'subscriber failed' } | Out-Null
$failedEvent = Publish-HybridRuntimeEvent -EventName 'Runtime.RefreshRequested' -Source 'Test'
Assert-True (@($failedEvent.SubscriberErrors).Count -eq 1) 'Runtime event bus isolates subscriber failures'

Publish-HybridRuntimeEvent -EventName 'Runtime.ProviderStatusChanged' -Source 'Test' | Out-Null
$history = @(Get-HybridRuntimeEvents)
Assert-True ($history.Count -eq 2 -and $history[-1].EventName -eq 'Runtime.ProviderStatusChanged') 'Runtime event bus keeps bounded event history'

$removed = Unregister-HybridRuntimeEventSubscriber -SubscriptionId $subscription.Id
Assert-True ([bool]$removed) 'Runtime event subscribers can be unregistered'

$eventText = Get-Content -LiteralPath $eventModule -Raw
$runtimeText = Get-Content -LiteralPath $runtimeModule -Raw
Assert-ContainsText $eventText 'Publish-HybridRuntimeEvent' 'Runtime event module exports publish function'
Assert-ContainsText $eventText 'Register-HybridRuntimeEventSubscriber' 'Runtime event module exports subscription function'
Assert-ContainsText $runtimeText 'Core.RuntimeEvents.psm1' 'Runtime bootstrap imports runtime event bus module'
Assert-ContainsText $runtimeText "Register-HybridService -Name 'RuntimeEventBus'" 'Runtime bootstrap registers event bus service'
Assert-ContainsText $runtimeText "Publish-HybridRuntimeEvent -EventName 'Runtime.Initialized'" 'Runtime bootstrap publishes initialized event'

Write-Host 'Milestone 9 runtime event bus tests passed.'
