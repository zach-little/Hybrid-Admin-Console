#region Module Information
# Name: Core.Paths
# Purpose: Centralized path discovery and folder validation for Hybrid Administration Platform.
# Dependencies: None
# Exports: Initialize-HybridPaths, Get-HybridPath, Test-HybridStructure, New-HybridHostContext
#endregion

Set-StrictMode -Version Latest

$script:State = @{
    Initialized = $false
    Paths       = @{}
}

#region Private
function Resolve-HybridRootPath {
    [CmdletBinding()]
    param(
        [string]$RootPath
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        $RootPath = (Get-Location).Path
    }

    try {
        return (Resolve-Path -Path $RootPath -ErrorAction Stop).Path
    }
    catch {
        throw "Unable to resolve root path '$RootPath'. $($_.Exception.Message)"
    }
}
#endregion

#region Public
function New-HybridHostContext {
    <#
    .SYNOPSIS
    Creates the shared host context used by the framework.

    .DESCRIPTION
    The host context is the dependency container passed through the bootstrap,
    tests, services, providers, workflows, and plugins. It avoids uncontrolled
    global state while keeping common framework state discoverable.
    #>
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        PSTypeName     = 'Hybrid.HostContext'
        Root           = $null
        ProfileName    = $null
        Paths          = @{}
        Configuration  = $null
        Logger         = $null
        Cache          = $null
        Services       = @{}
        Plugins        = @{}
        Theme          = $null
        Environment    = $null
        StartupTimeUtc = [datetime]::UtcNow
    }
}

function Initialize-HybridPaths {
    <#
    .SYNOPSIS
    Initializes the canonical folder map for the application.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Context,

        [string]$RootPath
    )

    $Root = Resolve-HybridRootPath -RootPath $RootPath

    $Paths = [ordered]@{
        Root           = $Root
        Source         = Join-Path $Root 'src'
        Core           = Join-Path $Root 'src\Core'
        Domain         = Join-Path $Root 'src\Domain'
        Application    = Join-Path $Root 'src\Application'
        Infrastructure = Join-Path $Root 'src\Infrastructure'
        UI             = Join-Path $Root 'src\UI'
        Plugins        = Join-Path $Root 'src\Plugins'
        Profiles       = Join-Path $Root 'profiles'
        Assets         = Join-Path $Root 'assets'
        Logs           = Join-Path $Root 'logs'
        Tests          = Join-Path $Root 'tests'
        Docs           = Join-Path $Root 'docs'
        Tools          = Join-Path $Root 'tools'
        Build          = Join-Path $Root 'build'
        Legacy         = Join-Path $Root 'legacy'
    }

    foreach ($key in $Paths.Keys) {
        if ($key -eq 'Root') { continue }
        if (-not (Test-Path -LiteralPath $Paths[$key])) {
            New-Item -ItemType Directory -Path $Paths[$key] -Force | Out-Null
        }
    }

    $Context.Root = $Root
    $Context.Paths = $Paths
    $script:State.Paths = $Paths
    $script:State.Initialized = $true

    return $Paths
}

function Get-HybridPath {
    <#
    .SYNOPSIS
    Returns a named framework path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [object]$Context,

        [string]$ChildPath
    )

    $paths = if ($Context -and $Context.Paths -and $Context.Paths.Count -gt 0) { $Context.Paths } else { $script:State.Paths }

    if (-not $paths.Contains($Name)) {
        throw "Unknown Hybrid path '$Name'. Known paths: $($paths.Keys -join ', ')"
    }

    $base = $paths[$Name]
    if ([string]::IsNullOrWhiteSpace($ChildPath)) { return $base }
    return (Join-Path $base $ChildPath)
}

function Test-HybridStructure {
    <#
    .SYNOPSIS
    Validates that required folders exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Context
    )

    $required = @('Source','Core','Domain','Application','Infrastructure','UI','Plugins','Profiles','Assets','Tests','Docs','Tools','Build','Legacy')
    $items = foreach ($name in $required) {
        $path = Get-HybridPath -Context $Context -Name $name
        [pscustomobject]@{
            PSTypeName = 'Hybrid.StructureCheck'
            Name       = $name
            Path       = $path
            Exists     = Test-Path -LiteralPath $path
        }
    }

    return $items
}
#endregion

#region Initialization
Export-ModuleMember -Function New-HybridHostContext, Initialize-HybridPaths, Get-HybridPath, Test-HybridStructure
#endregion
