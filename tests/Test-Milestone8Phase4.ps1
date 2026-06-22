Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeModule = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'

Assert-Pass -Condition (Test-Path $runtimeModule) -Message 'Runtime bootstrap module exists'

Remove-Module Core.Runtime,Core.RuntimeProfile,Core.ServiceRegistry,Application.HybridUserService,Application.GraphProfileService,Application.AuthenticationProfileService,Application.HybridUserAggregationService,Infrastructure.DirectorySimulator -Force -ErrorAction SilentlyContinue
Import-Module $runtimeModule -Force

foreach ($commandName in @(
    'Initialize-HybridRuntime',
    'Get-HybridRuntime',
    'Reset-HybridRuntime',
    'Get-HybridRuntimeProviderRegistration',
    'Get-HybridRuntimeProviderModeSummary',
    'Get-HybridRuntimeDiagnostics',
    'Test-HybridRuntimeDiagnostics'
)) {
    Assert-Pass -Condition ($null -ne (Get-Command $commandName -ErrorAction SilentlyContinue)) -Message "$commandName exported"
}

$runtime = Initialize-HybridRuntime -ProfileName 'Simulation' -RootPath $repoRoot -Force
$diagnostics = Get-HybridRuntimeDiagnostics

Assert-Pass -Condition ($diagnostics.PSTypeName -eq 'Hybrid.RuntimeDiagnostics') -Message 'Runtime diagnostics has canonical type marker'
Assert-Pass -Condition ($diagnostics.Status -eq 'Initialized') -Message 'Runtime diagnostics status initialized'
Assert-Pass -Condition ($diagnostics.OverallStatus -eq 'Warning' -or $diagnostics.OverallStatus -eq 'Healthy') -Message 'Runtime diagnostics overall status exposed'
Assert-Pass -Condition ($null -ne $diagnostics.Summary) -Message 'Runtime diagnostics summary exists'
Assert-Pass -Condition ($diagnostics.Summary.PSTypeName -eq 'Hybrid.RuntimeDiagnosticSummary') -Message 'Runtime diagnostics summary has canonical type marker'
Assert-Pass -Condition (@($diagnostics.Checks).Count -ge 8) -Message 'Runtime diagnostics include startup checks'
Assert-Pass -Condition (@($diagnostics.Records).Count -ge 1) -Message 'Runtime diagnostics preserve bootstrap records'
Assert-Pass -Condition (-not [bool]$diagnostics.HasErrors) -Message 'Simulation runtime diagnostics have no errors'
Assert-Pass -Condition ($diagnostics.Summary.Errors -eq 0) -Message 'Simulation runtime diagnostic summary reports zero errors'

$profileCheck = @($diagnostics.Checks | Where-Object { $_.Name -eq 'RuntimeProfileLoaded' -and $_.Status -eq 'Passed' })
Assert-Pass -Condition ($profileCheck.Count -ge 1) -Message 'Diagnostics include profile loaded check'

$modeCheck = @($diagnostics.Checks | Where-Object { $_.Name -eq 'RuntimeModeSupported' -and $_.Target -eq 'Simulation' })
Assert-Pass -Condition ($modeCheck.Count -ge 1) -Message 'Diagnostics include runtime mode check'

$adProviderCheck = @($diagnostics.Checks | Where-Object { $_.Name -eq 'ProviderRegistration' -and $_.Target -eq 'ActiveDirectory' -and $_.Status -eq 'Initialized' })
Assert-Pass -Condition ($adProviderCheck.Count -eq 1) -Message 'Diagnostics include Active Directory provider check'

$serviceCheck = @($diagnostics.Checks | Where-Object { $_.Name -eq 'ServiceRegistration' -and $_.Target -eq 'HybridUser' -and $_.Status -eq 'Passed' })
Assert-Pass -Condition ($serviceCheck.Count -eq 1) -Message 'Diagnostics include HybridUser service check'

$result = Test-HybridRuntimeDiagnostics
Assert-Pass -Condition ($result.PSTypeName -eq 'Hybrid.RuntimeDiagnosticResult') -Message 'Diagnostic test result has canonical type marker'
Assert-Pass -Condition ([bool]$result.IsHealthy) -Message 'Diagnostic test result reports simulation runtime healthy'
Assert-Pass -Condition ($result.Summary.TotalChecks -eq $diagnostics.Summary.TotalChecks) -Message 'Diagnostic test result carries summary'

$liveProfilePath = Join-Path $repoRoot 'profiles\Runtime\Atlas-GCCHigh-Live.example.json'
$liveRuntime = Initialize-HybridRuntime -ProfilePath $liveProfilePath -RootPath $repoRoot -Force
$liveDiagnostics = Get-HybridRuntimeDiagnostics -Runtime $liveRuntime
Assert-Pass -Condition (-not [bool]$liveDiagnostics.HasErrors) -Message 'Live example diagnostics have no bootstrap errors'
Assert-Pass -Condition ([bool]$liveDiagnostics.HasWarnings) -Message 'Live example diagnostics report deferred-provider warnings'
Assert-Pass -Condition ($liveDiagnostics.OverallStatus -eq 'Warning') -Message 'Live example diagnostics overall status is Warning'

$deferredGraphCheck = @($liveDiagnostics.Checks | Where-Object { $_.Name -eq 'ProviderRegistration' -and $_.Target -eq 'MicrosoftGraph' -and $_.Status -eq 'Deferred' -and $_.Severity -eq 'Warning' })
Assert-Pass -Condition ($deferredGraphCheck.Count -eq 1) -Message 'Diagnostics classify deferred Microsoft Graph provider as warning'

$liveResult = Test-HybridRuntimeDiagnostics -Runtime $liveRuntime
Assert-Pass -Condition ([bool]$liveResult.IsHealthy) -Message 'Diagnostic test result treats deferred live providers as non-fatal'
Assert-Pass -Condition ([bool]$liveResult.HasWarnings) -Message 'Diagnostic test result preserves warnings'

Reset-HybridRuntime | Out-Null
Write-Host ''
Write-Host 'Milestone 8 Phase 4 startup diagnostics tests passed.' -ForegroundColor Cyan
