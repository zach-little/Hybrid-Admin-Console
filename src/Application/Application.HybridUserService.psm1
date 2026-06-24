#region Module Information
# Name: Application.HybridUserService
# Purpose: Vertical-slice service layer for unified Hybrid.User search and enriched user details.
# Dependencies: Provider services supplied by caller.
# Exports: Initialize-HybridUserService, Search-HybridUser, Get-HybridUser, Get-HybridUserDetails, Get-HybridUserMailboxDetails, Get-HybridUserServiceHealth, Clear-HybridUserService
#endregion

Set-StrictMode -Version Latest

$script:HybridUserServiceState = @{
    Initialized      = $false
    ActiveDirectory  = $null
    MicrosoftGraph   = $null
    ExchangeOnline   = $null
    ExchangeOnPremises = $null
    Cache            = @{}
    DetailCache      = @{}
    MailboxCache     = @{}
    LastQuery        = $null
    LastResult       = $null
    LastError        = $null
}

function Write-HybridUserHydrationDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Stage,
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')][string]$Level = 'INFO',
        [AllowNull()][object]$Data = $null
    )

    try {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        $repoRoot = Split-Path -Parent $moduleRoot
        $logRoot = Join-Path $repoRoot 'logs'
        if (-not (Test-Path -LiteralPath $logRoot)) { New-Item -Path $logRoot -ItemType Directory -Force | Out-Null }
        $logPath = Join-Path $logRoot 'hydration-diagnostics.log'
        $line = '[{0:u}] [{1}] [Application.HybridUserService:{2}] {3}' -f ([datetime]::UtcNow), $Level, $Stage, $Message
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
        if ($null -ne $Data) {
            Add-Content -LiteralPath $logPath -Value ('    Data: ' + ($Data | ConvertTo-Json -Depth 6 -Compress)) -Encoding UTF8
        }
    }
    catch { }
}

function Get-HybridObjectValue {
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
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                return $value
            }
        }

        if ($InputObject.PSObject.Properties.Name -contains $name) {
            $value = $InputObject.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                return $value
            }
        }
    }

    return $Default
}

function Get-HybridActiveDirectoryStableIdentity {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$User,
        [AllowNull()][object]$ActiveDirectoryUser
    )

    $candidateSources = @($ActiveDirectoryUser, $User)

    foreach ($source in $candidateSources) {
        $candidate = Get-HybridObjectValue -InputObject $source -Names @('DistinguishedName','DN') -Default $null
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { return [string]$candidate }

        $attributes = Get-HybridObjectValue -InputObject $source -Names @('Attributes') -Default $null
        $candidate = Get-HybridObjectValue -InputObject $attributes -Names @('DistinguishedName','DN') -Default $null
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { return [string]$candidate }

        $candidate = Get-HybridObjectValue -InputObject $source -Names @('ObjectGuid','ObjectGUID','Guid','Id') -Default $null
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { return [string]$candidate }

        $candidate = Get-HybridObjectValue -InputObject $attributes -Names @('ObjectGuid','ObjectGUID','Guid') -Default $null
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { return [string]$candidate }

        $candidate = Get-HybridObjectValue -InputObject $source -Names @('ObjectSid','SID','Sid') -Default $null
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { return [string]$candidate }

        $candidate = Get-HybridObjectValue -InputObject $attributes -Names @('ObjectSid','SID','Sid') -Default $null
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { return [string]$candidate }

        $candidate = Get-HybridObjectValue -InputObject $source -Names @('SamAccountName','SAMAccountName','sAMAccountName') -Default $null
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { return [string]$candidate }

        $candidate = Get-HybridObjectValue -InputObject $attributes -Names @('SamAccountName','SAMAccountName','sAMAccountName') -Default $null
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { return [string]$candidate }
    }

    $fallback = Get-HybridObjectValue -InputObject $User -Names @('UserPrincipalName','Identity','Mail') -Default $null
    if (-not [string]::IsNullOrWhiteSpace([string]$fallback)) { return [string]$fallback }

    return ''
}

function Add-HybridUserActiveDirectoryIdentityMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$User,
        [AllowNull()][object]$ActiveDirectoryUser
    )

    $stableIdentity = Get-HybridActiveDirectoryStableIdentity -User $User -ActiveDirectoryUser $ActiveDirectoryUser
    $distinguishedName = [string](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('DistinguishedName','DN') -Default (Get-HybridObjectValue -InputObject $User -Names @('DistinguishedName','DN') -Default ''))
    $samAccountName = [string](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('SamAccountName','SAMAccountName','sAMAccountName') -Default (Get-HybridObjectValue -InputObject $User -Names @('SamAccountName','SAMAccountName','sAMAccountName') -Default ''))

    if ($User.PSObject.Properties.Name -notcontains 'ActiveDirectoryIdentity') {
        Add-Member -InputObject $User -NotePropertyName ActiveDirectoryIdentity -NotePropertyValue $stableIdentity
    }
    else {
        $User.ActiveDirectoryIdentity = $stableIdentity
    }

    if ($User.PSObject.Properties.Name -notcontains 'ActiveDirectoryDistinguishedName') {
        Add-Member -InputObject $User -NotePropertyName ActiveDirectoryDistinguishedName -NotePropertyValue $distinguishedName
    }
    else {
        $User.ActiveDirectoryDistinguishedName = $distinguishedName
    }

    if ($User.PSObject.Properties.Name -notcontains 'ActiveDirectorySamAccountName') {
        Add-Member -InputObject $User -NotePropertyName ActiveDirectorySamAccountName -NotePropertyValue $samAccountName
    }
    else {
        $User.ActiveDirectorySamAccountName = $samAccountName
    }

    return $User
}


