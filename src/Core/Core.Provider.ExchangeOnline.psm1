Set-StrictMode -Version Latest

$script:HybridExchangeOnlineDefaultMailboxes = @(
    [pscustomobject]@{
        Id                 = 'alex.morgan'
        UserPrincipalName  = 'alex.morgan@atlas-tech.com'
        PrimarySmtpAddress = 'alex.morgan@atlas-tech.com'
        DisplayName        = 'Alex Morgan'
        MailboxType        = 'UserMailbox'
        ExchangeGuid       = '11111111-1111-1111-1111-111111111111'
        RecipientType      = 'UserMailbox'
        Source             = 'ExchangeOnline'
    },
    [pscustomobject]@{
        Id                 = 'jamie.rivera'
        UserPrincipalName  = 'jamie.rivera@atlas-tech.com'
        PrimarySmtpAddress = 'jamie.rivera@atlas-tech.com'
        DisplayName        = 'Jamie Rivera'
        MailboxType        = 'SharedMailbox'
        ExchangeGuid       = '22222222-2222-2222-2222-222222222222'
        RecipientType      = 'SharedMailbox'
        Source             = 'ExchangeOnline'
    }
)

function Get-HybridExchangeOnlineObjectValue {
    [CmdletBinding()]
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

function New-HybridExchangeOnlineMailboxModel {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Mailbox)

    $model = [pscustomobject]@{
        PSTypeName         = 'Hybrid.ExchangeOnline.Mailbox'
        Id                 = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('Id','ExternalDirectoryObjectId','Guid') -Default '')
        UserPrincipalName  = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('UserPrincipalName','UPN') -Default '')
        PrimarySmtpAddress = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('PrimarySmtpAddress','Mail','EmailAddress') -Default '')
        DisplayName        = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('DisplayName','Name') -Default '')
        MailboxType        = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('MailboxType','RecipientTypeDetails','RecipientType') -Default 'UserMailbox')
        ExchangeGuid       = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('ExchangeGuid','Guid') -Default '')
        RecipientType      = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Mailbox -Names @('RecipientType','RecipientTypeDetails') -Default 'UserMailbox')
        Source             = 'ExchangeOnline'
        Raw                = $Mailbox
    }

    $model.PSObject.TypeNames.Insert(0, 'Hybrid.ExchangeOnline.Mailbox')
    return $model
}

function New-HybridExchangeOnlineCloudEnvironment {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$CloudEnvironment)

    if ($CloudEnvironment.PSObject.Properties.Name -contains 'Endpoints' -and $null -ne $CloudEnvironment.Endpoints) {
        return $CloudEnvironment
    }

    $graphEndpoint = [string](Get-HybridExchangeOnlineObjectValue -InputObject $CloudEnvironment -Names @('Graph','GraphEndpoint','GraphBaseUri') -Default 'https://graph.microsoft.com')
    $loginEndpoint = [string](Get-HybridExchangeOnlineObjectValue -InputObject $CloudEnvironment -Names @('Login','LoginEndpoint','AuthorityHost') -Default 'https://login.microsoftonline.com')
    $exchangeEndpoint = [string](Get-HybridExchangeOnlineObjectValue -InputObject $CloudEnvironment -Names @('ExchangeOnline','ExchangeOnlineEndpoint','ExchangeEndpoint') -Default 'https://outlook.office365.com')
    $azureManagementEndpoint = [string](Get-HybridExchangeOnlineObjectValue -InputObject $CloudEnvironment -Names @('AzureManagement','AzureManagementEndpoint','ManagementEndpoint') -Default 'https://management.azure.com')

    $name = [string](Get-HybridExchangeOnlineObjectValue -InputObject $CloudEnvironment -Names @('Name') -Default 'Commercial')
    $displayName = [string](Get-HybridExchangeOnlineObjectValue -InputObject $CloudEnvironment -Names @('DisplayName') -Default $name)

    $normalized = [pscustomobject]@{
        PSTypeName   = 'Hybrid.CloudEnvironment'
        Name         = $name
        DisplayName  = $displayName
        Description  = [string](Get-HybridExchangeOnlineObjectValue -InputObject $CloudEnvironment -Names @('Description') -Default '')
        Aliases      = @()
        Endpoints    = @{
            Graph = $graphEndpoint.TrimEnd('/')
            Login = $loginEndpoint.TrimEnd('/')
            AzureManagement = $azureManagementEndpoint.TrimEnd('/')
            ExchangeOnline = $exchangeEndpoint.TrimEnd('/')
            GraphScopeSuffix = ('{0}/.default' -f $graphEndpoint.TrimEnd('/'))
        }
        OriginalCloudEnvironment = $CloudEnvironment
    }
    $normalized.PSObject.TypeNames.Insert(0, 'Hybrid.CloudEnvironment')
    return $normalized
}

function New-HybridExchangeOnlineAuthenticationRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)

    $tenantContext = Get-HybridExchangeOnlineObjectValue -InputObject $Context -Names @('TenantContext','Tenant')
    $cloudEnvironment = Get-HybridExchangeOnlineObjectValue -InputObject $Context -Names @('CloudEnvironment','Cloud')
    $authenticationMethod = [string](Get-HybridExchangeOnlineObjectValue -InputObject $Context -Names @('AuthenticationMethod','MethodName') -Default 'Interactive')
    $scopes = @((Get-HybridExchangeOnlineObjectValue -InputObject $Context -Names @('Scopes','RequiredScopes') -Default @('https://outlook.office365.com/.default')))

    if ($null -eq $tenantContext) {
        throw 'Exchange Online authentication requires a tenant context.'
    }

    if ($null -eq $cloudEnvironment -and $tenantContext.PSObject.Properties.Name -contains 'CloudEnvironment') {
        $cloudEnvironment = $tenantContext.CloudEnvironment
    }

    if ($null -eq $cloudEnvironment) {
        throw 'Exchange Online authentication requires a cloud environment.'
    }

    $cloudEnvironment = New-HybridExchangeOnlineCloudEnvironment -CloudEnvironment $cloudEnvironment

    if ($tenantContext.PSObject.Properties.Name -notcontains 'CloudEnvironment' -or $null -eq $tenantContext.CloudEnvironment) {
        $tenantContext = [pscustomobject]@{
            PSTypeName        = 'Hybrid.TenantContext'
            TenantId          = Get-HybridExchangeOnlineObjectValue -InputObject $tenantContext -Names @('TenantId','Id') -Default ''
            PrimaryDomain     = Get-HybridExchangeOnlineObjectValue -InputObject $tenantContext -Names @('PrimaryDomain','Domain','DefaultDomain') -Default ''
            CloudEnvironment  = $cloudEnvironment
            Source            = 'ExchangeOnline'
            OriginalContext   = $tenantContext
        }
        $tenantContext.PSObject.TypeNames.Insert(0, 'Hybrid.TenantContext')
    }
    else {
        $tenantContext.CloudEnvironment = $cloudEnvironment
    }

    $command = Get-Command New-HybridAuthenticationRequest -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $params = @{}
        if ($command.Parameters.ContainsKey('TenantContext')) { $params['TenantContext'] = $tenantContext }
        elseif ($command.Parameters.ContainsKey('Tenant')) { $params['Tenant'] = $tenantContext }
        if ($command.Parameters.ContainsKey('CloudEnvironment')) { $params['CloudEnvironment'] = $cloudEnvironment }
        elseif ($command.Parameters.ContainsKey('Cloud')) { $params['Cloud'] = $cloudEnvironment }
        if ($command.Parameters.ContainsKey('AuthenticationMethod')) { $params['AuthenticationMethod'] = $authenticationMethod }
        elseif ($command.Parameters.ContainsKey('MethodName')) { $params['MethodName'] = $authenticationMethod }
        elseif ($command.Parameters.ContainsKey('Method')) { $params['Method'] = $authenticationMethod }
        if ($command.Parameters.ContainsKey('Scopes')) { $params['Scopes'] = $scopes }
        elseif ($command.Parameters.ContainsKey('RequiredScopes')) { $params['RequiredScopes'] = $scopes }

        if ($params.Count -gt 0) {
            return New-HybridAuthenticationRequest @params
        }
    }

    return [pscustomobject]@{
        PSTypeName           = 'Hybrid.AuthenticationRequest'
        TenantContext        = $tenantContext
        CloudEnvironment     = $cloudEnvironment
        AuthenticationMethod = $authenticationMethod
        MethodName           = $authenticationMethod
        Scopes               = $scopes
        RequiredScopes       = $scopes
    }
}

