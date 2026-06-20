#region Module Information
# Name: Core.ModuleLoader
# Purpose: Discovers and imports framework modules in deterministic order.
# Dependencies: Core.Paths recommended, Core.Logging optional.
# Exports: Import-HybridModuleTree, Get-HybridLoadedModules
#endregion

Set-StrictMode -Version Latest

$script:State = @{
    LoadedModules = @()
}

#region Private
function Get-HybridModuleLoadOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath
    )

    $preferred = @(
        'Core.Paths.psm1',
        'Core.Logging.psm1',
        'Core.Configuration.psm1',
        'Core.Cache.psm1',
        'Core.Environment.psm1',
        'Core.Security.psm1',
        'Core.Theme.psm1',
        'Core.ServiceRegistry.psm1',
        'Core.PluginLoader.psm1',
        'Hybrid.Models.psm1',
        'Infrastructure.Mock.psm1',
        'Application.UserService.psm1',
        'Application.ServiceLocator.psm1',
        'UI.Shell.psm1'
    )

    $all = @(Get-ChildItem -Path $SourcePath -Recurse -Filter '*.psm1' -File | Sort-Object FullName)
    $ordered = @()

    foreach ($name in $preferred) {
        $match = $all | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($null -ne $match) {
            $ordered += $match
        }
    }

    foreach ($module in $all) {
        $alreadyOrdered = @($ordered | Where-Object { $_.FullName -eq $module.FullName }).Count -gt 0
        if (-not $alreadyOrdered) {
            $ordered += $module
        }
    }

    return $ordered
}

function Write-HybridModuleLoaderMessage {
    param(
        [string]$Level = 'Information',
        [string]$Message,
        $Exception
    )

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        if ($PSBoundParameters.ContainsKey('Exception')) {
            Write-HybridLog -Level $Level -Module 'Core.ModuleLoader' -Message $Message -Exception $Exception | Out-Null
        }
        else {
            Write-HybridLog -Level $Level -Module 'Core.ModuleLoader' -Message $Message | Out-Null
        }
    }
}
#endregion

#region Public
function Import-HybridModuleTree {
    <#
    .SYNOPSIS
    Imports all framework modules below a source path.

    .DESCRIPTION
    Discovers PowerShell modules under the source tree and imports them in a deterministic order.
    The module loader intentionally avoids removing itself while it is running.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,

        [switch]$Refresh,

        [switch]$Global
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Source path '$SourcePath' does not exist."
    }

    $modules = @(Get-HybridModuleLoadOrder -SourcePath $SourcePath)
    $loaded = @()
    $currentModulePath = $PSCommandPath

    foreach ($moduleFile in $modules) {
        try {
            # Core.ModuleLoader is already imported by bootstrap before this function can run.
            # Do not remove/re-import the currently executing module.
            if ($currentModulePath -and ($moduleFile.FullName -eq $currentModulePath)) {
                $loaded += [pscustomobject]@{
                    PSTypeName = 'Hybrid.LoadedModule'
                    Name       = $moduleFile.BaseName
                    Path       = $moduleFile.FullName
                    LoadedUtc  = [datetime]::UtcNow
                    Skipped    = $true
                    Reason     = 'Current module already loaded'
                }
                continue
            }

            $existing = @(Get-Module | Where-Object { $_.Path -and ($_.Path -eq $moduleFile.FullName) })
            if ($Refresh -and $existing.Count -gt 0) {
                foreach ($item in $existing) {
                    Remove-Module -Name $item.Name -Force -ErrorAction SilentlyContinue
                }
            }

            $scope = if ($Global) { 'Global' } else { 'Local' }
            Import-Module -Name $moduleFile.FullName -Force -Scope $scope -ErrorAction Stop

            $loaded += [pscustomobject]@{
                PSTypeName = 'Hybrid.LoadedModule'
                Name       = $moduleFile.BaseName
                Path       = $moduleFile.FullName
                LoadedUtc  = [datetime]::UtcNow
                Skipped    = $false
                Reason     = $null
            }

            Write-HybridModuleLoaderMessage -Level Debug -Message "Imported module '$($moduleFile.BaseName)'."
        }
        catch {
            Write-HybridModuleLoaderMessage -Level Error -Message "Failed to import '$($moduleFile.FullName)'." -Exception $_
            throw
        }
    }

    $script:State.LoadedModules = @($loaded)
    return @($script:State.LoadedModules)
}

function Get-HybridLoadedModules {
    <#
    .SYNOPSIS
    Returns modules loaded by Import-HybridModuleTree.
    #>
    [CmdletBinding()]
    param()

    return @($script:State.LoadedModules)
}
#endregion

#region Initialization
Export-ModuleMember -Function Import-HybridModuleTree, Get-HybridLoadedModules
#endregion
