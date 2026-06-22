[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$testPath = Join-Path $repoRoot 'tests\Test-Milestone8Phase6.ps1'

if (-not (Test-Path $uiPath)) { throw "Missing UI script: $uiPath" }
if (-not (Test-Path $testPath)) { throw "Missing Phase 6 test: $testPath" }

$content = Get-Content -LiteralPath $uiPath -Raw
foreach ($marker in @('Runtime Profile Wizard','RuntimeProfileWizardView','Show-HybridRuntimeProfileWizard','Save-HybridRuntimeProfileFromWizard')) {
    if ($content -notmatch [regex]::Escape($marker)) { throw "Phase 6 wizard marker missing: $marker" }
}

Write-Host 'Milestone 8 Phase 6 Runtime Profile Wizard applied.'
Write-Host 'Run .\tests\Test-Milestone8Phase6.ps1, then cumulative Milestone 8 Phase 5.5 through Phase 1 tests.'
