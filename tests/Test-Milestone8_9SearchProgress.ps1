Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Content,[string]$Expected,[string]$Message)
    if ($Content -notlike "*$Expected*") { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$ui = Get-Content -LiteralPath (Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1') -Raw

Assert-Contains -Content $ui -Expected 'x:Name="SearchProgressPanel"' -Message 'Bottom status bar declares search progress panel'
Assert-Contains -Content $ui -Expected 'x:Name="SearchProgressStageText"' -Message 'Search progress has stage label'
Assert-Contains -Content $ui -Expected 'function Set-HybridSearchProgressStage' -Message 'Search progress stage function exists'
foreach ($stage in @('Search','Base User','Active Directory Details','Microsoft Graph','Exchange Online','Authentication Posture','Aggregation','Complete')) {
    Assert-Contains -Content $ui -Expected "Set-HybridSearchProgressStage -Stage '$stage'" -Message "Search progress includes $stage stage"
}
Assert-Contains -Content $ui -Expected "Exchange Online mailbox not loaded. Showing AD mail attribute only where available." -Message 'Exchange panel distinguishes AD mail from Exchange Online mailbox data'

Write-Host 'Milestone 8.9 search progress tests passed.'
