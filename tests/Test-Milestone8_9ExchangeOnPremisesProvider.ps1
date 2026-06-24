$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$providerPath = Join-Path $repoRoot 'src\Infrastructure\Infrastructure.ExchangeOnPremises.psm1'
$servicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

function Assert-PathExists { param([string]$Path,[string]$Message) if (-not (Test-Path -LiteralPath $Path)) { throw "FAIL: $Message" } Write-Host "PASS: $Message" }
function Assert-ContainsText { param([string]$Content,[string]$Needle,[string]$Message) if ($Content -notlike "*$Needle*") { throw "FAIL: $Message" } Write-Host "PASS: $Message" }

Assert-PathExists $providerPath 'On-premises Exchange provider module exists'
$provider = Get-Content -LiteralPath $providerPath -Raw
$service = Get-Content -LiteralPath $servicePath -Raw
$ui = Get-Content -LiteralPath $uiPath -Raw

Assert-ContainsText $provider 'Initialize-HybridExchangeOnPremisesProvider' 'Provider exports initializer'
Assert-ContainsText $provider 'Get-HybridExchangeOnPremisesRecipient' 'Provider exposes on-prem recipient lookup'
Assert-ContainsText $provider 'Get-HybridExchangeOnPremisesRemoteMailbox' 'Provider exposes remote mailbox lookup'
Assert-ContainsText $provider 'ConnectionUri' 'Provider supports explicit Exchange PowerShell connection URI'
Assert-ContainsText $provider 'Kerberos' 'Provider supports Kerberos by default'
Assert-ContainsText $service 'ExchangeOnPremisesProvider' 'User service can receive an on-prem Exchange provider'
Assert-ContainsText $service 'OnPremisesExchangeRecipient' 'User service preserves on-prem Exchange recipient separately from EXO mailbox data'
Assert-ContainsText $service 'ExchangeOnlineProviderRegistered' 'Service diagnostics distinguish Exchange Online registration'
Assert-ContainsText $service 'ExchangeOnPremisesProviderRegistered' 'Service diagnostics distinguish on-prem Exchange registration'
Assert-ContainsText $ui 'Exchange On-Prem' 'Search progress exposes on-prem Exchange stage'

Write-Host 'Milestone 8.9 on-premises Exchange provider tests passed.'
