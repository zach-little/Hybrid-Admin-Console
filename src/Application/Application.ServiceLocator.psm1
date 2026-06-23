#region Module Information
# Name: Application.ServiceLocator
# Purpose: Application-level service initialization and access helpers.
# Dependencies: Core.ServiceRegistry, Infrastructure.Mock optional, Application.UserService.
# Exports: Initialize-HybridApplicationServices, Invoke-HybridDirectorySearch
#endregion

Set-StrictMode -Version Latest

#region Private
function Get-HybridProviderMode {
    param([Parameter(Mandatory=$true)][object]$Context)

    $providerMode = 'Mock'
    if ($Context.Configuration -and $Context.Configuration.Settings -and $Context.Configuration.Settings.ProviderMode) {
        $providerMode = $Context.Configuration.Settings.ProviderMode
    }
    return $providerMode
}
#endregion

#region Public
function Initialize-HybridApplicationServices {
    <#.SYNOPSIS Initializes application service bindings for the active profile.#>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Context)

    $providerMode = Get-HybridProviderMode -Context $Context

    if ($providerMode -eq 'Mock') {
        Initialize-HybridMockProvider -Context $Context | Out-Null
    }
    else {
        throw "Provider mode '$providerMode' is not implemented yet. Use ProviderMode 'Mock' for Milestone 2."
    }

    $directoryService = $null
    if (Get-Command Get-HybridService -ErrorAction SilentlyContinue) {
        try { $directoryService = Get-HybridService -Name 'Directory' } catch { $directoryService = $null }
    }
    Initialize-HybridUserService -ActiveDirectoryProvider $directoryService | Out-Null

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        Write-HybridLog -Level Information -Module 'Application.ServiceLocator' -Message "Application services initialized using provider mode '$providerMode'." | Out-Null
    }
}

function Invoke-HybridDirectorySearch {
    <#.SYNOPSIS Searches users through the registered directory service.#>
    [CmdletBinding()] param([string]$Query='')

    $service = Get-HybridService -Name 'Directory'
    return & $service.SearchUser $Query
}
#endregion

#region Initialization
Export-ModuleMember -Function Initialize-HybridApplicationServices, Invoke-HybridDirectorySearch
#endregion
