$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

function Assert-ContainsText {
    param([string]$Content, [string]$Needle, [string]$Message)
    if ($Content -notlike "*$Needle*") { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$profileModule = Join-Path $repoRoot 'src\Core\Core.RuntimeProfile.psm1'
$runtimeModule = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'
$msalModule = Join-Path $repoRoot 'src\Core\Core.Authentication.MSAL.psm1'
$exchangeOnlineModule = Join-Path $repoRoot 'src\Core\Core.Provider.ExchangeOnline.psm1'
$serviceModule = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
$aggregationModule = Join-Path $repoRoot 'src\Application\Application.HybridUserAggregationService.psm1'
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

Import-Module $profileModule -Force
Import-Module $exchangeOnlineModule -Force
Import-Module $serviceModule -Force
Import-Module $aggregationModule -Force

$tempProfilePath = Join-Path ([System.IO.Path]::GetTempPath()) ('hap-hybrid-auth-{0}.json' -f ([guid]::NewGuid().ToString('N')))
$profileJson = @{
    ProfileName = 'Hybrid Auth Test'
    Mode = 'Live'
    Cloud = 'GCCHigh'
    Environment = 'Development'
    Organization = 'Atlas'
    TenantId = '11111111-1111-1111-1111-111111111111'
    Authentication = @{
        Cloud = 'GCCHigh'
        AppOnly = @{
            Enabled = $true
            TenantId = '11111111-1111-1111-1111-111111111111'
            TenantDomain = 'tenant.onmicrosoft.us'
            ClientId = '22222222-2222-2222-2222-222222222222'
            CredentialMode = 'Certificate'
            CertificateThumbprint = 'ABC123'
            CertificatePath = ''
            SecretReference = ''
        }
        Delegated = @{
            Enabled = $true
            PromptWhenRequired = $true
        }
    }
    Providers = @{
        ActiveDirectory = @{ Enabled = $true; Mode = 'Live'; Required = $true; Authentication = 'Integrated' }
        MicrosoftGraph = @{ Enabled = $true; Mode = 'Live'; Required = $true; Authentication = 'AppOnly' }
        ExchangeOnline = @{ Enabled = $true; Mode = 'Live'; Required = $true; Authentication = 'AppOnly' }
        ExchangeOnPremises = @{ Enabled = $true; Mode = 'Live'; Required = $false; Authentication = 'Kerberos'; Server = 'exchange01'; ConnectionUri = '' }
    }
} | ConvertTo-Json -Depth 10
Set-Content -LiteralPath $tempProfilePath -Value $profileJson -Encoding UTF8

try {
    $profile = Initialize-HybridRuntimeProfile -Path $tempProfilePath -RootPath $repoRoot
    Assert-True ([string]$profile.Authentication.Cloud -eq 'GCCHigh') 'Runtime profile parser preserves authentication cloud'
    Assert-True ([bool]$profile.Authentication.AppOnly.Enabled) 'Runtime profile parser preserves app-only enabled setting'
    Assert-True ([string]$profile.Authentication.AppOnly.ClientId -eq '22222222-2222-2222-2222-222222222222') 'Runtime profile parser preserves app-only client ID'
    Assert-True ([string]$profile.Authentication.AppOnly.TenantDomain -eq 'tenant.onmicrosoft.us') 'Runtime profile parser preserves app-only tenant domain'
    Assert-True ([string]$profile.Authentication.AppOnly.CertificateThumbprint -eq 'ABC123') 'Runtime profile parser preserves certificate thumbprint'
    Assert-True ([string]$profile.Authentication.Delegated.ClientId -eq '22222222-2222-2222-2222-222222222222') 'Runtime profile parser defaults delegated client ID from app-only client ID'
    Assert-True ([bool]$profile.Authentication.Delegated.PromptWhenRequired) 'Runtime profile parser preserves delegated prompt setting'
    Assert-True (@($profile.Providers | Where-Object { $_.Name -eq 'ExchangeOnline' -and $_.Enabled -and $_.Authentication -eq 'AppOnly' }).Count -eq 1) 'Runtime profile parser preserves Exchange Online provider settings'
}
finally {
    Remove-Item -LiteralPath $tempProfilePath -Force -ErrorAction SilentlyContinue
}

$ui = Get-Content -LiteralPath $uiPath -Raw
$exchangeOnlineText = Get-Content -LiteralPath $exchangeOnlineModule -Raw
Assert-ContainsText $ui 'WizardAppOnlyEnabledCheckBox' 'Runtime profile wizard exposes app-only enabled setting'
Assert-ContainsText $ui 'WizardAppOnlyCredentialModeComboBox' 'Runtime profile wizard exposes app-only credential mode'
Assert-ContainsText $ui 'WizardAppOnlyTenantDomainTextBox' 'Runtime profile wizard exposes tenant domain for Exchange Online organization'
Assert-ContainsText $ui 'TenantDomain = $controls.WizardAppOnlyTenantDomainTextBox.Text.Trim()' 'Runtime profile wizard saves tenant domain in app-only settings'
Assert-ContainsText $ui 'Text="Dashboard layout foundation | Runtime Profile Wizard ready"' 'Runtime profile header uses pipe separator'
Assert-ContainsText $ui 'WizardDelegatedEnabledCheckBox' 'Runtime profile wizard exposes delegated as on/off'
Assert-True (-not ($ui -match 'WizardDelegatedPromptWhenRequiredCheckBox|WizardDelegatedClientIdTextBox')) 'Runtime profile wizard does not require delegated client details'
Assert-ContainsText $ui 'Authentication = $authentication' 'Runtime profile wizard saves hybrid authentication block'
Assert-ContainsText $ui 'ToolTip="Thumbprint of a certificate installed in the Windows certificate store' 'Runtime profile wizard explains certificate thumbprint'
Assert-ContainsText $ui 'ToolTip="Path to a local certificate file for app-only auth' 'Runtime profile wizard explains certificate path'
Assert-ContainsText $ui 'ToolTip="Name or URI of a secret stored outside this profile' 'Runtime profile wizard explains secret reference'
Assert-ContainsText $ui 'Normalize-HybridWizardCertificateThumbprint' 'Runtime profile wizard normalizes pasted certificate thumbprints'
Assert-ContainsText $ui '<ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">' 'Runtime profile wizard and startup summary support vertical scrolling on shorter screens'
Assert-ContainsText $ui '<Grid Margin="0,0,5,0">' 'Runtime summary scroll content leaves a gutter before the scrollbar'
Assert-ContainsText $ui 'ImportExportRuntimeProfileButton' 'Runtime home combines import and export into one action'
Assert-ContainsText $ui 'Show-HybridRuntimeProfileImportExportWizard' 'Runtime home opens an import/export chooser workflow'
Assert-True (-not ($ui -match '<Button x:Name="DuplicateRuntimeProfileButton"')) 'Runtime home removes Duplicate from the footer'
Assert-True ($ui -match '<Button x:Name="ExitButton" Style="\{StaticResource RuntimeActionButton\}"') 'Runtime home keeps Exit in the same dynamic button flow'
Assert-ContainsText $ui 'HorizontalContentAlignment="Center"><WrapPanel HorizontalAlignment="Center"' 'Runtime home centers footer buttons in available space'
Assert-ContainsText $ui 'BadgeIdText' 'Directory Facts displays Badge ID'
Assert-ContainsText $ui 'StateText' 'Directory Facts displays state'
Assert-ContainsText $ui 'PhoneNumberText' 'Directory Facts displays phone number'
Assert-ContainsText $ui "'BadgeId','BadgeID','EmployeeNumber'" 'Directory Facts reads legacy BadgeID property name'
Assert-ContainsText $ui "Set-HybridSearchProgressStage -Stage 'Exchange On-Prem'" 'Search progress includes Exchange On-Premises stage'
Assert-ContainsText $ui "Set-HybridSearchProgressStage -Stage 'Exchange Online'" 'Search progress includes Exchange Online stage'
Assert-ContainsText $exchangeOnlineText 'Get-HybridExchangeOnlineMailboxDelegations' 'Exchange Online provider implements delegated mailbox lookup'
Assert-ContainsText $exchangeOnlineText 'Get-HybridExchangeOnlineDistributionGroups' 'Exchange Online provider implements distribution group lookup'
Assert-ContainsText $exchangeOnlineText 'Get-EXOMailboxPermission -User $Identity' 'Exchange Online provider queries mailboxes delegated to the selected user'
Assert-ContainsText $exchangeOnlineText 'Get-RecipientPermission -Trustee $Identity' 'Exchange Online provider queries SendAs delegations for the selected user'
Assert-True (-not ($exchangeOnlineText -match 'GetDistributionGroups = \(\{ param\(\[string\]\$Identity\) @\(\) \}\)')) 'Exchange Online distribution group operation is not a stub'
Assert-True (-not ($exchangeOnlineText -match 'GetMailboxDelegations = \(\{ param\(\[string\]\$Identity\) @\(\) \}\)')) 'Exchange Online mailbox delegation operation is not a stub'

$providerContext = New-HybridExchangeOnlineProviderContext -Cloud 'GCCHigh'
$provider = Initialize-HybridExchangeOnlineProvider -Context $providerContext -DeferConnection
$health = & $provider.GetHealth
Assert-True ($health.Status -eq 'NotConfigured') 'Exchange Online provider reports NotConfigured when app-only settings are absent'
Assert-True (-not [bool]$health.Connected) 'Exchange Online provider does not report connected from unrelated AD mail attributes'

$configuredContext = New-HybridExchangeOnlineProviderContext -Cloud 'GCCHigh' -AppOnlyEnabled -TenantId 'tenant.onmicrosoft.us' -ClientId '22222222-2222-2222-2222-222222222222' -CredentialMode 'Certificate' -CertificateThumbprint 'ABC123'
$configuredProvider = Initialize-HybridExchangeOnlineProvider -Context $configuredContext -DeferConnection
$configuredHealth = & $configuredProvider.GetHealth
Assert-True ($configuredHealth.Status -in @('Deferred','ModuleMissing')) 'Exchange Online provider reports Deferred or ModuleMissing distinctly when configured'

$spacedThumbprintContext = New-HybridExchangeOnlineProviderContext -Cloud 'Commercial' -AppOnlyEnabled -TenantId 'tenant.onmicrosoft.com' -ClientId '22222222-2222-2222-2222-222222222222' -CredentialMode 'Certificate' -CertificateThumbprint 'ab cd:12 34'
$spacedThumbprintHealth = & (Initialize-HybridExchangeOnlineProvider -Context $spacedThumbprintContext -DeferConnection).GetHealth
Assert-True ($spacedThumbprintHealth.Configuration.CertificateThumbprint -eq 'ABCD1234') 'Exchange Online provider normalizes certificate thumbprint delimiters and casing'

$tenantDomainContext = New-HybridExchangeOnlineProviderContext -Cloud 'Commercial' -AppOnlyEnabled -TenantId '11111111-1111-1111-1111-111111111111' -TenantDomain 'tenant.onmicrosoft.com' -ClientId '22222222-2222-2222-2222-222222222222' -CredentialMode 'Certificate' -CertificateThumbprint 'ABC123'
$tenantDomainHealth = & (Initialize-HybridExchangeOnlineProvider -Context $tenantDomainContext -DeferConnection).GetHealth
Assert-True ($tenantDomainHealth.Configuration.Organization -eq 'tenant.onmicrosoft.com') 'Exchange Online provider uses tenant domain as Connect-ExchangeOnline organization when supplied'

$guidOnlyContext = New-HybridExchangeOnlineProviderContext -Cloud 'Commercial' -AppOnlyEnabled -TenantId '11111111-1111-1111-1111-111111111111' -ClientId '22222222-2222-2222-2222-222222222222' -CredentialMode 'Certificate' -CertificateThumbprint 'ABC123'
$guidOnlyHealth = & (Initialize-HybridExchangeOnlineProvider -Context $guidOnlyContext -DeferConnection).GetHealth
Assert-True ($guidOnlyHealth.Status -eq 'NotConfigured' -and $guidOnlyHealth.Configuration.Message -match 'TenantDomain is required') 'Exchange Online provider requires tenant domain when TenantId is a GUID'

$adProvider = [pscustomobject]@{
    GetUser = {
        param([string]$Identity)
        [pscustomobject]@{
            DisplayName = 'Alex Morgan'
            UserPrincipalName = 'alex.morgan@atlas.test'
            SamAccountName = 'amorgan'
            Mail = 'alex.morgan@atlas.test'
            EmployeeId = 'E100'
            BadgeID = 'B200'
            State = 'WA'
            PhoneNumber = '+1 555 0100'
            DistinguishedName = 'CN=Alex Morgan,OU=Users,DC=atlas,DC=test'
        }
    }.GetNewClosure()
}
$exoProvider = [pscustomobject]@{
    GetMailbox = {
        param([string]$Identity)
        [pscustomobject]@{
            RecipientTypeDetails = 'UserMailbox'
            PrimarySmtpAddress = 'alex.morgan@atlas.test'
            ExternalDirectoryObjectId = 'exo-1'
            ExchangeGuid = '44444444-4444-4444-4444-444444444444'
            HiddenFromAddressListsEnabled = $false
        }
    }.GetNewClosure()
    GetProviderHealth = { [pscustomobject]@{ Available = $true; Connected = $true; Status = 'Connected' } }.GetNewClosure()
    GetMailboxStatistics = {
        param([string]$Identity)
        [pscustomobject]@{ ItemCount = 42; TotalItemSize = '1 GB' }
    }.GetNewClosure()
    GetMailboxDelegations = {
        param([string]$Identity)
        [pscustomobject]@{
            Mailbox = 'shared.finance@atlas.test'
            Trustee = $Identity
            AccessRights = @('FullAccess')
            DelegationType = 'FullAccess'
        }
    }.GetNewClosure()
    GetDistributionGroups = {
        param([string]$Identity)
        [pscustomobject]@{
            DisplayName = 'Finance Notifications'
            PrimarySmtpAddress = 'finance-notifications@atlas.test'
            RecipientTypeDetails = 'MailUniversalDistributionGroup'
        }
    }.GetNewClosure()
}
$onPremProvider = [pscustomobject]@{
    GetRemoteMailbox = {
        param([string]$Identity)
        [pscustomobject]@{
            RecipientTypeDetails = 'RemoteMailbox'
            PrimarySmtpAddress = 'alex.morgan@atlas.test'
            RemoteRoutingAddress = 'alex.morgan@tenant.mail.onmicrosoft.com'
        }
    }.GetNewClosure()
    GetRecipient = {
        param([string]$Identity)
        [pscustomobject]@{
            RecipientTypeDetails = 'RemoteMailbox'
            PrimarySmtpAddress = 'alex.morgan@atlas.test'
            HiddenFromAddressListsEnabled = $false
        }
    }.GetNewClosure()
    GetProviderHealth = { [pscustomobject]@{ Available = $true; Connected = $true; Status = 'Connected' } }.GetNewClosure()
}

Initialize-HybridUserService -ActiveDirectoryProvider $adProvider -ExchangeOnlineProvider $exoProvider -ExchangeOnPremisesProvider $onPremProvider | Out-Null
Initialize-HybridUserAggregationService | Out-Null
$user = Get-HybridUserMailboxDetails -Identity 'alex.morgan@atlas.test'
Assert-True ($null -ne $user.Mailbox.AdMailAttributes) 'HybridUserService mailbox hydration preserves AD mail attributes separately'
Assert-True ($null -ne $user.Mailbox.ExchangeOnPremises) 'HybridUserService mailbox hydration preserves Exchange On-Premises data separately'
Assert-True ($null -ne $user.Mailbox.ExchangeOnline) 'HybridUserService mailbox hydration preserves Exchange Online data separately'
Assert-True ($user.Mailbox.Summary.SourcePriority -eq 'ExchangeOnline') 'HybridUserService mailbox summary prioritizes Exchange Online when cloud mailbox exists'
Assert-True ($user.BadgeId -eq 'B200' -and $user.State -eq 'WA' -and $user.PhoneNumber -eq '+1 555 0100') 'HybridUserService composite user includes legacy BadgeID, state, and phone number'
Assert-True (@($user.MailboxDetails.Delegations).Count -eq 1 -and $user.MailboxDetails.Delegations[0].Mailbox -eq 'shared.finance@atlas.test') 'HybridUserService mailbox hydration includes delegated mailboxes from Exchange Online'
Assert-True (@($user.MailboxDetails.DistributionGroups).Count -eq 1 -and $user.MailboxDetails.DistributionGroups[0].DisplayName -eq 'Finance Notifications') 'HybridUserService mailbox hydration includes Exchange Online distribution groups'

$aggregate = Get-HybridUserAggregateProfile -Identity 'alex.morgan@atlas.test' -Refresh
Assert-True (@($aggregate.Verticals | Where-Object { $_.Name -eq 'ExchangeOnPremisesRecipient' }).Count -eq 1) 'Aggregation includes Exchange On-Premises vertical status'
Assert-True (@($aggregate.Verticals | Where-Object { $_.Name -eq 'ExchangeOnlineMailbox' }).Count -eq 1) 'Aggregation includes Exchange Online vertical status'

$failingAdProvider = [pscustomobject]@{
    SearchUser = { param([string]$Query) throw 'Simulated AD search outage' }.GetNewClosure()
    GetUser = { param([string]$Identity) throw 'Simulated AD get outage' }.GetNewClosure()
}
$fallbackGraphProvider = [pscustomobject]@{
    SearchUser = {
        param([string]$Query)
        [pscustomobject]@{
            Id = 'graph-1'
            DisplayName = 'Cloud Only User'
            UserPrincipalName = 'cloud.only@atlas.test'
            Mail = 'cloud.only@atlas.test'
            Source = 'MicrosoftGraph'
        }
    }.GetNewClosure()
    GetUser = {
        param([string]$Identity)
        [pscustomobject]@{
            Id = 'graph-1'
            DisplayName = 'Cloud Only User'
            UserPrincipalName = 'cloud.only@atlas.test'
            Mail = 'cloud.only@atlas.test'
            Source = 'MicrosoftGraph'
        }
    }.GetNewClosure()
}
Initialize-HybridUserService -ActiveDirectoryProvider $failingAdProvider -MicrosoftGraphProvider $fallbackGraphProvider | Out-Null
$fallbackResults = @(Search-HybridUser -Query 'cloud.only')
Assert-True ($fallbackResults.Count -eq 1 -and $fallbackResults[0].UserPrincipalName -eq 'cloud.only@atlas.test') 'HybridUserService search continues with Graph results when AD search fails'

$exactOnlyGraphProvider = [pscustomobject]@{
    SearchUser = { param([string]$Query) @() }.GetNewClosure()
    GetUser = {
        param([string]$Identity)
        if ($Identity -eq 'exact.user@atlas.test') {
            [pscustomobject]@{
                Id = 'graph-exact-1'
                DisplayName = 'Exact User'
                UserPrincipalName = 'exact.user@atlas.test'
                Mail = 'exact.user@atlas.test'
                Source = 'MicrosoftGraph'
            }
        }
    }.GetNewClosure()
}
Initialize-HybridUserService -MicrosoftGraphProvider $exactOnlyGraphProvider | Out-Null
$exactFallbackResults = @(Search-HybridUser -Query 'exact.user@atlas.test')
Assert-True ($exactFallbackResults.Count -eq 1 -and $exactFallbackResults[0].UserPrincipalName -eq 'exact.user@atlas.test') 'HybridUserService search tries exact identity lookup before returning no users'

$enrichedGraphProvider = [pscustomobject]@{
    GetUser = {
        param([string]$Identity)
        [pscustomobject]@{
            Id = 'graph-enriched-1'
            DisplayName = 'Secure User'
            UserPrincipalName = 'secure.user@atlas.test'
            Mail = 'secure.user@atlas.test'
            UserType = 'Member'
            UsageLocation = 'US'
            PreferredLanguage = 'en-US'
            AuthenticationMethods = @('Microsoft Authenticator','FIDO2 security key')
            MfaRegistered = $true
            MfaCapable = $true
            PasswordlessRegistered = $true
            AuthenticationStrength = 'Multi-factor capable'
            LastSignInDateTime = [datetime]'2026-06-24T12:00:00Z'
            PasswordLastChangedDateTime = [datetime]'2026-06-01T12:00:00Z'
            RiskState = 'atRisk'
            SignInRiskState = 'atRisk'
            ConditionalAccessState = 'success'
            Source = 'MicrosoftGraph'
        }
    }.GetNewClosure()
}
Initialize-HybridUserService -MicrosoftGraphProvider $enrichedGraphProvider | Out-Null
$graphProfile = Get-HybridUserGraphProfile -Identity 'secure.user@atlas.test'
$authProfile = Get-HybridUserAuthenticationProfile -Identity 'secure.user@atlas.test'
Assert-True (@($graphProfile.AuthenticationMethods).Count -eq 2 -and $graphProfile.RiskState -eq 'atRisk') 'Graph profile preserves authentication methods and risk state from provider data'
Assert-True ($null -ne $graphProfile.LastSignInDateTime -and $null -ne $graphProfile.PasswordLastChangedDateTime) 'Graph profile preserves last sign-in and password last changed values'
Assert-True ($authProfile.ConditionalAccessState -eq 'success' -and $authProfile.SignInRiskState -eq 'atRisk') 'Authentication profile preserves conditional access and sign-in risk values'
Assert-True (@($authProfile.AuthenticationMethods).Count -eq 2 -and [bool]$authProfile.PasswordlessRegistered) 'Authentication profile preserves real methods and passwordless state'

$runtimeText = Get-Content -LiteralPath $runtimeModule -Raw
$msalText = Get-Content -LiteralPath $msalModule -Raw
$graphProviderText = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Core\Core.Provider.MicrosoftGraph.psm1') -Raw
$authManagerText = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Core\Core.Authentication.Manager.psm1') -Raw
Assert-ContainsText $runtimeText 'Initialize-HybridRuntimeLiveExchangeOnlineProvider' 'Runtime bootstrap can initialize Exchange Online provider'
Assert-ContainsText $runtimeText 'Initialize-HybridRuntimeLiveMicrosoftGraphProvider' 'Runtime bootstrap can initialize Microsoft Graph provider'
Assert-ContainsText $runtimeText 'Microsoft Graph delegated authentication is requested during console launch.' 'Microsoft Graph bootstrap requests delegated authentication during console launch'
Assert-ContainsText $runtimeText 'Microsoft Graph delegated authentication completed during console launch.' 'Microsoft Graph bootstrap records delegated authentication completion during console launch'
Assert-ContainsText $runtimeText 'SearchUser = $searchGraphUsers' 'Microsoft Graph lazy provider exposes search fallback'
Assert-ContainsText $runtimeText "if (`$delegatedEnabled) { 'InteractiveBrowser' }" 'Microsoft Graph runtime prefers delegated browser auth when delegated is enabled'
Assert-ContainsText $ui 'Starting delegated sign-in if enabled...' 'Runtime launch overlay announces delegated sign-in during loading'
Assert-ContainsText $msalText 'Invoke-HybridMsalCertificateClientCredentials' 'MSAL adapter supports certificate client credentials for Graph app-only auth'
Assert-ContainsText $msalText 'client_assertion_type' 'MSAL adapter builds certificate client assertions instead of delegated desktop auth'
Assert-ContainsText $msalText 'Invoke-HybridMsalLoopbackInteractive' 'MSAL adapter prompts delegated auth with browser loopback flow'
Assert-ContainsText $msalText 'Start-Process $authorizeUri' 'Delegated browser auth launches a sign-in prompt'
Assert-ContainsText $runtimeText 'ProviderRegistry.ContainsKey(''ExchangeOnline'')' 'Exchange Online appears in provider diagnostics and service registration when enabled'
Assert-ContainsText $graphProviderText "/authentication/methods" 'Microsoft Graph provider requests authentication methods for profile enrichment'
Assert-ContainsText $graphProviderText "/auditLogs/signIns" 'Microsoft Graph provider requests sign-in records for conditional access and risk enrichment'
Assert-ContainsText $graphProviderText "/identityProtection/riskyUsers" 'Microsoft Graph provider requests risky user state when available'
Assert-ContainsText $graphProviderText "`$select = 'id,displayName,userPrincipalName,mail,userType,preferredLanguage,usageLocation'" 'Microsoft Graph base user request uses a conservative select set'
Assert-ContainsText $graphProviderText 'Invoke-HybridMicrosoftGraphOptionalRequest -Uri $profileUri' 'Microsoft Graph extended user fields are loaded with optional fallback requests'
Assert-ContainsText $graphProviderText 'LastAuthenticationSession' 'Microsoft Graph provider reuses an existing valid authentication session'
Assert-ContainsText $authManagerText '$tenantId,$cloudName,$methodName,$clientId,$scopeText' 'Authentication manager cache key includes client ID'
Assert-ContainsText $ui '$script:HybridRuntimeLaunchInProgress' 'Runtime launch guards against repeated launch clicks'
Assert-ContainsText $ui '$controls.LaunchConsoleButton.IsEnabled = $false' 'Runtime launch disables launch button while authentication is in progress'

$allText = Get-ChildItem -Path $repoRoot -Recurse -File -Include *.ps1,*.psm1,*.psd1,*.json,*.md |
    Where-Object { $_.FullName -notlike '*\.git\*' } |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue }
Assert-True (-not (($allText -join [Environment]::NewLine) -match 'Register-HybridAuthenticationAdapter\s+-Name\s+DeviceCode|AllowedMethods\s*=\s*@\([^)]*DeviceCode')) 'Device Code authentication is not introduced as an available method'

Write-Host 'Milestone 8.9 hybrid Graph authentication and Exchange Online tests passed.'
