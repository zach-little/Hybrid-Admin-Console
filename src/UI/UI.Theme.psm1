Set-StrictMode -Version Latest

function New-HybridUiThemeObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Properties)

    $typeName = 'Hybrid.UI.Theme'
    if ($Properties.ContainsKey('PSTypeName') -and -not [string]::IsNullOrWhiteSpace([string]$Properties.PSTypeName)) {
        $typeName = [string]$Properties.PSTypeName
    }

    $objectProperties = [ordered]@{}
    foreach ($key in $Properties.Keys) {
        if ($key -eq 'PSTypeName') { continue }
        $objectProperties[$key] = $Properties[$key]
    }

    $theme = [pscustomobject]$objectProperties
    $theme.PSObject.TypeNames.Insert(0, $typeName)
    $theme | Add-Member -MemberType NoteProperty -Name 'PSTypeName' -Value $typeName -Force
    return $theme
}

function Get-HybridUiThemeDefault {
    [CmdletBinding()]
    param()

    return New-HybridUiThemeObject -Properties @{
        PSTypeName              = 'Hybrid.UI.Theme'
        Name                    = 'HAP Dark'
        AccentColor             = '#38BDF8'
        AccentMutedColor        = '#0F2A44'
        BackgroundColor         = '#0B1220'
        BackgroundAltColor      = '#08111E'
        SurfaceColor            = '#111827'
        SurfaceAltColor         = '#152033'
        PanelColor              = '#0F172A'
        BorderColor             = '#26364F'
        BorderActiveColor       = '#38BDF8'
        ForegroundColor         = '#F8FAFC'
        TextColor               = '#E5E7EB'
        MutedTextColor          = '#94A3B8'
        SubtleTextColor         = '#CBD5E1'
        SuccessColor            = '#22C55E'
        SuccessMutedColor       = '#14532D'
        WarningColor            = '#FACC15'
        WarningMutedColor       = '#713F12'
        ErrorColor              = '#F87171'
        PurpleColor             = '#C084FC'
        PurpleMutedColor        = '#312E81'
        LogoPath                = $null
        IconPath                = $null
        Source                  = 'Default'
    }
}

function Merge-HybridUiThemeObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$BaseTheme,
        [AllowNull()][object]$Override,
        [string]$Source = 'Override'
    )

    if ($null -eq $Override) { return $BaseTheme }

    $theme = $BaseTheme.PSObject.Copy()
    foreach ($property in $Override.PSObject.Properties) {
        if ($null -eq $property.Value) { continue }
        if ([string]::IsNullOrWhiteSpace([string]$property.Value)) { continue }

        $targetName = switch -Regex ($property.Name) {
            '^ThemeName$' { 'Name'; break }
            '^Accent$' { 'AccentColor'; break }
            '^Background$' { 'BackgroundColor'; break }
            '^Foreground$' { 'ForegroundColor'; break }
            default { $property.Name; break }
        }

        if ($theme.PSObject.Properties.Match($targetName).Count -gt 0) {
            $theme.$targetName = $property.Value
        }
        else {
            $theme | Add-Member -MemberType NoteProperty -Name $targetName -Value $property.Value -Force
        }
    }

    $theme.Source = $Source
    if ($theme.PSObject.Properties.Match('PSTypeName').Count -eq 0) {
        $theme | Add-Member -MemberType NoteProperty -Name 'PSTypeName' -Value 'Hybrid.UI.Theme' -Force
    }
    if ($theme.PSObject.TypeNames[0] -ne 'Hybrid.UI.Theme') {
        $theme.PSObject.TypeNames.Insert(0, 'Hybrid.UI.Theme')
    }
    return $theme
}

function Import-HybridUiThemeJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Verbose "Unable to read UI theme file '$Path': $($_.Exception.Message)"
        return $null
    }
}

