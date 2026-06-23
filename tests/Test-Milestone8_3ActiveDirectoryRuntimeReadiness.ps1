Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$root = Split-Path -Parent $PSScriptRoot
$adModule = Join-Path $root 'src\Infrastructure\Infrastructure.ActiveDirectory.psm1'
Assert-Pass -Condition (Test-Path $adModule) -Message 'Active Directory infrastructure module exists'

$content = Get-Content -LiteralPath $adModule -Raw
Assert-Pass -Condition ($content -match 'function Initialize-HybridActiveDirectoryRuntime') -Message 'AD runtime readiness helper exists'
Assert-Pass -Condition ($content -match 'Import-Module ActiveDirectory -ErrorAction Stop') -Message 'AD runtime readiness imports ActiveDirectory module explicitly'
Assert-Pass -Condition ($content -match 'Get-Command -Name \$requiredCommand') -Message 'AD runtime readiness validates required AD commands'
Assert-Pass -Condition ($content -match "'Get-ADUser','Get-ADPrincipalGroupMembership','Get-ADOrganizationalUnit'") -Message 'AD runtime readiness covers user, group membership, and OU commands'
Assert-Pass -Condition ($content -match 'ActiveDirectoryRuntimeUnavailable') -Message 'AD runtime readiness emits structured unavailable error code'
Assert-Pass -Condition ($content -match 'RuntimeReady') -Message 'AD provider tracks runtime readiness state'
Assert-Pass -Condition ($content -match 'LastReadinessError') -Message 'AD provider tracks readiness error detail'
Assert-Pass -Condition ($content -match 'RuntimeReadiness') -Message 'AD provider declares runtime readiness capability'
Assert-Pass -Condition ($content -match 'function Assert-HybridADProviderAvailable[\s\S]*Initialize-HybridActiveDirectoryRuntime \| Out-Null') -Message 'AD provider availability assertion performs runtime readiness check'
Assert-Pass -Condition ($content -match 'function Invoke-HybridADCommand[\s\S]*Initialize-HybridActiveDirectoryRuntime \| Out-Null[\s\S]*Get-Command \$CommandName') -Message 'AD command wrapper performs runtime readiness before command invocation'
Assert-Pass -Condition ($content -match 'function Test-HybridActiveDirectoryProviderAvailable[\s\S]*Initialize-HybridActiveDirectoryRuntime') -Message 'AD availability check uses runtime readiness path'
Assert-Pass -Condition ($content -match 'function Get-HybridADProviderHealth[\s\S]*Initialize-HybridActiveDirectoryRuntime') -Message 'AD health uses runtime readiness path when initialized'
Assert-Pass -Condition ($content -match "-Version '0.8.3'") -Message 'AD provider lifecycle reports v0.8.3 hotfix version'
Assert-Pass -Condition ($content -match "'Initialize-HybridActiveDirectoryRuntime'") -Message 'AD runtime readiness helper is exported for diagnostics'

Write-Host 'Milestone 8.3 Active Directory runtime readiness tests passed.'
