#region Module Information
# Name: Application.GraphProfileService
# Purpose: Service-layer vertical for Microsoft Graph profile details.
# Exports: Initialize-HybridGraphProfileService, Get-HybridGraphProfile, Clear-HybridGraphProfileService
#endregion

Set-StrictMode -Version Latest

$script:GraphProfileServiceState = @{
    Initialized = $false
    MicrosoftGraph = $null
    Cache = @{}
    LastError = $null
}

function Get-HybridGraphObjectValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory=$true)][string[]]$Names,
        [AllowNull()][object]$Default = $null
    )

    foreach ($name in $Names) {
        if ($null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains $name) {
            $value = $InputObject.$name
            if ($null -eq $value) { continue }
            if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { continue }
            if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                if (@($value).Count -eq 0) { continue }
                return $value
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) { return $value }
        }
    }
    return $Default
}

function Invoke-HybridGraphProviderOperation {
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

function ConvertTo-HybridGraphProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$InputObject,
        [Parameter(Mandatory=$true)][string]$Identity
    )

    if ($InputObject.PSObject.TypeNames -contains 'Hybrid.GraphProfile') { return $InputObject }

    $methods = @(Get-HybridGraphObjectValue -InputObject $InputObject -Names @('AuthenticationMethods','Methods') -Default @())
    $methodDetails = @(Get-HybridGraphObjectValue -InputObject $InputObject -Names @('AuthenticationMethodDetails','AuthMethodDetails','MethodDetails') -Default @())
    $licenses = @(Get-HybridGraphObjectValue -InputObject $InputObject -Names @('Licenses','licenses') -Default @())
    $assignedLicenses = @(Get-HybridGraphObjectValue -InputObject $InputObject -Names @('AssignedLicenses','assignedLicenses') -Default @())
    if ($licenses.Count -eq 0 -and $assignedLicenses.Count -gt 0) { $licenses = @($assignedLicenses) }
    if ($assignedLicenses.Count -eq 0 -and $licenses.Count -gt 0) { $assignedLicenses = @($licenses) }
    $licenseAssignmentStates = @(Get-HybridGraphObjectValue -InputObject $InputObject -Names @('LicenseAssignmentStates','licenseAssignmentStates') -Default @())
    $pimRoles = @(Get-HybridGraphObjectValue -InputObject $InputObject -Names @('PimRoles','PIMRoles','PrivilegedIdentityRoles','DirectoryRoles','AzureRoles') -Default @())
    $directoryRoles = @(Get-HybridGraphObjectValue -InputObject $InputObject -Names @('DirectoryRoles','AzureRoles') -Default @())
    if ($directoryRoles.Count -eq 0 -and $pimRoles.Count -gt 0) { $directoryRoles = @($pimRoles) }
    $graphDiagnostics = @(Get-HybridGraphObjectValue -InputObject $InputObject -Names @('GraphDiagnostics','Diagnostics') -Default @())
    $licenseDiagnostic = [string](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('LicenseDiagnostic','LicenseDiagnostics') -Default '')
    $pimDiagnostic = [string](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('PimRoleDiagnostic','PimRoleDiagnostics','PimDiagnostics','RoleDiagnostic','RoleDiagnostics') -Default '')
    $lastSignIn = Get-HybridGraphObjectValue -InputObject $InputObject -Names @('LastSignInDateTime','LastSignIn','SignInActivity') -Default $null
    $lastNonInteractive = Get-HybridGraphObjectValue -InputObject $InputObject -Names @('LastNonInteractiveSignInDateTime','LastNonInteractiveSignIn') -Default $null
    $passwordChanged = Get-HybridGraphObjectValue -InputObject $InputObject -Names @('PasswordLastChangedDateTime','LastPasswordChange','PasswordLastChanged') -Default $null
    $riskState = [string](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('RiskState','UserRiskState','SignInRiskState','riskState') -Default 'none')
    $userRiskState = [string](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('UserRiskState','RiskState','riskState') -Default $riskState)
    $signInRiskState = [string](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('SignInRiskState','RiskState','riskState') -Default $riskState)
    $riskDetails = @(Get-HybridGraphObjectValue -InputObject $InputObject -Names @('RiskDetails','RiskDetections','RiskySignIns') -Default @())

    [pscustomobject]@{
        PSTypeName = 'Hybrid.GraphProfile'
        ObjectId = [string](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('ObjectId','Id','GraphObjectId') -Default '')
        UserPrincipalName = [string](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('UserPrincipalName','UPN') -Default $Identity)
        DisplayName = [string](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('DisplayName','Name') -Default $Identity)
        UserType = [string](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('UserType') -Default 'Member')
        PreferredLanguage = [string](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('PreferredLanguage') -Default 'en-US')
        UsageLocation = [string](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('UsageLocation') -Default 'US')
        LastSignInDateTime = $lastSignIn
        LastNonInteractiveSignInDateTime = $lastNonInteractive
        PasswordLastChangedDateTime = $passwordChanged
        AuthenticationMethods = @($methods)
        AuthenticationMethodDetails = @($methodDetails)
        Licenses = @($licenses)
        AssignedLicenses = @($assignedLicenses)
        LicenseAssignmentStates = @($licenseAssignmentStates)
        PimRoles = @($pimRoles)
        DirectoryRoles = @($directoryRoles)
        GraphDiagnostics = @($graphDiagnostics)
        LicenseDiagnostic = $licenseDiagnostic
        LicenseDiagnostics = $licenseDiagnostic
        PimRoleDiagnostic = $pimDiagnostic
        PimRoleDiagnostics = $pimDiagnostic
        PimDiagnostics = $pimDiagnostic
        MfaRegistered = [bool](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('MfaRegistered','MfaEnabled','IsMfaRegistered') -Default $false)
        MfaCapable = [bool](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('MfaCapable','IsMfaCapable') -Default $false)
        RiskState = $riskState
        UserRiskState = $userRiskState
        SignInRiskState = $signInRiskState
        RiskDetails = @($riskDetails)
        Source = [string](Get-HybridGraphObjectValue -InputObject $InputObject -Names @('Source') -Default 'MicrosoftGraph')
        RetrievedOn = [datetime]::UtcNow
        Attributes = @{}
    }
}

