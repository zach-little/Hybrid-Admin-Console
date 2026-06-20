#region Module Information
# Name: Application.ServiceLocator
# Purpose: Application-level service initialization and access helpers.
# Dependencies: Core.ServiceRegistry, Infrastructure.Mock optional.
# Exports: Initialize-HybridApplicationServices, Invoke-HybridDirectorySearch
#endregion

Set-StrictMode -Version Latest

#region Private
#endregion

#region Public
function Initialize-HybridApplicationServices {
    <#.SYNOPSIS Initializes application service bindings for the active profile.#>
    [CmdletBinding()] param([Parameter(Mandatory=$true)][object]$Context)

    $providerMode = 'Mock'
    if ($Context.Configuration -and $Context.Configuration.Settings -and $Context.Configuration.Settings.ProviderMode) {
        $providerMode = $Context.Configuration.Settings.ProviderMode
    }

    if ($providerMode -eq 'Mock') {
        Initialize-HybridMockProvider -Context $Context | Out-Null
    }

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