function Invoke-HybridServiceOperation {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Service,
        [Parameter(Mandatory=$true)][string[]]$OperationNames,
        [object[]]$Arguments = @()
    )

    if ($null -eq $Service) {
        Write-HybridUserHydrationDiagnostic -Stage 'ProviderOperation' -Message 'Skipped provider operation because service was null.' -Level WARN -Data ([pscustomobject]@{
            OperationNames = $OperationNames
        })
        return @()
    }

    foreach ($operationName in $OperationNames) {
        if ($Service.PSObject.Properties.Name -contains $operationName) {
            $operation = $Service.$operationName
            if ($operation -is [scriptblock]) {
                try {
                    Write-HybridUserHydrationDiagnostic -Stage 'ProviderOperation' -Message "Invoking $operationName."
                    $result = @(& $operation @Arguments)
                    Write-HybridUserHydrationDiagnostic -Stage 'ProviderOperation' -Message "Completed $operationName. Returned $($result.Count) item(s)." -Level SUCCESS
                    return @($result)
                }
                catch {
                    Write-HybridUserHydrationDiagnostic -Stage 'ProviderOperation' -Message "Failed $operationName - $($_.Exception.Message)" -Level ERROR -Data ([pscustomobject]@{
                        Operation = $operationName
                        Arguments = @($Arguments)
                        ExceptionType = $_.Exception.GetType().FullName
                        FullyQualifiedErrorId = $_.FullyQualifiedErrorId
                        ScriptStackTrace = $_.ScriptStackTrace
                    })
                    throw
                }
            }
            if ($null -ne $operation -and $operation.PSObject.Methods.Name -contains 'Invoke') {
                try {
                    Write-HybridUserHydrationDiagnostic -Stage 'ProviderOperation' -Message "Invoking $operationName."
                    $result = @($operation.Invoke($Arguments))
                    Write-HybridUserHydrationDiagnostic -Stage 'ProviderOperation' -Message "Completed $operationName. Returned $($result.Count) item(s)." -Level SUCCESS
                    return @($result)
                }
                catch {
                    Write-HybridUserHydrationDiagnostic -Stage 'ProviderOperation' -Message "Failed $operationName - $($_.Exception.Message)" -Level ERROR -Data ([pscustomobject]@{
                        Operation = $operationName
                        Arguments = @($Arguments)
                        ExceptionType = $_.Exception.GetType().FullName
                        FullyQualifiedErrorId = $_.FullyQualifiedErrorId
                        ScriptStackTrace = $_.ScriptStackTrace
                    })
                    throw
                }
            }
        }
    }

    Write-HybridUserHydrationDiagnostic -Stage 'ProviderOperation' -Message 'No matching provider operation found.' -Level WARN -Data ([pscustomobject]@{
        RequestedOperations = $OperationNames
        ServiceTypeNames = @($Service.PSObject.TypeNames)
        ServiceProperties = @($Service.PSObject.Properties.Name)
    })
    return @()
}

function Get-HybridProviderHealthSnapshot {
    [CmdletBinding()]
    param([AllowNull()][object]$Service)

    $health = @(Invoke-HybridServiceOperation -Service $Service -OperationNames @('GetHealth','GetProviderHealth') -Arguments @() | Select-Object -First 1)
    if ($health.Count -gt 0) { return $health[0] }

    if ($null -eq $Service) {
        return [pscustomobject]@{
            PSTypeName = 'Hybrid.ProviderHealth.ApplicationSnapshot'
            Initialized = $false
            Available = $false
            Connected = $false
            LastError = $null
        }
    }

    return [pscustomobject]@{
        PSTypeName = 'Hybrid.ProviderHealth.ApplicationSnapshot'
        Initialized = $true
        Available = [bool](Get-HybridObjectValue -InputObject $Service -Names @('ProviderAvailable','Available') -Default $true)
        Connected = [bool](Get-HybridObjectValue -InputObject $Service -Names @('ProviderConnected','Connected','ProviderAvailable','Available') -Default $true)
        LastError = Get-HybridObjectValue -InputObject $Service -Names @('LastError','Error','ErrorMessage') -Default $null
    }
}

function ConvertTo-HybridSourceStatus {
    [CmdletBinding()]
    param(
        [string]$Name,
        [AllowNull()][object]$Object,
        [AllowNull()][object]$ProviderHealth
    )

    $available = ($null -ne $Object)
    $connected = $available
    $lastError = $null

    if ($null -ne $ProviderHealth) {
        $available = [bool](Get-HybridObjectValue -InputObject $ProviderHealth -Names @('Available','ProviderAvailable','Initialized') -Default $available)
        $connected = [bool](Get-HybridObjectValue -InputObject $ProviderHealth -Names @('Connected','ProviderConnected','Available') -Default $available)
        $lastError = Get-HybridObjectValue -InputObject $ProviderHealth -Names @('LastError','Error','ErrorMessage') -Default $null
    }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.UserSourceStatus'
        Name       = $Name
        Available  = $available
        Connected  = $connected
        LastError  = $lastError
        Object     = $Object
        Health     = $ProviderHealth
    }
}

function ConvertTo-HybridUserOrganizationalUnit {
    [CmdletBinding()]
    param([AllowNull()][string]$DistinguishedName)

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { return '' }

    $ouParts = @($DistinguishedName -split ',' | Where-Object { $_ -like 'OU=*' } | ForEach-Object { $_.Substring(3) })
    if ($ouParts.Count -eq 0) { return '' }

    [array]::Reverse($ouParts)
    return ($ouParts -join ' / ')
}

