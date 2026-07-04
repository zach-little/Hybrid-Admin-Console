#region Module Information
# Name: Hybrid.AuthenticationProfile
# Purpose: Canonical authentication posture domain model for Milestone 7 Phase 6.
#endregion

Set-StrictMode -Version Latest

function New-HybridAuthenticationProfile {
    [CmdletBinding()]
    param(
        [string]$UserPrincipalName,
        [string]$DisplayName,
        [string]$DefaultMethod = 'password',
        [string[]]$AuthenticationMethods = @(),
        [object[]]$AuthenticationMethodDetails = @(),
        [bool]$MfaRegistered = $false,
        [bool]$MfaCapable = $false,
        [bool]$PasswordlessRegistered = $false,
        [bool]$TemporaryAccessPassEligible = $false,
        [string]$AuthenticationStrength = 'Single-factor',
        [string]$ConditionalAccessState = 'Not evaluated',
        [object[]]$ConditionalAccessDetails = @(),
        [string]$SignInRiskState = 'none',
        [string]$UserRiskState = '',
        [string]$RiskLevel = '',
        [object[]]$RiskDetails = @(),
        [AllowNull()][Nullable[datetime]]$LastMfaRegistrationDateTime = $null,
        [AllowNull()][Nullable[datetime]]$LastSuccessfulSignInDateTime = $null,
        [AllowNull()][Nullable[datetime]]$PasswordLastChangedDateTime = $null,
        [string]$Source = 'MicrosoftGraph',
        [hashtable]$Attributes = @{}
    )

    if ([string]::IsNullOrWhiteSpace($UserRiskState)) { $UserRiskState = $SignInRiskState }
    if ([string]::IsNullOrWhiteSpace($RiskLevel)) { $RiskLevel = $SignInRiskState }

    $profile = [pscustomobject]@{
        PSTypeName = 'Hybrid.AuthenticationProfile'
        UserPrincipalName = $UserPrincipalName
        DisplayName = $DisplayName
        DefaultMethod = $DefaultMethod
        AuthenticationMethods = @($AuthenticationMethods)
        AuthenticationMethodDetails = @($AuthenticationMethodDetails)
        MfaRegistered = [bool]$MfaRegistered
        MfaCapable = [bool]$MfaCapable
        PasswordlessRegistered = [bool]$PasswordlessRegistered
        TemporaryAccessPassEligible = [bool]$TemporaryAccessPassEligible
        AuthenticationStrength = $AuthenticationStrength
        ConditionalAccessState = $ConditionalAccessState
        ConditionalAccessDetails = @($ConditionalAccessDetails)
        SignInRiskState = $SignInRiskState
        UserRiskState = $UserRiskState
        RiskLevel = $RiskLevel
        RiskDetails = @($RiskDetails)
        LastMfaRegistrationDateTime = $LastMfaRegistrationDateTime
        LastSuccessfulSignInDateTime = $LastSuccessfulSignInDateTime
        PasswordLastChangedDateTime = $PasswordLastChangedDateTime
        Source = $Source
        RetrievedOn = [datetime]::UtcNow
        Attributes = $Attributes
    }

    $profile.PSObject.TypeNames.Insert(0, 'Hybrid.AuthenticationProfile.Milestone7Phase6')
    return $profile
}

Export-ModuleMember -Function @('New-HybridAuthenticationProfile')
