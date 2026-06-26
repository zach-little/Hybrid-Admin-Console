Set-StrictMode -Version Latest

$script:HybridExchangeOnlineState = @{
    Initialized = $false
    Context = $null
    Connected = $false
    Deferred = $true
    Status = 'NotConfigured'
    LastError = $null
}

function Get-HybridExchangeOnlineObjectValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory=$true)][string[]]$Names,
        [AllowNull()][object]$Default = $null
    )

    foreach ($name in $Names) {
        if ($null -eq $InputObject) { continue }
        if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($name)) {
            $value = $InputObject[$name]
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return $value }
        }
        if ($InputObject.PSObject.Properties.Name -contains $name) {
            $value = $InputObject.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return $value }
        }
    }

    return $Default
}

function Resolve-HybridExchangeOnlineEndpoint {
    [CmdletBinding()]
    param([string]$Cloud = 'Commercial')

    switch -Regex ($Cloud) {
        '^(GCC\s*High|GCCHigh|USGov|AzureUSGovernment)$' {
            return [pscustomobject]@{
                PSTypeName = 'Hybrid.ExchangeOnline.Endpoint'
                Cloud = 'GCCHigh'
                ExchangeEnvironmentName = 'O365USGovGCCHigh'
                ExchangeOnlineEndpoint = 'https://outlook.office365.us'
                AuthorityHost = 'https://login.microsoftonline.us'
            }
        }
        '^(DoD|DepartmentOfDefense)$' {
            return [pscustomobject]@{
                PSTypeName = 'Hybrid.ExchangeOnline.Endpoint'
                Cloud = 'DoD'
                ExchangeEnvironmentName = 'O365USGovDoD'
                ExchangeOnlineEndpoint = 'https://webmail.apps.mil'
                AuthorityHost = 'https://login.microsoftonline.us'
            }
        }
        default {
            return [pscustomobject]@{
                PSTypeName = 'Hybrid.ExchangeOnline.Endpoint'
                Cloud = 'Commercial'
                ExchangeEnvironmentName = 'O365Default'
                ExchangeOnlineEndpoint = 'https://outlook.office365.com'
                AuthorityHost = 'https://login.microsoftonline.com'
            }
        }
    }
}

function Normalize-HybridExchangeOnlineCertificateThumbprint {
    [CmdletBinding()]
    param([AllowNull()][string]$Thumbprint)

    if ([string]::IsNullOrWhiteSpace($Thumbprint)) { return '' }
    return ([regex]::Replace($Thumbprint.Trim(), '[^0-9A-Fa-f]', '')).ToUpperInvariant()
}

function Test-HybridExchangeOnlineModuleAvailable {
    [CmdletBinding()]
    param()

    $connectCommand = Get-Command -Name Connect-ExchangeOnline -ErrorAction SilentlyContinue
    $mailboxCommand = Get-Command -Name Get-EXOMailbox -ErrorAction SilentlyContinue
    if ($null -eq $mailboxCommand) { $mailboxCommand = Get-Command -Name Get-Mailbox -ErrorAction SilentlyContinue }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnline.ModuleStatus'
        Available = ($null -ne $connectCommand)
        MailboxCommandAvailable = ($null -ne $mailboxCommand)
        ConnectCommand = if ($null -ne $connectCommand) { $connectCommand.Name } else { '' }
        MailboxCommand = if ($null -ne $mailboxCommand) { $mailboxCommand.Name } else { '' }
        ModuleName = if ($null -ne $connectCommand) { [string]$connectCommand.ModuleName } else { '' }
    }
}

