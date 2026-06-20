#region Module Information
# Name: Core.Authentication
# Purpose: Authentication framework contracts and session shell for Hybrid Admin Console.
# Dependencies: Core.CloudEnvironment, Core.TenantContext
# Exports: New-HybridAuthenticationPolicy, Get-HybridAuthenticationPolicy,
#          Set-HybridAuthenticationPolicy, Register-HybridAuthenticationMethod,
#          Get-HybridAuthenticationMethod, Get-HybridAuthenticationMethodNames,
#          New-HybridAuthenticationRequest, New-HybridAuthenticationSession,
#          Test-HybridAuthenticationSession
#endregion

Set-StrictMode -Version Latest

$script:HybridAuthenticationMethods = @{}
$script:HybridAuthenticationPolicy = $null

function New-HybridAuthenticationPolicy {
    [CmdletBinding()]
    param(
        [string[]]$AllowedMethods = @('Interactive', 'InteractiveBrowser', 'AppOnlyClientCredentials', 'ManagedIdentity'),
        [string]$DefaultMethod = 'Interactive',
        [string[]]$RequiredScopes = @(),
        [bool]$AllowInteractive = $true,
        [bool]$AllowAppOnly = $true,
        [bool]$AllowManagedIdentity = $true,
        [bool]$AllowDeviceCode = $false,
        [hashtable]$Attributes = @{}
    )

    if ($AllowedMethods -contains 'DeviceCode' -and -not $AllowDeviceCode) {
        throw 'Device Code Flow is prohibited by the project charter and cannot be allowed by default policy.'
    }

    if (-not ($AllowedMethods -contains $DefaultMethod)) {
        throw "Default authentication method '$DefaultMethod' is not included in AllowedMethods."
    }

    [pscustomobject]@{
        PSTypeName             = 'Hybrid.AuthenticationPolicy'
        AllowedMethods         = @($AllowedMethods)
        DefaultMethod          = $DefaultMethod
        RequiredScopes         = @($RequiredScopes)
        AllowInteractive       = $AllowInteractive
        AllowAppOnly           = $AllowAppOnly
        AllowManagedIdentity   = $AllowManagedIdentity
        AllowDeviceCode        = $AllowDeviceCode
        Attributes             = $Attributes
    }
}

function Set-HybridAuthenticationPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Policy
    )

    foreach ($propertyName in @('AllowedMethods', 'DefaultMethod', 'AllowDeviceCode')) {
        if ($Policy.PSObject.Properties.Name -notcontains $propertyName) {
            throw "Invalid authentication policy. Missing $propertyName property."
        }
    }

    if ($Policy.AllowDeviceCode -eq $true) {
        throw 'Device Code Flow is prohibited by the project charter.'
    }

    if ($Policy.AllowedMethods -contains 'DeviceCode') {
        throw 'Device Code Flow is prohibited by the project charter.'
    }

    $script:HybridAuthenticationPolicy = $Policy
    return $script:HybridAuthenticationPolicy
}

function Get-HybridAuthenticationPolicy {
    [CmdletBinding()]
    param()

    if ($null -eq $script:HybridAuthenticationPolicy) {
        $script:HybridAuthenticationPolicy = New-HybridAuthenticationPolicy
    }

    return $script:HybridAuthenticationPolicy
}

function Register-HybridAuthenticationMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Delegated', 'Application', 'ManagedIdentity')]
        [string]$Mode,

        [string]$DisplayName = '',
        [string]$Description = '',
        [switch]$RequiresUserInteraction,
        [switch]$RequiresClientSecret,
        [switch]$Force,
        [hashtable]$Attributes = @{}
    )

    $normalizedName = $Name.Trim()

    if ($normalizedName -eq 'DeviceCode') {
        throw 'Device Code Flow is prohibited by the project charter.'
    }

    $key = $normalizedName.ToLowerInvariant()

    if ($script:HybridAuthenticationMethods.ContainsKey($key) -and -not $Force) {
        throw "Authentication method '$normalizedName' is already registered. Use -Force to replace it."
    }

    $method = [pscustomobject]@{
        PSTypeName               = 'Hybrid.AuthenticationMethod'
        Name                     = $normalizedName
        DisplayName              = if ([string]::IsNullOrWhiteSpace($DisplayName)) { $normalizedName } else { $DisplayName }
        Description              = $Description
        Mode                     = $Mode
        RequiresUserInteraction  = [bool]$RequiresUserInteraction
        RequiresClientSecret     = [bool]$RequiresClientSecret
        Attributes               = $Attributes
    }

    $script:HybridAuthenticationMethods[$key] = $method
    return $method
}

function Get-HybridAuthenticationMethod {
    [CmdletBinding()]
    param(
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $script:HybridAuthenticationMethods.Values | Sort-Object -Property Name
    }

    $key = $Name.Trim().ToLowerInvariant()

    if (-not $script:HybridAuthenticationMethods.ContainsKey($key)) {
        return $null
    }

    return $script:HybridAuthenticationMethods[$key]
}

function Get-HybridAuthenticationMethodNames {
    [CmdletBinding()]
    param()

    Get-HybridAuthenticationMethod | Select-Object -ExpandProperty Name
}

