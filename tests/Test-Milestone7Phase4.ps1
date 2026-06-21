$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "FAIL: $Message. Expected '$Expected' but got '$Actual'." }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
$simulatorPath = Join-Path $repoRoot 'src\Infrastructure\Mock\Infrastructure.DirectorySimulator.psm1'
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

Import-Module $servicePath -Force
Import-Module $simulatorPath -Force

Assert-True ([bool](Get-Command Get-HybridUserMailboxDetails -ErrorAction SilentlyContinue)) 'Get-HybridUserMailboxDetails exported'
Assert-True ([bool](Get-Command New-HybridDirectorySimulatorProviders -ErrorAction SilentlyContinue)) 'Directory simulator provider factory exported'

$providers = New-HybridDirectorySimulatorProviders
Initialize-HybridUserService -ActiveDirectoryProvider $providers.ActiveDirectory -MicrosoftGraphProvider $providers.MicrosoftGraph -ExchangeOnlineProvider $providers.ExchangeOnline | Out-Null

$user = Search-HybridUser -Query 'Alex Morgan' | Select-Object -First 1
Assert-Equal -Actual $user.DisplayName -Expected 'Alex Morgan' -Message 'Directory simulator returns searched user'

$details = Get-HybridUserDetails -Identity $user.UserPrincipalName
Assert-True ($details.ManagerDisplayName -ne $details.DisplayName) 'Directory simulator does not return the selected user as their own manager'
$directReportNames = @($details.DirectReports | ForEach-Object { $_.DisplayName })
Assert-True (-not ($directReportNames -contains $details.DisplayName)) 'Directory simulator does not return the selected user as their own direct report'

$manager = Search-HybridUser -Query 'Taylor Reed' | Select-Object -First 1
$managerDetails = Get-HybridUserDetails -Identity $manager.UserPrincipalName
$managerReportNames = @($managerDetails.DirectReports | ForEach-Object { $_.DisplayName })
Assert-True ($managerReportNames -contains 'Alex Morgan') 'Directory simulator keeps manager/direct-report relationships coherent'

$mailboxUser = Get-HybridUserMailboxDetails -Identity $user.UserPrincipalName
Assert-True ($mailboxUser.ExchangeLoaded -eq $true) 'Exchange detail lookup marks user exchange data loaded'
Assert-True ($null -ne $mailboxUser.MailboxDetails) 'Exchange detail lookup attaches MailboxDetails'
Assert-Equal -Actual $mailboxUser.MailboxDetails.PrimarySmtpAddress -Expected 'amorgan@atlas-tech.com' -Message 'Mailbox primary SMTP is populated'
Assert-Equal -Actual $mailboxUser.MailboxDetails.RecipientTypeDetails -Expected 'UserMailbox' -Message 'Recipient type is populated'
Assert-True (@($mailboxUser.MailboxDetails.Delegations).Count -gt 0) 'Mailbox delegation list is populated through Exchange provider'
Assert-True (@($mailboxUser.MailboxDetails.DistributionGroups).Count -gt 0) 'Distribution group list is populated through Exchange provider'

$health = Get-HybridUserServiceHealth
Assert-True ($health.MailboxCacheEntries -ge 1) 'Service health reports mailbox cache entries'

$ui = Get-Content -Path $uiPath -Raw
Assert-True ($ui -match 'Infrastructure\.DirectorySimulator\.psm1') 'UI consumes directory simulator in mock mode'
Assert-True ($ui -match 'Get-HybridUserMailboxDetails') 'UI consumes mailbox detail service'
Assert-True ($ui -match 'Exchange Mailbox') 'UI includes Exchange mailbox card'
Assert-True ($ui -match 'MailboxDelegationList') 'UI includes mailbox delegation list'
Assert-True ($ui -match 'DistributionGroupsList') 'UI includes distribution groups list'
Assert-True ($ui -match 'ForwardingText') 'UI includes forwarding status field'

Clear-HybridUserService | Out-Null
Write-Host ''
Write-Host 'Milestone 7 Phase 4 Exchange vertical and directory simulator tests passed.'
