Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Get-TestObjectPropertyValue {
    param(
        $InputObject,
        [Parameter(Mandatory)][string[]]$Names,
        $Default = $null
    )

    foreach ($name in $Names) {
        if ($null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains $name) {
            return $InputObject.$name
        }
    }

    return $Default
}


$repoRoot = Split-Path -Parent $PSScriptRoot

Import-Module (Join-Path $repoRoot 'src/Core/Core.Authentication.psm1') -Force
Import-Module (Join-Path $repoRoot 'src/Core/Core.Authentication.Manager.psm1') -Force
Import-Module (Join-Path $repoRoot 'src/Core/Core.Authentication.MSAL.psm1') -Force
Import-Module (Join-Path $repoRoot 'src/Core/Core.Provider.ExchangeOnline.psm1') -Force

Assert-Pass -Condition ([bool](Get-Command New-HybridExchangeOnlineProviderContext -ErrorAction SilentlyContinue)) -Message 'Exchange Online provider context helper exported'
Assert-Pass -Condition ([bool](Get-Command Initialize-HybridExchangeOnlineProvider -ErrorAction SilentlyContinue)) -Message 'Exchange Online provider initializer exported'
Assert-Pass -Condition ([bool](Get-Command Search-HybridExchangeOnlineMailbox -ErrorAction SilentlyContinue)) -Message 'Exchange Online mailbox search command exported'
Assert-Pass -Condition ([bool](Get-Command Get-HybridExchangeOnlineMailbox -ErrorAction SilentlyContinue)) -Message 'Exchange Online mailbox get command exported'
Assert-Pass -Condition ([bool](Get-Command Get-HybridExchangeOnlineProviderHealth -ErrorAction SilentlyContinue)) -Message 'Exchange Online provider health command exported'

Initialize-HybridMockAuthenticationAdapters -Force | Out-Null
Clear-HybridAuthenticationSessionCache

$tenant = [pscustomobject]@{
    PSTypeName = 'Hybrid.TenantContext'
    TenantId = '00000000-0000-0000-0000-000000000000'
    PrimaryDomain = 'atlas-tech.com'
}

$cloud = [pscustomobject]@{
    PSTypeName = 'Hybrid.CloudEnvironment'
    Name = 'USGovernment'
    GraphEndpoint = 'https://graph.microsoft.us'
    ExchangeOnlineEndpoint = 'https://outlook.office365.us'
}

$mailboxes = @(
    [pscustomobject]@{
        Id = 'alex.morgan'
        UserPrincipalName = 'alex.morgan@atlas-tech.com'
        PrimarySmtpAddress = 'alex.morgan@atlas-tech.com'
        DisplayName = 'Alex Morgan'
        MailboxType = 'UserMailbox'
        ExchangeGuid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        RecipientType = 'UserMailbox'
    },
    [pscustomobject]@{
        Id = 'shared.helpdesk'
        UserPrincipalName = 'shared.helpdesk@atlas-tech.com'
        PrimarySmtpAddress = 'helpdesk@atlas-tech.com'
        DisplayName = 'Helpdesk Shared Mailbox'
        MailboxType = 'SharedMailbox'
        ExchangeGuid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        RecipientType = 'SharedMailbox'
    }
)