function New-HybridExchangeOnlineProviderContext {
    [CmdletBinding()]
    param(
        $TenantContext,
        $CloudEnvironment,
        [string]$AuthenticationMethod = 'Interactive',
        [string[]]$Scopes = @('https://outlook.office365.com/.default'),
        [object[]]$MailboxData = $script:HybridExchangeOnlineDefaultMailboxes
    )

    $context = [pscustomobject]@{
        PSTypeName           = 'Hybrid.ExchangeOnline.ProviderContext'
        ProviderName         = 'ExchangeOnline'
        TenantContext        = $TenantContext
        CloudEnvironment     = $CloudEnvironment
        AuthenticationMethod = $AuthenticationMethod
        Scopes               = @($Scopes)
        MailboxData          = @($MailboxData)
    }

    $context.PSObject.TypeNames.Insert(0, 'Hybrid.ExchangeOnline.ProviderContext')
    return $context
}

function Initialize-HybridExchangeOnlineProvider {
    [CmdletBinding()]
    param($Context)

    if ($null -eq $Context) {
        $Context = New-HybridExchangeOnlineProviderContext
    }

    $service = [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnline.ProviderService'
        ProviderName = 'ExchangeOnline'
        Context = $Context
    }

    $service | Add-Member -MemberType ScriptMethod -Name Supports -Value {
        param([string]$Capability)
        return @('Mailboxes','AuthenticationSession','Health') -contains $Capability
    } -Force

    $service | Add-Member -MemberType ScriptMethod -Name GetAuthenticationSession -Value {
        $request = New-HybridExchangeOnlineAuthenticationRequest -Context $this.Context
        return Get-HybridAuthenticationSession -Request $request
    } -Force

    $service | Add-Member -MemberType ScriptMethod -Name SearchMailboxes -Value {
        param([string]$Query)
        $null = $this.GetAuthenticationSession()
        $mailboxes = @($this.Context.MailboxData)
        if (-not [string]::IsNullOrWhiteSpace($Query)) {
            $mailboxes = @($mailboxes | Where-Object {
                $_.DisplayName -like "*$Query*" -or
                $_.UserPrincipalName -like "*$Query*" -or
                $_.PrimarySmtpAddress -like "*$Query*"
            })
        }
        return @($mailboxes | ForEach-Object { New-HybridExchangeOnlineMailboxModel -Mailbox $_ })
    } -Force

    $service | Add-Member -MemberType ScriptMethod -Name GetMailbox -Value {
        param([string]$Identity)
        $null = $this.GetAuthenticationSession()
        $mailbox = @($this.Context.MailboxData | Where-Object {
            $_.Id -ieq $Identity -or
            $_.UserPrincipalName -ieq $Identity -or
            $_.PrimarySmtpAddress -ieq $Identity -or
            $_.DisplayName -ieq $Identity
        } | Select-Object -First 1)
        if ($null -eq $mailbox -or @($mailbox).Count -eq 0) { return $null }
        return New-HybridExchangeOnlineMailboxModel -Mailbox @($mailbox)[0]
    } -Force

    $service | Add-Member -MemberType ScriptMethod -Name GetHealth -Value {
        $session = $this.GetAuthenticationSession()
        $health = [pscustomobject]@{
            PSTypeName = 'Hybrid.ExchangeOnline.ProviderHealth'
            ProviderName = 'ExchangeOnline'
            Status = 'Healthy'
            AuthenticationSession = $session
            Capabilities = @('Mailboxes','AuthenticationSession','Health')
        }
        $health.PSObject.TypeNames.Insert(0, 'Hybrid.ExchangeOnline.ProviderHealth')
        return $health
    } -Force

    $service.PSObject.TypeNames.Insert(0, 'Hybrid.ExchangeOnline.ProviderService')
    return $service
}

function Search-HybridExchangeOnlineMailbox {
    [CmdletBinding()]
    param(
        [string]$Query,
        $Service,
        $Context
    )

    if ($null -eq $Service) {
        $Service = Initialize-HybridExchangeOnlineProvider -Context $Context
    }

    return @($Service.SearchMailboxes($Query))
}

function Get-HybridExchangeOnlineMailbox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identity,
        $Service,
        $Context
    )

    if ($null -eq $Service) {
        $Service = Initialize-HybridExchangeOnlineProvider -Context $Context
    }

    return $Service.GetMailbox($Identity)
}

function Get-HybridExchangeOnlineProviderHealth {
    [CmdletBinding()]
    param(
        $Service,
        $Context
    )

    if ($null -eq $Service) {
        $Service = Initialize-HybridExchangeOnlineProvider -Context $Context
    }

    return $Service.GetHealth()
}

Export-ModuleMember -Function `
    New-HybridExchangeOnlineProviderContext,`
    Initialize-HybridExchangeOnlineProvider,`
    Search-HybridExchangeOnlineMailbox,`
    Get-HybridExchangeOnlineMailbox,`
    Get-HybridExchangeOnlineProviderHealth