function ConvertTo-HybridDisplayNameFromDn {
    [CmdletBinding()]
    param([AllowNull()][string]$DistinguishedName)

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { return '' }
    $firstPart = ($DistinguishedName -split ',' | Select-Object -First 1)
    if ($firstPart -like 'CN=*') { return $firstPart.Substring(3) }
    return $DistinguishedName
}

function New-HybridCompositeUser {
    [CmdletBinding()]
    param(
        [string]$Identity,
        [AllowNull()][object]$ActiveDirectoryUser,
        [AllowNull()][object]$GraphUser,
        [AllowNull()][object]$Mailbox,
        [AllowNull()][object]$ActiveDirectoryHealth,
        [AllowNull()][object]$GraphHealth,
        [AllowNull()][object]$ExchangeHealth,
        [AllowNull()][object]$ExchangeOnPremisesHealth
    )

    $displayName = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('DisplayName','Name') -Default $null
    if ($null -eq $displayName) {
        $displayName = Get-HybridObjectValue -InputObject $GraphUser -Names @('DisplayName','Name') -Default $Identity
    }

    $upn = Get-HybridObjectValue -InputObject $GraphUser -Names @('UserPrincipalName','UPN') -Default $null
    if ($null -eq $upn) {
        $upn = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('UserPrincipalName','UPN') -Default $Identity
    }

    $mail = Get-HybridObjectValue -InputObject $Mailbox -Names @('PrimarySmtpAddress','Mail','EmailAddress') -Default $null
    if ($null -eq $mail) { $mail = Get-HybridObjectValue -InputObject $GraphUser -Names @('Mail','EmailAddress') -Default $null }
    if ($null -eq $mail) { $mail = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Mail','EmailAddress') -Default $null }

    $distinguishedName = [string](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('DistinguishedName','DN') -Default '')
    if ([string]::IsNullOrWhiteSpace($distinguishedName)) {
        $activeDirectoryAttributes = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Attributes') -Default $null
        $distinguishedName = [string](Get-HybridObjectValue -InputObject $activeDirectoryAttributes -Names @('DistinguishedName','DN') -Default '')
    }
    $manager = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Manager') -Default $null

    $user = [pscustomobject]@{
        PSTypeName            = 'Hybrid.User'
        Identity              = $Identity
        DisplayName           = [string]$displayName
        UserPrincipalName     = [string]$upn
        SamAccountName        = [string](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('SamAccountName','SAMAccountName') -Default '')
        Mail                  = [string]$mail
        Department            = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('Department') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Department') -Default ''))
        Title                 = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('JobTitle','Title') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Title') -Default ''))
        Company               = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('CompanyName','Company') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Company','CompanyName') -Default ''))
        Office                = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('OfficeLocation','Office') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Office','PhysicalDeliveryOfficeName','OfficeLocation') -Default ''))
        EmployeeId            = [string](Get-HybridObjectValue -InputObject $GraphUser -Names @('EmployeeId','EmployeeID') -Default (Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('EmployeeId','EmployeeID') -Default ''))
        Manager               = $manager
        ManagerDisplayName    = ConvertTo-HybridDisplayNameFromDn -DistinguishedName ([string]$manager)
        DistinguishedName     = $distinguishedName
        ActiveDirectoryIdentity = Get-HybridActiveDirectoryStableIdentity -User $null -ActiveDirectoryUser $ActiveDirectoryUser
        ActiveDirectoryDistinguishedName = $distinguishedName
        ActiveDirectorySamAccountName = [string](Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('SamAccountName','SAMAccountName','sAMAccountName') -Default '')
        OrganizationalUnit    = ConvertTo-HybridUserOrganizationalUnit -DistinguishedName $distinguishedName
        Enabled               = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('Enabled','AccountEnabled') -Default $null
        LockedOut             = Get-HybridObjectValue -InputObject $ActiveDirectoryUser -Names @('LockedOut','IsLockedOut') -Default $null
        Groups                = @()
        DirectReports         = @()
        Mailbox               = $Mailbox
        MailboxDetails        = $null
        ExchangeLoaded        = $false
        ExchangeRetrievedOn   = $null
        Sources               = @(
            ConvertTo-HybridSourceStatus -Name 'ActiveDirectory' -Object $ActiveDirectoryUser -ProviderHealth $ActiveDirectoryHealth
            ConvertTo-HybridSourceStatus -Name 'MicrosoftGraph' -Object $GraphUser -ProviderHealth $GraphHealth
            ConvertTo-HybridSourceStatus -Name 'ExchangeOnline' -Object $Mailbox -ProviderHealth $ExchangeHealth
            ConvertTo-HybridSourceStatus -Name 'ExchangeOnPremises' -Object $null -ProviderHealth $ExchangeOnPremisesHealth
        )
        Source                = 'HybridUserService'
        RetrievedOn           = [datetime]::UtcNow
        DetailsLoaded         = $false
        DetailRetrievedOn     = $null
    }

    $user.PSObject.TypeNames.Insert(0, 'Hybrid.User.VerticalSlice')
    Add-HybridUserActiveDirectoryIdentityMetadata -User $user -ActiveDirectoryUser $ActiveDirectoryUser | Out-Null
    Write-HybridUserHydrationDiagnostic -Stage 'BaseHydration' -Message 'Resolved Active Directory DN and OU metadata for composite user.' -Level INFO -Data ([pscustomobject]@{
        Identity = $Identity
        DistinguishedName = $user.DistinguishedName
        ActiveDirectoryDistinguishedName = $user.ActiveDirectoryDistinguishedName
        OrganizationalUnit = $user.OrganizationalUnit
        ActiveDirectoryIdentity = $user.ActiveDirectoryIdentity
        ActiveDirectoryUserProperties = if ($null -ne $ActiveDirectoryUser) { @($ActiveDirectoryUser.PSObject.Properties.Name) } else { @() }
    })
    return $user
}


function Add-HybridUserDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$User)

    $adIdentity = Get-HybridActiveDirectoryStableIdentity -User $User -ActiveDirectoryUser $null
    if ([string]::IsNullOrWhiteSpace($adIdentity)) {
        throw 'Unable to resolve a stable Active Directory identity for detail hydration.'
    }

    Write-HybridUserHydrationDiagnostic -Stage 'ActiveDirectoryDetails' -Message "Using stable Active Directory identity '$adIdentity' for detail hydration." -Level INFO -Data ([pscustomobject]@{
        InputIdentity = Get-HybridObjectValue -InputObject $User -Names @('Identity','UserPrincipalName','Mail') -Default ''
        ActiveDirectoryIdentity = $adIdentity
        DistinguishedName = Get-HybridObjectValue -InputObject $User -Names @('DistinguishedName','ActiveDirectoryDistinguishedName') -Default ''
        SamAccountName = Get-HybridObjectValue -InputObject $User -Names @('SamAccountName','ActiveDirectorySamAccountName') -Default ''
    })

    $groups = @()
    $directReports = @()
    $managerObject = $null

    try {
        $groups = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('GetUserGroups','GetGroups','GetADUserGroups') -Arguments @($adIdentity))
    }
    catch {
        Write-HybridUserHydrationDiagnostic -Stage 'ActiveDirectoryDetails' -Message "Group hydration failed for stable AD identity '$adIdentity' - $($_.Exception.Message)" -Level ERROR
    }

    try {
        $directReports = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('GetUserDirectReports','GetDirectReports','GetADUserDirectReports') -Arguments @($adIdentity))
    }
    catch {
        Write-HybridUserHydrationDiagnostic -Stage 'ActiveDirectoryDetails' -Message "Direct report hydration failed for stable AD identity '$adIdentity' - $($_.Exception.Message)" -Level ERROR
    }

    try {
        $managerObject = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('GetUserManager','GetManager','GetADUserManager') -Arguments @($adIdentity) | Select-Object -First 1)
    }
    catch {
        Write-HybridUserHydrationDiagnostic -Stage 'ActiveDirectoryDetails' -Message "Manager hydration failed for stable AD identity '$adIdentity' - $($_.Exception.Message)" -Level ERROR
    }

    if ($User.PSObject.Properties.Name -notcontains 'Groups') { Add-Member -InputObject $User -NotePropertyName Groups -NotePropertyValue @() }
    if ($User.PSObject.Properties.Name -notcontains 'DirectReports') { Add-Member -InputObject $User -NotePropertyName DirectReports -NotePropertyValue @() }
    if ($User.PSObject.Properties.Name -notcontains 'ManagerObject') { Add-Member -InputObject $User -NotePropertyName ManagerObject -NotePropertyValue $null }
    if ($User.PSObject.Properties.Name -notcontains 'DetailsLoaded') { Add-Member -InputObject $User -NotePropertyName DetailsLoaded -NotePropertyValue $false }
    if ($User.PSObject.Properties.Name -notcontains 'DetailRetrievedOn') { Add-Member -InputObject $User -NotePropertyName DetailRetrievedOn -NotePropertyValue $null }

    $User.Groups = @($groups)
    $User.DirectReports = @($directReports)
    $User.ManagerObject = ($managerObject | Select-Object -First 1)

    if ($null -ne $User.ManagerObject) {
        $managerName = Get-HybridObjectValue -InputObject $User.ManagerObject -Names @('DisplayName','Name','SamAccountName','UserPrincipalName') -Default $null
        if ($null -ne $managerName -and $User.PSObject.Properties.Name -contains 'ManagerDisplayName') {
            $User.ManagerDisplayName = [string]$managerName
        }
    }

    $User.DetailsLoaded = $true
    $User.DetailRetrievedOn = [datetime]::UtcNow
    return $User
}

