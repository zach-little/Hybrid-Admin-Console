#region Module Information
# Name: Application.ServiceLocator
# Purpose: Application-level service initialization and access helpers.
# Dependencies: Core.ServiceRegistry, Infrastructure.Mock optional, Application.UserService or Application.HybridUserService.
# Exports: Initialize-HybridApplicationServices, Invoke-HybridDirectorySearch
#endregion

Set-StrictMode -Version Latest

#region Private
function Get-HybridProviderMode {
    param([Parameter(Mandatory=$true)][object]$Context)

    $providerMode = 'Mock'
    if ($Context.PSObject.Properties['Configuration'] -and
        $Context.Configuration -and
        $Context.Configuration.PSObject.Properties['Settings'] -and
        $Context.Configuration.Settings -and
        $Context.Configuration.Settings.PSObject.Properties['ProviderMode'] -and
        $Context.Configuration.Settings.ProviderMode) {
        $providerMode = $Context.Configuration.Settings.ProviderMode
    }

    return $providerMode
}

function Initialize-HybridUserServiceCompat {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Context)

    $command = Get-Command Initialize-HybridUserService -ErrorAction Stop

    if ($command.Parameters.ContainsKey('Context')) {
        Initialize-HybridUserService -Context $Context | Out-Null
        return
    }

    # Milestone 7+ composite service initializer accepts provider objects instead of the old Context parameter.
    Initialize-HybridUserService | Out-Null
}
#endregion

#region Public
function Initialize-HybridApplicationServices {
    <#.SYNOPSIS Initializes application service bindings for the active profile.#>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Context)

    $providerMode = Get-HybridProviderMode -Context $Context

    if ($providerMode -eq 'Mock' -and (Get-Command Initialize-HybridMockProvider -ErrorAction SilentlyContinue)) {
        Initialize-HybridMockProvider -Context $Context | Out-Null
    }
    elseif ($providerMode -eq 'Mock') {
        if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
            Write-HybridLog -Level Warning -Module 'Application.ServiceLocator' -Message 'Mock provider initializer was not loaded; continuing with existing service registrations.' | Out-Null
        }
    }
    else {
        throw "Provider mode '$providerMode' is not implemented in the legacy service locator path. Runtime Profiles should use the runtime bootstrap provider path."
    }

    Initialize-HybridUserServiceCompat -Context $Context

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        Write-HybridLog -Level Information -Module 'Application.ServiceLocator' -Message "Application services initialized using provider mode '$providerMode'." | Out-Null
    }
}

function Invoke-HybridDirectorySearch {
    <#.SYNOPSIS Searches users through the registered directory service.#>
    [CmdletBinding()]
    param([string]$Query='')

    $service = Get-HybridService -Name 'Directory'
    return & $service.SearchUser $Query
}
#endregion

#region Initialization
Export-ModuleMember -Function Initialize-HybridApplicationServices, Invoke-HybridDirectorySearch
#endregion
