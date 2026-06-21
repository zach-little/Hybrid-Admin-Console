Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeModule = Join-Path $repoRoot 'src\Core\Core.RuntimeProfile.psm1'
Assert-Pass -Condition (Test-Path $runtimeModule) -Message 'Runtime profile module exists'

Import-Module $runtimeModule -Force

foreach ($commandName in @(
    'Initialize-HybridRuntimeProfile',
    'Get-HybridRuntimeProfile',
    'Test-HybridRuntimeProfile',
    'Resolve-HybridRuntimeProfilePath',
    'Get-HybridRuntimeProviderMode',
    'New-HybridRuntimeBootstrapPlan'
)) {
    Assert-Pass -Condition ($null -ne (Get-Command $commandName -ErrorAction SilentlyContinue)) -Message "$commandName exported"
}

$simulationPath = Join-Path $repoRoot 'profiles\Runtime\Simulation.json'
$liveExamplePath = Join-Path $repoRoot 'profiles\Runtime\Atlas-GCCHigh-Live.example.json'
Assert-Pass -Condition (Test-Path $simulationPath) -Message 'Simulation runtime profile exists'
Assert-Pass -Condition (Test-Path $liveExamplePath) -Message 'Live GCC High runtime profile example exists'

$profile = Initialize-HybridRuntimeProfile -Name 'Simulation' -RootPath $repoRoot
Assert-Pass -Condition ($profile.PSTypeName -eq 'Hybrid.RuntimeProfile') -Message 'Runtime profile has canonical type name'
Assert-Pass -Condition ($profile.ProfileName -eq 'Simulation') -Message 'Simulation profile loaded by name'
Assert-Pass -Condition ($profile.Mode -eq 'Simulation') -Message 'Simulation profile declares Simulation mode'
Assert-Pass -Condition ((Get-HybridRuntimeProviderMode -ProviderName 'DirectorySimulator') -eq 'Simulation') -Message 'Directory Simulator provider resolves to Simulation mode'
Assert-Pass -Condition ((Get-HybridRuntimeProviderMode -ProviderName 'ActiveDirectory') -eq 'Disabled') -Message 'Active Directory resolves to Disabled in simulation profile'

$validation = Test-HybridRuntimeProfile -Profile $profile
Assert-Pass -Condition ($validation.Success -eq $true) -Message 'Simulation runtime profile validates successfully'

$plan = New-HybridRuntimeBootstrapPlan -Profile $profile
Assert-Pass -Condition ($plan.PSTypeName -eq 'Hybrid.RuntimeBootstrapPlan') -Message 'Runtime bootstrap plan has canonical type name'
Assert-Pass -Condition ($plan.ProviderCount -eq 1) -Message 'Simulation bootstrap plan enables one provider'
Assert-Pass -Condition (@($plan.Steps | Where-Object { $_.Provider -eq 'DirectorySimulator' -and $_.Action -eq 'InitializeDirectorySimulator' }).Count -eq 1) -Message 'Bootstrap plan initializes Directory Simulator'
Assert-Pass -Condition (@($plan.Steps | Where-Object { $_.Provider -eq 'MicrosoftGraph' -and $_.Action -eq 'Skip' }).Count -eq 1) -Message 'Bootstrap plan skips disabled Microsoft Graph provider'

$liveProfile = Initialize-HybridRuntimeProfile -Path $liveExamplePath
Assert-Pass -Condition ($liveProfile.Mode -eq 'Live') -Message 'Live profile example declares Live mode'
Assert-Pass -Condition ($liveProfile.Cloud -eq 'GCCHigh') -Message 'Live profile example declares GCC High cloud'
Assert-Pass -Condition ((Get-HybridRuntimeProviderMode -ProviderName 'MicrosoftGraph' -Profile $liveProfile) -eq 'Live') -Message 'Microsoft Graph resolves to Live in live profile example'
Assert-Pass -Condition ((Get-HybridRuntimeProviderMode -ProviderName 'DirectorySimulator' -Profile $liveProfile) -eq 'Disabled') -Message 'Directory Simulator resolves to Disabled in live profile example'

$liveValidation = Test-HybridRuntimeProfile -Profile $liveProfile
Assert-Pass -Condition ($liveValidation.Success -eq $true) -Message 'Live profile example validates successfully'

Write-Host ''
Write-Host 'Milestone 8 Phase 1 runtime profile foundation tests passed.' -ForegroundColor Cyan
