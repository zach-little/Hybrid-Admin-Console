Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeModule = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'
$runtimeManifest = Join-Path $repoRoot 'src\Core\Core.Runtime.psd1'

Assert-Pass -Condition (Test-Path $runtimeModule) -Message 'Runtime bootstrap module exists'
Assert-Pass -Condition (Test-Path $runtimeManifest) -Message 'Runtime bootstrap module manifest exists'

Remove-Module Core.Runtime,Core.RuntimeProfile,Core.ServiceRegistry,Application.HybridUserService,Application.GraphProfileService,Application.AuthenticationProfileService,Application.HybridUserAggregationService,Infrastructure.DirectorySimulator -Force -ErrorAction SilentlyContinue
Import-Module $runtimeModule -Force

foreach ($commandName in @(
    'Initialize-HybridRuntime',
    'Get-HybridRuntime',
    'Reset-HybridRuntime'
)) {
    Assert-Pass -Condition ($null -ne (Get-Command $commandName -ErrorAction SilentlyContinue)) -Message "$commandName exported"
}

$runtime = Initialize-HybridRuntime -ProfileName 'Simulation' -RootPath $repoRoot
Assert-Pass -Condition ($null -ne $runtime) -Message 'Runtime bootstrap returned a context'
Assert-Pass -Condition ($runtime.PSObject.Properties.Name -contains 'PSTypeName') -Message 'Runtime context exposes canonical type marker'
Assert-Pass -Condition ($runtime.PSTypeName -eq 'Hybrid.RuntimeContext') -Message 'Runtime context has canonical type name'
Assert-Pass -Condition ($runtime.Version -eq 'v0.9.0') -Message 'Runtime reports current development version'
Assert-Pass -Condition ($runtime.Profile.Mode -eq 'Simulation') -Message 'Runtime profile loaded by bootstrap engine'
Assert-Pass -Condition ($runtime.RuntimeMode -eq 'Simulation') -Message 'Runtime mode exposed on context'
Assert-Pass -Condition ($runtime.CloudEnvironment -eq 'Commercial') -Message 'Cloud environment exposed on context'
Assert-Pass -Condition ($runtime.IsSimulation -eq $true) -Message 'Runtime identifies simulation mode'
Assert-Pass -Condition ($null -ne $runtime.BootstrapPlan) -Message 'Runtime includes bootstrap plan'
Assert-Pass -Condition ($runtime.Diagnostics.Status -eq 'Initialized') -Message 'Runtime diagnostics report initialized'
Assert-Pass -Condition (@($runtime.Diagnostics.Records).Count -ge 4) -Message 'Runtime diagnostics include bootstrap records'

$current = Get-HybridRuntime
Assert-Pass -Condition ([object]::ReferenceEquals($runtime, $current)) -Message 'Get-HybridRuntime returns initialized runtime'

$second = Initialize-HybridRuntime -ProfileName 'Simulation' -RootPath $repoRoot
Assert-Pass -Condition ([object]::ReferenceEquals($runtime, $second)) -Message 'Runtime initialization is idempotent without Force'

foreach ($providerName in @('DirectorySimulator','ActiveDirectory','MicrosoftGraph','ExchangeOnline')) {
    Assert-Pass -Condition ($runtime.ProviderRegistry.ContainsKey($providerName)) -Message "$providerName provider registration exists"
}
Assert-Pass -Condition ($runtime.ProviderRegistry['DirectorySimulator'].Status -eq 'Initialized') -Message 'Directory Simulator provider initialized'
Assert-Pass -Condition ($runtime.ProviderRegistry['ActiveDirectory'].Mode -eq 'Simulation') -Message 'Active Directory simulation provider registered'
Assert-Pass -Condition ($runtime.ProviderRegistry['MicrosoftGraph'].Mode -eq 'Simulation') -Message 'Microsoft Graph simulation provider registered'
Assert-Pass -Condition ($runtime.ProviderRegistry['ExchangeOnline'].Mode -eq 'Simulation') -Message 'Exchange Online simulation provider registered'

foreach ($serviceName in @('HybridUser','GraphProfile','AuthenticationProfile','UserAggregation')) {
    Assert-Pass -Condition ($runtime.ServiceRegistry.ContainsKey($serviceName)) -Message "$serviceName application service initialized"
}

$alex = Search-HybridUser -Query 'Alex'
Assert-Pass -Condition (@($alex).Count -ge 1) -Message 'Runtime initialized service layer can search simulator users'
$aggregate = Get-HybridUserAggregateProfile -Identity 'amorgan@atlas-tech.com'
Assert-Pass -Condition ($aggregate.PSTypeName -eq 'Hybrid.UserAggregateProfile') -Message 'Runtime initialized aggregation service returns aggregate profile'
Assert-Pass -Condition ($aggregate.Complete -eq $true) -Message 'Runtime aggregation profile is complete in simulation mode'

$liveExamplePath = Join-Path $repoRoot 'profiles\Runtime\Atlas-GCCHigh-Live.example.json'
$liveRuntime = Initialize-HybridRuntime -ProfilePath $liveExamplePath -RootPath $repoRoot -Force
Assert-Pass -Condition ($liveRuntime.RuntimeMode -eq 'Live') -Message 'Runtime supports profile path initialization'
Assert-Pass -Condition ($liveRuntime.CloudEnvironment -eq 'GCCHigh') -Message 'Live runtime exposes GCC High cloud environment'
Assert-Pass -Condition ($liveRuntime.ProviderRegistry['MicrosoftGraph'].Status -in @('Deferred','Connected','Failed')) -Message 'Live Microsoft Graph provider registers with a live bootstrap status'
Assert-Pass -Condition ($liveRuntime.Authentication.Status -eq 'Deferred') -Message 'Authentication remains deferred during Phase 2 bootstrap'

Reset-HybridRuntime | Out-Null
$resetFailed = $false
try { Get-HybridRuntime | Out-Null }
catch { $resetFailed = $true }
Assert-Pass -Condition $resetFailed -Message 'Reset-HybridRuntime clears runtime state'

Write-Host ''
Write-Host 'Milestone 8 Phase 2 runtime bootstrap engine tests passed.' -ForegroundColor Cyan
