#region Module Information
# Name: DirectorySimulator.AuthenticationVertical
# Purpose: Deterministic authentication posture vertical data for Milestone 7 Phase 6.
#endregion

Set-StrictMode -Version Latest

function Resolve-HybridAuthenticationProfileSeed {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $clean = $Identity.Trim().ToLowerInvariant()
    if ($clean -like '*@*') { $clean = ($clean -split '@')[0] }
    $clean = $clean -replace '[^a-z0-9]',''
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = 'sampleuser' }
    return $clean
}

function New-HybridDirectorySimulatorAuthenticationProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $seed = Resolve-HybridAuthenticationProfileSeed -Identity $Identity
    $hash = [Math]::Abs($seed.GetHashCode())
    $upn = if ($Identity -like '*@*') { $Identity.ToLowerInvariant() } else { "$seed@atlas-tech.com" }
    $displayName = switch -Regex ($seed) {
        'amorgan|alex' { 'Alex Morgan'; break }
        'treed|taylor' { 'Taylor Reed'; break }
        'jlee|jordan' { 'Jordan Lee'; break }
        default { (Get-Culture).TextInfo.ToTitleCase(($seed -replace '[^a-z]',' ')).Trim(); break }
    }
    if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = $upn }

    $methodSets = @(
        @('password','microsoftAuthenticatorPush','fido2SecurityKey'),
        @('password','microsoftAuthenticatorPush','softwareOath'),
        @('password','sms','voiceMobile'),
        @('password')
    )
    $methods = @($methodSets[$hash % $methodSets.Count])
    $hasStrongMethod = @($methods | Where-Object { $_ -ne 'password' -and $_ -ne 'sms' -and $_ -ne 'voiceMobile' }).Count -gt 0
    $mfaRegistered = @($methods | Where-Object { $_ -ne 'password' }).Count -gt 0
    $passwordless = @($methods | Where-Object { $_ -in @('fido2SecurityKey','windowsHelloForBusiness','temporaryAccessPass') }).Count -gt 0

    [pscustomobject]@{
        PSTypeName = 'Hybrid.AuthenticationProfile'
        UserPrincipalName = $upn
        DisplayName = $displayName
        DefaultMethod = if ($methods.Count -gt 1) { [string]$methods[1] } else { 'password' }
        AuthenticationMethods = @($methods)
        MfaRegistered = [bool]$mfaRegistered
        MfaCapable = [bool]$mfaRegistered
        PasswordlessRegistered = [bool]$passwordless
        TemporaryAccessPassEligible = [bool]($hash % 3 -ne 0)
        AuthenticationStrength = if ($hasStrongMethod) { 'Phishing-resistant capable' } elseif ($mfaRegistered) { 'Multifactor capable' } else { 'Single-factor only' }
        ConditionalAccessState = if ($mfaRegistered) { 'Satisfied' } else { 'Requires registration' }
        SignInRiskState = @('none','low','none','none','medium')[$hash % 5]
        LastMfaRegistrationDateTime = if ($mfaRegistered) { (Get-Date).Date.AddDays(-1 * (($hash % 120) + 3)) } else { $null }
        LastSuccessfulSignInDateTime = (Get-Date).AddHours(-1 * (($hash % 72) + 1))
        PasswordLastChangedDateTime = (Get-Date).Date.AddDays(-1 * (($hash % 90) + 10))
        Source = 'DirectorySimulator.MicrosoftGraph.Authentication'
        RetrievedOn = [datetime]::UtcNow
        Attributes = @{ Seed = $seed; Deterministic = $true }
    }
}

function Initialize-HybridDirectorySimulatorAuthenticationVertical {
    [CmdletBinding()]
    param([AllowNull()][object]$Provider)

    if ($null -eq $Provider) { return $null }

    if ($Provider.PSObject.Properties.Name -notcontains 'GetAuthenticationProfile') {
        Add-Member -InputObject $Provider -MemberType NoteProperty -Name GetAuthenticationProfile -Value ({ param([string]$Identity) New-HybridDirectorySimulatorAuthenticationProfile -Identity $Identity }).GetNewClosure() -Force
    }
    if ($Provider.PSObject.Properties.Name -notcontains 'GetUserAuthenticationProfile') {
        Add-Member -InputObject $Provider -MemberType NoteProperty -Name GetUserAuthenticationProfile -Value ({ param([string]$Identity) New-HybridDirectorySimulatorAuthenticationProfile -Identity $Identity }).GetNewClosure() -Force
    }
    return $Provider
}

Export-ModuleMember -Function @(
    'New-HybridDirectorySimulatorAuthenticationProfile',
    'Initialize-HybridDirectorySimulatorAuthenticationVertical'
)
