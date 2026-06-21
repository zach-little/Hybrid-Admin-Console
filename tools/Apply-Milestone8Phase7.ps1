Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $root 'src\Core\Core.Deployment.psd1'

if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Core.Deployment module manifest not found: $modulePath"
}

Import-Module $modulePath -Force
$result = Initialize-HybridDeployment -RepositoryRoot $root

if (-not $result.IsReady) {
    Write-Host 'Milestone 8 Phase 7 deployment support applied, but deployment validation reported errors.' -ForegroundColor Yellow
    $result.Checks | Where-Object { -not $_.Passed } | ForEach-Object {
        Write-Host ("{0}: {1}" -f $_.Name, $_.Message) -ForegroundColor Yellow
    }
    throw 'Deployment layout is not ready.'
}

Write-Host 'Milestone 8 Phase 7 deployment and packaging support applied.' -ForegroundColor Green
Write-Host 'Run .\tests\Test-Milestone8Phase7.ps1, then cumulative Milestone 8 Phase 6.1 through Phase 1 tests.'
