#region Module Information
# Name: Core.HttpRetry
# Purpose: Retry policy contracts and retry execution helpers for HAP HTTP pipeline.
# Dependencies: None.
# Exports: New-HybridHttpRetryPolicy, Test-HybridHttpRetryPolicy, Get-HybridHttpRetryDelay, Invoke-HybridHttpRetry
#endregion

Set-StrictMode -Version Latest

function New-HybridHttpRetryPolicy {
    [CmdletBinding()]
    param(
        [int]$MaxAttempts = 3,
        [int]$BaseDelayMilliseconds = 250,
        [int[]]$RetryStatusCodes = @(408, 429, 500, 502, 503, 504),
        [switch]$ExponentialBackoff,
        [switch]$DisableDelay
    )

    if ($MaxAttempts -lt 1) { throw 'MaxAttempts must be at least 1.' }
    if ($BaseDelayMilliseconds -lt 0) { throw 'BaseDelayMilliseconds cannot be negative.' }

    [pscustomobject]@{
        PSTypeName             = 'Hybrid.HttpRetryPolicy'
        MaxAttempts            = $MaxAttempts
        BaseDelayMilliseconds  = $BaseDelayMilliseconds
        RetryStatusCodes       = @($RetryStatusCodes)
        ExponentialBackoff     = [bool]$ExponentialBackoff
        DisableDelay           = [bool]$DisableDelay
    }
}

function Test-HybridHttpRetryPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Policy
    )

    if ($null -eq $Policy) { return $false }

    foreach ($propertyName in @('MaxAttempts', 'BaseDelayMilliseconds', 'RetryStatusCodes')) {
        if ($Policy.PSObject.Properties.Name -notcontains $propertyName) {
            return $false
        }
    }

    return ($Policy.MaxAttempts -ge 1 -and $Policy.BaseDelayMilliseconds -ge 0)
}

function Get-HybridHttpRetryDelay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Policy,
        [Parameter(Mandatory=$true)][int]$Attempt
    )

    if (-not (Test-HybridHttpRetryPolicy -Policy $Policy)) {
        throw 'Invalid HTTP retry policy.'
    }

    if ($Attempt -lt 1) { throw 'Attempt must be at least 1.' }

    if ($Policy.DisableDelay) { return 0 }

    if ($Policy.ExponentialBackoff) {
        return [int]($Policy.BaseDelayMilliseconds * [math]::Pow(2, ($Attempt - 1)))
    }

    return [int]$Policy.BaseDelayMilliseconds
}

function Invoke-HybridHttpRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Operation,
        [Parameter(Mandatory=$true)][object]$Policy
    )

    if (-not (Test-HybridHttpRetryPolicy -Policy $Policy)) {
        throw 'Invalid HTTP retry policy.'
    }

    $attempt = 0
    $lastResult = $null

    while ($attempt -lt $Policy.MaxAttempts) {
        $attempt++
        $lastResult = & $Operation $attempt

        $statusCode = 0
        if ($null -ne $lastResult -and $lastResult.PSObject.Properties.Name -contains 'StatusCode') {
            $statusCode = [int]$lastResult.StatusCode
        }

        if ($Policy.RetryStatusCodes -notcontains $statusCode) {
            return $lastResult
        }

        if ($attempt -lt $Policy.MaxAttempts) {
            $delay = Get-HybridHttpRetryDelay -Policy $Policy -Attempt $attempt
            if ($delay -gt 0) {
                Start-Sleep -Milliseconds $delay
            }
        }
    }

    return $lastResult
}

Export-ModuleMember -Function @(
    'New-HybridHttpRetryPolicy',
    'Test-HybridHttpRetryPolicy',
    'Get-HybridHttpRetryDelay',
    'Invoke-HybridHttpRetry'
)
