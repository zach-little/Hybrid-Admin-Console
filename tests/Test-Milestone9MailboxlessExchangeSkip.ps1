Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1') -Force
Clear-HybridUserService | Out-Null

$script:OnPremExchangeCallCount = 0

$adProvider = [pscustomobject]@{
    GetUser = {
        param([string]$Identity)
        [pscustomobject]@{
            DisplayName = 'Mailboxless User'
            UserPrincipalName = 'mailboxless.user@atlas.test'
            SamAccountName = 'mailboxless'
            Mail = ''
            ProxyAddresses = @()
            TargetAddress = ''
            MailNickname = ''
        }
    }.GetNewClosure()
    GetProviderHealth = { [pscustomobject]@{ Available = $true; Connected = $true; Status = 'Connected' } }.GetNewClosure()
}

$exchangeOnlineProvider = [pscustomobject]@{
    GetMailbox = {
        param([string]$Identity)
        return $null
    }.GetNewClosure()
    GetProviderHealth = { [pscustomobject]@{ Available = $true; Connected = $true; Status = 'Connected' } }.GetNewClosure()
}

$onPremProvider = [pscustomobject]@{
    GetRemoteMailbox = {
        param([string]$Identity)
        $script:OnPremExchangeCallCount++
        throw 'On-prem Exchange should not be queried for a user with no mail signal.'
    }.GetNewClosure()
    GetRecipient = {
        param([string]$Identity)
        $script:OnPremExchangeCallCount++
        throw 'On-prem Exchange should not be queried for a user with no mail signal.'
    }.GetNewClosure()
    GetMailboxForwarding = {
        param([string]$Identity)
        $script:OnPremExchangeCallCount++
        throw 'On-prem forwarding should not be queried without a recipient.'
    }.GetNewClosure()
    GetDistributionGroups = {
        param([string]$Identity)
        $script:OnPremExchangeCallCount++
        throw 'On-prem distribution groups should not be queried without a recipient.'
    }.GetNewClosure()
    GetProviderHealth = { [pscustomobject]@{ Available = $true; Connected = $true; Status = 'Connected' } }.GetNewClosure()
}

Initialize-HybridUserService -ActiveDirectoryProvider $adProvider -ExchangeOnlineProvider $exchangeOnlineProvider -ExchangeOnPremisesProvider $onPremProvider | Out-Null

$user = Get-HybridUserMailboxDetails -Identity 'mailboxless.user@atlas.test'

Assert-True ($script:OnPremExchangeCallCount -eq 0) 'Mailboxless users skip on-prem Exchange recipient, forwarding, and distribution group lookups'
Assert-True ($null -ne $user.Mailbox -and -not [bool]$user.Mailbox.Summary.HasExchangeData) 'Mailboxless users return a clean no-Exchange-data mailbox source envelope'
Assert-True (-not [bool]$user.ExchangeLoaded) 'Mailboxless users complete mailbox hydration without reporting Exchange loaded'

Write-Host 'Milestone 9 mailboxless Exchange skip tests passed.'
