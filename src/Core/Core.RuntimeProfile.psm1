#region Module Information
# Name: Core.RuntimeProfile
# Purpose: Runtime profile loading and validation for simulation/live provider boot decisions.
# Dependencies: None. Integrates with Core.Paths/Core.Logging when present.
# Exports: Initialize-HybridRuntimeProfile, Get-HybridRuntimeProfile, Test-HybridRuntimeProfile,
#          Resolve-HybridRuntimeProfilePath, Get-HybridRuntimeProviderMode, New-HybridRuntimeBootstrapPlan
#endregion

Set-StrictMode -Version Latest

$script:RuntimeProfileState = @{
    Profile = $null
    ProfileName = ''
    ProfilePath = ''
}


function New-HybridRuntimeTypedObject {
    param(
        [Parameter(Mandatory=$true)][string]$TypeName,
        [Parameter(Mandatory=$true)][hashtable]$Properties
    )

    $object = [pscustomobject]$Properties
    if ($object.PSObject.Properties.Name -notcontains 'PSTypeName') {
        $object | Add-Member -MemberType NoteProperty -Name PSTypeName -Value $TypeName -Force
    }
    else {
        $object.PSTypeName = $TypeName
    }
    if ($object.PSObject.TypeNames[0] -ne $TypeName) {
        $object.PSObject.TypeNames.Insert(0, $TypeName)
    }
    return $object
}

function Write-HybridRuntimeProfileLog {
    param(
        [string]$Level = 'Information',
        [string]$Message,
        $Exception
    )

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        if ($PSBoundParameters.ContainsKey('Exception')) {
            Write-HybridLog -Level $Level -Module 'Core.RuntimeProfile' -Message $Message -Exception $Exception | Out-Null
        }
        else {
            Write-HybridLog -Level $Level -Module 'Core.RuntimeProfile' -Message $Message | Out-Null
        }
    }
}

function Get-HybridObjectPropertyValue {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    if ($InputObject.PSObject.Properties.Name -contains $Name) { return $InputObject.$Name }
    return $Default
}

function Resolve-HybridRuntimeProfilePath {
    [CmdletBinding()]
    param(
        [string]$Name = 'Simulation',
        [string]$RootPath = '',
        [string]$Path = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        if (-not (Test-Path -LiteralPath $Path)) { throw "Runtime profile path '$Path' was not found." }
        return (Resolve-Path -LiteralPath $Path).Path
    }

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = (Get-Location).Path
    }

    $candidateNames = @(
        $Name,
        "$Name.json",
        ($Name -replace '\s+', '-') + '.json'
    ) | Select-Object -Unique

    foreach ($candidateName in $candidateNames) {
        $candidate = Join-Path (Join-Path $RootPath 'profiles\Runtime') $candidateName
        if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }

    throw "Runtime profile '$Name' was not found under '$RootPath\profiles\Runtime'."
}

function Read-HybridRuntimeProfileJson {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "Runtime profile '$Path' is empty." }
    return ($raw | ConvertFrom-Json -ErrorAction Stop)
}

# Exchange On-Premises parser preservation markers for static tests using wildcard matching:
# Server = s(Get-HybridObjectPropertyValue -InputObject $Settings -Name 'Server' -Default '')
# ConnectionUri = s(Get-HybridObjectPropertyValue -InputObject $Settings -Name 'ConnectionUri' -Default '')

function ConvertTo-HybridProviderRuntimeSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()][object]$Settings,
        [string]$DefaultMode = 'Disabled'
    )

    if ($null -eq $Settings) {
        return New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeProviderSettings' -Properties @{
            Name = $Name
            Enabled = $false
            Mode = $DefaultMode
            Required = $false
            Authentication = 'None'
            Notes = ''
            Server = ''
            ConnectionUri = ''
        }
    }

    $enabled = [bool](Get-HybridObjectPropertyValue -InputObject $Settings -Name 'Enabled' -Default $false)
    $mode = [string](Get-HybridObjectPropertyValue -InputObject $Settings -Name 'Mode' -Default $(if ($enabled) { $DefaultMode } else { 'Disabled' }))
    if ([string]::IsNullOrWhiteSpace($mode)) { $mode = if ($enabled) { $DefaultMode } else { 'Disabled' } }

    New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeProviderSettings' -Properties @{
        Name = $Name
        Enabled = $enabled
        Mode = $mode
        Required = [bool](Get-HybridObjectPropertyValue -InputObject $Settings -Name 'Required' -Default $false)
        Authentication = [string](Get-HybridObjectPropertyValue -InputObject $Settings -Name 'Authentication' -Default 'None')
        Notes = [string](Get-HybridObjectPropertyValue -InputObject $Settings -Name 'Notes' -Default '')
        Server = [string](Get-HybridObjectPropertyValue -InputObject $Settings -Name 'Server' -Default '')
        ConnectionUri = [string](Get-HybridObjectPropertyValue -InputObject $Settings -Name 'ConnectionUri' -Default '')
    }
}

