[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot 'src\Application\Application.HybridUserAggregationService.psm1'
$packageSource = Join-Path $repoRoot 'src\Application\Application.HybridUserAggregationService.psm1.phase7fix'
if (-not (Test-Path -LiteralPath $packageSource)) {
    throw "Package source not found: $packageSource"
}
$backup = "$source.bak_phase7_hf15_$(Get-Date -Format yyyyMMddHHmmss)"
Copy-Item -LiteralPath $source -Destination $backup -Force
Copy-Item -LiteralPath $packageSource -Destination $source -Force
Write-Host 'Milestone 7 Phase 7 aggregation service repair applied.'
Write-Host "Backup: $backup"
