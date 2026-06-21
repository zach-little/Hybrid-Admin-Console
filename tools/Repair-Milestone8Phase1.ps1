[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot 'src\Core\Core.RuntimeProfile.psm1'
$package = Join-Path $repoRoot 'src\Core\Core.RuntimeProfile.psm1'

if (-not (Test-Path -LiteralPath $source)) {
    throw "Runtime profile module was not found at $source"
}

# The ZIP is designed to be extracted at the repository root, so the repaired module
# is already placed in the final repo-relative location. This script exists to make
# the validation workflow explicit and to clear stale module state.
Remove-Module Core.RuntimeProfile -Force -ErrorAction SilentlyContinue

Write-Host 'Milestone 8 Phase 1 runtime profile strict-mode repair applied.' -ForegroundColor Cyan
Write-Host 'Run .\tests\Test-Milestone8Phase1.ps1' -ForegroundColor Gray