function Add-HybridUserMailboxDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$User)

    $identityCandidates = @(
        (Get-HybridObjectValue -InputObject $User -Names @('UserPrincipalName') -Default $null),
        (Get-HybridObjectValue -InputObject $User -Names @('Mail') -Default $null),
        (Get-HybridObjectValue -InputObject $User -Names @('SamAccountName') -Default $null),
        (Get-HybridObjectValue -InputObject $User -Names @('Identity') -Default $null)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    $identity = [string]($identityCandidates | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($identity)) { return $User }

    $onPremRecipient = $null
    if ($null -ne $script:HybridUserServiceState.ExchangeOnPremises) {
        $onPremRecipient = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnPremises -OperationNames @('GetRecipient','GetExchangeRecipient','GetRemoteMailbox','GetMailbox','Get') -Arguments @($identity) | Select-Object -First 1)
        $onPremRecipient = ($onPremRecipient | Select-Object -First 1)
    }

    $mailbox = $null
    if ($null -ne $script:HybridUserServiceState.ExchangeOnline) {
        $mailbox = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetMailbox','GetUserMailbox','Get') -Arguments @($identity) | Select-Object -First 1)
        $mailbox = ($mailbox | Select-Object -First 1)
    }

    if ($null -eq $mailbox) {
        if ($User.PSObject.Properties.Name -notcontains 'ExchangeLoaded') { Add-Member -InputObject $User -NotePropertyName ExchangeLoaded -NotePropertyValue $false }
        if ($User.PSObject.Properties.Name -notcontains 'MailboxDetails') { Add-Member -InputObject $User -NotePropertyName MailboxDetails -NotePropertyValue $null }
        $User.ExchangeLoaded = $false
        $User.MailboxDetails = $null
        if ($User.PSObject.Properties.Name -notcontains 'OnPremisesExchangeRecipient') { Add-Member -InputObject $User -NotePropertyName OnPremisesExchangeRecipient -NotePropertyValue $onPremRecipient }
        $User.OnPremisesExchangeRecipient = $onPremRecipient
        Write-HybridUserHydrationDiagnostic -Stage 'ExchangeMailbox' -Message 'Exchange Online mailbox provider did not return mailbox data; AD mail attributes are not treated as Exchange mailbox data.' -Level WARN -Data ([pscustomobject]@{ Identity = $identity; ExchangeOnlineProviderRegistered = ($null -ne $script:HybridUserServiceState.ExchangeOnline); ExchangeOnPremisesProviderRegistered = ($null -ne $script:HybridUserServiceState.ExchangeOnPremises); OnPremisesRecipientReturned = ($null -ne $onPremRecipient) })
        return $User
    }

    $statistics = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetMailboxStatistics','GetMailboxStats','GetStatistics') -Arguments @($identity) | Select-Object -First 1)
    $delegations = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetMailboxDelegations','GetDelegations','GetMailboxPermissions','GetPermissions') -Arguments @($identity))
    $distributionGroups = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetDistributionGroups','GetOwnedDistributionGroups','GetRecipientGroups') -Arguments @($identity))
    $forwarding = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetMailboxForwarding','GetForwarding') -Arguments @($identity) | Select-Object -First 1)

    $mailboxDetails = [pscustomobject]@{
        PSTypeName = 'Hybrid.UserMailboxDetails'
        Mailbox = $mailbox
        OnPremisesRecipient = $onPremRecipient
        PrimarySmtpAddress = [string](Get-HybridObjectValue -InputObject $mailbox -Names @('PrimarySmtpAddress','Mail','EmailAddress') -Default '')
        RecipientTypeDetails = [string](Get-HybridObjectValue -InputObject $mailbox -Names @('RecipientTypeDetails','RecipientType','Type') -Default '')
        HiddenFromAddressListsEnabled = Get-HybridObjectValue -InputObject $mailbox -Names @('HiddenFromAddressListsEnabled') -Default $null
        LitigationHoldEnabled = Get-HybridObjectValue -InputObject $mailbox -Names @('LitigationHoldEnabled') -Default $null
        ForwardingSmtpAddress = Get-HybridObjectValue -InputObject $forwarding -Names @('ForwardingSmtpAddress','ForwardingAddress') -Default (Get-HybridObjectValue -InputObject $mailbox -Names @('ForwardingSmtpAddress','ForwardingAddress') -Default $null)
        DeliverToMailboxAndForward = Get-HybridObjectValue -InputObject $forwarding -Names @('DeliverToMailboxAndForward') -Default (Get-HybridObjectValue -InputObject $mailbox -Names @('DeliverToMailboxAndForward') -Default $null)
        Statistics = ($statistics | Select-Object -First 1)
        Delegations = @($delegations)
        DistributionGroups = @($distributionGroups)
        RetrievedOn = [datetime]::UtcNow
    }

    if ($User.PSObject.Properties.Name -notcontains 'OnPremisesExchangeRecipient') { Add-Member -InputObject $User -NotePropertyName OnPremisesExchangeRecipient -NotePropertyValue $onPremRecipient }
    if ($User.PSObject.Properties.Name -notcontains 'Mailbox') { Add-Member -InputObject $User -NotePropertyName Mailbox -NotePropertyValue $mailbox }
    if ($User.PSObject.Properties.Name -notcontains 'MailboxDetails') { Add-Member -InputObject $User -NotePropertyName MailboxDetails -NotePropertyValue $mailboxDetails }
    if ($User.PSObject.Properties.Name -notcontains 'ExchangeLoaded') { Add-Member -InputObject $User -NotePropertyName ExchangeLoaded -NotePropertyValue $false }
    if ($User.PSObject.Properties.Name -notcontains 'ExchangeRetrievedOn') { Add-Member -InputObject $User -NotePropertyName ExchangeRetrievedOn -NotePropertyValue $null }

    $User.OnPremisesExchangeRecipient = $onPremRecipient
    $User.Mailbox = $mailbox
    $User.MailboxDetails = $mailboxDetails
    $User.ExchangeLoaded = $true
    $User.ExchangeRetrievedOn = [datetime]::UtcNow
    return $User
}

