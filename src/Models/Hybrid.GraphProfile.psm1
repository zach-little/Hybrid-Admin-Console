#region Module Information
# Name: Hybrid.GraphProfile
# Purpose: Canonical Microsoft Graph profile domain model for Milestone 7 Phase 5.
#endregion

Set-StrictMode -Version Latest

function New-HybridGraphProfile {
    [CmdletBinding()]
    param(
        [string]$ObjectId,
        [string]$UserPrincipalName,
        [string]$DisplayName,
        [string]$UserType = 'Member',
        [string]$PreferredLanguage = 'en-US',
        [string]$UsageLocation = 'US',
        [AllowNull()][datetime]$LastSignInDateTime = $null,
        [AllowNull()][datetime]$LastNonInteractiveSignInDateTime = $null,
        [AllowNull()][datetime]$PasswordLastChangedDateTime = $null,
        [string[]]$AuthenticationMethods = @(),
        [object[]]$Licenses = @(),
        [object[]]$PimRoles = @(),
        [bool]$MfaRegistered = $false,
        [bool]$MfaCapable = $false,
        [string]$RiskState = 'none',
        [string]$Source = 'MicrosoftGraph',
        [hashtable]$Attributes = @{}
    )

    $profile = [pscustomobject]@{
        PSTypeName = 'Hybrid.GraphProfile'
        ObjectId = $ObjectId
        UserPrincipalName = $UserPrincipalName
        DisplayName = $DisplayName
        UserType = $UserType
        PreferredLanguage = $PreferredLanguage
        UsageLocation = $UsageLocation
        LastSignInDateTime = $LastSignInDateTime
        LastNonInteractiveSignInDateTime = $LastNonInteractiveSignInDateTime
        PasswordLastChangedDateTime = $PasswordLastChangedDateTime
        AuthenticationMethods = @($AuthenticationMethods)
        Licenses = @($Licenses)
        AssignedLicenses = @($Licenses)
        PimRoles = @($PimRoles)
        MfaRegistered = [bool]$MfaRegistered
        MfaCapable = [bool]$MfaCapable
        RiskState = $RiskState
        Source = $Source
        RetrievedOn = [datetime]::UtcNow
        Attributes = $Attributes
    }

    $profile.PSObject.TypeNames.Insert(0, 'Hybrid.GraphProfile.Milestone7Phase5')
    return $profile
}

Export-ModuleMember -Function @('New-HybridGraphProfile')
