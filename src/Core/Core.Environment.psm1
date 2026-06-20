#region Module Information
# Name: Core.Environment
# Purpose: Runtime environment discovery and validation.
# Dependencies: None
# Exports: Initialize-HybridEnvironment, Test-HybridPowerShellHost
#endregion

Set-StrictMode -Version Latest
$script:State = @{ Environment = $null }

#region Private
#endregion

#region Public
function Test-HybridPowerShellHost {
    <#.SYNOPSIS Returns host compatibility details.#>
    [CmdletBinding()] param()
    [pscustomobject]@{
        PSTypeName        = 'Hybrid.PowerShellHost'
        PSVersion         = $PSVersionTable.PSVersion.ToString()
        PSEdition         = $PSVersionTable.PSEdition
        IsWindows         = if ($PSVersionTable.ContainsKey('Platform')) { $PSVersionTable.Platform -eq 'Win32NT' } else { $true }
        HasPresentation   = $null -ne ([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'PresentationFramework' } | Select-Object -First 1)
    }
}
function Initialize-HybridEnvironment {
    <#.SYNOPSIS Initializes runtime environment details on the context.#>
    [CmdletBinding()] param([Parameter(Mandatory=$true)][object]$Context,[switch]$NoNet)
    $env = [pscustomobject]@{
        PSTypeName = 'Hybrid.Environment'
        Host       = Test-HybridPowerShellHost
        UserName   = [Environment]::UserName
        Machine    = [Environment]::MachineName
        NoNet      = $NoNet.IsPresent
        StartedUtc = [datetime]::UtcNow
    }
    $script:State.Environment = $env
    $Context.Environment = $env
    return $env
}
#endregion

#region Initialization
Export-ModuleMember -Function Initialize-HybridEnvironment, Test-HybridPowerShellHost
#endregion