function Test-HybridExchangeOnlineConfiguration {
    [CmdletBinding()]
    param([AllowNull()][object]$Context)

    $messages = New-Object System.Collections.Generic.List[string]
    $appOnly = Get-HybridExchangeOnlineObjectValue -InputObject $Context -Names @('AppOnly') -Default $null
    $tenantId = [string](Get-HybridExchangeOnlineObjectValue -InputObject $appOnly -Names @('TenantId') -Default (Get-HybridExchangeOnlineObjectValue -InputObject $Context -Names @('TenantId') -Default ''))
    $organization = [string](Get-HybridExchangeOnlineObjectValue -InputObject $appOnly -Names @('TenantDomain','PrimaryDomain','Organization') -Default (Get-HybridExchangeOnlineObjectValue -InputObject $Context -Names @('TenantDomain','PrimaryDomain','Organization') -Default $tenantId))
    $clientId = [string](Get-HybridExchangeOnlineObjectValue -InputObject $appOnly -Names @('ClientId') -Default (Get-HybridExchangeOnlineObjectValue -InputObject $Context -Names @('ClientId') -Default ''))
    $credentialMode = [string](Get-HybridExchangeOnlineObjectValue -InputObject $appOnly -Names @('CredentialMode') -Default 'Certificate')
    $certificateThumbprint = Normalize-HybridExchangeOnlineCertificateThumbprint -Thumbprint ([string](Get-HybridExchangeOnlineObjectValue -InputObject $appOnly -Names @('CertificateThumbprint') -Default ''))
    $certificatePath = [string](Get-HybridExchangeOnlineObjectValue -InputObject $appOnly -Names @('CertificatePath') -Default '')
    $secretReference = [string](Get-HybridExchangeOnlineObjectValue -InputObject $appOnly -Names @('SecretReference') -Default '')
    $appOnlyEnabled = [bool](Get-HybridExchangeOnlineObjectValue -InputObject $appOnly -Names @('Enabled') -Default $false)

    if (-not $appOnlyEnabled) { $messages.Add('App-only authentication is disabled.') | Out-Null }
    if ([string]::IsNullOrWhiteSpace($tenantId)) { $messages.Add('TenantId is required for Exchange Online app-only authentication.') | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($tenantId) -and $tenantId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' -and $organization -eq $tenantId) {
        $messages.Add('TenantDomain is required for Exchange Online when TenantId is a GUID. Use the tenant onmicrosoft.com or primary accepted domain for Organization.') | Out-Null
    }
    if ([string]::IsNullOrWhiteSpace($clientId)) { $messages.Add('ClientId is required for Exchange Online app-only authentication.') | Out-Null }
    if ($credentialMode -eq 'Certificate' -and [string]::IsNullOrWhiteSpace($certificateThumbprint) -and [string]::IsNullOrWhiteSpace($certificatePath)) {
        $messages.Add('CertificateThumbprint or CertificatePath is required for certificate app-only authentication.') | Out-Null
    }
    if ($credentialMode -eq 'ClientSecretReference' -and [string]::IsNullOrWhiteSpace($secretReference)) {
        $messages.Add('SecretReference is required for client secret compatibility mode.') | Out-Null
    }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnline.ConfigurationStatus'
        IsConfigured = ($messages.Count -eq 0)
        Messages = @($messages)
        Message = if ($messages.Count -eq 0) { 'Exchange Online app-only authentication is configured.' } else { $messages -join ' ' }
        TenantId = $tenantId
        Organization = $organization
        ClientId = $clientId
        CredentialMode = $credentialMode
        CertificateThumbprint = $certificateThumbprint
        CertificatePath = $certificatePath
        SecretReference = $secretReference
    }
}

