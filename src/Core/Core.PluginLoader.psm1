#region Module Information
# Name: Core.PluginLoader
# Purpose: Plugin discovery, registration, and initialization.
# Dependencies: Core.Logging recommended.
# Exports: Initialize-HybridPluginRegistry, Register-HybridPlugin, Get-HybridPlugin, Get-HybridPlugins, Import-HybridPlugins
#endregion

Set-StrictMode -Version Latest

$script:State = @{
    Plugins = @{}
}

#region Private
function New-HybridPluginRecord {
    param(
        [string]$Name,
        [string]$Version,
        [string]$Path,
        [object]$Manifest,
        [scriptblock]$InitializeScript
    )

    [pscustomobject]@{
        PSTypeName        = 'Hybrid.PluginRecord'
        Name              = $Name
        Version           = $Version
        Path              = $Path
        Manifest          = $Manifest
        InitializeScript  = $InitializeScript
        RegisteredUtc     = [datetime]::UtcNow
    }
}
#endregion

#region Public
function Initialize-HybridPluginRegistry {
    <#
    .SYNOPSIS
    Initializes an empty plugin registry.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Context)

    $script:State.Plugins = @{}
    $Context.Plugins = $script:State.Plugins
    return $Context.Plugins
}

function Register-HybridPlugin {
    <#
    .SYNOPSIS
    Registers a plugin with the host.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Version = '0.1.0',
        [string]$Path = '',
        [object]$Manifest,
        [scriptblock]$Initialize,
        [switch]$Force
    )

    if ($script:State.Plugins.ContainsKey($Name) -and -not $Force) {
        throw "Plugin '$Name' is already registered. Use -Force to replace it."
    }

    $record = New-HybridPluginRecord -Name $Name -Version $Version -Path $Path -Manifest $Manifest -InitializeScript $Initialize
    $script:State.Plugins[$Name] = $record

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        Write-HybridLog -Level Information -Module 'Core.PluginLoader' -Message "Registered plugin '$Name' v$Version." | Out-Null
    }

    return $record
}

function Get-HybridPlugin {
    <#
    .SYNOPSIS
    Returns a registered plugin by name.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Name)

    if (-not $script:State.Plugins.ContainsKey($Name)) { throw "Plugin '$Name' is not registered." }
    return $script:State.Plugins[$Name]
}

function Get-HybridPlugins {
    <#
    .SYNOPSIS
    Lists registered plugins.
    #>
    [CmdletBinding()]
    param()

    return @($script:State.Plugins.Values | Sort-Object Name)
}

function Import-HybridPlugins {
    <#
    .SYNOPSIS
    Discovers and imports plugin modules from a plugin path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Context,
        [Parameter(Mandatory=$true)][string]$PluginPath
    )

    if (-not (Test-Path -LiteralPath $PluginPath)) { return @() }

    $pluginFiles = @(Get-ChildItem -Path $PluginPath -Recurse -Filter '*.plugin.psm1' -File | Sort-Object FullName)
    foreach ($file in $pluginFiles) {
        Import-Module -Name $file.FullName -Force -Global -ErrorAction Stop
        if (Get-Command Initialize-HybridPlugin -ErrorAction SilentlyContinue) {
            Initialize-HybridPlugin -Context $Context -PluginPath $file.Directory.FullName
        }
    }

    return Get-HybridPlugins
}
#endregion

#region Initialization
Export-ModuleMember -Function Initialize-HybridPluginRegistry, Register-HybridPlugin, Get-HybridPlugin, Get-HybridPlugins, Import-HybridPlugins
#endregion
