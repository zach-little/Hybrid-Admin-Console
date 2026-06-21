Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'src\Core\Core.RuntimeProfile.psm1',
    'profiles\Runtime\Simulation.json',
    'profiles\Runtime\Atlas-GCCHigh-Live.example.json',
    'tests\Test-Milestone8Phase1.ps1'
)

foreach ($relative in $required) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing required Phase 8 file: $relative" }
}

Write-Host 'Milestone 8 Phase 1 runtime profile foundation applied.' -ForegroundColor Cyan
Write-Host 'Run .\tests\Test-Milestone8Phase1.ps1, then cumulative Milestone 7 tests.' -ForegroundColor Cyan