function New-HybridExchangeOnlineProviderContext {
    [CmdletBinding()]
    param(
        [string]$Cloud = 'Commercial',
        [AllowNull()][object]$Authentication = $null,
        [AllowNull()][object]$ProviderSettings = $null,
        [string]$TenantId = '',
        [string]$TenantDomain = '',
        [string]$ClientId = '',
        [string]$CredentialMode = 'Certificate',
        [string]$CertificateThumbprint = '',
        [string]$CertificatePath = '',
        [string]$SecretReference = '',
        [switch]$AppOnlyEnabled,
        [switch]$DelegatedEnabled,
        [switch]$PromptWhenRequired
    )

    $auth = $Authentication
    if ($null -eq $auth) {
        $auth = [pscustomobject]@{
            PSTypeName = 'Hybrid.RuntimeAuthenticationSettings'
            Cloud = $Cloud
            AppOnly = [pscustomobject]@{
                Enabled = [bool]$AppOnlyEnabled
                TenantId = $TenantId
                TenantDomain = $TenantDomain
                ClientId = $ClientId
                CredentialMode = $CredentialMode
                CertificateThumbprint = Normalize-HybridExchangeOnlineCertificateThumbprint -Thumbprint $CertificateThumbprint
                CertificatePath = $CertificatePath
                SecretReference = $SecretReference
            }
            Delegated = [pscustomobject]@{
                Enabled = [bool]$DelegatedEnabled
                ClientId = $ClientId
                PromptWhenRequired = [bool]$PromptWhenRequired
            }
        }
    }

    $endpoint = Resolve-HybridExchangeOnlineEndpoint -Cloud $Cloud
    $appOnly = Get-HybridExchangeOnlineObjectValue -InputObject $auth -Names @('AppOnly') -Default $null
    $delegated = Get-HybridExchangeOnlineObjectValue -InputObject $auth -Names @('Delegated') -Default $null

    [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnline.ProviderContext'
        ProviderName = 'ExchangeOnline'
        Cloud = $endpoint.Cloud
        Endpoint = $endpoint
        Authentication = $auth
        AppOnly = $appOnly
        Delegated = $delegated
        TenantDomain = [string](Get-HybridExchangeOnlineObjectValue -InputObject $appOnly -Names @('TenantDomain','PrimaryDomain','Organization') -Default $TenantDomain)
        ProviderSettings = $ProviderSettings
    }
}

function ConvertTo-HybridExchangeOnlineMailboxModel {
    [CmdletBinding()]
    param([AllowNull()][object]$Mailbox)

    if ($null -eq $Mailbox) { return $null }

    $model = [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnline.Mailbox'
        RecipientTypeDetails = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('RecipientTypeDetails','RecipientType','MailboxType') -Default '')
        PrimarySmtpAddress = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('PrimarySmtpAddress','WindowsEmailAddress','Mail','EmailAddress') -Default '')
        EmailAddresses = @((Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('EmailAddresses','ProxyAddresses') -Default @()))
        ForwardingSmtpAddress = Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('ForwardingSmtpAddress') -Default $null
        ForwardingAddress = Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('ForwardingAddress') -Default $null
        DeliverToMailboxAndForward = Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('DeliverToMailboxAndForward') -Default $null
        ArchiveStatus = Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('ArchiveStatus') -Default $null
        LitigationHoldEnabled = Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('LitigationHoldEnabled') -Default $null
        HiddenFromAddressListsEnabled = Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('HiddenFromAddressListsEnabled') -Default $null
        MailboxPlan = Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('MailboxPlan','SkuAssigned','SkuPartNumber') -Default $null
        ExternalDirectoryObjectId = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('ExternalDirectoryObjectId','ExternalDirectoryObjectID','Id') -Default '')
        ExchangeGuid = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('ExchangeGuid','Guid') -Default '')
        DisplayName = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('DisplayName','Name') -Default '')
        UserPrincipalName = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('UserPrincipalName','UPN') -Default '')
        Source = 'ExchangeOnline'
        Raw = $Mailbox
    }
    $model.PSObject.TypeNames.Insert(0, 'Hybrid.ExchangeOnline.Mailbox')
    return $model
}

function ConvertTo-HybridExchangeOnlineDistributionGroupModel {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Group,
        [string]$MatchedBy = ''
    )

    if ($null -eq $Group) { return $null }
    [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnline.DistributionGroup'
        Name = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Group -Names @('DisplayName','Name') -Default '')
        DisplayName = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Group -Names @('DisplayName','Name') -Default '')
        PrimarySmtpAddress = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Group -Names @('PrimarySmtpAddress','WindowsEmailAddress','Mail') -Default '')
        RecipientTypeDetails = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Group -Names @('RecipientTypeDetails','RecipientType') -Default 'DistributionGroup')
        Identity = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Group -Names @('Identity','Id','ExternalDirectoryObjectId') -Default '')
        MatchedBy = $MatchedBy
        Source = 'ExchangeOnline'
        Raw = $Group
    }
}

