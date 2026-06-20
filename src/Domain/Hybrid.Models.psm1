#region Module Information
# Name: Hybrid.Models
# Purpose: Canonical domain model factory functions for Hybrid Administration Platform.
# Dependencies: None
# Exports: New-HybridResult, New-HybridUser, New-HybridGroup, New-HybridMailbox, New-HybridDevice, New-HybridLicense, New-HybridUserOverview, New-HybridWorkflow, ConvertTo-HybridResult
#endregion

Set-StrictMode -Version Latest

#region Private
function New-HybridTimestamp {
    return [datetime]::UtcNow
}

function ConvertTo-HybridArray {
    param([object]$Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [array]) { return @($Value) }
    return @($Value)
}

function Set-HybridTypeName {
    param(
        [Parameter(Mandatory=$true)][object]$InputObject,
        [Parameter(Mandatory=$true)][string]$TypeName
    )

    if ($InputObject.PSObject.TypeNames[0] -ne $TypeName) {
        $InputObject.PSObject.TypeNames.Insert(0, $TypeName)
    }

    return $InputObject
}
#endregion

#region Public
function New-HybridResult {
    <#
    .SYNOPSIS
    Creates a standard operation result object.

    .DESCRIPTION
    HybridResult is the standard return envelope for workflows and write actions.
    Read operations may return domain models directly, but any action that can partially fail should return this model so the UI has a consistent way to display success, warnings, errors, and metadata.
    #>
    [CmdletBinding()]
    param(
        [bool]$Success = $true,
        [string]$Message = '',
        [object]$Data = $null,
        [object[]]$Warnings = @(),
        [object[]]$Errors = @(),
        [hashtable]$Metadata = @{},
        [string]$CorrelationId = ([guid]::NewGuid().ToString())
    )

    $model = [pscustomobject]@{
        PSTypeName    = 'Hybrid.Result'
        Success       = $Success
        Message       = $Message
        Data          = $Data
        Warnings      = @(ConvertTo-HybridArray $Warnings)
        Errors        = @(ConvertTo-HybridArray $Errors)
        Metadata      = $Metadata
        CorrelationId = $CorrelationId
        CreatedUtc    = New-HybridTimestamp
    }

    return Set-HybridTypeName -InputObject $model -TypeName 'Hybrid.Result'
}

function ConvertTo-HybridResult {
    <#
    .SYNOPSIS
    Wraps arbitrary data in a HybridResult.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]$InputObject,
        [string]$Message = 'Operation completed.',
        [bool]$Success = $true
    )

    process {
        New-HybridResult -Success $Success -Message $Message -Data $InputObject
    }
}

function New-HybridUser {
    <#
    .SYNOPSIS
    Creates a canonical HybridUser model.
    #>
    [CmdletBinding()]
    param(
        [string]$Id = '',
        [string]$DisplayName = '',
        [string]$GivenName = '',
        [string]$Surname = '',
        [string]$SamAccountName = '',
        [string]$UserPrincipalName = '',
        [string]$Mail = '',
        [string]$EmployeeId = '',
        [string]$BadgeId = '',
        [string]$Department = '',
        [string]$Title = '',
        [string]$Company = '',
        [string]$Office = '',
        [string]$Manager = '',
        [string]$ManagerSamAccountName = '',
        [object]$ManagerUser = $null,
        [object[]]$DirectReports = @(),
        [bool]$Enabled = $true,
        [bool]$LockedOut = $false,
        [string]$Source = 'Unknown',
        [object[]]$Groups = @(),
        [object]$Mailbox = $null,
        [object[]]$Devices = @(),
        [object[]]$Licenses = @(),
        [hashtable]$Attributes = @{},
        [hashtable]$Hydration = @{}
    )

    $model = [pscustomobject]@{
        PSTypeName             = 'Hybrid.User'
        Id                     = $Id
        DisplayName            = $DisplayName
        GivenName              = $GivenName
        Surname                = $Surname
        SamAccountName         = $SamAccountName
        UserPrincipalName      = $UserPrincipalName
        Mail                   = $Mail
        EmployeeId             = $EmployeeId
        BadgeId                = $BadgeId
        Department             = $Department
        Title                  = $Title
        Company                = $Company
        Office                 = $Office
        Manager                = $Manager
        ManagerSamAccountName  = $ManagerSamAccountName
        ManagerUser            = $ManagerUser
        DirectReports          = @(ConvertTo-HybridArray $DirectReports)
        Enabled                = $Enabled
        LockedOut              = $LockedOut
        Source                 = $Source
        Groups                 = @(ConvertTo-HybridArray $Groups)
        Mailbox                = $Mailbox
        Devices                = @(ConvertTo-HybridArray $Devices)
        Licenses               = @(ConvertTo-HybridArray $Licenses)
        Hydration              = $Hydration
        Attributes             = $Attributes
        CreatedUtc             = New-HybridTimestamp
    }

    return Set-HybridTypeName -InputObject $model -TypeName 'Hybrid.User'
}

