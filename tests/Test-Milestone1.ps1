[CmdletBinding()]
param(
    [string]$Profile = 'Atlas'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $Root 'src'

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

Import-Module (Join-Path $Source 'Core\Core.Paths.psm1') -Force -Global
Import-Module (Join-Path $Source 'Core\Core.ModuleLoader.psm1') -Force -Global

$Context = New-HybridHostContext
Initialize-HybridPaths -Context $Context -RootPath $Root | Out-Null
$loaded = Import-HybridModuleTree -SourcePath $Source -Refresh -Global

Initialize-HybridEnvironment -Context $Context -NoNet | Out-Null
Initialize-HybridLogging -Context $Context -Level Debug -NoConsole | Out-Null
Initialize-HybridCache -Context $Context | Out-Null
Initialize-HybridServiceRegistry -Context $Context | Out-Null
Initialize-HybridPluginRegistry -Context $Context | Out-Null
Initialize-HybridConfiguration -Context $Context -ProfileName $Profile | Out-Null
Initialize-HybridTheme -Context $Context | Out-Null
Initialize-HybridApplicationServices -Context $Context | Out-Null

Assert-True (($loaded | Measure-Object).Count -ge 10) 'Framework modules loaded'
Assert-True ($Context.ProfileName -eq $Profile) 'Profile loaded into context'
Assert-True (Test-HybridService -Name 'Directory') 'Directory service registered'
Assert-True ((Invoke-HybridDirectorySearch -Query 'Alex' | Measure-Object).Count -ge 1) 'Mock directory search returns data'
Assert-True ((Test-HybridConfiguration).Success) 'Configuration validates'
Assert-True ((Test-HybridStructure -Context $Context | Where-Object { -not $_.Exists } | Measure-Object).Count -eq 0) 'Required folders exist'

Write-Host ''
Write-Host 'Milestone 1 framework tests passed.' -ForegroundColor Cyan