function ConvertTo-HybridExchangeOnlineMailboxDelegationModel {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Delegation,
        [string]$DelegationType = 'FullAccess'
    )

    if ($null -eq $Delegation) { return $null }
    $mailbox = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Delegation -Names @('Identity','Mailbox','RecipientIdentity','Name') -Default '')
    $trustee = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Delegation -Names @('User','Trustee') -Default '')
    $rights = @(Get-HybridExchangeOnlineObjectValue -InputObject $Delegation -Names @('AccessRights','AccessControlType','Rights') -Default @($DelegationType))
    [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnline.MailboxDelegation'
        Mailbox = $mailbox
        Identity = $mailbox
        Trustee = $trustee
        User = $trustee
        AccessRights = @($rights)
        Rights = (@($rights) -join ', ')
        DelegationType = $DelegationType
        Source = 'ExchangeOnline'
        Raw = $Delegation
    }
}

function Connect-HybridExchangeOnline {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Context)

    $moduleStatus = Test-HybridExchangeOnlineModuleAvailable
    if (-not $moduleStatus.Available) {
        $script:HybridExchangeOnlineState.Status = 'ModuleMissing'
        throw 'ExchangeOnlineManagement module command Connect-ExchangeOnline is not available.'
    }

    $configuration = Test-HybridExchangeOnlineConfiguration -Context $Context
    if (-not $configuration.IsConfigured) {
        $script:HybridExchangeOnlineState.Status = 'NotConfigured'
        throw $configuration.Message
    }

    $params = @{
        AppId = $configuration.ClientId
        Organization = $configuration.Organization
        ShowBanner = $false
        ErrorAction = 'Stop'
    }

    if ($Context.Endpoint.ExchangeEnvironmentName -ne 'O365Default') {
        $params.ExchangeEnvironmentName = $Context.Endpoint.ExchangeEnvironmentName
    }

    if ($configuration.CredentialMode -eq 'Certificate') {
        if (-not [string]::IsNullOrWhiteSpace($configuration.CertificateThumbprint)) {
            $params.CertificateThumbprint = $configuration.CertificateThumbprint
        }
        elseif (-not [string]::IsNullOrWhiteSpace($configuration.CertificatePath)) {
            $params.CertificateFilePath = $configuration.CertificatePath
        }
    }
    else {
        $script:HybridExchangeOnlineState.Status = 'AuthenticationUnavailable'
        throw 'Client secret compatibility mode requires a secret resolver. Plaintext secrets are not accepted in runtime profile configuration.'
    }

    Connect-ExchangeOnline @params | Out-Null
    $script:HybridExchangeOnlineState.Connected = $true
    $script:HybridExchangeOnlineState.Deferred = $false
    $script:HybridExchangeOnlineState.Status = 'Connected'
    $script:HybridExchangeOnlineState.LastError = $null
}

function Ensure-HybridExchangeOnlineConnection {
    [CmdletBinding()]
    param()

    if (-not [bool]$script:HybridExchangeOnlineState.Initialized) {
        throw 'Exchange Online provider has not been initialized.'
    }

    $context = $script:HybridExchangeOnlineState.Context
    $moduleStatus = Test-HybridExchangeOnlineModuleAvailable
    if (-not $moduleStatus.Available) {
        $script:HybridExchangeOnlineState.Status = 'ModuleMissing'
        throw 'ExchangeOnlineManagement module command Connect-ExchangeOnline is not available.'
    }

    $configuration = Test-HybridExchangeOnlineConfiguration -Context $context
    if (-not $configuration.IsConfigured) {
        $script:HybridExchangeOnlineState.Status = 'NotConfigured'
        throw $configuration.Message
    }

    if ([bool]$script:HybridExchangeOnlineState.Connected) { return }

    try {
        Connect-HybridExchangeOnline -Context $context
    }
    catch {
        if ([string]::IsNullOrWhiteSpace([string]$script:HybridExchangeOnlineState.Status) -or $script:HybridExchangeOnlineState.Status -eq 'Deferred') {
            $script:HybridExchangeOnlineState.Status = 'Failed'
        }
        $script:HybridExchangeOnlineState.LastError = $_.Exception.Message
        throw
    }
}

