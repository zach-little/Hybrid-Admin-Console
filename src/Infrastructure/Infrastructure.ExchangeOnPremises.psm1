#region Module Information
# Name: Infrastructure.ExchangeOnPremises
# Purpose: On-premises Exchange provider for hybrid recipient/mailbox data.
# Notes: This provider is infrastructure-only. UI and application layers consume it through provider scriptblock operations.
#endregion

Set-StrictMode -Version Latest

$script:HybridExchangeOnPremisesState = @{
    Initialized = $false
    Server = $null
    ConnectionUri = $null
    Authentication = 'Kerberos'
    Credential = $null
    Session = $null
    LastError = $null
}

function New-HybridExchangeOnPremisesConnectionUri {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Server,
        [AllowNull()][string]$ConnectionUri
    )

    if (-not [string]::IsNullOrWhiteSpace($ConnectionUri)) { return $ConnectionUri }
    if ([string]::IsNullOrWhiteSpace($Server)) { return $null }
    return ('http://{0}/PowerShell/' -f $Server.Trim())
}

function Connect-HybridExchangeOnPremisesSession {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Server,
        [AllowNull()][string]$ConnectionUri,
        [ValidateSet('Kerberos','Negotiate','Basic')][string]$Authentication = 'Kerberos',
        [AllowNull()][pscredential]$Credential
    )

    $uri = New-HybridExchangeOnPremisesConnectionUri -Server $Server -ConnectionUri $ConnectionUri
    if ([string]::IsNullOrWhiteSpace($uri)) { throw 'On-premises Exchange requires Server or ConnectionUri.' }

    $sessionParameters = @{
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri = $uri
        Authentication = $Authentication
        AllowRedirection = $true
    }
    if ($null -ne $Credential) { $sessionParameters.Credential = $Credential }

    $session = New-PSSession @sessionParameters
    Import-PSSession $session -DisableNameChecking -AllowClobber | Out-Null
    return $session
}

function Initialize-HybridExchangeOnPremisesProvider {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Server,
        [AllowNull()][string]$ConnectionUri,
        [ValidateSet('Kerberos','Negotiate','Basic')][string]$Authentication = 'Kerberos',
        [AllowNull()][pscredential]$Credential,
        [switch]$DeferConnection
    )

    $script:HybridExchangeOnPremisesState.Server = $Server
    $script:HybridExchangeOnPremisesState.ConnectionUri = New-HybridExchangeOnPremisesConnectionUri -Server $Server -ConnectionUri $ConnectionUri
    $script:HybridExchangeOnPremisesState.Authentication = $Authentication
    $script:HybridExchangeOnPremisesState.Credential = $Credential
    $script:HybridExchangeOnPremisesState.LastError = $null

    if (-not $DeferConnection) {
        try {
            $script:HybridExchangeOnPremisesState.Session = Connect-HybridExchangeOnPremisesSession -Server $Server -ConnectionUri $ConnectionUri -Authentication $Authentication -Credential $Credential
        }
        catch {
            $script:HybridExchangeOnPremisesState.LastError = $_.Exception.Message
            throw
        }
    }

    $script:HybridExchangeOnPremisesState.Initialized = $true

    [pscustomobject]@{
        PSTypeName = 'Hybrid.Provider.ExchangeOnPremises'
        Name = 'ExchangeOnPremises'
        Server = $script:HybridExchangeOnPremisesState.Server
        ConnectionUri = $script:HybridExchangeOnPremisesState.ConnectionUri
        Authentication = $script:HybridExchangeOnPremisesState.Authentication
        Deferred = [bool]$DeferConnection
        GetHealth = ({ Get-HybridExchangeOnPremisesHealth }).GetNewClosure()
        GetRecipient = ({ param([string]$Identity) Get-HybridExchangeOnPremisesRecipient -Identity $Identity }).GetNewClosure()
        GetExchangeRecipient = ({ param([string]$Identity) Get-HybridExchangeOnPremisesRecipient -Identity $Identity }).GetNewClosure()
        GetRemoteMailbox = ({ param([string]$Identity) Get-HybridExchangeOnPremisesRemoteMailbox -Identity $Identity }).GetNewClosure()
        GetMailbox = ({ param([string]$Identity) Get-HybridExchangeOnPremisesRecipient -Identity $Identity }).GetNewClosure()
        GetMailboxForwarding = ({ param([string]$Identity) Get-HybridExchangeOnPremisesForwarding -Identity $Identity }).GetNewClosure()
        GetDistributionGroups = ({ param([string]$Identity) Get-HybridExchangeOnPremisesDistributionGroups -Identity $Identity }).GetNewClosure()
    }
}

