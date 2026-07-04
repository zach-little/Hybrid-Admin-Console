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
        [AllowNull()][Nullable[datetime]]$LastSignInDateTime = $null,
        [AllowNull()][Nullable[datetime]]$LastNonInteractiveSignInDateTime = $null,
        [AllowNull()][Nullable[datetime]]$PasswordLastChangedDateTime = $null,
        [string[]]$AuthenticationMethods = @(),
        [object[]]$AuthenticationMethodDetails = @(),
        [object[]]$Licenses = @(),
        [object[]]$AssignedLicenses = @(),
        [object[]]$LicenseAssignmentStates = @(),
        [object[]]$PimRoles = @(),
        [object[]]$DirectoryRoles = @(),
        [object[]]$GraphDiagnostics = @(),
        [string]$LicenseDiagnostic = '',
        [string]$PimRoleDiagnostic = '',
        [bool]$MfaRegistered = $false,
        [bool]$MfaCapable = $false,
        [string]$RiskState = 'none',
        [string]$UserRiskState = '',
        [string]$SignInRiskState = '',
        [object[]]$RiskDetails = @(),
        [string]$Source = 'MicrosoftGraph',
        [hashtable]$Attributes = @{}
    )

    if ($AssignedLicenses.Count -eq 0) { $AssignedLicenses = @($Licenses) }
    if ($DirectoryRoles.Count -eq 0) { $DirectoryRoles = @($PimRoles) }
    if ([string]::IsNullOrWhiteSpace($UserRiskState)) { $UserRiskState = $RiskState }
    if ([string]::IsNullOrWhiteSpace($SignInRiskState)) { $SignInRiskState = $RiskState }

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
        AuthenticationMethodDetails = @($AuthenticationMethodDetails)
        Licenses = @($Licenses)
        AssignedLicenses = @($AssignedLicenses)
        LicenseAssignmentStates = @($LicenseAssignmentStates)
        PimRoles = @($PimRoles)
        DirectoryRoles = @($DirectoryRoles)
        GraphDiagnostics = @($GraphDiagnostics)
        LicenseDiagnostic = $LicenseDiagnostic
        LicenseDiagnostics = $LicenseDiagnostic
        PimRoleDiagnostic = $PimRoleDiagnostic
        PimRoleDiagnostics = $PimRoleDiagnostic
        PimDiagnostics = $PimRoleDiagnostic
        MfaRegistered = [bool]$MfaRegistered
        MfaCapable = [bool]$MfaCapable
        RiskState = $RiskState
        UserRiskState = $UserRiskState
        SignInRiskState = $SignInRiskState
        RiskDetails = @($RiskDetails)
        Source = $Source
        RetrievedOn = [datetime]::UtcNow
        Attributes = $Attributes
    }

    $profile.PSObject.TypeNames.Insert(0, 'Hybrid.GraphProfile.Milestone7Phase5')
    return $profile
}

Export-ModuleMember -Function @('New-HybridGraphProfile')
