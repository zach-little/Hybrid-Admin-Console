<#
.SYNOPSIS
Validates the Milestone 7 Phase 2 UI vertical slice additions.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

function Assert-HybridTest {
    param(
        [Parameter(Mandatory=$true)][bool]$Condition,
        [Parameter(Mandatory=$true)][string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    Write-Host "PASS: $Message"
}

Assert-HybridTest -Condition (Test-Path $uiPath) -Message 'Phase 2 UI entry point exists'

$content = Get-Content -Path $uiPath -Raw

Assert-HybridTest -Condition ($content -match 'Initialize-HybridUserService') -Message 'UI initializes the Hybrid User Service'
Assert-HybridTest -Condition ($content -match 'Search-HybridUser') -Message 'UI searches through the application service'
Assert-HybridTest -Condition ($content -notmatch 'Get-ADUser') -Message 'UI does not call Active Directory directly'
Assert-HybridTest -Condition ($content -match 'ProviderStatusText') -Message 'UI contains provider health status text'
Assert-HybridTest -Condition ($content -match 'ProviderDot') -Message 'UI contains provider health visual indicator'
Assert-HybridTest -Condition ($content -match 'SearchProgress') -Message 'UI contains search progress indicator'
Assert-HybridTest -Condition ($content -match 'Set-HybridUiBusyState') -Message 'UI implements loading/busy state handling'
Assert-HybridTest -Condition ($content -match 'Update-HybridUiHealth') -Message 'UI refreshes provider health'
Assert-HybridTest -Condition ($content -match 'Active Directory Properties') -Message 'UI displays live AD property section'
Assert-HybridTest -Condition ($content -match 'CompanyText') -Message 'UI exposes AD company field'
Assert-HybridTest -Condition ($content -match 'OfficeText') -Message 'UI exposes AD office field'
Assert-HybridTest -Condition ($content -match 'EmployeeIdText') -Message 'UI exposes AD employee ID field'
Assert-HybridTest -Condition ($content -match 'DistinguishedNameText') -Message 'UI exposes AD distinguished name field'
Assert-HybridTest -Condition ($content -match 'AccountStateText') -Message 'UI exposes AD account state field'
Assert-HybridTest -Condition ($content -match 'Search failed') -Message 'UI presents search errors in the result pane'
Assert-HybridTest -Condition ($content -match 'Live AD vertical slice result returned through HybridUserService') -Message 'UI identifies the service-backed vertical slice'

Write-Host ''
Write-Host 'Milestone 7 Phase 2 UI tests passed.'