function Resolve-HybridUiTheme {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot = (Get-Location).Path,
        [string]$ProfileName = '',
        [string]$ProfilePath = ''
    )

    $root = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { (Get-Location).Path } else { (Resolve-Path -Path $RepositoryRoot).Path }
    $theme = Get-HybridUiThemeDefault

    $runtimeProfile = $null
    if (-not [string]::IsNullOrWhiteSpace($ProfilePath) -and (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
        $runtimeProfile = Import-HybridUiThemeJson -Path $ProfilePath
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ProfileName)) {
        $candidate = Join-Path $root ('profiles\Runtime\{0}.json' -f (($ProfileName -replace '[\\/:*?"<>|]', '-')))
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $runtimeProfile = Import-HybridUiThemeJson -Path $candidate }
    }

    if ($null -ne $runtimeProfile) {
        $brandingProperty = $runtimeProfile.PSObject.Properties['Branding']
        $themeProperty = $runtimeProfile.PSObject.Properties['Theme']
        if ($null -ne $brandingProperty) { $theme = Merge-HybridUiThemeObject -BaseTheme $theme -Override $brandingProperty.Value -Source 'RuntimeProfile.Branding' }
        elseif ($null -ne $themeProperty) { $theme = Merge-HybridUiThemeObject -BaseTheme $theme -Override $themeProperty.Value -Source 'RuntimeProfile.Theme' }

        $org = $runtimeProfile.PSObject.Properties['Organization']
        if ($null -ne $org -and -not [string]::IsNullOrWhiteSpace([string]$org.Value)) {
            $orgBranding = Join-Path $root ('profiles\{0}\branding.json' -f ([string]$org.Value))
            $orgTheme = Import-HybridUiThemeJson -Path $orgBranding
            if ($null -ne $orgTheme) { $theme = Merge-HybridUiThemeObject -BaseTheme $theme -Override $orgTheme -Source "Organization.Branding:$($org.Value)" }
        }
    }

    $globalThemePath = Join-Path $root 'assets\themes\hap.theme.json'
    $globalTheme = Import-HybridUiThemeJson -Path $globalThemePath
    if ($null -ne $globalTheme) { $theme = Merge-HybridUiThemeObject -BaseTheme $theme -Override $globalTheme -Source 'assets/themes/hap.theme.json' }

    return $theme
}

function ConvertTo-HybridUiThemeTokenMap {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Theme)

    return @{
        '#38BDF8' = [string]$Theme.AccentColor
        '#20D5FF' = [string]$Theme.AccentColor
        '#0B1220' = [string]$Theme.BackgroundColor
        '#08111E' = [string]$Theme.BackgroundAltColor
        '#101826' = [string]$Theme.PanelColor
        '#111827' = [string]$Theme.SurfaceColor
        '#152033' = [string]$Theme.SurfaceAltColor
        '#0F172A' = [string]$Theme.PanelColor
        '#26364F' = [string]$Theme.BorderColor
        '#2B3A55' = [string]$Theme.BorderColor
        '#F8FAFC' = [string]$Theme.ForegroundColor
        '#F4F7FB' = [string]$Theme.ForegroundColor
        '#E5E7EB' = [string]$Theme.TextColor
        '#94A3B8' = [string]$Theme.MutedTextColor
        '#8EA4C2' = [string]$Theme.MutedTextColor
        '#CBD5E1' = [string]$Theme.SubtleTextColor
        '#22C55E' = [string]$Theme.SuccessColor
        '#14532D' = [string]$Theme.SuccessMutedColor
        '#FACC15' = [string]$Theme.WarningColor
        '#F87171' = [string]$Theme.ErrorColor
        '#C084FC' = [string]$Theme.PurpleColor
        '#312E81' = [string]$Theme.PurpleMutedColor
    }
}

function Set-HybridUiThemeOnXaml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Xaml,
        [Parameter(Mandatory)][object]$Theme
    )

    $result = $Xaml
    $tokens = ConvertTo-HybridUiThemeTokenMap -Theme $Theme
    foreach ($key in ($tokens.Keys | Sort-Object Length -Descending)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$tokens[$key])) {
            $result = $result.Replace($key, [string]$tokens[$key])
        }
    }
    return $result
}


function Apply-HybridUiThemeToXaml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Xaml,
        [Parameter(Mandatory)][object]$Theme
    )

    return Set-HybridUiThemeOnXaml -Xaml $Xaml -Theme $Theme
}

Export-ModuleMember -Function @(
    'Get-HybridUiThemeDefault',
    'Resolve-HybridUiTheme',
    'ConvertTo-HybridUiThemeTokenMap',
    'Set-HybridUiThemeOnXaml'
)
