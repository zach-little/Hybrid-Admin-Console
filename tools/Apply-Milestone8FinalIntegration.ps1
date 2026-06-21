Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$required = @(
    'src\UI\Start-HybridAdminConsole.ps1',
    'src\Application\Application.RuntimeProfileManager.psm1',
    'tests\Test-Milestone8FinalIntegration.ps1',
    'docs\Milestones\MILESTONE_8_FINAL_INTEGRATION.md'
)
foreach ($relative in $required) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required Phase 8 final integration file: $relative" }
}
Write-Host 'Milestone 8 final runtime platform integration applied.'
Write-Host 'Run .\tests\Test-Milestone8FinalIntegration.ps1, then cumulative Milestone 8 tests.'