function Get-HybridExchangeOnPremisesHealth {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        PSTypeName = 'Hybrid.ProviderHealth.ExchangeOnPremises'
        Initialized = [bool]$script:HybridExchangeOnPremisesState.Initialized
        Available = [bool]$script:HybridExchangeOnPremisesState.Initialized
        Connected = ($null -ne $script:HybridExchangeOnPremisesState.Session -or [string]::IsNullOrWhiteSpace([string]$script:HybridExchangeOnPremisesState.LastError))
        Deferred = ($null -eq $script:HybridExchangeOnPremisesState.Session)
        Server = $script:HybridExchangeOnPremisesState.Server
        ConnectionUri = $script:HybridExchangeOnPremisesState.ConnectionUri
        Authentication = $script:HybridExchangeOnPremisesState.Authentication
        LastError = $script:HybridExchangeOnPremisesState.LastError
    }
}

function Get-HybridExchangeOnPremisesRecipient {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not (Get-Command Get-Recipient -ErrorAction SilentlyContinue)) { throw 'Get-Recipient is unavailable. Connect the on-premises Exchange provider first.' }
    Get-Recipient -Identity $Identity -ErrorAction Stop | Select-Object *
}

function Get-HybridExchangeOnPremisesRemoteMailbox {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not (Get-Command Get-RemoteMailbox -ErrorAction SilentlyContinue)) { return $null }
    Get-RemoteMailbox -Identity $Identity -ErrorAction Stop | Select-Object *
}

function Get-HybridExchangeOnPremisesForwarding {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $recipient = Get-HybridExchangeOnPremisesRecipient -Identity $Identity
    if ($null -eq $recipient) { return $null }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.ExchangeOnPremises.Forwarding'
        Identity = $Identity
        ForwardingAddress = $recipient.ForwardingAddress
        ForwardingSmtpAddress = $recipient.ForwardingSmtpAddress
        DeliverToMailboxAndForward = $recipient.DeliverToMailboxAndForward
        RecipientTypeDetails = $recipient.RecipientTypeDetails
        RemoteRoutingAddress = $recipient.RemoteRoutingAddress
    }
}

function Get-HybridExchangeOnPremisesDistributionGroups {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not (Get-Command Get-Recipient -ErrorAction SilentlyContinue)) { throw 'Get-Recipient is unavailable. Connect the on-premises Exchange provider first.' }
    Get-Recipient -Filter "Members -eq '$Identity'" -RecipientTypeDetails MailUniversalDistributionGroup,MailUniversalSecurityGroup -ErrorAction SilentlyContinue | Select-Object *
}

function Disconnect-HybridExchangeOnPremisesProvider {
    [CmdletBinding()]
    param()

    if ($null -ne $script:HybridExchangeOnPremisesState.Session) {
        Remove-PSSession -Session $script:HybridExchangeOnPremisesState.Session -ErrorAction SilentlyContinue
    }
    $script:HybridExchangeOnPremisesState.Session = $null
    $script:HybridExchangeOnPremisesState.Initialized = $false
    return $true
}

Export-ModuleMember -Function Initialize-HybridExchangeOnPremisesProvider,Get-HybridExchangeOnPremisesHealth,Get-HybridExchangeOnPremisesRecipient,Get-HybridExchangeOnPremisesRemoteMailbox,Get-HybridExchangeOnPremisesForwarding,Get-HybridExchangeOnPremisesDistributionGroups,Disconnect-HybridExchangeOnPremisesProvider