function Initialize-HybridExchangeOnlineProvider {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Context,
        [switch]$DeferConnection
    )

    if ($null -eq $Context) { $Context = New-HybridExchangeOnlineProviderContext }

    $script:HybridExchangeOnlineState.Initialized = $true
    $script:HybridExchangeOnlineState.Context = $Context
    $script:HybridExchangeOnlineState.Connected = $false
    $script:HybridExchangeOnlineState.Deferred = [bool]$DeferConnection
    $script:HybridExchangeOnlineState.LastError = $null

    $moduleStatus = Test-HybridExchangeOnlineModuleAvailable
    $configuration = Test-HybridExchangeOnlineConfiguration -Context $Context
    if (-not $configuration.IsConfigured) { $script:HybridExchangeOnlineState.Status = 'NotConfigured' }
    elseif (-not $moduleStatus.Available) { $script:HybridExchangeOnlineState.Status = 'ModuleMissing' }
    elseif ($DeferConnection) { $script:HybridExchangeOnlineState.Status = 'Deferred' }
    else {
        try { Connect-HybridExchangeOnline -Context $Context }
        catch { $script:HybridExchangeOnlineState.LastError = $_.Exception.Message; throw }
    }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnline.ProviderService'
        ProviderName = 'ExchangeOnline'
        Context = $Context
        CapabilityDiagnostics = @(
            [pscustomobject]@{ Name = 'MailboxRead'; State = 'AppOnlySupported' }
            [pscustomobject]@{ Name = 'PIMRoleData'; State = 'DelegatedRequired' }
            [pscustomobject]@{ Name = 'MailboxStatistics'; State = 'Deferred' }
        )
        GetHealth = ({ Get-HybridExchangeOnlineProviderHealth }).GetNewClosure()
        GetProviderHealth = ({ Get-HybridExchangeOnlineProviderHealth }).GetNewClosure()
        GetMailbox = ({ param([string]$Identity) Get-HybridExchangeOnlineMailbox -Identity $Identity }).GetNewClosure()
        GetUserMailbox = ({ param([string]$Identity) Get-HybridExchangeOnlineMailbox -Identity $Identity }).GetNewClosure()
        GetMailboxForwarding = ({ param([string]$Identity) Get-HybridExchangeOnlineMailboxForwarding -Identity $Identity }).GetNewClosure()
        GetDistributionGroups = ({ param([string]$Identity) Get-HybridExchangeOnlineDistributionGroups -Identity $Identity }).GetNewClosure()
        SearchDistributionGroups = ({ param([string]$Query) Search-HybridExchangeOnlineDistributionGroups -Query $Query }).GetNewClosure()
        AddDistributionGroupMember = ({ param([string]$Identity, [string]$GroupIdentity) Add-HybridExchangeOnlineDistributionGroupMember -Identity $Identity -GroupIdentity $GroupIdentity }).GetNewClosure()
        RemoveDistributionGroupMember = ({ param([string]$Identity, [string]$GroupIdentity) Remove-HybridExchangeOnlineDistributionGroupMember -Identity $Identity -GroupIdentity $GroupIdentity }).GetNewClosure()
        GetMailboxStatistics = ({ param([string]$Identity) Get-HybridExchangeOnlineMailboxStatistics -Identity $Identity }).GetNewClosure()
        GetMailboxDelegations = ({ param([string]$Identity) Get-HybridExchangeOnlineMailboxDelegations -Identity $Identity }).GetNewClosure()
    }
}

function Get-HybridExchangeOnlineProviderHealth {
    [CmdletBinding()]
    param()

    $context = $script:HybridExchangeOnlineState.Context
    $moduleStatus = Test-HybridExchangeOnlineModuleAvailable
    $configuration = Test-HybridExchangeOnlineConfiguration -Context $context
    $status = [string]$script:HybridExchangeOnlineState.Status
    if ([string]::IsNullOrWhiteSpace($status)) { $status = 'NotConfigured' }
    if (-not $configuration.IsConfigured) { $status = 'NotConfigured' }
    elseif (-not $moduleStatus.Available) { $status = 'ModuleMissing' }
    elseif ([bool]$script:HybridExchangeOnlineState.Connected) { $status = 'Connected' }
    elseif ([bool]$script:HybridExchangeOnlineState.Deferred -and $status -ne 'Failed') { $status = 'Deferred' }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnline.ProviderHealth'
        ProviderName = 'ExchangeOnline'
        Initialized = [bool]$script:HybridExchangeOnlineState.Initialized
        Available = ($status -in @('Connected','Deferred'))
        Connected = ($status -eq 'Connected')
        Deferred = ($status -eq 'Deferred')
        Status = $status
        ModuleStatus = $moduleStatus
        Configuration = $configuration
        AuthenticationStatus = if ($configuration.IsConfigured) { 'AppOnlySupported' } else { 'NotConfigured' }
        Capabilities = @('MailboxRead','MailboxForwarding','MailboxStatistics','MailboxDelegationRead','DistributionGroupRead','DelegatedRequired')
        LastError = $script:HybridExchangeOnlineState.LastError
    }
}

