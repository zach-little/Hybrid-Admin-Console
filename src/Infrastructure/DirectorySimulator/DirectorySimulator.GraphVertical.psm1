#region Module Information
# Name: DirectorySimulator.GraphVertical
# Purpose: Deterministic Microsoft Graph profile data for the Directory Simulator.
#endregion

Set-StrictMode -Version Latest

$script:HybridDirectorySimulatorGraphProfiles = @{}

function New-HybridDirectorySimulatorGraphProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SamAccountName,
        [Parameter(Mandatory=$true)][string]$DisplayName,
        [Parameter(Mandatory=$true)][string]$UserPrincipalName,
        [string]$UserType = 'Member',
        [string]$PreferredLanguage = 'en-US',
        [string]$UsageLocation = 'US',
        [string[]]$AuthenticationMethods = @('password'),
        [bool]$MfaRegistered = $false,
        [bool]$MfaCapable = $false,
        [string]$RiskState = 'none',
        [int]$SignInDaysAgo = 1,
        [int]$PasswordDaysAgo = 45
    )

    $objectId = [guid]::NewGuid().ToString()
    [pscustomobject]@{
        PSTypeName = 'Hybrid.DirectorySimulator.GraphProfile'
        ObjectId = $objectId
        Id = $objectId
        SamAccountName = $SamAccountName
        DisplayName = $DisplayName
        UserPrincipalName = $UserPrincipalName
        UserType = $UserType
        PreferredLanguage = $PreferredLanguage
        UsageLocation = $UsageLocation
        LastSignInDateTime = ([datetime]::UtcNow.Date.AddDays(-1 * $SignInDaysAgo).AddHours(13))
        LastNonInteractiveSignInDateTime = ([datetime]::UtcNow.Date.AddDays(-1 * ($SignInDaysAgo + 1)).AddHours(4))
        PasswordLastChangedDateTime = ([datetime]::UtcNow.Date.AddDays(-1 * $PasswordDaysAgo).AddHours(9))
        AuthenticationMethods = @($AuthenticationMethods)
        MfaRegistered = [bool]$MfaRegistered
        MfaCapable = [bool]$MfaCapable
        RiskState = $RiskState
        Source = 'DirectorySimulator'
    }
}

function Initialize-HybridDirectorySimulatorGraphVertical {
    [CmdletBinding()]
    param()

    $profiles = @(
        New-HybridDirectorySimulatorGraphProfile -SamAccountName 'amorgan' -DisplayName 'Alex Morgan' -UserPrincipalName 'amorgan@atlas-tech.com' -AuthenticationMethods @('password','microsoftAuthenticatorPush','softwareOath') -MfaRegistered:$true -MfaCapable:$true -RiskState 'none' -SignInDaysAgo 1 -PasswordDaysAgo 34
        New-HybridDirectorySimulatorGraphProfile -SamAccountName 'jlee' -DisplayName 'Jordan Lee' -UserPrincipalName 'jlee@atlas-tech.com' -AuthenticationMethods @('password','sms') -MfaRegistered:$true -MfaCapable:$true -RiskState 'none' -SignInDaysAgo 2 -PasswordDaysAgo 52
        New-HybridDirectorySimulatorGraphProfile -SamAccountName 'tsmith' -DisplayName 'Taylor Smith' -UserPrincipalName 'tsmith@atlas-tech.com' -AuthenticationMethods @('password','fido2') -MfaRegistered:$true -MfaCapable:$true -RiskState 'none' -SignInDaysAgo 4 -PasswordDaysAgo 18
        New-HybridDirectorySimulatorGraphProfile -SamAccountName 'mrivera' -DisplayName 'Morgan Rivera' -UserPrincipalName 'mrivera@atlas-tech.com' -AuthenticationMethods @('password','microsoftAuthenticatorPush','fido2') -MfaRegistered:$true -MfaCapable:$true -RiskState 'none' -SignInDaysAgo 1 -PasswordDaysAgo 27
        New-HybridDirectorySimulatorGraphProfile -SamAccountName 'dsample' -DisplayName 'Disabled Sample' -UserPrincipalName 'dsample@atlas-tech.com' -AuthenticationMethods @('password') -MfaRegistered:$false -MfaCapable:$false -RiskState 'dismissed' -SignInDaysAgo 120 -PasswordDaysAgo 180
    )

    $script:HybridDirectorySimulatorGraphProfiles.Clear()
    foreach ($profile in $profiles) {
        $script:HybridDirectorySimulatorGraphProfiles[$profile.SamAccountName.ToLowerInvariant()] = $profile
        $script:HybridDirectorySimulatorGraphProfiles[$profile.UserPrincipalName.ToLowerInvariant()] = $profile
        $script:HybridDirectorySimulatorGraphProfiles[$profile.DisplayName.ToLowerInvariant()] = $profile
    }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.DirectorySimulator.GraphVertical'
        Initialized = $true
        Count = $profiles.Count
        GetGraphProfile = ({ param([string]$Identity) Get-HybridDirectorySimulatorGraphProfile -Identity $Identity }).GetNewClosure()
        GetUserGraphProfile = ({ param([string]$Identity) Get-HybridDirectorySimulatorGraphProfile -Identity $Identity }).GetNewClosure()
    }
}

function Get-HybridDirectorySimulatorGraphProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if ($script:HybridDirectorySimulatorGraphProfiles.Count -eq 0) { Initialize-HybridDirectorySimulatorGraphVertical | Out-Null }

    $key = $Identity.ToLowerInvariant()
    if ($script:HybridDirectorySimulatorGraphProfiles.ContainsKey($key)) { return $script:HybridDirectorySimulatorGraphProfiles[$key] }

    return $null
}

Export-ModuleMember -Function @(
    'Initialize-HybridDirectorySimulatorGraphVertical',
    'Get-HybridDirectorySimulatorGraphProfile'
)
