#region Module Information
# Name: UI.Shell
# Purpose: Minimal host shell proving the framework boots.
# Dependencies: Core.Logging recommended; Application.ServiceLocator optional.
# Exports: Show-HybridShell
#endregion

Set-StrictMode -Version Latest

#region Private
function Show-HybridConsoleShell {
    param([object]$Context)
    Write-Host ''
    Write-Host 'Hybrid Administration Platform' -ForegroundColor Cyan
    Write-Host ('Profile: {0}' -f $Context.ProfileName) -ForegroundColor Gray
    Write-Host ('Provider Mode: {0}' -f $Context.Configuration.Settings.ProviderMode) -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Registered services:' -ForegroundColor Yellow
    if (Get-Command Get-HybridServices -ErrorAction SilentlyContinue) {
        Get-HybridServices | Format-Table Name, Provider, Description -AutoSize
    }
}
#endregion

#region Public
function Show-HybridShell {
    <#.SYNOPSIS Displays the initial shell surface.#>
    [CmdletBinding()] param([Parameter(Mandatory=$true)][object]$Context,[switch]$ConsoleOnly)

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        Write-HybridLog -Level Information -Module 'UI.Shell' -Message 'Launching shell.' | Out-Null
    }

    # Milestone 1 intentionally uses a console shell. WPF shell migration starts later.
    Show-HybridConsoleShell -Context $Context
}
#endregion

#region Initialization
Export-ModuleMember -Function Show-HybridShell
#endregion
