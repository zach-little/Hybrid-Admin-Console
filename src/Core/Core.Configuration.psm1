#region Module Information
# Name: Core.Configuration
# Purpose: Profile-driven configuration loading and validation.
# Dependencies: Core.Paths, Core.Logging recommended.
# Exports: Initialize-HybridConfiguration, Get-HybridConfiguration, Test-HybridConfiguration
#endregion

Set-StrictMode -Version Latest

$script:State = @{
    Configuration = $null
    ProfileName   = $null
}

#region Private
function Read-HybridJsonFile {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json -ErrorAction Stop)
}

function Merge-HybridConfigurationObject {
    param(
        [object]$Base,
        [object]$Overlay
    )

    $result = [ordered]@{}

    foreach ($source in @($Base, $Overlay)) {
        if (-not $source) { continue }
        foreach ($prop in $source.PSObject.Properties) {
            $result[$prop.Name] = $prop.Value
        }
    }

    return [pscustomobject]$result
}
#endregion

#region Public
function Initialize-HybridConfiguration {
    <#
    .SYNOPSIS
    Loads the active profile configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Context,

        [string]$ProfileName = 'Atlas'
    )

    if (-not $Context.Paths -or -not $Context.Paths.Contains('Profiles')) {
        throw 'Hybrid paths must be initialized before configuration can be loaded.'
    }

    $profilePath = Join-Path $Context.Paths['Profiles'] $ProfileName
    if (-not (Test-Path -LiteralPath $profilePath)) {
        throw "Profile '$ProfileName' was not found at '$profilePath'."
    }

    $defaults = Read-HybridJsonFile -Path (Join-Path $profilePath 'defaults.json')
    $config   = Read-HybridJsonFile -Path (Join-Path $profilePath 'config.json')
    $branding = Read-HybridJsonFile -Path (Join-Path $profilePath 'branding.json')
    $mappings = Read-HybridJsonFile -Path (Join-Path $profilePath 'mappings.json')

    $merged = Merge-HybridConfigurationObject -Base $defaults -Overlay $config

    $configuration = [pscustomobject]@{
        PSTypeName  = 'Hybrid.Configuration'
        ProfileName = $ProfileName
        ProfilePath = $profilePath
        Settings    = $merged
        Branding    = $branding
        Mappings    = $mappings
    }

    $script:State.Configuration = $configuration
    $script:State.ProfileName = $ProfileName
    $Context.ProfileName = $ProfileName
    $Context.Configuration = $configuration

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        Write-HybridLog -Level Information -Module 'Core.Configuration' -Message "Loaded profile '$ProfileName'." | Out-Null
    }

    return $configuration
}

function Get-HybridConfiguration {
    <#
    .SYNOPSIS
    Returns the currently loaded configuration.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:State.Configuration) {
        throw 'Hybrid configuration has not been initialized.'
    }

    return $script:State.Configuration
}

function Test-HybridConfiguration {
    <#
    .SYNOPSIS
    Performs basic profile validation.
    #>
    [CmdletBinding()]
    param(
        [object]$Configuration = $script:State.Configuration
    )

    if (-not $Configuration) {
        return [pscustomobject]@{ PSTypeName='Hybrid.ValidationResult'; Success=$false; Message='Configuration is not loaded.' }
    }

    $success = $true
    $messages = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($Configuration.ProfileName)) {
        $success = $false
        $messages.Add('ProfileName is missing.')
    }

    if (-not $Configuration.Settings) {
        $success = $false
        $messages.Add('Settings object is missing.')
    }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.ValidationResult'
        Success    = $success
        Message    = if ($messages.Count -eq 0) { 'Configuration is valid.' } else { $messages -join ' ' }
    }
}
#endregion

#region Initialization
Export-ModuleMember -Function Initialize-HybridConfiguration, Get-HybridConfiguration, Test-HybridConfiguration
#endregion