function New-HybridGroup {
    <#
    .SYNOPSIS
    Creates a canonical HybridGroup model.
    #>
    [CmdletBinding()]
    param(
        [string]$Id = '',
        [string]$Name = '',
        [string]$SamAccountName = '',
        [string]$Mail = '',
        [string]$Type = 'Security',
        [string]$Scope = 'Global',
        [bool]$IsDefault = $false,
        [bool]$IsNested = $false,
        [string]$Source = 'Unknown',
        [hashtable]$Attributes = @{}
    )

    $model = [pscustomobject]@{
        PSTypeName     = 'Hybrid.Group'
        Id             = $Id
        Name           = $Name
        SamAccountName = $SamAccountName
        Mail           = $Mail
        Type           = $Type
        Scope          = $Scope
        IsDefault      = $IsDefault
        IsNested       = $IsNested
        Source         = $Source
        Attributes     = $Attributes
        CreatedUtc     = New-HybridTimestamp
    }

    return Set-HybridTypeName -InputObject $model -TypeName 'Hybrid.Group'
}

function New-HybridMailbox {
    <#
    .SYNOPSIS
    Creates a canonical HybridMailbox model.
    #>
    [CmdletBinding()]
    param(
        [string]$Identity = '',
        [string]$PrimarySmtpAddress = '',
        [string]$RecipientType = 'UserMailbox',
        [bool]$Exists = $true,
        [bool]$HiddenFromAddressLists = $false,
        [string]$ForwardingAddress = '',
        [bool]$DeliverToMailboxAndForward = $false,
        [object[]]$Aliases = @(),
        [object[]]$FullAccess = @(),
        [object[]]$SendAs = @(),
        [object[]]$SendOnBehalf = @(),
        [string]$Source = 'Unknown',
        [hashtable]$Attributes = @{}
    )

    $model = [pscustomobject]@{
        PSTypeName                 = 'Hybrid.Mailbox'
        Identity                   = $Identity
        PrimarySmtpAddress         = $PrimarySmtpAddress
        RecipientType              = $RecipientType
        Exists                     = $Exists
        HiddenFromAddressLists     = $HiddenFromAddressLists
        ForwardingAddress          = $ForwardingAddress
        DeliverToMailboxAndForward = $DeliverToMailboxAndForward
        Aliases                    = @(ConvertTo-HybridArray $Aliases)
        FullAccess                 = @(ConvertTo-HybridArray $FullAccess)
        SendAs                     = @(ConvertTo-HybridArray $SendAs)
        SendOnBehalf               = @(ConvertTo-HybridArray $SendOnBehalf)
        Source                     = $Source
        Attributes                 = $Attributes
        CreatedUtc                 = New-HybridTimestamp
    }

    return Set-HybridTypeName -InputObject $model -TypeName 'Hybrid.Mailbox'
}

