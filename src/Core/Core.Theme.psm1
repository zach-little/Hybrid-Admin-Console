#region Module Information
# Name: Core.Theme
# Purpose: Profile-driven theme loading for UI components.
# Dependencies: Core.Configuration recommended.
# Exports: Initialize-HybridTheme, Get-HybridTheme
#endregion

Set-StrictMode -Version Latest
$script:State = @{ Theme = $null }

#region Private

function Get-HybridThemeBrandingValue {
    param(
        [AllowNull()][object]$Branding,
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if ($null -ne $Branding -and $Branding.PSObject.Properties.Name -contains $Name) {
        $value = $Branding.$Name
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return $value }
    }

    return $Default
}
#endregion

#region Public
function Initialize-HybridTheme {
    <#.SYNOPSIS Initializes theme settings from the active profile branding file.#>
    [CmdletBinding()] param([Parameter(Mandatory=$true)][object]$Context)
    $branding = if ($Context.Configuration) { $Context.Configuration.Branding } else { $null }
    $theme = [pscustomobject]@{
        PSTypeName = 'Hybrid.Theme'
        Name          = Get-HybridThemeBrandingValue -Branding $branding -Name 'ThemeName' -Default 'Default Dark'
        Accent        = Get-HybridThemeBrandingValue -Branding $branding -Name 'AccentColor' -Default '#20D5FF'
        AccentColor   = Get-HybridThemeBrandingValue -Branding $branding -Name 'AccentColor' -Default '#20D5FF'
        Background    = Get-HybridThemeBrandingValue -Branding $branding -Name 'BackgroundColor' -Default '#0B1220'
        BackgroundColor = Get-HybridThemeBrandingValue -Branding $branding -Name 'BackgroundColor' -Default '#0B1220'
        Foreground    = Get-HybridThemeBrandingValue -Branding $branding -Name 'ForegroundColor' -Default '#F4F7FB'
        ForegroundColor = Get-HybridThemeBrandingValue -Branding $branding -Name 'ForegroundColor' -Default '#F4F7FB'
        SurfaceColor  = Get-HybridThemeBrandingValue -Branding $branding -Name 'SurfaceColor' -Default '#111827'
        PanelColor    = Get-HybridThemeBrandingValue -Branding $branding -Name 'PanelColor' -Default '#0F172A'
        BorderColor   = Get-HybridThemeBrandingValue -Branding $branding -Name 'BorderColor' -Default '#26364F'
        LogoPath      = Get-HybridThemeBrandingValue -Branding $branding -Name 'LogoPath' -Default $null
        IconPath      = Get-HybridThemeBrandingValue -Branding $branding -Name 'IconPath' -Default $null
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
