[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$testPath = Join-Path $repoRoot 'tests\Test-Milestone8Phase5_5.ps1'

if (-not (Test-Path $uiPath)) { throw "Missing UI script: $uiPath" }
if (-not (Test-Path $testPath)) { throw "Missing Phase 5.5 test: $testPath" }

$content = Get-Content -LiteralPath $uiPath -Raw
foreach ($marker in @('ShellRoot','StartupRegion','MainRegion','StatusBarRegion','OverlayRegion','MainDashboardGrid')) {
    if ($content -notmatch [regex]::Escape($marker)) { throw "Phase 5.5 layout marker missing: $marker" }
}

Write-Host 'Milestone 8 Phase 5.5 shell and dashboard layout foundation applied.'
Write-Host 'Run .\tests\Test-Milestone8Phase5_5.ps1, then cumulative Milestone 8 Phase 5 through Phase 1 tests.'
