Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$iconPath = Join-Path $repoRoot 'assets\icons\HAP_Icon.png'
$testPath = Join-Path $repoRoot 'tests\Test-Milestone8FinalBrandPolish.ps1'

if (-not (Test-Path -LiteralPath $uiPath)) { throw "Hybrid Admin Console UI script not found: $uiPath" }
if (-not (Test-Path -LiteralPath $iconPath)) { throw "HAP application icon not found: $iconPath" }
if (-not (Test-Path -LiteralPath $testPath)) { throw "Final brand polish test not found: $testPath" }

Write-Host 'Milestone 8 final brand polish applied.'
Write-Host 'Run .\tests\Test-Milestone8FinalBrandPolish.ps1, then final UI polish and final integration tests.'
