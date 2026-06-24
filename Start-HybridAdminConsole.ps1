<#
.SYNOPSIS
Primary launcher for the Hybrid Administration Platform runtime/profile UI.
#>
[CmdletBinding()]
param(
    [string]$Profile = 'Simulation',
    [switch]$NoNet,
    [switch]$HapDebug,
    [switch]$ConsoleOnly,
    [string]$InitialQuery = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$UiEntryPoint = Join-Path $Root 'src\UI\Start-HybridAdminConsole.ps1'

if (-not (Test-Path -LiteralPath $UiEntryPoint -PathType Leaf)) {
    throw "HAP UI entry point not found: $UiEntryPoint"
}

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',('"{0}"' -f $UiEntryPoint),'-Profile',('"{0}"' -f $Profile))
    if ($NoNet) { $arguments += '-Mock' }
    if (-not [string]::IsNullOrWhiteSpace($InitialQuery)) { $arguments += @('-InitialQuery',('"{0}"' -f $InitialQuery)) }
    Start-Process -FilePath 'powershell.exe' -ArgumentList ($arguments -join ' ') -Wait
    return
}

$uiParameters = @{ Profile = $Profile; InitialQuery = $InitialQuery }
if ($NoNet) { $uiParameters.Mock = $true }
& $UiEntryPoint @uiParameters
