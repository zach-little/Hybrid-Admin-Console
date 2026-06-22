[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $root 'src\Core\Core.Deployment.psd1'
Import-Module $modulePath -Force

$result = New-HybridDeploymentPackage -RepositoryRoot $root -OutputPath $OutputPath -Force:$Force
Write-Host ("Deployment package created: {0}" -f $result.PackagePath) -ForegroundColor Green
return $result
