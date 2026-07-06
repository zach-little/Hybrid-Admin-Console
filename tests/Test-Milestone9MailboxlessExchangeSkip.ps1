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
$script:ExchangeOnlineCallCount = 0
$script:GraphLookupIdentities = New-Object System.Collections.Generic.List[string]

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
        $script:ExchangeOnlineCallCount++
        throw 'Exchange Online should not be queried for a user with no mail signal.'
        return $null
    }.GetNewClosure()
    GetProviderHealth = { [pscustomobject]@{ Available = $true; Connected = $true; Status = 'Connected' } }.GetNewClosure()
}

$graphProvider = [pscustomobject]@{
    GetUser = {
        param([string]$Identity)
        [void]$script:GraphLookupIdentities.Add($Identity)
        if ([string]::Equals($Identity, 'mailboxless.user@atlas.test', [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                Id = 'graph-mailboxless-user'
                DisplayName = 'Mailboxless User'
                UserPrincipalName = 'mailboxless.user@atlas.test'
                Mail = ''
                PimRoles = @([pscustomobject]@{ DisplayName = 'Privileged Role Administrator'; AssignmentType = 'Eligible assignment'; Status = 'Eligible' })
                DirectoryRoles = @([pscustomobject]@{ DisplayName = 'Privileged Role Administrator'; AssignmentType = 'Eligible assignment'; Status = 'Eligible' })
            }
        }
        throw "Graph direct lookup failed for '$Identity'."
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

Initialize-HybridUserService -ActiveDirectoryProvider $adProvider -MicrosoftGraphProvider $graphProvider -ExchangeOnlineProvider $exchangeOnlineProvider -ExchangeOnPremisesProvider $onPremProvider | Out-Null

$user = Get-HybridUserMailboxDetails -Identity 'mailboxless'
$graphProfile = Get-HybridUserGraphProfile -Identity 'mailboxless'

Assert-True ($script:OnPremExchangeCallCount -eq 0) 'Mailboxless users skip on-prem Exchange recipient, forwarding, and distribution group lookups'
Assert-True ($script:ExchangeOnlineCallCount -eq 0) 'Mailboxless users skip Exchange Online mailbox lookup when no mail signal exists'
Assert-True ($null -ne $user.Mailbox -and -not [bool]$user.Mailbox.Summary.HasExchangeData) 'Mailboxless users return a clean no-Exchange-data mailbox source envelope'
Assert-True (-not [bool]$user.ExchangeLoaded) 'Mailboxless users complete mailbox hydration without reporting Exchange loaded'
Assert-True (@($script:GraphLookupIdentities | Where-Object { $_ -eq 'mailboxless' }).Count -gt 0 -and @($script:GraphLookupIdentities | Where-Object { $_ -eq 'mailboxless.user@atlas.test' }).Count -gt 0) 'Mailboxless ADM-style searches retry Graph with AD-derived UPN candidates'
Assert-True (@($graphProfile.PimRoles).Count -eq 1 -and $graphProfile.PimRoles[0].DisplayName -eq 'Privileged Role Administrator') 'Mailboxless ADM-style Graph fallback preserves PIM role data'

Write-Host 'Milestone 9 mailboxless Exchange skip tests passed.'