function Initialize-HybridGraphProfileService {
    [CmdletBinding()]
    param([AllowNull()][object]$MicrosoftGraphProvider)

    $script:GraphProfileServiceState.MicrosoftGraph = $MicrosoftGraphProvider
    $script:GraphProfileServiceState.Initialized = $true
    $script:GraphProfileServiceState.Cache.Clear()

    [pscustomobject]@{
        PSTypeName = 'Hybrid.GraphProfileService'
        Name = 'GraphProfileService'
        Initialized = $true
        MicrosoftGraphProvider = ($null -ne $MicrosoftGraphProvider)
        GetGraphProfile = ({ param([string]$Identity) Get-HybridGraphProfile -Identity $Identity }).GetNewClosure()
    }
}

function Get-HybridGraphProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not $script:GraphProfileServiceState.Initialized) { throw 'Hybrid Graph profile service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'Graph profile identity cannot be empty.' }

    $cacheKey = $Identity.ToLowerInvariant()
    if ($script:GraphProfileServiceState.Cache.ContainsKey($cacheKey)) { return $script:GraphProfileServiceState.Cache[$cacheKey] }

    try {
        $profile = @(Invoke-HybridGraphProviderOperation `
            -Provider $script:GraphProfileServiceState.MicrosoftGraph `
            -OperationNames @('GetGraphProfile','GetUserGraphProfile','GetAuthenticationProfile','GetUser','GetGraphUser','Get') `
            -Arguments @($Identity) | Select-Object -First 1)

        if ($profile.Count -eq 0 -or $null -eq $profile[0]) { return $null }

        $converted = ConvertTo-HybridGraphProfile -InputObject $profile[0] -Identity $Identity
        $script:GraphProfileServiceState.Cache[$cacheKey] = $converted
        return $converted
    } catch {
        $script:GraphProfileServiceState.LastError = $_.Exception.Message
        throw
    }
}

function Clear-HybridGraphProfileService {
    [CmdletBinding()]
    param()

    $script:GraphProfileServiceState.Initialized = $false
    $script:GraphProfileServiceState.MicrosoftGraph = $null
    $script:GraphProfileServiceState.Cache.Clear()
    $script:GraphProfileServiceState.LastError = $null
    return $true
}

Export-ModuleMember -Function @(
    'Initialize-HybridGraphProfileService',
    'Get-HybridGraphProfile',
    'Clear-HybridGraphProfileService'
)
