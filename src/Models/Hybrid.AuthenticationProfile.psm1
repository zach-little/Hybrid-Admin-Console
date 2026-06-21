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
        [bool]$MfaRegistered = $false,
        [bool]$MfaCapable = $false,
        [bool]$PasswordlessRegistered = $false,
        [bool]$TemporaryAccessPassEligible = $false,
        [string]$AuthenticationStrength = 'Single-factor',
        [string]$ConditionalAccessState = 'Not evaluated',
        [string]$SignInRiskState = 'none',
        [AllowNull()][datetime]$LastMfaRegistrationDateTime = $null,
        [AllowNull()][datetime]$LastSuccessfulSignInDateTime = $null,
        [AllowNull()][datetime]$PasswordLastChangedDateTime = $null,
        [string]$Source = 'MicrosoftGraph',
        [hashtable]$Attributes = @{}
    )

    $profile = [pscustomobject]@{
        PSTypeName = 'Hybrid.AuthenticationProfile'
        UserPrincipalName = $UserPrincipalName
        DisplayName = $DisplayName
        DefaultMethod = $DefaultMethod
        AuthenticationMethods = @($AuthenticationMethods)
        MfaRegistered = [bool]$MfaRegistered
        MfaCapable = [bool]$MfaCapable
        PasswordlessRegistered = [bool]$PasswordlessRegistered
        TemporaryAccessPassEligible = [bool]$TemporaryAccessPassEligible
        AuthenticationStrength = $AuthenticationStrength
        ConditionalAccessState = $ConditionalAccessState
        SignInRiskState = $SignInRiskState
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