function Initialize-HybridUserService {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$ActiveDirectoryProvider,
        [AllowNull()][object]$MicrosoftGraphProvider,
        [AllowNull()][object]$ExchangeOnlineProvider,
        [AllowNull()][object]$ExchangeOnPremisesProvider
    )

    $script:HybridUserServiceState.ActiveDirectory = $ActiveDirectoryProvider
    $script:HybridUserServiceState.MicrosoftGraph = $MicrosoftGraphProvider
    $script:HybridUserServiceState.ExchangeOnline = $ExchangeOnlineProvider
    $script:HybridUserServiceState.ExchangeOnPremises = $ExchangeOnPremisesProvider
    $script:HybridUserServiceState.Initialized = $true
    $script:HybridUserServiceState.Cache.Clear()
    $script:HybridUserServiceState.DetailCache.Clear()
    $script:HybridUserServiceState.MailboxCache.Clear()

    [pscustomobject]@{
        PSTypeName = 'Hybrid.UserService'
        Name       = 'HybridUserService'
        Initialized = $true
        Providers  = @{
            ActiveDirectory = ($null -ne $ActiveDirectoryProvider)
            MicrosoftGraph  = ($null -ne $MicrosoftGraphProvider)
            ExchangeOnline  = ($null -ne $ExchangeOnlineProvider)
            ExchangeOnPremises = ($null -ne $ExchangeOnPremisesProvider)
        }
        SearchUser     = ({ param([string]$Query) Search-HybridUser -Query $Query }).GetNewClosure()
        GetUser        = ({ param([string]$Identity) Get-HybridUser -Identity $Identity }).GetNewClosure()
        GetUserDetails = ({ param([string]$Identity) Get-HybridUserDetails -Identity $Identity }).GetNewClosure()
        GetMailboxDetails = ({ param([string]$Identity) Get-HybridUserMailboxDetails -Identity $Identity }).GetNewClosure()
        GetHealth      = ({ Get-HybridUserServiceHealth }).GetNewClosure()
    }
}

