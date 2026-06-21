Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$root = Split-Path -Parent $PSScriptRoot
$moduleManifest = Join-Path $root 'src\Core\Core.Deployment.psd1'
$moduleFile = Join-Path $root 'src\Core\Core.Deployment.psm1'

Assert-Pass -Condition (Test-Path -LiteralPath $moduleFile -PathType Leaf) -Message 'Deployment module exists'
Assert-Pass -Condition (Test-Path -LiteralPath $moduleManifest -PathType Leaf) -Message 'Deployment module manifest exists'

Remove-Module Core.Deployment -Force -ErrorAction SilentlyContinue
Import-Module $moduleManifest -Force

$commands = @(
    'Get-HybridDeploymentLayout',
    'Get-HybridDeploymentRuntimeProfile',
    'Initialize-HybridDeployment',
    'Test-HybridDeploymentLayout',
    'New-HybridDeploymentPackage'
)

foreach ($command in $commands) {
    Assert-Pass -Condition ($null -ne (Get-Command $command -ErrorAction SilentlyContinue)) -Message "$command exported"
}

$layout = Get-HybridDeploymentLayout -RepositoryRoot $root
Assert-Pass -Condition ($null -ne $layout) -Message 'Deployment layout object is returned'
Assert-Pass -Condition ($layout.PSTypeName -eq 'Hybrid.DeploymentLayout') -Message 'Deployment layout exposes canonical type marker'
Assert-Pass -Condition ($layout.TypeName -eq 'Hybrid.DeploymentLayout') -Message 'Deployment layout has canonical type name'
Assert-Pass -Condition ($layout.Version -eq 'v0.8.0-dev') -Message 'Deployment layout reports current development version'
Assert-Pass -Condition (Test-Path -LiteralPath $layout.Source -PathType Container) -Message 'Deployment layout resolves source root'
Assert-Pass -Condition (Test-Path -LiteralPath $layout.EntryPoint -PathType Leaf) -Message 'Deployment layout resolves UI entry point'
Assert-Pass -Condition ($layout.RuntimeProfiles -like '*profiles*Runtime*') -Message 'Deployment layout resolves runtime profile folder'

$init = Initialize-HybridDeployment -RepositoryRoot $root
Assert-Pass -Condition ($null -ne $init) -Message 'Deployment initialization returned a result'
Assert-Pass -Condition ($init.PSTypeName -eq 'Hybrid.DeploymentResult') -Message 'Deployment initialization returns canonical result'
Assert-Pass -Condition ($init.IsReady -eq $true) -Message 'Deployment initialization reports ready layout'
Assert-Pass -Condition (Test-Path -LiteralPath $layout.Logs -PathType Container) -Message 'Deployment initialization ensures logs folder'
Assert-Pass -Condition (Test-Path -LiteralPath $layout.Build -PathType Container) -Message 'Deployment initialization ensures build folder'
Assert-Pass -Condition (Test-Path -LiteralPath $layout.RuntimeProfiles -PathType Container) -Message 'Deployment initialization ensures runtime profile folder'

$profiles = @(Get-HybridDeploymentRuntimeProfile -RepositoryRoot $root)
Assert-Pass -Condition ($profiles.Count -ge 1) -Message 'Deployment profile discovery returns runtime profiles'
Assert-Pass -Condition (@($profiles | Where-Object { $_.FileName -eq 'Simulation.json' }).Count -eq 1) -Message 'Deployment profile discovery includes Simulation profile'
Assert-Pass -Condition (@($profiles | Where-Object { $_.Status -eq 'Readable' }).Count -ge 1) -Message 'Deployment profile discovery reads JSON profiles'
Assert-Pass -Condition (@($profiles | Where-Object { $_.PSTypeName -eq 'Hybrid.DeploymentRuntimeProfile' }).Count -eq $profiles.Count) -Message 'Deployment profiles expose canonical type marker'

$validation = Test-HybridDeploymentLayout -RepositoryRoot $root
Assert-Pass -Condition ($validation.IsReady -eq $true) -Message 'Deployment validation reports ready'
Assert-Pass -Condition ($validation.ErrorCount -eq 0) -Message 'Deployment validation reports zero errors'
Assert-Pass -Condition (@($validation.Checks | Where-Object { $_.Name -eq 'Simulation first-run profile' -and $_.Passed }).Count -eq 1) -Message 'Deployment validation checks first-run Simulation profile'
Assert-Pass -Condition (@($validation.Checks | Where-Object { $_.Name -eq 'No Device Code authentication in UI entry point' -and $_.Passed }).Count -eq 1) -Message 'Deployment validation enforces no Device Code authentication in UI entry point'

$packagePath = Join-Path $layout.Build 'Milestone8Phase7-TestPackage.zip'
if (Test-Path -LiteralPath $packagePath -PathType Leaf) { Remove-Item -LiteralPath $packagePath -Force }
$package = New-HybridDeploymentPackage -RepositoryRoot $root -OutputPath $packagePath -Force
Assert-Pass -Condition ($package.PackagePath -eq $packagePath) -Message 'Deployment package result exposes package path'
Assert-Pass -Condition (Test-Path -LiteralPath $packagePath -PathType Leaf) -Message 'Deployment package file is created'
Assert-Pass -Condition ((Get-Item -LiteralPath $packagePath).Length -gt 0) -Message 'Deployment package file is not empty'
Remove-Item -LiteralPath $packagePath -Force

$applyScript = Join-Path $root 'tools\Apply-Milestone8Phase7.ps1'
$packageScript = Join-Path $root 'tools\New-HybridAdminDeploymentPackage.ps1'
$testScript = Join-Path $root 'tools\Test-HybridDeployment.ps1'
$phaseDoc = Join-Path $root 'docs\Milestones\MILESTONE_8_PHASE_7.md'
$deploymentDoc = Join-Path $root 'docs\Deployment\DEPLOYMENT.md'

Assert-Pass -Condition (Test-Path -LiteralPath $applyScript -PathType Leaf) -Message 'Phase 7 apply script exists'
Assert-Pass -Condition (Test-Path -LiteralPath $packageScript -PathType Leaf) -Message 'Deployment packaging script exists'
Assert-Pass -Condition (Test-Path -LiteralPath $testScript -PathType Leaf) -Message 'Deployment validation script exists'
Assert-Pass -Condition (Test-Path -LiteralPath $phaseDoc -PathType Leaf) -Message 'Phase 7 milestone document exists'
Assert-Pass -Condition (Test-Path -LiteralPath $deploymentDoc -PathType Leaf) -Message 'Deployment documentation exists'

Write-Host ''
Write-Host 'Milestone 8 Phase 7 deployment and packaging tests passed.' -ForegroundColor Green