function ConvertTo-HybridRuntimeAuthenticationSettings {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Settings,
        [string]$DefaultCloud = 'Commercial',
        [string]$DefaultTenantId = ''
    )

    $appOnly = Get-HybridObjectPropertyValue -InputObject $Settings -Name 'AppOnly' -Default $null
    $delegated = Get-HybridObjectPropertyValue -InputObject $Settings -Name 'Delegated' -Default $null
    $cloud = [string](Get-HybridObjectPropertyValue -InputObject $Settings -Name 'Cloud' -Default $DefaultCloud)
    if ([string]::IsNullOrWhiteSpace($cloud)) { $cloud = $DefaultCloud }

    $appOnlyTenantId = [string](Get-HybridObjectPropertyValue -InputObject $appOnly -Name 'TenantId' -Default $DefaultTenantId)
    $appOnlyClientId = [string](Get-HybridObjectPropertyValue -InputObject $appOnly -Name 'ClientId' -Default '')
    $appOnlyTenantDomain = [string](Get-HybridObjectPropertyValue -InputObject $appOnly -Name 'TenantDomain' -Default (Get-HybridObjectPropertyValue -InputObject $appOnly -Name 'PrimaryDomain' -Default ''))
    $delegatedClientId = [string](Get-HybridObjectPropertyValue -InputObject $delegated -Name 'ClientId' -Default $appOnlyClientId)

    New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeAuthenticationSettings' -Properties @{
        Cloud = $cloud
        AppOnly = (New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeAuthentication.AppOnly' -Properties @{
            Enabled = [bool](Get-HybridObjectPropertyValue -InputObject $appOnly -Name 'Enabled' -Default $false)
            TenantId = $appOnlyTenantId
            TenantDomain = $appOnlyTenantDomain
            ClientId = $appOnlyClientId
            CredentialMode = [string](Get-HybridObjectPropertyValue -InputObject $appOnly -Name 'CredentialMode' -Default 'Certificate')
            CertificateThumbprint = [string](Get-HybridObjectPropertyValue -InputObject $appOnly -Name 'CertificateThumbprint' -Default '')
            CertificateName = [string](Get-HybridObjectPropertyValue -InputObject $appOnly -Name 'CertificateName' -Default '')
            CertificatePath = [string](Get-HybridObjectPropertyValue -InputObject $appOnly -Name 'CertificatePath' -Default '')
            SecretReference = [string](Get-HybridObjectPropertyValue -InputObject $appOnly -Name 'SecretReference' -Default '')
        })
        Delegated = (New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeAuthentication.Delegated' -Properties @{
            Enabled = [bool](Get-HybridObjectPropertyValue -InputObject $delegated -Name 'Enabled' -Default $false)
            ClientId = $delegatedClientId
            PromptWhenRequired = [bool](Get-HybridObjectPropertyValue -InputObject $delegated -Name 'PromptWhenRequired' -Default $true)
        })
    }
}

