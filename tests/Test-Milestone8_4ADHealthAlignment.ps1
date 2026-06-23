Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repo = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repo 'src/UI/Start-HybridAdminConsole.ps1'
Assert-Pass -Condition (Test-Path $uiPath) -Message 'Runtime UI entry point exists'

$content = Get-Content -LiteralPath $uiPath -Raw

Assert-Pass -Condition ($content -notmatch 'Active Directory\s+Ready') -Message 'Launch page no longer hard-codes Active Directory Ready'
Assert-Pass -Condition ($content -match 'RuntimeActiveDirectoryStatusText') -Message 'Launch page AD provider status is addressable'
Assert-Pass -Condition ($content -match 'function Get-HybridActiveDirectoryUiReadiness') -Message 'Runtime UI has shared AD readiness helper'
Assert-Pass -Condition ($content -match 'Get-HybridADProviderHealth') -Message 'AD readiness helper uses provider health when available'
Assert-Pass -Condition ($content -match 'Test-HybridActiveDirectoryProviderAvailable') -Message 'AD readiness helper falls back to module detection'
Assert-Pass -Condition ($content -match 'function Update-HybridRuntimeProviderStatus') -Message 'Startup launch page updates provider statuses dynamically'
Assert-Pass -Condition ($content -match 'Update-HybridRuntimeProviderStatus -Profile \$selectedProfile') -Message 'Selected runtime profile refreshes AD readiness text'
Assert-Pass -Condition ($content -match 'Set-HybridActiveDirectoryProviderStatusText -Readiness') -Message 'Console Provider Health card uses shared AD readiness result'
Assert-Pass -Condition ($content -notmatch 'Get-HybridUserServiceHealth\s*\r?\n\s*\$adAvailable') -Message 'Console Provider Health no longer relies on user-service provider slot only'
Assert-Pass -Condition ($content -match 'Detected / not connected') -Message 'UI distinguishes module detection from connected provider readiness'

Write-Host 'Milestone 8.4 AD health alignment tests passed.'
