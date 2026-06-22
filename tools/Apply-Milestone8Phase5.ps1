[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'src\UI\Start-HybridAdminConsole.ps1',
    'tests\Test-Milestone8Phase5.ps1',
    'docs\Milestones\MILESTONE_8_PHASE_5.md'
)

foreach ($relativePath in $required) {
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "Required Phase 5 file missing: $relativePath" }
}

Write-Host 'Milestone 8 Phase 5 startup shell applied.'
Write-Host 'Run .\tests\Test-Milestone8Phase5.ps1, then cumulative Milestone 8 Phase 4 through Phase 1 tests.'
