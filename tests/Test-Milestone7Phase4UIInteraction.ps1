$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$ui = Get-Content -Path $uiPath -Raw

Assert-True ($ui -match 'Invoke-UserSearch -Query \$controls\.SearchBox\.Text') 'Manual search still reads current textbox value'
Assert-True ($ui -match 'Update-DetailPanels -User \$user -Query \$effectiveQuery') 'Manual search refreshes AD detail panels'
Assert-True ($ui -match 'Update-ExchangePanels -User \$user -Query \$effectiveQuery') 'Manual search refreshes Exchange panels'
Assert-True ($ui -match 'MailboxDelegationList\.Items\.Clear\(\)') 'Search reset clears stale mailbox delegations'
Assert-True ($ui -match 'DistributionGroupsList\.Items\.Clear\(\)') 'Search reset clears stale distribution groups'
Assert-True ($ui -match 'No forwarding configured') 'Exchange panel shows clear forwarding empty state'
Assert-True ($ui -match 'Live AD and Exchange vertical slice result returned through HybridUserService') 'Status identifies Exchange vertical slice'

Write-Host ''
Write-Host 'Milestone 7 Phase 4 UI interaction tests passed.'
