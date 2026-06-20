#region Module Information
# Name: Hybrid.Models
# Purpose: Canonical domain model factory functions for Hybrid Administration Platform.
# Dependencies: None
# Exports: New-HybridResult, New-HybridUser, New-HybridGroup, New-HybridMailbox, New-HybridDevice, New-HybridLicense, New-HybridWorkflow, ConvertTo-HybridResult
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

    # PowerShell 5.1 can be inconsistent when relying on a PSTypeName
    # hashtable key during module-to-module returns. Insert the type name
    # explicitly so tests, format views, and future UI bindings can rely on it.
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
    Read operations may return domain models directly, but any action that can
    partially fail should return this model so the UI has a consistent way to
    display success, warnings, errors, and metadata.
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
        PSTypeName     = 'Hybrid.Result'
        Success        = $Success
        Message        = $Message
        Data           = $Data
        Warnings       = @(ConvertTo-HybridArray $Warnings)
        Errors         = @(ConvertTo-HybridArray $Errors)
        Metadata       = $Metadata
        CorrelationId  = $CorrelationId
        CreatedUtc     = New-HybridTimestamp
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
        [bool]$Enabled = $true,
        [bool]$LockedOut = $false,
        [string]$Source = 'Unknown',
        [object[]]$Groups = @(),
        [object]$Mailbox = $null,
        [object[]]$Devices = @(),
        [object[]]$Licenses = @(),
        [hashtable]$Attributes = @{}
    )

    $model = [pscustomobject]@{
        PSTypeName            = 'Hybrid.User'
        Id                    = $Id
        DisplayName           = $DisplayName
        GivenName             = $GivenName
        Surname               = $Surname
        SamAccountName        = $SamAccountName
        UserPrincipalName     = $UserPrincipalName
        Mail                  = $Mail
        EmployeeId            = $EmployeeId
        BadgeId               = $BadgeId
        Department            = $Department
        Title                 = $Title
        Company               = $Company
        Office                = $Office
        Manager               = $Manager
        ManagerSamAccountName = $ManagerSamAccountName
        Enabled               = $Enabled
        LockedOut             = $LockedOut
        Source                = $Source
        Groups                = @(ConvertTo-HybridArray $Groups)
        Mailbox               = $Mailbox
        Devices               = @(ConvertTo-HybridArray $Devices)
        Licenses              = @(ConvertTo-HybridArray $Licenses)
        Attributes            = $Attributes
        CreatedUtc            = New-HybridTimestamp
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
        PSTypeName       = 'Hybrid.Device'
        Id               = $Id
        Name             = $Name
        OperatingSystem  = $OperatingSystem
        ComplianceState  = $ComplianceState
        PrimaryUser      = $PrimaryUser
        LastCheckInUtc   = $LastCheckInUtc
        Source           = $Source
        Attributes       = $Attributes
        CreatedUtc       = New-HybridTimestamp
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
    'New-HybridWorkflow'
)
#endregion