function New-HybridAuthenticationRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$TenantContext,

        [string]$MethodName,
        [string]$ClientId = '',
        [string[]]$Scopes = @(),
        [hashtable]$Attributes = @{}
    )

    foreach ($propertyName in @('TenantId', 'CloudEnvironment')) {
        if ($TenantContext.PSObject.Properties.Name -notcontains $propertyName) {
            throw "Invalid tenant context. Missing $propertyName property."
        }
    }

    $policy = Get-HybridAuthenticationPolicy
    $resolvedMethodName = if ([string]::IsNullOrWhiteSpace($MethodName)) { [string]$policy.DefaultMethod } else { $MethodName.Trim() }
    $method = Get-HybridAuthenticationMethod -Name $resolvedMethodName

    if ($null -eq $method) {
        throw "Authentication method '$resolvedMethodName' is not registered."
    }

    if (-not ($policy.AllowedMethods -contains $method.Name)) {
        throw "Authentication method '$($method.Name)' is not allowed by the current policy."
    }

    $loginEndpoint = [string]$TenantContext.CloudEnvironment.Endpoints['Login']
    if ([string]::IsNullOrWhiteSpace($loginEndpoint)) {
        throw "Tenant cloud environment '$($TenantContext.CloudEnvironment.Name)' does not define a Login endpoint."
    }

    $resolvedScopes = @($Scopes)
    if ($resolvedScopes.Count -eq 0 -and $policy.RequiredScopes.Count -gt 0) {
        $resolvedScopes = @($policy.RequiredScopes)
    }

    [pscustomobject]@{
        PSTypeName        = 'Hybrid.AuthenticationRequest'
        TenantContext     = $TenantContext
        CloudEnvironment  = $TenantContext.CloudEnvironment
        Method            = $method
        MethodName        = $method.Name
        ClientId          = $ClientId
        Scopes            = @($resolvedScopes)
        Authority         = ($loginEndpoint.TrimEnd('/') + '/' + $TenantContext.TenantId)
        Attributes        = $Attributes
    }
}

function New-HybridAuthenticationSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$AuthenticationRequest,

        [string]$AccessToken = '',
        [string]$TokenType = 'Bearer',
        [datetime]$ExpiresOn = ([datetime]::UtcNow),
        [hashtable]$Attributes = @{}
    )

    foreach ($propertyName in @('TenantContext', 'CloudEnvironment', 'MethodName', 'Authority')) {
        if ($AuthenticationRequest.PSObject.Properties.Name -notcontains $propertyName) {
            throw "Invalid authentication request. Missing $propertyName property."
        }
    }

    [pscustomobject]@{
        PSTypeName             = 'Hybrid.AuthenticationSession'
        SessionId              = [guid]::NewGuid().ToString()
        TenantContext          = $AuthenticationRequest.TenantContext
        CloudEnvironment       = $AuthenticationRequest.CloudEnvironment
        MethodName             = $AuthenticationRequest.MethodName
        Authority              = $AuthenticationRequest.Authority
        AccessToken            = $AccessToken
        TokenType              = $TokenType
        ExpiresOn              = $ExpiresOn
        Scopes                 = @($AuthenticationRequest.Scopes)
        IsAuthenticated        = (-not [string]::IsNullOrWhiteSpace($AccessToken))
        CreatedOn              = [datetime]::UtcNow
        Attributes             = $Attributes
    }
}

function Test-HybridAuthenticationSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Session,
        [switch]$Detailed
    )

    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($propertyName in @('SessionId', 'TenantContext', 'CloudEnvironment', 'MethodName', 'Authority', 'IsAuthenticated', 'ExpiresOn')) {
        if ($Session.PSObject.Properties.Name -notcontains $propertyName) {
            $errors.Add("Missing required property: $propertyName")
        }
    }

    if ($Session.PSObject.Properties.Name -contains 'ExpiresOn' -and $Session.ExpiresOn -lt [datetime]::UtcNow) {
        $errors.Add('Authentication session is expired.')
    }

    $result = [pscustomobject]@{
        PSTypeName = 'Hybrid.AuthenticationSessionValidationResult'
        IsValid    = ($errors.Count -eq 0)
        Errors     = @($errors)
    }

    if ($Detailed) {
        return $result
    }

    return [bool]$result.IsValid
}

function Initialize-HybridBuiltInAuthenticationMethods {
    [CmdletBinding()]
    param()

    Register-HybridAuthenticationMethod -Name 'Interactive' -DisplayName 'Interactive MSAL/WAM' -Mode Delegated -RequiresUserInteraction -Force -Description 'Interactive delegated authentication for enterprise MFA and Conditional Access.' | Out-Null
    Register-HybridAuthenticationMethod -Name 'InteractiveBrowser' -DisplayName 'Interactive Browser' -Mode Delegated -RequiresUserInteraction -Force -Description 'Browser-based delegated authentication.' | Out-Null
    Register-HybridAuthenticationMethod -Name 'AppOnlyClientCredentials' -DisplayName 'App-only Client Credentials' -Mode Application -RequiresClientSecret -Force -Description 'Application permission authentication using client credentials.' | Out-Null
    Register-HybridAuthenticationMethod -Name 'ManagedIdentity' -DisplayName 'Managed Identity' -Mode ManagedIdentity -Force -Description 'Managed identity authentication for supported hosted runtimes.' | Out-Null

    Set-HybridAuthenticationPolicy -Policy (New-HybridAuthenticationPolicy) | Out-Null
}

Initialize-HybridBuiltInAuthenticationMethods

Export-ModuleMember -Function @(
    'New-HybridAuthenticationPolicy',
    'Get-HybridAuthenticationPolicy',
    'Set-HybridAuthenticationPolicy',
    'Register-HybridAuthenticationMethod',
    'Get-HybridAuthenticationMethod',
    'Get-HybridAuthenticationMethodNames',
    'New-HybridAuthenticationRequest',
    'New-HybridAuthenticationSession',
    'Test-HybridAuthenticationSession'
)