function New-HybridDevice {
    <#
    .SYNOPSIS
    Creates a canonical HybridDevice model.
    #>
    [CmdletBinding()]
    param(
        [string]$Id = '',
        [string]$Name = '',
        [string]$OperatingSystem = '',
        [string]$ComplianceState = 'Unknown',
        [string]$PrimaryUser = '',
        [datetime]$LastCheckInUtc = ([datetime]::MinValue),
        [string]$Source = 'Unknown',
        [hashtable]$Attributes = @{}
    )

    $model = [pscustomobject]@{
        PSTypeName      = 'Hybrid.Device'
        Id              = $Id
        Name            = $Name
        OperatingSystem = $OperatingSystem
        ComplianceState = $ComplianceState
        PrimaryUser     = $PrimaryUser
        LastCheckInUtc  = $LastCheckInUtc
        Source          = $Source
        Attributes      = $Attributes
        CreatedUtc      = New-HybridTimestamp
    }

    return Set-HybridTypeName -InputObject $model -TypeName 'Hybrid.Device'
}

function New-HybridLicense {
    <#
    .SYNOPSIS
    Creates a canonical HybridLicense model.
    #>
    [CmdletBinding()]
    param(
        [string]$SkuId = '',
        [string]$SkuPartNumber = '',
        [string]$DisplayName = '',
        [string]$AssignmentSource = 'Direct',
        [string]$AssignedByGroup = '',
        [bool]$Enabled = $true,
        [string]$Source = 'Unknown',
        [hashtable]$Attributes = @{}
    )

    $model = [pscustomobject]@{
        PSTypeName       = 'Hybrid.License'
        SkuId            = $SkuId
        SkuPartNumber    = $SkuPartNumber
        DisplayName      = $DisplayName
        AssignmentSource = $AssignmentSource
        AssignedByGroup  = $AssignedByGroup
        Enabled          = $Enabled
        Source           = $Source
        Attributes       = $Attributes
        CreatedUtc       = New-HybridTimestamp
    }

    return Set-HybridTypeName -InputObject $model -TypeName 'Hybrid.License'
}

