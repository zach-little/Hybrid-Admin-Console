#region Module Information
# Name: Core.Theme
# Purpose: Profile-driven theme loading for UI components.
# Dependencies: Core.Configuration recommended.
# Exports: Initialize-HybridTheme, Get-HybridTheme
#endregion

Set-StrictMode -Version Latest
$script:State = @{ Theme = $null }

#region Private
#endregion

#region Public
function Initialize-HybridTheme {
    <#.SYNOPSIS Initializes theme settings from the active profile branding file.#>
    [CmdletBinding()] param([Parameter(Mandatory=$true)][object]$Context)
    $branding = if ($Context.Configuration) { $Context.Configuration.Branding } else { $null }
    $theme = [pscustomobject]@{
        PSTypeName = 'Hybrid.Theme'
        Name       = if ($branding -and $branding.ThemeName) { $branding.ThemeName } else { 'Default Dark' }
        Accent     = if ($branding -and $branding.AccentColor) { $branding.AccentColor } else { '#20D5FF' }
        Background = if ($branding -and $branding.BackgroundColor) { $branding.BackgroundColor } else { '#0B1220' }
        Foreground = if ($branding -and $branding.ForegroundColor) { $branding.ForegroundColor } else { '#F4F7FB' }
        LogoPath   = if ($branding -and $branding.LogoPath) { $branding.LogoPath } else { $null }
    }
    $script:State.Theme = $theme
    $Context.Theme = $theme
    return $theme
}
function Get-HybridTheme {
    <#.SYNOPSIS Returns current theme settings.#>
    [CmdletBinding()] param()
    if (-not $script:State.Theme) { throw 'Theme has not been initialized.' }
    return $script:State.Theme
}
#endregion

#region Initialization
Export-ModuleMember -Function Initialize-HybridTheme, Get-HybridTheme
#endregion