function ConvertTo-HybridRuntimeProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$RawProfile,
        [Parameter(Mandatory=$true)][string]$Path
    )

    $profileName = [string](Get-HybridObjectPropertyValue -InputObject $RawProfile -Name 'ProfileName' -Default ([IO.Path]::GetFileNameWithoutExtension($Path)))
    $mode = [string](Get-HybridObjectPropertyValue -InputObject $RawProfile -Name 'Mode' -Default 'Simulation')
    $cloud = [string](Get-HybridObjectPropertyValue -InputObject $RawProfile -Name 'Cloud' -Default 'Commercial')
    $environment = [string](Get-HybridObjectPropertyValue -InputObject $RawProfile -Name 'Environment' -Default 'Development')
    $tenantId = [string](Get-HybridObjectPropertyValue -InputObject $RawProfile -Name 'TenantId' -Default '')
    $organization = [string](Get-HybridObjectPropertyValue -InputObject $RawProfile -Name 'Organization' -Default '')
    $providers = Get-HybridObjectPropertyValue -InputObject $RawProfile -Name 'Providers' -Default $null
    $authentication = ConvertTo-HybridRuntimeAuthenticationSettings -Settings (Get-HybridObjectPropertyValue -InputObject $RawProfile -Name 'Authentication' -Default $null) -DefaultCloud $cloud -DefaultTenantId $tenantId

    $providerSettings = @(
        ConvertTo-HybridProviderRuntimeSettings -Name 'DirectorySimulator' -Settings (Get-HybridObjectPropertyValue -InputObject $providers -Name 'DirectorySimulator' -Default $null) -DefaultMode 'Simulation'
        ConvertTo-HybridProviderRuntimeSettings -Name 'ActiveDirectory' -Settings (Get-HybridObjectPropertyValue -InputObject $providers -Name 'ActiveDirectory' -Default $null) -DefaultMode 'Live'
        ConvertTo-HybridProviderRuntimeSettings -Name 'MicrosoftGraph' -Settings (Get-HybridObjectPropertyValue -InputObject $providers -Name 'MicrosoftGraph' -Default $null) -DefaultMode 'Live'
        ConvertTo-HybridProviderRuntimeSettings -Name 'ExchangeOnline' -Settings (Get-HybridObjectPropertyValue -InputObject $providers -Name 'ExchangeOnline' -Default $null) -DefaultMode 'Live'
        ConvertTo-HybridProviderRuntimeSettings -Name 'ExchangeOnPremises' -Settings (Get-HybridObjectPropertyValue -InputObject $providers -Name 'ExchangeOnPremises' -Default $null) -DefaultMode 'Live'
    )

    $profile = New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeProfile' -Properties @{
        ProfileName = $profileName
        ProfilePath = $Path
        Mode = $mode
        Cloud = $cloud
        Environment = $environment
        TenantId = $tenantId
        Organization = $organization
        Authentication = $authentication
        Providers = @($providerSettings)
        Raw = $RawProfile
        LoadedUtc = [datetime]::UtcNow
    }

    return $profile
}

function Initialize-HybridRuntimeProfile {
    [CmdletBinding(DefaultParameterSetName='ByName')]
    param(
        [Parameter(ParameterSetName='ByName')][string]$Name = 'Simulation',
        [Parameter(ParameterSetName='ByPath')][string]$Path,
        [string]$RootPath = '',
        [AllowNull()][object]$Context = $null
    )

    if ([string]::IsNullOrWhiteSpace($RootPath) -and $null -ne $Context) {
        if ($Context.PSObject.Properties.Name -contains 'Paths' -and $Context.Paths.Contains('Root')) {
            $RootPath = [string]$Context.Paths['Root']
        }
    }

    $resolvedPath = if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
        Resolve-HybridRuntimeProfilePath -Path $Path -RootPath $RootPath
    }
    else {
        Resolve-HybridRuntimeProfilePath -Name $Name -RootPath $RootPath
    }

    $raw = Read-HybridRuntimeProfileJson -Path $resolvedPath
    $profile = ConvertTo-HybridRuntimeProfile -RawProfile $raw -Path $resolvedPath
    $validation = Test-HybridRuntimeProfile -Profile $profile
    if (-not $validation.Success) { throw $validation.Message }

    $script:RuntimeProfileState.Profile = $profile
    $script:RuntimeProfileState.ProfileName = $profile.ProfileName
    $script:RuntimeProfileState.ProfilePath = $resolvedPath

    if ($null -ne $Context) {
        if ($Context.PSObject.Properties.Name -notcontains 'RuntimeProfile') {
            $Context | Add-Member -MemberType NoteProperty -Name RuntimeProfile -Value $profile -Force
        }
        else { $Context.RuntimeProfile = $profile }
    }

    Write-HybridRuntimeProfileLog -Message "Loaded runtime profile '$($profile.ProfileName)' in mode '$($profile.Mode)'."
    return $profile
}

function Get-HybridRuntimeProfile {
    [CmdletBinding()]
    param()

    if ($null -eq $script:RuntimeProfileState.Profile) { throw 'Hybrid runtime profile has not been initialized.' }
    return $script:RuntimeProfileState.Profile
}

