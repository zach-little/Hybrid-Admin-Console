Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
Assert-True -Condition (Test-Path $uiPath) -Message 'Phase 4 UI entry point exists'

$content = Get-Content -Path $uiPath -Raw
Assert-True -Condition ($content -match 'x:Name="ExchangeMailboxCard"') -Message 'UI defines a visible Exchange mailbox card'
Assert-True -Condition ($content -match 'x:Name="ExchangeSummaryText"') -Message 'UI defines Exchange summary text'
Assert-True -Condition ($content -match 'Get-HybridUserMailboxDetails') -Message 'UI loads mailbox details through the application service'
Assert-True -Condition ($content -match 'Exchange loaded:') -Message 'UI reports Exchange details after mailbox load'

$exchangeIndex = $content.IndexOf('x:Name="ExchangeMailboxCard"')
$managerIndex = $content.IndexOf('x:Name="ManagerCard"')
Assert-True -Condition ($exchangeIndex -ge 0 -and $managerIndex -ge 0 -and $exchangeIndex -lt $managerIndex) -Message 'Exchange card is positioned before secondary AD cards for immediate visibility'

foreach ($marker in @('Primary SMTP','Recipient Type','Mailbox Status','Forwarding','Delegation','Distribution Groups')) {
    Assert-True -Condition ($content -match [regex]::Escape($marker)) -Message "Exchange UI exposes $marker"
}

Write-Host ''
Write-Host 'Milestone 7 Phase 4 visible Exchange UI tests passed.'
