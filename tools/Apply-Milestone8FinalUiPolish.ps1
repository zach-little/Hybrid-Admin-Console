Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$required = @(
    'src\UI\Start-HybridAdminConsole.ps1',
    'tests\Test-Milestone8FinalUiPolish.ps1',
    'docs\Milestones\MILESTONE_8_FINAL_UI_POLISH.md'
)
foreach ($relative in $required) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required UI polish file: $relative" }
}
Write-Host 'Milestone 8 final UI polish applied.'
Write-Host 'Run .\tests\Test-Milestone8FinalUiPolish.ps1, then final integration and Phase 8.2 tests.'