function Search-HybridUser {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Query)

    if (-not $script:HybridUserServiceState.Initialized) { throw 'Hybrid user service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Query)) { throw 'Search query cannot be empty.' }

    try {
        $script:HybridUserServiceState.LastQuery = $Query
        $adUsers = Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('SearchUser','SearchADUser','Search') -Arguments @($Query)
        $graphUsers = Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.MicrosoftGraph -OperationNames @('SearchUser','SearchGraphUser','Search') -Arguments @($Query)
        Write-HybridUserHydrationDiagnostic -Stage 'Search' -Message "Search providers returned AD=$(@($adUsers).Count), Graph=$(@($graphUsers).Count) for query '$Query'." -Level INFO -Data ([pscustomobject]@{
            Query = $Query
            ActiveDirectoryResultCount = @($adUsers).Count
            MicrosoftGraphResultCount = @($graphUsers).Count
        })

        $candidateUsers = @()
        if (@($adUsers).Count -gt 0) { $candidateUsers += @($adUsers) }
        if (@($adUsers).Count -eq 0 -and @($graphUsers).Count -gt 0) { $candidateUsers += @($graphUsers) }

        if ($candidateUsers.Count -eq 0) {
            $script:HybridUserServiceState.LastResult = @()
            return @()
        }

        $results = @()
        $seen = @{}
        foreach ($candidate in $candidateUsers) {
            $identity = [string](Get-HybridObjectValue -InputObject $candidate -Names @('UserPrincipalName','UPN','SamAccountName','Identity','Mail','DistinguishedName') -Default $Query)
            if ([string]::IsNullOrWhiteSpace($identity)) { continue }
            $dedupeKey = $identity.ToLowerInvariant()
            if ($seen.ContainsKey($dedupeKey)) { continue }
            $seen[$dedupeKey] = $true
            try { $results += @(Get-HybridUser -Identity $identity) }
            catch {
                Write-HybridUserHydrationDiagnostic -Stage 'Search' -Message "Candidate hydration failed for '$identity' - $($_.Exception.Message)" -Level WARN
            }
        }

        $script:HybridUserServiceState.LastResult = @($results)
        return @($results)
    }
    catch {
        $script:HybridUserServiceState.LastError = $_.Exception.Message
        throw
    }
}

function Get-HybridUser {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not $script:HybridUserServiceState.Initialized) { throw 'Hybrid user service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'User identity cannot be empty.' }

    $cacheKey = $Identity.ToLowerInvariant()
    if ($script:HybridUserServiceState.Cache.ContainsKey($cacheKey)) {
        return $script:HybridUserServiceState.Cache[$cacheKey]
    }

    $adUser = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ActiveDirectory -OperationNames @('GetUser','GetADUser','Get') -Arguments @($Identity) | Select-Object -First 1)
    $graphUser = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.MicrosoftGraph -OperationNames @('GetUser','GetGraphUser','Get') -Arguments @($Identity) | Select-Object -First 1)
    $mailbox = @(Invoke-HybridServiceOperation -Service $script:HybridUserServiceState.ExchangeOnline -OperationNames @('GetMailbox','GetUserMailbox','Get') -Arguments @($Identity) | Select-Object -First 1)
    Write-HybridUserHydrationDiagnostic -Stage 'BaseHydration' -Message "Base hydration results AD=$(@($adUser).Count), Graph=$(@($graphUser).Count), Exchange=$(@($mailbox).Count) for identity '$Identity'." -Level INFO -Data ([pscustomobject]@{
        Identity = $Identity
        ActiveDirectoryResultCount = @($adUser).Count
        MicrosoftGraphResultCount = @($graphUser).Count
        ExchangeMailboxResultCount = @($mailbox).Count
    })

    $adHealth = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.ActiveDirectory
    $graphHealth = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.MicrosoftGraph
    $exchangeHealth = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.ExchangeOnline
    $exchangeOnPremisesHealth = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.ExchangeOnPremises

    $user = New-HybridCompositeUser `
        -Identity $Identity `
        -ActiveDirectoryUser ($adUser | Select-Object -First 1) `
        -GraphUser ($graphUser | Select-Object -First 1) `
        -Mailbox ($mailbox | Select-Object -First 1) `
        -ActiveDirectoryHealth $adHealth `
        -GraphHealth $graphHealth `
        -ExchangeHealth $exchangeHealth `
        -ExchangeOnPremisesHealth $exchangeOnPremisesHealth

    $script:HybridUserServiceState.Cache[$cacheKey] = $user
    return $user
}

