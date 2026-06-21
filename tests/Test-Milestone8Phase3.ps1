Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeModule = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'
$hybridProfilePath = Join-Path $repoRoot 'profiles\Runtime\Hybrid.example.json'

Assert-Pass -Condition (Test-Path $runtimeModule) -Message 'Runtime bootstrap module exists'
Assert-Pass -Condition (Test-Path $hybridProfilePath) -Message 'Hybrid runtime profile example exists'

Remove-Module Core.Runtime,Core.RuntimeProfile,Core.ServiceRegistry,Application.HybridUserService,Application.GraphProfileService,Application.AuthenticationProfileService,Application.HybridUserAggregationService,Infrastructure.DirectorySimulator -Force -ErrorAction SilentlyContinue
Import-Module $runtimeModule -Force

foreach ($commandName in @(
    'Initialize-HybridRuntime',
    'Get-HybridRuntime',
    'Reset-HybridRuntime',
    'Get-HybridRuntimeProviderRegistration',
    'Get-HybridRuntimeProviderModeSummary'
)) {
    Assert-Pass -Condition ($null -ne (Get-Command $commandName -ErrorAction SilentlyContinue)) -Message "$commandName exported"
}

$simulationRuntime = Initialize-HybridRuntime -ProfileName 'Simulation' -RootPath $repoRoot -Force
$simulationSummary = Get-HybridRuntimeProviderModeSummary
Assert-Pass -Condition ($simulationRuntime.ProviderModes.PSTypeName -eq 'Hybrid.RuntimeProviderModeSummary') -Message 'Runtime exposes canonical provider mode summary'
Assert-Pass -Condition ($simulationSummary.Modes['ActiveDirectory'] -eq 'Simulation') -Message 'Simulation runtime maps Active Directory to Simulation'
Assert-Pass -Condition ($simulationSummary.Modes['MicrosoftGraph'] -eq 'Simulation') -Message 'Simulation runtime maps Microsoft Graph to Simulation'
Assert-Pass -Condition ($simulationSummary.Modes['ExchangeOnline'] -eq 'Simulation') -Message 'Simulation runtime maps Exchange Online to Simulation'
Assert-Pass -Condition (@($simulationSummary.SimulationProviders).Count -ge 4) -Message 'Simulation summary includes simulator-backed providers'

$graphRegistration = Get-HybridRuntimeProviderRegistration -Name 'MicrosoftGraph'
Assert-Pass -Condition ($graphRegistration.Mode -eq 'Simulation') -Message 'Provider registration lookup returns Microsoft Graph simulation registration'
Assert-Pass -Condition ($graphRegistration.Status -eq 'Initialized') -Message 'Provider registration lookup returns initialized status'

$liveProfilePath = Join-Path $repoRoot 'profiles\Runtime\Atlas-GCCHigh-Live.example.json'
$liveRuntime = Initialize-HybridRuntime -ProfilePath $liveProfilePath -RootPath $repoRoot -Force
$liveSummary = Get-HybridRuntimeProviderModeSummary -Runtime $liveRuntime
Assert-Pass -Condition ($liveRuntime.RuntimeMode -eq 'Live') -Message 'Live runtime mode still initializes'
Assert-Pass -Condition ($liveSummary.Modes['ActiveDirectory'] -eq 'Live') -Message 'Live runtime maps Active Directory to Live'
Assert-Pass -Condition ($liveSummary.Modes['MicrosoftGraph'] -eq 'Live') -Message 'Live runtime maps Microsoft Graph to Live'
Assert-Pass -Condition ($liveSummary.Modes['ExchangeOnline'] -eq 'Live') -Message 'Live runtime maps Exchange Online to Live'
Assert-Pass -Condition (@($liveSummary.DeferredProviders).Count -ge 3) -Message 'Live providers remain deferred during Phase 3'
Assert-Pass -Condition ((Get-HybridRuntimeProviderRegistration -Name 'MicrosoftGraph' -Runtime $liveRuntime).Status -eq 'Deferred') -Message 'Live Microsoft Graph registration is deferred'

$hybridRuntime = Initialize-HybridRuntime -ProfilePath $hybridProfilePath -RootPath $repoRoot -Force
$hybridSummary = Get-HybridRuntimeProviderModeSummary -Runtime $hybridRuntime
Assert-Pass -Condition ($hybridRuntime.RuntimeMode -eq 'Hybrid') -Message 'Hybrid runtime profile initializes'
Assert-Pass -Condition ($hybridRuntime.CloudEnvironment -eq 'GCCHigh') -Message 'Hybrid runtime exposes GCC High cloud'
Assert-Pass -Condition ($hybridSummary.Modes['DirectorySimulator'] -eq 'Simulation') -Message 'Hybrid runtime initializes Directory Simulator'
Assert-Pass -Condition ($hybridSummary.Modes['ActiveDirectory'] -eq 'Simulation') -Message 'Hybrid runtime maps Active Directory to Simulation'
Assert-Pass -Condition ($hybridSummary.Modes['MicrosoftGraph'] -eq 'Live') -Message 'Hybrid runtime maps Microsoft Graph to Live'
Assert-Pass -Condition ($hybridSummary.Modes['ExchangeOnline'] -eq 'Live') -Message 'Hybrid runtime maps Exchange Online to Live'
Assert-Pass -Condition ((Get-HybridRuntimeProviderRegistration -Name 'ActiveDirectory' -Runtime $hybridRuntime).Status -eq 'Initialized') -Message 'Hybrid Active Directory simulation provider is initialized'
Assert-Pass -Condition ((Get-HybridRuntimeProviderRegistration -Name 'MicrosoftGraph' -Runtime $hybridRuntime).Status -eq 'Deferred') -Message 'Hybrid Microsoft Graph live provider is deferred'
Assert-Pass -Condition ((Get-HybridRuntimeProviderRegistration -Name 'ExchangeOnline' -Runtime $hybridRuntime).Status -eq 'Deferred') -Message 'Hybrid Exchange Online live provider is deferred'
Assert-Pass -Condition (@($hybridSummary.SimulationProviders) -contains 'ActiveDirectory') -Message 'Hybrid summary tracks simulation providers'
Assert-Pass -Condition (@($hybridSummary.LiveProviders) -contains 'MicrosoftGraph') -Message 'Hybrid summary tracks live providers'
Assert-Pass -Condition (@($hybridSummary.DeferredProviders) -contains 'MicrosoftGraph') -Message 'Hybrid summary tracks deferred providers'

$alex = Search-HybridUser -Query 'Alex'
Assert-Pass -Condition (@($alex).Count -ge 1) -Message 'Hybrid runtime preserves simulator-backed AD search'

Reset-HybridRuntime | Out-Null
Write-Host ''
Write-Host 'Milestone 8 Phase 3 runtime provider mode tests passed.' -ForegroundColor Cyan