function Get-HybridExchangeOnlineMailbox {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    Ensure-HybridExchangeOnlineConnection
    $command = Get-Command -Name Get-EXOMailbox -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $mailbox = Get-EXOMailbox -Identity $Identity -Properties RecipientTypeDetails,PrimarySmtpAddress,EmailAddresses,ForwardingSmtpAddress,ForwardingAddress,DeliverToMailboxAndForward,ArchiveStatus,LitigationHoldEnabled,HiddenFromAddressListsEnabled,MailboxPlan,ExternalDirectoryObjectId,ExchangeGuid -ErrorAction Stop
        return ConvertTo-HybridExchangeOnlineMailboxModel -Mailbox $mailbox
    }

    $legacyCommand = Get-Command -Name Get-Mailbox -ErrorAction SilentlyContinue
    if ($null -eq $legacyCommand) { throw 'No Exchange Online mailbox cmdlet is available after connecting.' }
    $legacyMailbox = Get-Mailbox -Identity $Identity -ErrorAction Stop
    return ConvertTo-HybridExchangeOnlineMailboxModel -Mailbox $legacyMailbox
}

function Get-HybridExchangeOnlineMailboxForwarding {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $mailbox = Get-HybridExchangeOnlineMailbox -Identity $Identity
    if ($null -eq $mailbox) { return $null }
    [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnline.Forwarding'
        Identity = $Identity
        ForwardingSmtpAddress = $mailbox.ForwardingSmtpAddress
        ForwardingAddress = $mailbox.ForwardingAddress
        DeliverToMailboxAndForward = $mailbox.DeliverToMailboxAndForward
    }
}

function Get-HybridExchangeOnlineMailboxStatistics {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    Ensure-HybridExchangeOnlineConnection
    $command = Get-Command -Name Get-EXOMailboxStatistics -ErrorAction SilentlyContinue
    if ($null -eq $command) { $command = Get-Command -Name Get-MailboxStatistics -ErrorAction SilentlyContinue }
    if ($null -eq $command) { return $null }

    $statistics = & $command -Identity $Identity -ErrorAction Stop
    return [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnline.MailboxStatistics'
        Identity = $Identity
        DisplayName = [string](Get-HybridExchangeOnlineObjectValue -InputObject $statistics -Names @('DisplayName') -Default '')
        TotalItemSize = Get-HybridExchangeOnlineObjectValue -InputObject $statistics -Names @('TotalItemSize') -Default $null
        ItemCount = Get-HybridExchangeOnlineObjectValue -InputObject $statistics -Names @('ItemCount') -Default $null
        LastLogonTime = Get-HybridExchangeOnlineObjectValue -InputObject $statistics -Names @('LastLogonTime') -Default $null
        Raw = $statistics
    }
}