function New-HybridUserOverview {
    <#
    .SYNOPSIS
    Creates a card-ready overview model for a fully hydrated HybridUser.

    .DESCRIPTION
    The overview model gives the UI and future workflow cards a stable, provider-agnostic summary without embedding UI logic in the application or infrastructure layers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$User,
        [hashtable]$Metadata = @{}
    )

    $groups = @(ConvertTo-HybridArray $User.Groups)
    $devices = @(ConvertTo-HybridArray $User.Devices)
    $licenses = @(ConvertTo-HybridArray $User.Licenses)
    $mailbox = $User.Mailbox
    $directReports = @(ConvertTo-HybridArray $User.DirectReports)

    $enabledLicenses = @($licenses | Where-Object { $_.Enabled })
    $nonCompliantDevices = @($devices | Where-Object { $_.ComplianceState -and $_.ComplianceState -ne 'Compliant' -and $_.ComplianceState -ne 'Unknown' })

    $cards = @(
        [pscustomobject]@{ PSTypeName = 'Hybrid.UserOverviewCard'; Name = 'Identity'; Title = $User.DisplayName; Subtitle = $User.UserPrincipalName; Value = $User.SamAccountName; Status = if ($User.Enabled) { 'Enabled' } else { 'Disabled' } }
        [pscustomobject]@{ PSTypeName = 'Hybrid.UserOverviewCard'; Name = 'Manager'; Title = 'Manager'; Subtitle = $User.ManagerSamAccountName; Value = if ($null -ne $User.ManagerUser) { $User.ManagerUser.DisplayName } else { $User.Manager }; Status = if ($null -ne $User.ManagerUser -or -not [string]::IsNullOrWhiteSpace($User.Manager)) { 'Ready' } else { 'Warning' } }
        [pscustomobject]@{ PSTypeName = 'Hybrid.UserOverviewCard'; Name = 'DirectReports'; Title = 'Direct Reports'; Subtitle = 'Users managed by this account'; Value = $directReports.Count; Status = 'Ready' }
        [pscustomobject]@{ PSTypeName = 'Hybrid.UserOverviewCard'; Name = 'Groups'; Title = 'Groups'; Subtitle = 'Security and distribution memberships'; Value = $groups.Count; Status = 'Ready' }
        [pscustomobject]@{ PSTypeName = 'Hybrid.UserOverviewCard'; Name = 'Mailbox'; Title = 'Mailbox'; Subtitle = if ($null -ne $mailbox) { $mailbox.PrimarySmtpAddress } else { '' }; Value = if ($null -ne $mailbox -and $mailbox.Exists) { 'Present' } else { 'Missing' }; Status = if ($null -ne $mailbox -and $mailbox.Exists) { 'Ready' } else { 'Warning' } }
        [pscustomobject]@{ PSTypeName = 'Hybrid.UserOverviewCard'; Name = 'Devices'; Title = 'Devices'; Subtitle = 'Associated managed devices'; Value = $devices.Count; Status = if ($nonCompliantDevices.Count -gt 0) { 'Warning' } else { 'Ready' } }
        [pscustomobject]@{ PSTypeName = 'Hybrid.UserOverviewCard'; Name = 'Licenses'; Title = 'Licenses'; Subtitle = 'Enabled assignments'; Value = $enabledLicenses.Count; Status = 'Ready' }
    )

    foreach ($card in $cards) {
        if ($card.PSObject.TypeNames[0] -ne 'Hybrid.UserOverviewCard') {
            $card.PSObject.TypeNames.Insert(0, 'Hybrid.UserOverviewCard')
        }
    }

    $model = [pscustomobject]@{
        PSTypeName              = 'Hybrid.UserOverview'
        User                    = $User
        DisplayName             = $User.DisplayName
        SamAccountName          = $User.SamAccountName
        UserPrincipalName       = $User.UserPrincipalName
        Mail                    = $User.Mail
        Department              = $User.Department
        Title                   = $User.Title
        Manager                 = $User.Manager
        ManagerSamAccountName  = $User.ManagerSamAccountName
        DirectReportCount      = $directReports.Count
        Enabled                 = $User.Enabled
        LockedOut               = $User.LockedOut
        GroupCount              = $groups.Count
        DeviceCount             = $devices.Count
        LicenseCount            = $licenses.Count
        EnabledLicenseCount     = $enabledLicenses.Count
        HasMailbox              = ($null -ne $mailbox -and $mailbox.Exists)
        NonCompliantDeviceCount = $nonCompliantDevices.Count
        Cards                   = @($cards)
        Metadata                = $Metadata
        CreatedUtc              = New-HybridTimestamp
    }

    return Set-HybridTypeName -InputObject $model -TypeName 'Hybrid.UserOverview'
}

function New-HybridWorkflow {
    <#
    .SYNOPSIS
    Creates a canonical HybridWorkflow model.
    #>
    [CmdletBinding()]
    param(
        [string]$Name = '',
        [string]$DisplayName = '',
        [string]$Description = '',
        [string]$Category = 'General',
        [string[]]$RequiredServices = @(),
        [scriptblock]$Execute = $null,
        [hashtable]$Metadata = @{}
    )

    $model = [pscustomobject]@{
        PSTypeName        = 'Hybrid.Workflow'
        Name              = $Name
        DisplayName       = $DisplayName
        Description       = $Description
        Category          = $Category
        RequiredServices  = @($RequiredServices)
        Execute           = $Execute
        Metadata          = $Metadata
        CreatedUtc        = New-HybridTimestamp
    }

    return Set-HybridTypeName -InputObject $model -TypeName 'Hybrid.Workflow'
}
#endregion

#region Initialization
Export-ModuleMember -Function @(
    'New-HybridResult',
    'ConvertTo-HybridResult',
    'New-HybridUser',
    'New-HybridGroup',
    'New-HybridMailbox',
    'New-HybridDevice',
    'New-HybridLicense',
    'New-HybridUserOverview',
    'New-HybridWorkflow'
)
#endregion
