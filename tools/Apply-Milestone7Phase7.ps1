[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'src\Application\Application.HybridUserAggregationService.psm1',
    'src\UI\Start-HybridAdminConsole.ps1',
    'tests\Test-Milestone7Phase7.ps1',
    'tests\Test-Milestone7Phase7AggregationCard.ps1',
    'docs\Milestones\MILESTONE_7_PHASE_7.md'
)

foreach ($relative in $required) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing Phase 7 file: $relative. Extract the ZIP into the repository root first." }
}

$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$parseErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $uiPath -Raw), [ref]$parseErrors)
if (@($parseErrors).Count -gt 0) {
    throw "UI parse check failed after Phase 7 apply: $($parseErrors[0].Message)"
}

Write-Host 'Milestone 7 Phase 7 aggregation layer applied.'
Write-Host 'Run cumulative tests through .\tests\Test-Milestone7Phase7.ps1 and .\tests\Test-Milestone7Phase7AggregationCard.ps1.'
