#region Module Information
# Name: Core.RuntimeEvents
# Purpose: Runtime event bus foundation for background services, refresh scheduling, and status synchronization.
# Exports: Initialize-HybridRuntimeEventBus, Register-HybridRuntimeEventSubscriber, Unregister-HybridRuntimeEventSubscriber,
#          Publish-HybridRuntimeEvent, Get-HybridRuntimeEvents, Clear-HybridRuntimeEventBus
#endregion

Set-StrictMode -Version Latest

$script:HybridRuntimeEventBusState = @{
    Initialized = $false
    Subscribers = @{}
    History = New-Object System.Collections.ArrayList
    MaxHistory = 200
}

function New-HybridRuntimeEventObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$EventName,
        [AllowNull()][object]$Data = $null,
        [string]$Source = 'Runtime',
        [string]$CorrelationId = ''
    )

    if ([string]::IsNullOrWhiteSpace($CorrelationId)) { $CorrelationId = [guid]::NewGuid().ToString('N') }
    [pscustomobject]@{
        PSTypeName = 'Hybrid.RuntimeEvent'
        EventName = $EventName
        Name = $EventName
        Source = $Source
        Data = $Data
        CorrelationId = $CorrelationId
        TimestampUtc = [datetime]::UtcNow
        SubscriberErrors = @()
    }
}

function Initialize-HybridRuntimeEventBus {
    [CmdletBinding()]
    param([int]$MaxHistory = 200)

    if ($MaxHistory -lt 1) { $MaxHistory = 1 }
    $script:HybridRuntimeEventBusState.Initialized = $true
    $script:HybridRuntimeEventBusState.Subscribers = @{}
    $script:HybridRuntimeEventBusState.History = New-Object System.Collections.ArrayList
    $script:HybridRuntimeEventBusState.MaxHistory = $MaxHistory

    [pscustomobject]@{
        PSTypeName = 'Hybrid.RuntimeEventBus'
        Initialized = $true
        MaxHistory = $MaxHistory
        SubscriberCount = 0
    }
}

function Assert-HybridRuntimeEventBusInitialized {
    if (-not [bool]$script:HybridRuntimeEventBusState.Initialized) {
        Initialize-HybridRuntimeEventBus | Out-Null
    }
}

function Register-HybridRuntimeEventSubscriber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$EventName,
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [string]$Name = ''
    )

    Assert-HybridRuntimeEventBusInitialized
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = ('subscriber-{0}' -f ([guid]::NewGuid().ToString('N'))) }
    if (-not $script:HybridRuntimeEventBusState.Subscribers.ContainsKey($EventName)) {
        $script:HybridRuntimeEventBusState.Subscribers[$EventName] = New-Object System.Collections.ArrayList
    }

    $subscription = [pscustomobject]@{
        PSTypeName = 'Hybrid.RuntimeEventSubscription'
        Id = [guid]::NewGuid().ToString('N')
        Name = $Name
        EventName = $EventName
        Handler = $Action
        RegisteredUtc = [datetime]::UtcNow
    }
    $script:HybridRuntimeEventBusState.Subscribers[$EventName].Add($subscription) | Out-Null
    return $subscription
}

function Unregister-HybridRuntimeEventSubscriber {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SubscriptionId)

    Assert-HybridRuntimeEventBusInitialized
    foreach ($eventName in @($script:HybridRuntimeEventBusState.Subscribers.Keys)) {
        $remaining = @($script:HybridRuntimeEventBusState.Subscribers[$eventName] | Where-Object { $_.Id -ne $SubscriptionId })
        if ($remaining.Count -ne $script:HybridRuntimeEventBusState.Subscribers[$eventName].Count) {
            $script:HybridRuntimeEventBusState.Subscribers[$eventName] = New-Object System.Collections.ArrayList
            foreach ($subscriber in $remaining) { $script:HybridRuntimeEventBusState.Subscribers[$eventName].Add($subscriber) | Out-Null }
            return $true
        }
    }

    return $false
}

function Get-HybridRuntimeEventSubscribers {
    [CmdletBinding()]
    param([string]$EventName = '')

    Assert-HybridRuntimeEventBusInitialized
    if (-not [string]::IsNullOrWhiteSpace($EventName)) {
        if (-not $script:HybridRuntimeEventBusState.Subscribers.ContainsKey($EventName)) { return @() }
        return @($script:HybridRuntimeEventBusState.Subscribers[$EventName])
    }

    return @($script:HybridRuntimeEventBusState.Subscribers.Keys | ForEach-Object { $script:HybridRuntimeEventBusState.Subscribers[$_] })
}

function Publish-HybridRuntimeEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$EventName,
        [AllowNull()][object]$Data = $null,
        [string]$Source = 'Runtime',
        [string]$CorrelationId = ''
    )

    Assert-HybridRuntimeEventBusInitialized
    $event = New-HybridRuntimeEventObject -EventName $EventName -Data $Data -Source $Source -CorrelationId $CorrelationId
    $subscribers = @()
    if ($script:HybridRuntimeEventBusState.Subscribers.ContainsKey($EventName)) { $subscribers += @($script:HybridRuntimeEventBusState.Subscribers[$EventName].ToArray()) }
    if ($script:HybridRuntimeEventBusState.Subscribers.ContainsKey('*')) { $subscribers += @($script:HybridRuntimeEventBusState.Subscribers['*'].ToArray()) }

    $subscriberErrors = @()
    foreach ($subscriber in $subscribers) {
        try {
            $handler = $subscriber.Handler
            & $handler $event
        }
        catch {
            $subscriberErrors += [pscustomobject]@{
                SubscriberId = $subscriber.Id
                SubscriberName = $subscriber.Name
                EventName = $EventName
                Message = $_.Exception.Message
            }
        }
    }

    $event.SubscriberErrors = @($subscriberErrors)
    $script:HybridRuntimeEventBusState.History.Add($event) | Out-Null
    while ($script:HybridRuntimeEventBusState.History.Count -gt [int]$script:HybridRuntimeEventBusState.MaxHistory) {
        $script:HybridRuntimeEventBusState.History.RemoveAt(0)
    }

    return $event
}

function Get-HybridRuntimeEvents {
    [CmdletBinding()]
    param(
        [string]$EventName = '',
        [int]$Last = 0
    )

    Assert-HybridRuntimeEventBusInitialized
    $events = @($script:HybridRuntimeEventBusState.History)
    if (-not [string]::IsNullOrWhiteSpace($EventName)) {
        $events = @($events | Where-Object { $_.EventName -eq $EventName })
    }
    if ($Last -gt 0 -and $events.Count -gt $Last) {
        return @($events | Select-Object -Last $Last)
    }

    return @($events)
}

function Clear-HybridRuntimeEventBus {
    [CmdletBinding()]
    param()

    $script:HybridRuntimeEventBusState.Initialized = $false
    $script:HybridRuntimeEventBusState.Subscribers = @{}
    $script:HybridRuntimeEventBusState.History = New-Object System.Collections.ArrayList
    return $true
}

Export-ModuleMember -Function `
    Initialize-HybridRuntimeEventBus,`
    Register-HybridRuntimeEventSubscriber,`
    Unregister-HybridRuntimeEventSubscriber,`
    Get-HybridRuntimeEventSubscribers,`
    Publish-HybridRuntimeEvent,`
    Get-HybridRuntimeEvents,`
    Clear-HybridRuntimeEventBus
