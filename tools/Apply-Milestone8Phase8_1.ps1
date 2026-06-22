Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'src\Application\Application.RuntimeProfileManager.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Runtime Profile Manager module not found: $modulePath"
}

Import-Module $modulePath -Force -Global
$profiles = @(Get-HybridRuntimeProfileSummary -RepositoryRoot $repoRoot)
if ($profiles.Count -eq 0) {
    throw 'No runtime profiles were discovered. Ensure profiles\Runtime contains at least Simulation.json.'
}

$selection = Get-HybridRuntimeProfileSelection -RepositoryRoot $repoRoot
if ($null -eq $selection) {
    throw 'Runtime Profile Manager could not resolve an initial profile selection.'
}

Write-Host 'Milestone 8 Phase 8.1 Runtime Profile Discovery applied.'
Write-Host ('Discovered {0} runtime profile(s). Initial selection: {1}' -f $profiles.Count, $selection.ProfileName)
Write-Host 'Run .\tests\Test-Milestone8Phase8_1.ps1, then cumulative Milestone 8 Phase 7 through Phase 1 tests.'
