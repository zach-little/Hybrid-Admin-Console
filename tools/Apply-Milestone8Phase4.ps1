Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeModule = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'
$runtimeManifest = Join-Path $repoRoot 'src\Core\Core.Runtime.psd1'
$testPath = Join-Path $repoRoot 'tests\Test-Milestone8Phase4.ps1'
$docPath = Join-Path $repoRoot 'docs\Milestones\MILESTONE_8_PHASE_4.md'

foreach ($path in @($runtimeModule,$runtimeManifest,$testPath,$docPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required Phase 4 file missing: $path" }
}

Write-Host 'Milestone 8 Phase 4 startup diagnostics engine applied.' -ForegroundColor Cyan
Write-Host 'Run .\tests\Test-Milestone8Phase4.ps1, then cumulative Milestone 8 Phase 3, Phase 2, and Phase 1 tests.' -ForegroundColor Yellow
