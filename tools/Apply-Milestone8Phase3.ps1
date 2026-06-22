Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'src\Core\Core.Runtime.psm1',
    'src\Core\Core.Runtime.psd1',
    'profiles\Runtime\Hybrid.example.json',
    'tests\Test-Milestone8Phase3.ps1',
    'docs\Milestones\MILESTONE_8_PHASE_3.md'
)

foreach ($relativePath in $required) {
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing Phase 3 file: $relativePath" }
}

Write-Host 'Milestone 8 Phase 3 runtime provider modes applied.' -ForegroundColor Cyan
Write-Host 'Run .\tests\Test-Milestone8Phase3.ps1, then cumulative Phase 2, Phase 1, and Milestone 7 tests.' -ForegroundColor Yellow