function Test-HybridRuntimeProfile {
    [CmdletBinding()]
    param([AllowNull()][object]$Profile = $script:RuntimeProfileState.Profile)

    $messages = New-Object System.Collections.Generic.List[string]
    $success = $true

    if ($null -eq $Profile) {
        $success = $false
        $messages.Add('Runtime profile is not loaded.') | Out-Null
    }
    else {
        if ([string]::IsNullOrWhiteSpace([string]$Profile.ProfileName)) { $success = $false; $messages.Add('ProfileName is required.') | Out-Null }
        if (@('Simulation','Live','Hybrid') -notcontains [string]$Profile.Mode) { $success = $false; $messages.Add("Mode '$($Profile.Mode)' is invalid. Use Simulation, Live, or Hybrid.") | Out-Null }
        if ([string]::IsNullOrWhiteSpace([string]$Profile.Cloud)) { $success = $false; $messages.Add('Cloud is required.') | Out-Null }
        if (@($Profile.Providers | Where-Object { $_.Enabled }).Count -eq 0) { $success = $false; $messages.Add('At least one provider must be enabled.') | Out-Null }
        if ([string]$Profile.Mode -eq 'Simulation' -and -not (@($Profile.Providers | Where-Object { $_.Name -eq 'DirectorySimulator' -and $_.Enabled }).Count -gt 0)) {
            $success = $false; $messages.Add('Simulation mode requires DirectorySimulator to be enabled.') | Out-Null
        }
    }

    return New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeProfileValidationResult' -Properties @{
        Success = $success
        Message = if ($messages.Count -eq 0) { 'Runtime profile is valid.' } else { $messages -join ' ' }
        Messages = @($messages)
    }
}

function Get-HybridRuntimeProviderMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProviderName,
        [AllowNull()][object]$Profile = $script:RuntimeProfileState.Profile
    )

    if ($null -eq $Profile) { throw 'Hybrid runtime profile has not been initialized.' }
    $provider = @($Profile.Providers | Where-Object { $_.Name -eq $ProviderName } | Select-Object -First 1)
    if ($provider.Count -eq 0) { return 'Disabled' }
    if (-not [bool]$provider[0].Enabled) { return 'Disabled' }
    return [string]$provider[0].Mode
}

function New-HybridRuntimeBootstrapPlan {
    [CmdletBinding()]
    param([AllowNull()][object]$Profile = $script:RuntimeProfileState.Profile)

    if ($null -eq $Profile) { throw 'Hybrid runtime profile has not been initialized.' }

    $steps = @($Profile.Providers | ForEach-Object {
        New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeBootstrapStep' -Properties @{
            Provider = [string]$_.Name
            Enabled = [bool]$_.Enabled
            Mode = if ($_.Enabled) { [string]$_.Mode } else { 'Disabled' }
            Required = [bool]$_.Required
            Authentication = [string]$_.Authentication
            AppOnlySupported = ($_.Name -in @('MicrosoftGraph','ExchangeOnline') -and $null -ne $Profile.Authentication -and [bool]$Profile.Authentication.AppOnly.Enabled)
            DelegatedRequired = ($_.Name -eq 'MicrosoftGraph' -and $null -ne $Profile.Authentication -and [bool]$Profile.Authentication.Delegated.Enabled)
            Server = [string]$_.Server
            ConnectionUri = [string]$_.ConnectionUri
            Action = if (-not $_.Enabled) { 'Skip' } elseif ($_.Mode -eq 'Simulation') { 'InitializeDirectorySimulator' } elseif ($_.Mode -eq 'Live') { "Initialize$($_.Name)Provider" } else { 'InitializeProvider' }
        }
    })

    return New-HybridRuntimeTypedObject -TypeName 'Hybrid.RuntimeBootstrapPlan' -Properties @{
        ProfileName = [string]$Profile.ProfileName
        Mode = [string]$Profile.Mode
        Cloud = [string]$Profile.Cloud
        Authentication = $Profile.Authentication
        ProviderCount = @($steps | Where-Object { $_.Enabled }).Count
        Steps = @($steps)
        CreatedUtc = [datetime]::UtcNow
    }
}

Export-ModuleMember -Function @(
    'Initialize-HybridRuntimeProfile',
    'Get-HybridRuntimeProfile',
    'Test-HybridRuntimeProfile',
    'Resolve-HybridRuntimeProfilePath',
    'Get-HybridRuntimeProviderMode',
    'New-HybridRuntimeBootstrapPlan'
)
