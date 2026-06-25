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
            ClientId = '22222222-2222-2222-2222-222222222222'
            CredentialMode = 'Certificate'
            CertificateThumbprint = 'ABC123'
            CertificatePath = ''
            SecretReference = ''
        }
        Delegated = @{
            Enabled = $true
            ClientId = '33333333-3333-3333-3333-333333333333'
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
    Assert-True ([string]$profile.Authentication.AppOnly.CertificateThumbprint -eq 'ABC123') 'Runtime profile parser preserves certificate thumbprint'
    Assert-True ([bool]$profile.Authentication.Delegated.PromptWhenRequired) 'Runtime profile parser preserves delegated prompt setting'
    Assert-True (@($profile.Providers | Where-Object { $_.Name -eq 'ExchangeOnline' -and $_.Enabled -and $_.Authentication -eq 'AppOnly' }).Count -eq 1) 'Runtime profile parser preserves Exchange Online provider settings'
}
finally {
    Remove-Item -LiteralPath $tempProfilePath -Force -ErrorAction SilentlyContinue
}

$ui = Get-Content -LiteralPath $uiPath -Raw
Assert-ContainsText $ui 'WizardAppOnlyEnabledCheckBox' 'Runtime profile wizard exposes app-only enabled setting'
Assert-ContainsText $ui 'WizardAppOnlyCredentialModeComboBox' 'Runtime profile wizard exposes app-only credential mode'
Assert-ContainsText $ui 'WizardDelegatedPromptWhenRequiredCheckBox' 'Runtime profile wizard exposes delegated prompt setting'
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
Assert-ContainsText $ui "Set-HybridSearchProgressStage -Stage 'Exchange On-Prem'" 'Search progress includes Exchange On-Premises stage'
Assert-ContainsText $ui "Set-HybridSearchProgressStage -Stage 'Exchange Online'" 'Search progress includes Exchange Online stage'

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

$adProvider = [pscustomobject]@{
    GetUser = {
        param([string]$Identity)
        [pscustomobject]@{
            DisplayName = 'Alex Morgan'
            UserPrincipalName = 'alex.morgan@atlas.test'
            SamAccountName = 'amorgan'
            Mail = 'alex.morgan@atlas.test'
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

$aggregate = Get-HybridUserAggregateProfile -Identity 'alex.morgan@atlas.test' -Refresh
Assert-True (@($aggregate.Verticals | Where-Object { $_.Name -eq 'ExchangeOnPremisesRecipient' }).Count -eq 1) 'Aggregation includes Exchange On-Premises vertical status'
Assert-True (@($aggregate.Verticals | Where-Object { $_.Name -eq 'ExchangeOnlineMailbox' }).Count -eq 1) 'Aggregation includes Exchange Online vertical status'

$runtimeText = Get-Content -LiteralPath $runtimeModule -Raw
Assert-ContainsText $runtimeText 'Initialize-HybridRuntimeLiveExchangeOnlineProvider' 'Runtime bootstrap can initialize Exchange Online provider'
Assert-ContainsText $runtimeText 'ProviderRegistry.ContainsKey(''ExchangeOnline'')' 'Exchange Online appears in provider diagnostics and service registration when enabled'

$allText = Get-ChildItem -Path $repoRoot -Recurse -File -Include *.ps1,*.psm1,*.psd1,*.json,*.md |
    Where-Object { $_.FullName -notlike '*\.git\*' } |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue }
Assert-True (-not (($allText -join [Environment]::NewLine) -match 'Register-HybridAuthenticationAdapter\s+-Name\s+DeviceCode|AllowedMethods\s*=\s*@\([^)]*DeviceCode')) 'Device Code authentication is not introduced as an available method'

Write-Host 'Milestone 8.9 hybrid Graph authentication and Exchange Online tests passed.'