function Get-HybridUserDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not $script:HybridUserServiceState.Initialized) { throw 'Hybrid user service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'User identity cannot be empty.' }

    $cacheKey = $Identity.ToLowerInvariant()
    if ($script:HybridUserServiceState.DetailCache.ContainsKey($cacheKey)) {
        return $script:HybridUserServiceState.DetailCache[$cacheKey]
    }

    $user = Get-HybridUser -Identity $Identity
    $detailedUser = Add-HybridUserDetails -User $user
    $script:HybridUserServiceState.DetailCache[$cacheKey] = $detailedUser
    return $detailedUser
}

function Get-HybridUserMailboxDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not $script:HybridUserServiceState.Initialized) { throw 'Hybrid user service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'User identity cannot be empty.' }

    $cacheKey = $Identity.ToLowerInvariant()
    if ($script:HybridUserServiceState.MailboxCache.ContainsKey($cacheKey)) {
        return $script:HybridUserServiceState.MailboxCache[$cacheKey]
    }

    $user = Get-HybridUserDetails -Identity $Identity
    $exchangeUser = Add-HybridUserMailboxDetails -User $user
    $script:HybridUserServiceState.MailboxCache[$cacheKey] = $exchangeUser
    return $exchangeUser
}

function Get-HybridUserServiceHealth {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        PSTypeName    = 'Hybrid.UserServiceHealth'
        Initialized   = [bool]$script:HybridUserServiceState.Initialized
        Providers     = @{
            ActiveDirectory = ($null -ne $script:HybridUserServiceState.ActiveDirectory)
            MicrosoftGraph  = ($null -ne $script:HybridUserServiceState.MicrosoftGraph)
            ExchangeOnline  = ($null -ne $script:HybridUserServiceState.ExchangeOnline)
            ExchangeOnPremises = ($null -ne $script:HybridUserServiceState.ExchangeOnPremises)
        }
        ProviderHealth     = @{
            ActiveDirectory = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.ActiveDirectory
            MicrosoftGraph  = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.MicrosoftGraph
            ExchangeOnline  = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.ExchangeOnline
            ExchangeOnPremises = Get-HybridProviderHealthSnapshot -Service $script:HybridUserServiceState.ExchangeOnPremises
        }
        CacheEntries       = $script:HybridUserServiceState.Cache.Count
        DetailCacheEntries = $script:HybridUserServiceState.DetailCache.Count
        MailboxCacheEntries = $script:HybridUserServiceState.MailboxCache.Count
        LastQuery          = $script:HybridUserServiceState.LastQuery
        LastError          = $script:HybridUserServiceState.LastError
    }
}

function Clear-HybridUserService {
    [CmdletBinding()]
    param()

    $script:HybridUserServiceState.Initialized = $false
    $script:HybridUserServiceState.ActiveDirectory = $null
    $script:HybridUserServiceState.MicrosoftGraph = $null
    $script:HybridUserServiceState.ExchangeOnline = $null
    $script:HybridUserServiceState.ExchangeOnPremises = $null
    $script:HybridUserServiceState.Cache.Clear()
    $script:HybridUserServiceState.DetailCache.Clear()
    $script:HybridUserServiceState.MailboxCache.Clear()
    $script:HybridUserServiceState.LastQuery = $null
    $script:HybridUserServiceState.LastResult = $null
    $script:HybridUserServiceState.LastError = $null
    return $true
}


#region Milestone 7 Phase 5 - Microsoft Graph Profile Extension
function Get-HybridUserGraphProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not $script:HybridUserServiceState.Initialized) { throw 'Hybrid user service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'User identity cannot be empty.' }

    $provider = $script:HybridUserServiceState.MicrosoftGraph
    $profile = @(Invoke-HybridServiceOperation -Service $provider -OperationNames @('GetGraphProfile','GetUserGraphProfile','GetAuthenticationProfile','GetUser','GetGraphUser','Get') -Arguments @($Identity) | Select-Object -First 1)
    if ($profile.Count -eq 0 -or $null -eq $profile[0]) { return $null }

    $raw = $profile[0]
    $methods = @(Get-HybridObjectValue -InputObject $raw -Names @('AuthenticationMethods','Methods') -Default @())
    $graphProfile = [pscustomobject]@{
        PSTypeName = 'Hybrid.GraphProfile'
        ObjectId = [string](Get-HybridObjectValue -InputObject $raw -Names @('ObjectId','Id','GraphObjectId') -Default '')
        UserPrincipalName = [string](Get-HybridObjectValue -InputObject $raw -Names @('UserPrincipalName','UPN') -Default $Identity)
        DisplayName = [string](Get-HybridObjectValue -InputObject $raw -Names @('DisplayName','Name') -Default $Identity)
        UserType = [string](Get-HybridObjectValue -InputObject $raw -Names @('UserType') -Default 'Member')
        PreferredLanguage = [string](Get-HybridObjectValue -InputObject $raw -Names @('PreferredLanguage') -Default 'en-US')
        UsageLocation = [string](Get-HybridObjectValue -InputObject $raw -Names @('UsageLocation') -Default 'US')
        LastSignInDateTime = Get-HybridObjectValue -InputObject $raw -Names @('LastSignInDateTime','LastSignIn','SignInActivity') -Default $null
        LastNonInteractiveSignInDateTime = Get-HybridObjectValue -InputObject $raw -Names @('LastNonInteractiveSignInDateTime','LastNonInteractiveSignIn') -Default $null
        PasswordLastChangedDateTime = Get-HybridObjectValue -InputObject $raw -Names @('PasswordLastChangedDateTime','LastPasswordChange','PasswordLastChanged') -Default $null
        AuthenticationMethods = @($methods)
        MfaRegistered = [bool](Get-HybridObjectValue -InputObject $raw -Names @('MfaRegistered','MfaEnabled','IsMfaRegistered') -Default $false)
        MfaCapable = [bool](Get-HybridObjectValue -InputObject $raw -Names @('MfaCapable','IsMfaCapable') -Default $false)
        RiskState = [string](Get-HybridObjectValue -InputObject $raw -Names @('RiskState','UserRiskState') -Default 'none')
        Source = [string](Get-HybridObjectValue -InputObject $raw -Names @('Source') -Default 'MicrosoftGraph')
        RetrievedOn = [datetime]::UtcNow
    }
    $graphProfile.PSObject.TypeNames.Insert(0, 'Hybrid.GraphProfile.Milestone7Phase5')
    return $graphProfile
}
#endregion

