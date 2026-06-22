Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'src\Core\Core.Runtime.psm1',
    'src\Core\Core.Runtime.psd1',
    'tests\Test-Milestone8Phase2.ps1',
    'docs\Milestones\MILESTONE_8_PHASE_2.md'
)

foreach ($relative in $required) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing required Phase 8.2 file: $relative" }
}

Write-Host 'Milestone 8 Phase 2 runtime bootstrap engine applied.' -ForegroundColor Cyan
Write-Host 'Run .\tests\Test-Milestone8Phase2.ps1, then cumulative Milestone 8 Phase 1 and Milestone 7 tests.' -ForegroundColor Cyan