function Get-HybridExchangeOnlineMailboxDelegations {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    Ensure-HybridExchangeOnlineConnection
    $delegations = New-Object System.Collections.Generic.List[object]

    $exoPermission = Get-Command -Name Get-EXOMailboxPermission -ErrorAction SilentlyContinue
    if ($null -ne $exoPermission -and $exoPermission.Parameters.ContainsKey('User')) {
        try {
            @(Get-EXOMailboxPermission -User $Identity -ResultSize Unlimited -ErrorAction Stop |
                Where-Object { -not [bool](Get-HybridExchangeOnlineObjectValue -InputObject $_ -Names @('Deny','IsInherited') -Default $false) }) |
                ForEach-Object { $delegations.Add((ConvertTo-HybridExchangeOnlineMailboxDelegationModel -Delegation $_ -DelegationType 'FullAccess')) | Out-Null }
        }
        catch { }
    }

    $recipientPermission = Get-Command -Name Get-RecipientPermission -ErrorAction SilentlyContinue
    if ($null -ne $recipientPermission -and $recipientPermission.Parameters.ContainsKey('Trustee')) {
        try {
            @(Get-RecipientPermission -Trustee $Identity -ResultSize Unlimited -ErrorAction Stop |
                Where-Object { -not [bool](Get-HybridExchangeOnlineObjectValue -InputObject $_ -Names @('Deny','IsInherited') -Default $false) }) |
                ForEach-Object { $delegations.Add((ConvertTo-HybridExchangeOnlineMailboxDelegationModel -Delegation $_ -DelegationType 'SendAs')) | Out-Null }
        }
        catch { }
    }

    if ($delegations.Count -eq 0) {
        $mailboxPermission = Get-Command -Name Get-MailboxPermission -ErrorAction SilentlyContinue
        $mailboxCommand = Get-Command -Name Get-EXOMailbox -ErrorAction SilentlyContinue
        if ($null -eq $mailboxCommand) { $mailboxCommand = Get-Command -Name Get-Mailbox -ErrorAction SilentlyContinue }
        if ($null -ne $mailboxPermission -and $null -ne $mailboxCommand) {
            try {
                @(& $mailboxCommand -ResultSize Unlimited -ErrorAction Stop) | ForEach-Object {
                    $mailboxIdentity = [string](Get-HybridExchangeOnlineObjectValue -InputObject $_ -Names @('UserPrincipalName','PrimarySmtpAddress','Identity') -Default '')
                    if ([string]::IsNullOrWhiteSpace($mailboxIdentity)) { return }
                    @(Get-MailboxPermission -Identity $mailboxIdentity -User $Identity -ErrorAction SilentlyContinue |
                        Where-Object { -not [bool](Get-HybridExchangeOnlineObjectValue -InputObject $_ -Names @('Deny','IsInherited') -Default $false) }) |
                        ForEach-Object { $delegations.Add((ConvertTo-HybridExchangeOnlineMailboxDelegationModel -Delegation $_ -DelegationType 'FullAccess')) | Out-Null }
                }
            }
            catch { }
        }
    }

    return @($delegations | Where-Object { $null -ne $_ } | Sort-Object Mailbox,DelegationType -Unique)
}

function Get-HybridExchangeOnlineDistributionGroups {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    Ensure-HybridExchangeOnlineConnection
    $groups = New-Object System.Collections.Generic.List[object]
    $recipient = $null

    $recipientCommand = Get-Command -Name Get-EXORecipient -ErrorAction SilentlyContinue
    if ($null -eq $recipientCommand) { $recipientCommand = Get-Command -Name Get-Recipient -ErrorAction SilentlyContinue }
    if ($null -ne $recipientCommand) {
        try { $recipient = @(& $recipientCommand -Identity $Identity -ErrorAction Stop | Select-Object -First 1)[0] } catch { $recipient = $null }
    }

    $candidateValues = @(
        $Identity,
        (Get-HybridExchangeOnlineObjectValue -InputObject $recipient -Names @('DistinguishedName') -Default $null),
        (Get-HybridExchangeOnlineObjectValue -InputObject $recipient -Names @('PrimarySmtpAddress','WindowsEmailAddress') -Default $null),
        (Get-HybridExchangeOnlineObjectValue -InputObject $recipient -Names @('ExternalDirectoryObjectId','Guid','Id') -Default $null)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    $distributionCommand = Get-Command -Name Get-EXODistributionGroup -ErrorAction SilentlyContinue
    if ($null -eq $distributionCommand) { $distributionCommand = Get-Command -Name Get-DistributionGroup -ErrorAction SilentlyContinue }
    if ($null -eq $distributionCommand) { return @() }

    foreach ($candidate in $candidateValues) {
        $escaped = ([string]$candidate).Replace("'", "''")
        foreach ($filter in @("Members -eq '$escaped'", "ManagedBy -eq '$escaped'")) {
            try {
                @(& $distributionCommand -ResultSize Unlimited -Filter $filter -ErrorAction Stop) |
                    ForEach-Object { $groups.Add((ConvertTo-HybridExchangeOnlineDistributionGroupModel -Group $_ -MatchedBy $filter)) | Out-Null }
            }
            catch { }
        }
    }

    return @($groups | Where-Object { $null -ne $_ } | Sort-Object Identity,PrimarySmtpAddress -Unique)
}

function Search-HybridExchangeOnlineDistributionGroups {
    [CmdletBinding()]
    param(
        [string]$Query = '',
        [int]$ResultSize = 50
    )

    Ensure-HybridExchangeOnlineConnection
    $distributionCommand = Get-Command -Name Get-EXODistributionGroup -ErrorAction SilentlyContinue
    if ($null -eq $distributionCommand) { $distributionCommand = Get-Command -Name Get-DistributionGroup -ErrorAction SilentlyContinue }
    if ($null -eq $distributionCommand) { return @() }

    $groups = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($Query)) {
        @(& $distributionCommand -ResultSize $ResultSize -ErrorAction Stop) |
            ForEach-Object { $groups.Add((ConvertTo-HybridExchangeOnlineDistributionGroupModel -Group $_ -MatchedBy 'Browse')) | Out-Null }
    }
    else {
        $escaped = $Query.Replace("'", "''")
        try {
            @(& $distributionCommand -Identity $Query -ErrorAction Stop) |
                ForEach-Object { $groups.Add((ConvertTo-HybridExchangeOnlineDistributionGroupModel -Group $_ -MatchedBy 'Identity')) | Out-Null }
        }
        catch { }

        foreach ($filter in @("DisplayName -like '*$escaped*'", "Name -like '*$escaped*'", "Alias -like '*$escaped*'", "PrimarySmtpAddress -like '*$escaped*'")) {
            try {
                @(& $distributionCommand -ResultSize $ResultSize -Filter $filter -ErrorAction Stop) |
                    ForEach-Object { $groups.Add((ConvertTo-HybridExchangeOnlineDistributionGroupModel -Group $_ -MatchedBy $filter)) | Out-Null }
            }
            catch { }
        }
    }

    return @($groups | Where-Object { $null -ne $_ } | Sort-Object Identity,PrimarySmtpAddress -Unique | Select-Object -First $ResultSize)
}

