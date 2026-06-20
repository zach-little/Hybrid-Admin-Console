<#
.SYNOPSIS
Bootstrap launcher for the Hybrid Administration Platform using the Atlas profile by default.
#>
[CmdletBinding()]
param(
    [string]$Profile = 'Atlas',
    [switch]$NoNet,
    [switch]$HapDebug,
    [switch]$ConsoleOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Source = Join-Path $Root 'src'

# Load only the minimal bootstrap dependency first.
Import-Module (Join-Path $Source 'Core\Core.Paths.psm1') -Force -Global
Import-Module (Join-Path $Source 'Core\Core.ModuleLoader.psm1') -Force -Global

$Context = New-HybridHostContext
Initialize-HybridPaths -Context $Context -RootPath $Root | Out-Null

# Import everything else in deterministic framework order.
Import-HybridModuleTree -SourcePath $Source -Refresh -Global | Out-Null

Initialize-HybridEnvironment -Context $Context -NoNet:$NoNet | Out-Null
Initialize-HybridLogging -Context $Context -Level $(if ($HapDebug) { 'Debug' } else { 'Information' }) | Out-Null
Initialize-HybridCache -Context $Context | Out-Null
Initialize-HybridServiceRegistry -Context $Context | Out-Null
Initialize-HybridPluginRegistry -Context $Context | Out-Null
Initialize-HybridConfiguration -Context $Context -ProfileName $Profile | Out-Null
Initialize-HybridTheme -Context $Context | Out-Null
Initialize-HybridApplicationServices -Context $Context | Out-Null
Import-HybridPlugins -Context $Context -PluginPath (Get-HybridPath -Context $Context -Name Plugins) | Out-Null

Write-HybridLog -Level Information -Module 'Bootstrap' -Message 'Hybrid Administration Platform bootstrap complete.' | Out-Null
Show-HybridShell -Context $Context -ConsoleOnly:$ConsoleOnly
