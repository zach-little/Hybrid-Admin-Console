$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$providerPath = Join-Path $repoRoot 'src\Infrastructure\Infrastructure.ExchangeOnPremises.psm1'
$servicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

function Assert-ContainsText {
    param([string]$Content,[string]$Needle,[string]$Message)
    if ($Content -notlike "*$Needle*") { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$provider = Get-Content -LiteralPath $providerPath -Raw
$service = Get-Content -LiteralPath $servicePath -Raw
$ui = Get-Content -LiteralPath $uiPath -Raw

Assert-ContainsText $provider 'Ensure-HybridExchangeOnPremisesConnection' 'On-prem Exchange provider connects when recipient data is requested'
Assert-ContainsText $provider 'Get-RemoteMailbox -Identity $Identity' 'On-prem Exchange provider queries remote mailbox data'
Assert-ContainsText $provider 'Get-HybridExchangeOnPremisesDistributionGroups' 'On-prem Exchange provider exposes distribution group lookup'
Assert-ContainsText $provider 'Members -eq' 'On-prem Exchange distribution group lookup uses recipient membership'
Assert-ContainsText $service 'OnPremisesRemoteMailbox' 'User service preserves on-prem remote mailbox separately'
Assert-ContainsText $service 'SourceProvider = if ($null -ne $mailbox) { ''ExchangeOnline'' } else { ''ExchangeOnPremises'' }' 'Mailbox details record whether data came from Exchange Online or Exchange On-Premises'
Assert-ContainsText $service '$distributionGroups.Count -eq 0 -and $onPremDistributionGroups.Count -gt 0' 'User service falls back to on-prem distribution groups when EXO groups are unavailable'
Assert-ContainsText $service '$effectiveMailbox = if ($null -ne $mailbox) { $mailbox } elseif ($null -ne $onPremRemoteMailbox) { $onPremRemoteMailbox } else { $onPremRecipient }' 'User service treats on-prem remote mailbox as valid mailbox detail data'
Assert-ContainsText $ui 'RuntimeProviderDetailsText' 'Start page provider card has dynamic provider detail text'
Assert-ContainsText $ui 'Set-HybridRuntimeProviderDetailsText' 'Start page refreshes provider details from runtime/profile providers'
Assert-ContainsText $ui '$sourceProvider loaded: $recipientType | $primarySmtp' 'Exchange mailbox card displays the source provider used for mailbox details'
Assert-ContainsText $ui '$state = "$state ($exchangeSource)"' 'Aggregation card annotates ExchangeMailbox with Exchange Online or Exchange On-Premises source'

Write-Host 'Milestone 8.9 Exchange On-Premises runtime hydration tests passed.'
