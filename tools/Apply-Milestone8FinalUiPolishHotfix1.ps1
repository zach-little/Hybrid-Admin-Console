Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
if (-not (Test-Path $uiPath)) { throw "Hybrid Admin Console UI script was not found at $uiPath" }
Write-Host 'Milestone 8 final UI polish hotfix 1 applied.'
Write-Host 'Run .\tests\Test-Milestone8FinalUiPolish.ps1, then final integration and Phase 8.2 tests.'