#region Milestone 7 Phase 6 - Authentication Profile Extension
function Get-HybridUserAuthenticationProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not $script:HybridUserServiceState.Initialized) { throw 'Hybrid user service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'User identity cannot be empty.' }

    $provider = $script:HybridUserServiceState.MicrosoftGraph
    $profile = @(Invoke-HybridServiceOperation -Service $provider -OperationNames @('GetAuthenticationProfile','GetUserAuthenticationProfile','GetGraphAuthenticationProfile','GetGraphProfile','GetUserGraphProfile','Get') -Arguments @($Identity) | Select-Object -First 1)
    if ($profile.Count -eq 0 -or $null -eq $profile[0]) { return $null }

    $raw = $profile[0]
    $methods = @(Get-HybridObjectValue -InputObject $raw -Names @('AuthenticationMethods','Methods') -Default @())
    $defaultMethod = [string](Get-HybridObjectValue -InputObject $raw -Names @('DefaultMethod','DefaultAuthenticationMethod') -Default '')
    if ([string]::IsNullOrWhiteSpace($defaultMethod)) { $defaultMethod = if ($methods.Count -gt 0) { [string]$methods[0] } else { 'password' } }

    $authProfile = [pscustomobject]@{
        PSTypeName = 'Hybrid.AuthenticationProfile'
        UserPrincipalName = [string](Get-HybridObjectValue -InputObject $raw -Names @('UserPrincipalName','UPN') -Default $Identity)
        DisplayName = [string](Get-HybridObjectValue -InputObject $raw -Names @('DisplayName','Name') -Default $Identity)
        DefaultMethod = $defaultMethod
        AuthenticationMethods = @($methods)
        MfaRegistered = [bool](Get-HybridObjectValue -InputObject $raw -Names @('MfaRegistered','MfaEnabled','IsMfaRegistered') -Default $false)
        MfaCapable = [bool](Get-HybridObjectValue -InputObject $raw -Names @('MfaCapable','IsMfaCapable') -Default $false)
        PasswordlessRegistered = [bool](Get-HybridObjectValue -InputObject $raw -Names @('PasswordlessRegistered','IsPasswordlessRegistered') -Default $false)
        TemporaryAccessPassEligible = [bool](Get-HybridObjectValue -InputObject $raw -Names @('TemporaryAccessPassEligible','TapEligible') -Default $false)
        AuthenticationStrength = [string](Get-HybridObjectValue -InputObject $raw -Names @('AuthenticationStrength','StrongAuthenticationRequirement') -Default 'Single-factor')
        ConditionalAccessState = [string](Get-HybridObjectValue -InputObject $raw -Names @('ConditionalAccessState','ConditionalAccess') -Default 'Not evaluated')
        SignInRiskState = [string](Get-HybridObjectValue -InputObject $raw -Names @('SignInRiskState','RiskState','UserRiskState') -Default 'none')
        LastMfaRegistrationDateTime = Get-HybridObjectValue -InputObject $raw -Names @('LastMfaRegistrationDateTime','MfaRegisteredOn') -Default $null
        LastSuccessfulSignInDateTime = Get-HybridObjectValue -InputObject $raw -Names @('LastSuccessfulSignInDateTime','LastSignInDateTime','LastSignIn') -Default $null
        PasswordLastChangedDateTime = Get-HybridObjectValue -InputObject $raw -Names @('PasswordLastChangedDateTime','PasswordLastChanged','LastPasswordChange') -Default $null
        Source = [string](Get-HybridObjectValue -InputObject $raw -Names @('Source') -Default 'MicrosoftGraph')
        RetrievedOn = [datetime]::UtcNow
    }
    $authProfile.PSObject.TypeNames.Insert(0, 'Hybrid.AuthenticationProfile.Milestone7Phase6')
    return $authProfile
}
#endregion
Export-ModuleMember -Function @(
    'Initialize-HybridUserService',
    'Search-HybridUser',
    'Get-HybridUser',
    'Get-HybridUserDetails',
    'Get-HybridUserMailboxDetails',
    'Get-HybridUserGraphProfile',
    
    'Get-HybridUserAuthenticationProfile',
    'Get-HybridUserServiceHealth',
    'Clear-HybridUserService'
)





