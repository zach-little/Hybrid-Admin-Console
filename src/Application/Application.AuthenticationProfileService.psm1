#region Module Information
# Name: Application.AuthenticationProfileService
# Purpose: Service-layer vertical for user authentication posture.
# Exports: Initialize-HybridAuthenticationProfileService, Get-HybridAuthenticationProfile, Clear-HybridAuthenticationProfileService
#endregion

Set-StrictMode -Version Latest

$script:AuthenticationProfileServiceState = @{
    Initialized = $false
    MicrosoftGraph = $null
    Cache = @{}
    LastError = $null
}

function Get-HybridAuthenticationObjectValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory=$true)][string[]]$Names,
        [AllowNull()][object]$Default = $null
    )

    foreach ($name in $Names) {
        if ($null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains $name) {
            $value = $InputObject.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return $value }
        }
    }
    return $Default
}

function Invoke-HybridAuthenticationProviderOperation {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Provider,
        [Parameter(Mandatory=$true)][string[]]$OperationNames,
        [object[]]$Arguments = @()
    )

    if ($null -eq $Provider) { return @() }

    foreach ($operationName in $OperationNames) {
        if ($Provider.PSObject.Properties.Name -contains $operationName) {
            $operation = $Provider.$operationName
            if ($operation -is [scriptblock]) { return @(& $operation @Arguments) }
            if ($null -ne $operation -and $operation.PSObject.Methods.Name -contains 'Invoke') { return @($operation.Invoke($Arguments)) }
        }
    }

    return @()
}

function ConvertTo-HybridAuthenticationProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$InputObject,
        [Parameter(Mandatory=$true)][string]$Identity
    )

    if ($InputObject.PSObject.TypeNames -contains 'Hybrid.AuthenticationProfile') { return $InputObject }

    $methods = @(Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('AuthenticationMethods','Methods') -Default @())
    $defaultMethod = [string](Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('DefaultMethod','DefaultAuthenticationMethod') -Default '')
    if ([string]::IsNullOrWhiteSpace($defaultMethod)) {
        $defaultMethod = if ($methods.Count -gt 0) { [string]$methods[0] } else { 'password' }
    }

    $profile = [pscustomobject]@{
        PSTypeName = 'Hybrid.AuthenticationProfile'
        UserPrincipalName = [string](Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('UserPrincipalName','UPN') -Default $Identity)
        DisplayName = [string](Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('DisplayName','Name') -Default $Identity)
        DefaultMethod = $defaultMethod
        AuthenticationMethods = @($methods)
        MfaRegistered = [bool](Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('MfaRegistered','MfaEnabled','IsMfaRegistered') -Default $false)
        MfaCapable = [bool](Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('MfaCapable','IsMfaCapable') -Default $false)
        PasswordlessRegistered = [bool](Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('PasswordlessRegistered','IsPasswordlessRegistered') -Default $false)
        TemporaryAccessPassEligible = [bool](Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('TemporaryAccessPassEligible','TapEligible') -Default $false)
        AuthenticationStrength = [string](Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('AuthenticationStrength','StrongAuthenticationRequirement') -Default 'Single-factor')
        ConditionalAccessState = [string](Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('ConditionalAccessState','ConditionalAccess') -Default 'Not evaluated')
        SignInRiskState = [string](Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('SignInRiskState','RiskState','UserRiskState') -Default 'none')
        LastMfaRegistrationDateTime = Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('LastMfaRegistrationDateTime','MfaRegisteredOn') -Default $null
        LastSuccessfulSignInDateTime = Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('LastSuccessfulSignInDateTime','LastSignInDateTime','LastSignIn') -Default $null
        PasswordLastChangedDateTime = Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('PasswordLastChangedDateTime','PasswordLastChanged','LastPasswordChange') -Default $null
        Source = [string](Get-HybridAuthenticationObjectValue -InputObject $InputObject -Names @('Source') -Default 'MicrosoftGraph')
        RetrievedOn = [datetime]::UtcNow
        Attributes = @{}
    }
    $profile.PSObject.TypeNames.Insert(0, 'Hybrid.AuthenticationProfile.Milestone7Phase6')
    return $profile
}

function Initialize-HybridAuthenticationProfileService {
    [CmdletBinding()]
    param([AllowNull()][object]$MicrosoftGraphProvider)

    $script:AuthenticationProfileServiceState.MicrosoftGraph = $MicrosoftGraphProvider
    $script:AuthenticationProfileServiceState.Initialized = $true
    $script:AuthenticationProfileServiceState.Cache.Clear()

    [pscustomobject]@{
        PSTypeName = 'Hybrid.AuthenticationProfileService'
        Name = 'AuthenticationProfileService'
        Initialized = $true
        MicrosoftGraphProvider = ($null -ne $MicrosoftGraphProvider)
        GetAuthenticationProfile = ({ param([string]$Identity) Get-HybridAuthenticationProfile -Identity $Identity }).GetNewClosure()
    }
}

function Get-HybridAuthenticationProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not $script:AuthenticationProfileServiceState.Initialized) { throw 'Hybrid authentication profile service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'Authentication profile identity cannot be empty.' }

    $cacheKey = $Identity.ToLowerInvariant()
    if ($script:AuthenticationProfileServiceState.Cache.ContainsKey($cacheKey)) { return $script:AuthenticationProfileServiceState.Cache[$cacheKey] }

    try {
        $profile = @(Invoke-HybridAuthenticationProviderOperation `
            -Provider $script:AuthenticationProfileServiceState.MicrosoftGraph `
            -OperationNames @('GetAuthenticationProfile','GetUserAuthenticationProfile','GetGraphAuthenticationProfile','GetGraphProfile','GetUserGraphProfile') `
            -Arguments @($Identity) | Select-Object -First 1)

        if ($profile.Count -eq 0 -or $null -eq $profile[0]) { return $null }

        $converted = ConvertTo-HybridAuthenticationProfile -InputObject $profile[0] -Identity $Identity
        $script:AuthenticationProfileServiceState.Cache[$cacheKey] = $converted
        return $converted
    } catch {
        $script:AuthenticationProfileServiceState.LastError = $_.Exception.Message
        throw
    }
}

function Clear-HybridAuthenticationProfileService {
    [CmdletBinding()]
    param()

    $script:AuthenticationProfileServiceState.Initialized = $false
    $script:AuthenticationProfileServiceState.MicrosoftGraph = $null
    $script:AuthenticationProfileServiceState.Cache.Clear()
    $script:AuthenticationProfileServiceState.LastError = $null
    return $true
}

Export-ModuleMember -Function @(
    'Initialize-HybridAuthenticationProfileService',
    'Get-HybridAuthenticationProfile',
    'Clear-HybridAuthenticationProfileService'
)
