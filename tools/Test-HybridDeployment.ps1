Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $root 'src\Core\Core.Deployment.psd1'
Import-Module $modulePath -Force

$result = Test-HybridDeploymentLayout -RepositoryRoot $root
$result.Checks | ForEach-Object {
    $prefix = if ($_.Passed) { 'PASS' } else { $_.Severity.ToUpperInvariant() }
    Write-Host ("{0}: {1} - {2}" -f $prefix, $_.Name, $_.Message)
}

if (-not $result.IsReady) {
    throw 'Deployment validation failed.'
}

Write-Host 'Hybrid Admin Platform deployment layout is ready.' -ForegroundColor Green
return $result
