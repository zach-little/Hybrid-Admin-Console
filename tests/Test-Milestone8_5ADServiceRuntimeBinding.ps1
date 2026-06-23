Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$root = Split-Path -Parent $PSScriptRoot
$adPath = Join-Path $root 'src\Infrastructure\Infrastructure.ActiveDirectory.psm1'
$coreRuntimePath = Join-Path $root 'src\Core\Core.Runtime.psm1'
$uiPath = Join-Path $root 'src\UI\Start-HybridAdminConsole.ps1'
$serviceLocatorPath = Join-Path $root 'src\Application\Application.ServiceLocator.psm1'
$coreThemePath = Join-Path $root 'src\Core\Core.Theme.psm1'

Assert-Pass -Condition (Test-Path $adPath) -Message 'Active Directory infrastructure module exists'
Assert-Pass -Condition (Test-Path $coreRuntimePath) -Message 'Runtime bootstrap module exists'
Assert-Pass -Condition (Test-Path $uiPath) -Message 'Runtime UI exists'

$ad = Get-Content -LiteralPath $adPath -Raw
$core = Get-Content -LiteralPath $coreRuntimePath -Raw
$ui = Get-Content -LiteralPath $uiPath -Raw
$locator = Get-Content -LiteralPath $serviceLocatorPath -Raw
$theme = Get-Content -LiteralPath $coreThemePath -Raw

Assert-Pass -Condition ($ad -match 'function Initialize-HybridActiveDirectoryRuntime') -Message 'AD provider exposes runtime readiness function'
Assert-Pass -Condition ($ad -match 'Import-Module ActiveDirectory -ErrorAction Stop') -Message 'AD readiness imports ActiveDirectory inside provider runtime session'
Assert-Pass -Condition ($ad -match 'Get-Command -Name \$requiredCommand') -Message 'AD readiness validates required AD commands'
Assert-Pass -Condition ($ad -match "Invoke-HybridADCommand -CommandName 'Get-ADDomain'") -Message 'AD readiness validates domain connectivity through provider command path'
Assert-Pass -Condition ($ad -match 'logs.*ad-runtime-diagnostics\.log|ad-runtime-diagnostics\.log') -Message 'AD readiness writes persistent AD diagnostics'
Assert-Pass -Condition ($ad -match 'InitializeRuntime\s*=\s*\{ Initialize-HybridActiveDirectoryRuntime \}') -Message 'AD service exposes runtime readiness operation'
Assert-Pass -Condition ($ad -match 'Get-HybridADProviderHealth[\s\S]*Initialize-HybridActiveDirectoryRuntime') -Message 'AD provider health uses runtime readiness path'
Assert-Pass -Condition ($ad -match 'Assert-HybridADProviderAvailable[\s\S]*Initialize-HybridActiveDirectoryRuntime -ThrowOnFailure') -Message 'AD operations force runtime readiness before live commands'

Assert-Pass -Condition ($core -match 'function Initialize-HybridRuntimeLiveActiveDirectoryProvider') -Message 'Runtime bootstrap has live AD binding function'
Assert-Pass -Condition ($core -match 'Infrastructure\\Infrastructure\.ActiveDirectory\.psm1') -Message 'Runtime bootstrap imports AD infrastructure for live AD provider'
Assert-Pass -Condition ($core -match 'Initialize-HybridActiveDirectoryProvider -Context \$Context') -Message 'Runtime bootstrap initializes registered AD provider service with runtime context'
Assert-Pass -Condition ($core -match 'RuntimeDiagnosticsPath \$diagnosticPath') -Message 'Runtime bootstrap passes persistent AD diagnostic path into AD provider'
Assert-Pass -Condition ($core -match 'Status = ''Connected''|\$status = ''Connected''') -Message 'Runtime provider registration can report AD connected'
Assert-Pass -Condition ($core -match 'Status = ''Unavailable''|\$status = ''Unavailable''') -Message 'Runtime provider registration can report AD unavailable'
Assert-Pass -Condition ($core -match 'runtime-diagnostics\.log') -Message 'Runtime bootstrap writes persistent runtime diagnostics'
Assert-Pass -Condition ($core -match 'Name -eq ''ActiveDirectory'' -and \[string\]\$provider\.Mode -eq ''Live''') -Message 'Live Active Directory no longer remains a deferred provider during launch'

Assert-Pass -Condition ($ui -match 'RuntimeActiveDirectoryStatusText') -Message 'Launch page has named Active Directory provider status text'
Assert-Pass -Condition ($ui -match 'Set-HybridRuntimeActiveDirectoryStatusText') -Message 'Launch page updates Active Directory status dynamically'
Assert-Pass -Condition ($ui -notmatch 'Active Directory\s+Ready') -Message 'Launch page no longer hardcodes Active Directory Ready'
Assert-Pass -Condition ($ui -match 'ProviderHealth\.ActiveDirectory') -Message 'Console provider health reads service provider-health details'
Assert-Pass -Condition ($ui -match 'Provider health: AD unavailable') -Message 'Console still reports AD unavailable when provider health is unavailable'

Assert-Pass -Condition ($locator -notmatch 'Initialize-HybridUserService -Context') -Message 'Legacy service locator no longer passes unsupported -Context parameter'
Assert-Pass -Condition ($theme -match 'Get-HybridThemeBrandingValue') -Message 'Core theme uses strict-mode-safe branding value helper'

Write-Host 'Milestone 8.5 AD service runtime binding tests passed.'