$context = New-HybridExchangeOnlineProviderContext `
    -TenantContext $tenant `
    -CloudEnvironment $cloud `
    -AuthenticationMethod 'Interactive' `
    -Scopes @('https://outlook.office365.us/.default') `
    -MailboxData $mailboxes

Assert-Pass -Condition ($context.PSObject.TypeNames -contains 'Hybrid.ExchangeOnline.ProviderContext') -Message 'Exchange Online provider context has platform type name'
Assert-Pass -Condition ($context.TenantContext.TenantId -eq $tenant.TenantId) -Message 'Exchange Online provider context preserves tenant'
Assert-Pass -Condition (@($context.Scopes) -contains 'https://outlook.office365.us/.default') -Message 'Exchange Online provider context preserves scopes'

$service = Initialize-HybridExchangeOnlineProvider -Context $context
Assert-Pass -Condition ($service.PSObject.TypeNames -contains 'Hybrid.ExchangeOnline.ProviderService') -Message 'Exchange Online provider service has platform type name'
Assert-Pass -Condition ($service.ProviderName -eq 'ExchangeOnline') -Message 'Exchange Online provider service has provider name'

$session = @($service.GetAuthenticationSession())[0]
Assert-Pass -Condition ($session.PSObject.TypeNames -contains 'Hybrid.AuthenticationSession') -Message 'Exchange Online provider acquires platform authentication session'
$sessionMethod = [string](Get-TestObjectPropertyValue -InputObject $session -Names @('AuthenticationMethod','MethodName','Method') -Default '')
Assert-Pass -Condition ($sessionMethod -eq 'Interactive') -Message 'Exchange Online provider uses authentication manager adapter'

Assert-Pass -Condition ([bool](@($service.Supports('Mailboxes'))[0])) -Message 'Exchange Online provider reports Mailboxes capability'
Assert-Pass -Condition ([bool](@($service.Supports('AuthenticationSession'))[0])) -Message 'Exchange Online provider reports AuthenticationSession capability'
Assert-Pass -Condition (-not [bool](@($service.Supports('DeviceCode'))[0])) -Message 'Exchange Online provider does not report Device Code capability'

$searchResults = @(Search-HybridExchangeOnlineMailbox -Query 'Alex' -Service $service)
Assert-Pass -Condition ($searchResults.Count -eq 1) -Message 'Exchange Online provider search returns matching mailbox'
Assert-Pass -Condition ($searchResults[0].PSObject.TypeNames -contains 'Hybrid.ExchangeOnline.Mailbox') -Message 'Exchange Online search returns mailbox model'
Assert-Pass -Condition ($searchResults[0].Source -eq 'ExchangeOnline') -Message 'Exchange Online mailbox model records ExchangeOnline source'
Assert-Pass -Condition ($searchResults[0].PrimarySmtpAddress -eq 'alex.morgan@atlas-tech.com') -Message 'Exchange Online mailbox model preserves primary SMTP address'

$mailbox = @(Get-HybridExchangeOnlineMailbox -Identity 'helpdesk@atlas-tech.com' -Service $service)[0]
Assert-Pass -Condition ($null -ne $mailbox) -Message 'Exchange Online provider get returns a mailbox result'
Assert-Pass -Condition ($mailbox.PSObject.TypeNames -contains 'Hybrid.ExchangeOnline.Mailbox') -Message 'Exchange Online provider get returns mailbox model'
Assert-Pass -Condition ($mailbox.MailboxType -eq 'SharedMailbox') -Message 'Exchange Online provider get returns expected mailbox type'

$mailboxAgain = @(Get-HybridExchangeOnlineMailbox -Identity 'helpdesk@atlas-tech.com' -Service $service)[0]
Assert-Pass -Condition ($mailboxAgain.PrimarySmtpAddress -eq $mailbox.PrimarySmtpAddress) -Message 'Exchange Online provider returns stable cached mailbox result'

$health = @(Get-HybridExchangeOnlineProviderHealth -Service $service)[0]
Assert-Pass -Condition ($health.PSObject.TypeNames -contains 'Hybrid.ExchangeOnline.ProviderHealth') -Message 'Exchange Online provider health has platform type name'
Assert-Pass -Condition ($health.ProviderName -eq 'ExchangeOnline') -Message 'Exchange Online provider health has provider name'
Assert-Pass -Condition ($health.Status -eq 'Healthy') -Message 'Exchange Online provider health reports healthy status'
Assert-Pass -Condition (@($health.Capabilities) -contains 'Mailboxes') -Message 'Exchange Online provider health reports mailbox capability'
Assert-Pass -Condition ($health.AuthenticationSession.PSObject.TypeNames -contains 'Hybrid.AuthenticationSession') -Message 'Exchange Online provider health includes authentication session'

Write-Host ''
Write-Host 'Milestone 6 Phase 4 Exchange Online provider foundation tests passed' -ForegroundColor Cyan
