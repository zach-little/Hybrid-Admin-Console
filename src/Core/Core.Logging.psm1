#region Module Information
# Name: Core.Logging
# Purpose: Structured logging for console, file, and future UI subscribers.
# Dependencies: Core.Paths initialized before file logging is enabled.
# Exports: Initialize-HybridLogging, Write-HybridLog, Get-HybridLogEntries, Clear-HybridLogBuffer
#endregion

Set-StrictMode -Version Latest

$script:State = @{
    Initialized = $false
    LogFile     = $null
    Level       = 'Information'
    Buffer      = New-Object System.Collections.ArrayList
    ToConsole   = $true
}

#region Private
function ConvertTo-HybridLogLevelValue {
    param([string]$Level)

    switch ($Level) {
        'Debug'       { 0 }
        'Information' { 1 }
        'Warning'     { 2 }
        'Error'       { 3 }
        'Critical'    { 4 }
        default       { 1 }
    }
}

function Test-HybridShouldLog {
    param([string]$Level)
    return ((ConvertTo-HybridLogLevelValue $Level) -ge (ConvertTo-HybridLogLevelValue $script:State.Level))
}
#endregion

#region Public
function Initialize-HybridLogging {
    <#
    .SYNOPSIS
    Initializes structured logging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Context,

        [ValidateSet('Debug','Information','Warning','Error','Critical')]
        [string]$Level = 'Information',

        [switch]$NoConsole
    )

    $logsPath = $null
    if ($Context.Paths -and $Context.Paths.Contains('Logs')) {
        $logsPath = $Context.Paths['Logs']
    }
    else {
        $logsPath = Join-Path $Context.Root 'logs'
    }

    if (-not (Test-Path -LiteralPath $logsPath)) {
        New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
    }

    $logFile = Join-Path $logsPath ("HybridAdminConsole_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))

    $script:State.LogFile = $logFile
    $script:State.Level = $Level
    $script:State.ToConsole = -not $NoConsole.IsPresent
    $script:State.Initialized = $true

    $Context.Logger = [pscustomobject]@{
        PSTypeName = 'Hybrid.Logger'
        LogFile    = $logFile
        Level      = $Level
    }

    Write-HybridLog -Level Information -Module 'Core.Logging' -Message "Logging initialized at level '$Level'."
    return $Context.Logger
}

function Write-HybridLog {
    <#
    .SYNOPSIS
    Writes a structured log entry.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Debug','Information','Warning','Error','Critical')]
        [string]$Level = 'Information',

        [string]$Module = 'General',

        [string]$Function = '',

        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$Message,

        [object]$Exception,

        [string]$CorrelationId = ([guid]::NewGuid().ToString())
    )

    if (-not (Test-HybridShouldLog -Level $Level)) { return }

    $entry = [pscustomobject]@{
        PSTypeName     = 'Hybrid.LogEntry'
        TimestampLocal = Get-Date
        TimestampUtc   = [datetime]::UtcNow
        Level          = $Level
        Module         = $Module
        Function       = $Function
        Message        = $Message
        Exception      = if ($Exception) { $Exception.ToString() } else { $null }
        CorrelationId  = $CorrelationId
        ProcessId      = $PID
    }

    [void]$script:State.Buffer.Add($entry)

    $line = '[{0}] [{1}] [{2}] {3}' -f $entry.TimestampLocal.ToString('s'), $Level.ToUpperInvariant(), $Module, $Message
    if ($Exception) { $line = "$line :: $($entry.Exception)" }

    if ($script:State.ToConsole) {
        switch ($Level) {
            'Debug'       { Write-Verbose $line }
            'Information' { Write-Host $line -ForegroundColor Gray }
            'Warning'     { Write-Warning $line }
            'Error'       { Write-Error $line -ErrorAction Continue }
            'Critical'    { Write-Error $line -ErrorAction Continue }
        }
    }

    if ($script:State.LogFile) {
        Add-Content -Path $script:State.LogFile -Value $line -Encoding UTF8
    }

    return $entry
}

function Get-HybridLogEntries {
    <#
    .SYNOPSIS
    Returns in-memory log entries.
    #>
    [CmdletBinding()]
    param(
        [int]$Last = 0
    )

    $items = @($script:State.Buffer)
    if ($Last -gt 0 -and $items.Count -gt $Last) {
        return $items[($items.Count - $Last)..($items.Count - 1)]
    }
    return $items
}

function Clear-HybridLogBuffer {
    <#
    .SYNOPSIS
    Clears the in-memory log buffer.
    #>
    [CmdletBinding()]
    param()

    $script:State.Buffer.Clear()
}
#endregion

#region Initialization
Export-ModuleMember -Function Initialize-HybridLogging, Write-HybridLog, Get-HybridLogEntries, Clear-HybridLogBuffer
#endregion
