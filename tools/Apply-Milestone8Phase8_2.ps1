Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'src\Application\Application.RuntimeProfileManager.psm1',
    'src\UI\Start-HybridAdminConsole.ps1',
    'tests\Test-Milestone8Phase8_2.ps1',
    'docs\Milestones\MILESTONE_8_PHASE_8_2.md'
)
foreach ($relative in $required) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required Phase 8.2 file missing: $relative" }
}

Write-Host 'Milestone 8 Phase 8.2 runtime profile card view applied.'
Write-Host 'Run .\tests\Test-Milestone8Phase8_2.ps1, then cumulative Milestone 8 Phase 8.1 and prior tests.'
