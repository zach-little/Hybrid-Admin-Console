Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src/UI/Start-HybridAdminConsole.ps1'
$servicePath = Join-Path $repoRoot 'src/Application/Application.HybridUserService.psm1'

$ui = Get-Content -LiteralPath $uiPath -Raw
$svc = Get-Content -LiteralPath $servicePath -Raw

Assert-Pass -Condition ($ui -match 'function Write-HybridUiHydrationDiagnostic') -Message 'Runtime UI has persistent hydration diagnostics writer'
Assert-Pass -Condition ($ui -match 'logs\\hydration-diagnostics\.log|hydration-diagnostics\.log') -Message 'Runtime UI points operators to hydration diagnostics log'
Assert-Pass -Condition ($ui -match 'function Invoke-HybridUiHydrationStage') -Message 'Runtime UI has isolated hydration stage executor'
Assert-Pass -Condition ($ui -match "Stage 'ActiveDirectoryDetails'") -Message 'AD details hydration is tracked as an independent stage'
Assert-Pass -Condition ($ui -match "Stage 'ExchangeMailbox'") -Message 'Exchange mailbox hydration is tracked as an independent stage'
Assert-Pass -Condition ($ui -match "Stage 'MicrosoftGraph'") -Message 'Graph hydration is tracked as an independent stage'
Assert-Pass -Condition ($ui -match "Stage 'AuthenticationPosture'") -Message 'Authentication hydration is tracked as an independent stage'
Assert-Pass -Condition ($ui -match 'AD details failed') -Message 'AD detail failures are surfaced visibly in UI'
Assert-Pass -Condition ($ui -match 'Exchange mailbox load failed') -Message 'Exchange failures are surfaced visibly in UI'
Assert-Pass -Condition ($ui -match 'Update-DetailPanels -User \$user -Query \$effectiveQuery[\s\S]+Update-ExchangePanels -User \$user -Query \$effectiveQuery') -Message 'AD detail hydration runs before Exchange mailbox hydration'

Assert-Pass -Condition ($svc -match 'function Write-HybridUserHydrationDiagnostic') -Message 'Hybrid user service has persistent hydration diagnostics writer'
Assert-Pass -Condition ($svc -match 'Application\.HybridUserService') -Message 'Service diagnostics identify application service source'
Assert-Pass -Condition ($svc -match 'Failed \$operationName') -Message 'Provider operation failures are logged'
Assert-Pass -Condition ($svc -match 'Search providers returned AD=') -Message 'Search provider result counts are logged'
Assert-Pass -Condition ($svc -match 'Base hydration results AD=') -Message 'Base hydration provider result counts are logged'

Write-Host 'Milestone 8.6 hydration diagnostics tests passed.'
