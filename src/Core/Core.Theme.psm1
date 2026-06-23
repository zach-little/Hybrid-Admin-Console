#region Module Information
# Name: Core.Theme
# Purpose: Profile-driven theme loading for UI components.
# Dependencies: Core.Configuration recommended.
# Exports: Initialize-HybridTheme, Get-HybridTheme
#endregion

Set-StrictMode -Version Latest
$script:State = @{ Theme = $null }

#region Private
function Get-HybridThemePropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    if ($null -eq $property.Value) { return $Default }

    return $property.Value
}
#endregion

#region Public
function Initialize-HybridTheme {
    <#.SYNOPSIS Initializes theme settings from the active profile branding file.#>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Context)

    $configuration = Get-HybridThemePropertyValue -InputObject $Context -Name 'Configuration'
    $branding = Get-HybridThemePropertyValue -InputObject $configuration -Name 'Branding'

    $theme = [pscustomobject]@{
        PSTypeName       = 'Hybrid.Theme'
        Name             = Get-HybridThemePropertyValue -InputObject $branding -Name 'ThemeName' -Default 'Default Dark'
        Accent           = Get-HybridThemePropertyValue -InputObject $branding -Name 'AccentColor' -Default '#20D5FF'
        AccentColor      = Get-HybridThemePropertyValue -InputObject $branding -Name 'AccentColor' -Default '#20D5FF'
        Background       = Get-HybridThemePropertyValue -InputObject $branding -Name 'BackgroundColor' -Default '#0B1220'
        BackgroundColor  = Get-HybridThemePropertyValue -InputObject $branding -Name 'BackgroundColor' -Default '#0B1220'
        Foreground       = Get-HybridThemePropertyValue -InputObject $branding -Name 'ForegroundColor' -Default '#F4F7FB'
        ForegroundColor  = Get-HybridThemePropertyValue -InputObject $branding -Name 'ForegroundColor' -Default '#F4F7FB'
        SurfaceColor     = Get-HybridThemePropertyValue -InputObject $branding -Name 'SurfaceColor' -Default '#111827'
        PanelColor       = Get-HybridThemePropertyValue -InputObject $branding -Name 'PanelColor' -Default '#0F172A'
        BorderColor      = Get-HybridThemePropertyValue -InputObject $branding -Name 'BorderColor' -Default '#26364F'
        LogoPath         = Get-HybridThemePropertyValue -InputObject $branding -Name 'LogoPath'
        IconPath         = Get-HybridThemePropertyValue -InputObject $branding -Name 'IconPath'
    }

    $script:State.Theme = $theme

    if ($Context.PSObject.Properties['Theme']) {
        $Context.Theme = $theme
    }
    else {
        Add-Member -InputObject $Context -MemberType NoteProperty -Name 'Theme' -Value $theme -Force
    }

    return $theme
}

function Get-HybridTheme {
    <#.SYNOPSIS Returns current theme settings.#>
    [CmdletBinding()]
    param()

    if (-not $script:State.Theme) { throw 'Theme has not been initialized.' }
    return $script:State.Theme
}
#endregion

#region Initialization
Export-ModuleMember -Function Initialize-HybridTheme, Get-HybridTheme
#endregion
