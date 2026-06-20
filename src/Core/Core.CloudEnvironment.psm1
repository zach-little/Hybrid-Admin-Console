#region Module Information
# Name: Core.CloudEnvironment
# Purpose: Cloud environment and endpoint resolution for Hybrid Admin Console.
# Dependencies: None.
# Exports: New-HybridCloudEnvironment, Register-HybridCloudEnvironment,
#          Get-HybridCloudEnvironment, Get-HybridCloudEnvironmentNames,
#          Get-HybridCloudEnvironmentEndpoint, Resolve-HybridCloudEndpoint,
#          Test-HybridCloudEnvironment
#endregion

Set-StrictMode -Version Latest

$script:HybridCloudEnvironments = @{}
$script:HybridCloudEnvironmentCanonicalNames = @{}

function New-HybridCloudEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [hashtable]$Endpoints,

        [string]$Description = '',

        [string[]]$Aliases = @()
    )

    if ($Endpoints.Count -eq 0) {
        throw 'Cloud environment endpoints cannot be empty.'
    }

    $normalizedEndpoints = @{}

    foreach ($key in $Endpoints.Keys) {
        $endpointName = [string]$key
        $endpointValue = [string]$Endpoints[$key]

        if ([string]::IsNullOrWhiteSpace($endpointName)) {
            throw 'Cloud environment endpoint keys cannot be empty.'
        }

        if ([string]::IsNullOrWhiteSpace($endpointValue)) {
            throw "Cloud environment endpoint '$endpointName' cannot be empty."
        }

        $normalizedEndpoints[$endpointName.Trim()] = $endpointValue.Trim().TrimEnd('/')
    }

    [pscustomobject]@{
        PSTypeName  = 'Hybrid.CloudEnvironment'
        Name        = $Name.Trim()
        DisplayName = $DisplayName.Trim()
        Description = $Description
        Aliases     = @($Aliases | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
        Endpoints   = $normalizedEndpoints
    }
}

function Register-HybridCloudEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [object]$Environment,

        [switch]$Force
    )

    process {
        foreach ($propertyName in @('Name', 'DisplayName', 'Endpoints')) {
            if ($Environment.PSObject.Properties.Name -notcontains $propertyName) {
                throw "Invalid cloud environment. Missing $propertyName property."
            }
        }

        $canonicalName = [string]$Environment.Name

        if ([string]::IsNullOrWhiteSpace($canonicalName)) {
            throw 'Cloud environment Name cannot be empty.'
        }

        if ($null -eq $Environment.Endpoints -or $Environment.Endpoints.Count -eq 0) {
            throw "Cloud environment '$canonicalName' must define at least one endpoint."
        }

        $keysToRegister = @($canonicalName)

        if ($Environment.PSObject.Properties.Name -contains 'Aliases') {
            $keysToRegister += @($Environment.Aliases)
        }

        foreach ($key in $keysToRegister) {
            if ([string]::IsNullOrWhiteSpace([string]$key)) {
                continue
            }

            $normalizedKey = ([string]$key).Trim().ToLowerInvariant()

            if ($script:HybridCloudEnvironments.ContainsKey($normalizedKey) -and -not $Force) {
                throw "Cloud environment '$key' is already registered. Use -Force to replace it."
            }
        }

        foreach ($key in $keysToRegister) {
            if ([string]::IsNullOrWhiteSpace([string]$key)) {
                continue
            }

            $normalizedKey = ([string]$key).Trim().ToLowerInvariant()
            $script:HybridCloudEnvironments[$normalizedKey] = $Environment
            $script:HybridCloudEnvironmentCanonicalNames[$normalizedKey] = $canonicalName
        }

        return $Environment
    }
}

function Get-HybridCloudEnvironment {
    [CmdletBinding()]
    param(
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $seen = @{}

        foreach ($item in $script:HybridCloudEnvironments.Values) {
            if (-not $seen.ContainsKey($item.Name)) {
                $seen[$item.Name] = $true
                $item
            }
        }

        return
    }

    $normalizedName = $Name.Trim().ToLowerInvariant()

    if (-not $script:HybridCloudEnvironments.ContainsKey($normalizedName)) {
        throw "Cloud environment '$Name' is not registered."
    }

    return $script:HybridCloudEnvironments[$normalizedName]
}

function Get-HybridCloudEnvironmentNames {
    [CmdletBinding()]
    param()

    Get-HybridCloudEnvironment |
        Sort-Object -Property Name |
        Select-Object -ExpandProperty Name
}

function Get-HybridCloudEnvironmentEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EnvironmentName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EndpointName
    )

    $environment = Get-HybridCloudEnvironment -Name $EnvironmentName

    if (-not $environment.Endpoints.ContainsKey($EndpointName)) {
        throw "Cloud environment '$($environment.Name)' does not define endpoint '$EndpointName'."
    }

    return [string]$environment.Endpoints[$EndpointName]
}

function Resolve-HybridCloudEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EnvironmentName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EndpointName,

        [string]$Path = ''
    )

    $baseEndpoint = Get-HybridCloudEnvironmentEndpoint -EnvironmentName $EnvironmentName -EndpointName $EndpointName

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $baseEndpoint
    }

    $cleanPath = $Path.Trim()

    if ($cleanPath.StartsWith('/')) {
        return "$baseEndpoint$cleanPath"
    }

    return "$baseEndpoint/$cleanPath"
}

function Test-HybridCloudEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Environment,

        [string[]]$RequiredEndpoints = @('Graph', 'Login')
    )

    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($propertyName in @('Name', 'DisplayName', 'Endpoints')) {
        if ($Environment.PSObject.Properties.Name -notcontains $propertyName) {
            $errors.Add("Missing required property: $propertyName")
        }
    }

    if ($Environment.PSObject.Properties.Name -contains 'Endpoints') {
        foreach ($endpointName in $RequiredEndpoints) {
            if (-not $Environment.Endpoints.ContainsKey($endpointName)) {
                $errors.Add("Missing required endpoint: $endpointName")
            }
        }
    }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.CloudEnvironmentValidationResult'
        IsValid    = ($errors.Count -eq 0)
        Errors     = @($errors)
    }
}

function Initialize-HybridBuiltInCloudEnvironments {
    [CmdletBinding()]
    param()

    $builtInEnvironments = @(
        New-HybridCloudEnvironment `
            -Name 'Commercial' `
            -DisplayName 'Microsoft Commercial Cloud' `
            -Description 'Default Microsoft public cloud endpoints.' `
            -Aliases @('Public', 'Global', 'AzureCloud') `
            -Endpoints @{
                Graph            = 'https://graph.microsoft.com'
                Login            = 'https://login.microsoftonline.com'
                AzureManagement  = 'https://management.azure.com'
                ExchangeOnline   = 'https://outlook.office365.com'
                GraphScopeSuffix = 'https://graph.microsoft.com/.default'
            }

        New-HybridCloudEnvironment `
            -Name 'GCC' `
            -DisplayName 'Microsoft Government Community Cloud' `
            -Description 'Microsoft 365 GCC endpoints where Graph remains on the public Graph host.' `
            -Aliases @('GovernmentCommunityCloud') `
            -Endpoints @{
                Graph            = 'https://graph.microsoft.com'
                Login            = 'https://login.microsoftonline.com'
                AzureManagement  = 'https://management.azure.com'
                ExchangeOnline   = 'https://outlook.office365.com'
                GraphScopeSuffix = 'https://graph.microsoft.com/.default'
            }

        New-HybridCloudEnvironment `
            -Name 'GCCHigh' `
            -DisplayName 'Microsoft GCC High' `
            -Description 'Microsoft GCC High / Azure US Government endpoints.' `
            -Aliases @('GCC High', 'USGov', 'AzureUSGovernment', 'Government') `
            -Endpoints @{
                Graph            = 'https://graph.microsoft.us'
                Login            = 'https://login.microsoftonline.us'
                AzureManagement  = 'https://management.usgovcloudapi.net'
                ExchangeOnline   = 'https://outlook.office365.us'
                GraphScopeSuffix = 'https://graph.microsoft.us/.default'
            }

        New-HybridCloudEnvironment `
            -Name 'DoD' `
            -DisplayName 'Microsoft DoD' `
            -Description 'Microsoft Department of Defense cloud endpoints.' `
            -Aliases @('DepartmentOfDefense') `
            -Endpoints @{
                Graph            = 'https://dod-graph.microsoft.us'
                Login            = 'https://login.microsoftonline.us'
                AzureManagement  = 'https://management.usgovcloudapi.net'
                ExchangeOnline   = 'https://webmail.apps.mil'
                GraphScopeSuffix = 'https://dod-graph.microsoft.us/.default'
            }
    )

    foreach ($environment in $builtInEnvironments) {
        Register-HybridCloudEnvironment -Environment $environment -Force | Out-Null
    }
}

Initialize-HybridBuiltInCloudEnvironments

Export-ModuleMember -Function @(
    'New-HybridCloudEnvironment',
    'Register-HybridCloudEnvironment',
    'Get-HybridCloudEnvironment',
    'Get-HybridCloudEnvironmentNames',
    'Get-HybridCloudEnvironmentEndpoint',
    'Resolve-HybridCloudEndpoint',
    'Test-HybridCloudEnvironment'
)