function Add-HybridExchangeOnlineDistributionGroupMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][string]$GroupIdentity
    )

    Ensure-HybridExchangeOnlineConnection
    $command = Get-Command -Name Add-DistributionGroupMember -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw 'Add-DistributionGroupMember is not available after connecting to Exchange Online.' }

    & $command -Identity $GroupIdentity -Member $Identity -BypassSecurityGroupManagerCheck -ErrorAction Stop
    return [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnline.DistributionGroupMembershipUpdate'
        Action = 'Add'
        Identity = $Identity
        GroupIdentity = $GroupIdentity
        Success = $true
    }
}

function Remove-HybridExchangeOnlineDistributionGroupMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Identity,
        [Parameter(Mandatory=$true)][string]$GroupIdentity
    )

    Ensure-HybridExchangeOnlineConnection
    $command = Get-Command -Name Remove-DistributionGroupMember -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw 'Remove-DistributionGroupMember is not available after connecting to Exchange Online.' }

    & $command -Identity $GroupIdentity -Member $Identity -Confirm:$false -BypassSecurityGroupManagerCheck -ErrorAction Stop
    return [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnline.DistributionGroupMembershipUpdate'
        Action = 'Remove'
        Identity = $Identity
        GroupIdentity = $GroupIdentity
        Success = $true
    }
}

Export-ModuleMember -Function `
    Resolve-HybridExchangeOnlineEndpoint,`
    Test-HybridExchangeOnlineModuleAvailable,`
    Test-HybridExchangeOnlineConfiguration,`
    New-HybridExchangeOnlineProviderContext,`
    Initialize-HybridExchangeOnlineProvider,`
    Get-HybridExchangeOnlineProviderHealth,`
    Get-HybridExchangeOnlineMailbox,`
    Get-HybridExchangeOnlineMailboxForwarding,`
    Get-HybridExchangeOnlineMailboxStatistics,`
    Get-HybridExchangeOnlineMailboxDelegations,`
    Get-HybridExchangeOnlineDistributionGroups,`
    Search-HybridExchangeOnlineDistributionGroups,`
    Add-HybridExchangeOnlineDistributionGroupMember,`
    Remove-HybridExchangeOnlineDistributionGroupMember
