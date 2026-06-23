Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$root = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $root 'Start-AtlasHybridAdminConsole.ps1'
$ui = Join-Path $root 'src\UI\Start-HybridAdminConsole.ps1'
$themeModule = Join-Path $root 'src\UI\UI.Theme.psm1'
$launchModule = Join-Path $root 'src\UI\UI.RuntimeLaunch.psm1'
$profileModule = Join-Path $root 'src\UI\UI.RuntimeProfileManager.psm1'
$homeModule = Join-Path $root 'src\UI\UI.RuntimeHome.psm1'
$wizardModule = Join-Path $root 'src\UI\UI.RuntimeProfileWizard.psm1'
$dashboardModule = Join-Path $root 'src\UI\UI.UserDashboard.psm1'
$statusModule = Join-Path $root 'src\UI\UI.StatusBar.psm1'
$coreThemeModule = Join-Path $root 'src\Core\Core.Theme.psm1'
$runtimeModule = Join-Path $root 'src\Core\Core.Runtime.psm1'
$profileManagerModule = Join-Path $root 'src\Application\Application.RuntimeProfileManager.psm1'

Assert-Pass -Condition (Test-Path $launcher) -Message 'Root HAP launcher exists'
Assert-Pass -Condition (Test-Path $ui) -Message 'Runtime WPF UI entry point exists'

$launcherText = Get-Content -LiteralPath $launcher -Raw
Assert-Pass -Condition ($launcherText -match 'src\\UI\\Start-HybridAdminConsole\.ps1') -Message 'Root launcher targets runtime/profile WPF entry point'
Assert-Pass -Condition ($launcherText -notmatch 'Show-HybridShell') -Message 'Root launcher no longer enters legacy shell directly'
Assert-Pass -Condition ($launcherText -match '-STA') -Message 'Root launcher preserves STA startup for WPF'

$uiText = Get-Content -LiteralPath $ui -Raw
Assert-Pass -Condition ($uiText -match '\[string\]\$Profile') -Message 'Runtime UI accepts explicit profile parameter'
Assert-Pass -Condition ($uiText -match 'UI\.Theme\.psm1') -Message 'Runtime UI imports theme module'
Assert-Pass -Condition ($uiText -match 'UI\.RuntimeHome\.psm1') -Message 'Runtime UI imports runtime home module'
Assert-Pass -Condition ($uiText -match 'UI\.RuntimeLaunch\.psm1') -Message 'Runtime UI imports launch module'
Assert-Pass -Condition ($uiText -match 'UI\.RuntimeProfileManager\.psm1') -Message 'Runtime UI imports profile manager UI module'
Assert-Pass -Condition ($uiText -match 'UI\.RuntimeProfileWizard\.psm1') -Message 'Runtime UI imports profile wizard module'
Assert-Pass -Condition ($uiText -match 'UI\.UserDashboard\.psm1') -Message 'Runtime UI imports dashboard helper module'
Assert-Pass -Condition ($uiText -match 'UI\.StatusBar\.psm1') -Message 'Runtime UI imports status bar helper module'
Assert-Pass -Condition ($uiText -match 'Set-HybridUiThemeToXaml') -Message 'Runtime UI sets resolved theme on XAML before load'
Assert-Pass -Condition ($uiText -match 'Height="900"') -Message 'Runtime UI default height reduced for safer display fit'
Assert-Pass -Condition ($uiText -match 'Width="1480"') -Message 'Runtime UI default width reduced for safer display fit'
Assert-Pass -Condition ($uiText -match 'MinHeight="720"') -Message 'Runtime UI minimum height relaxed for RDP and smaller screens'
Assert-Pass -Condition ($uiText -match 'MinWidth="1180"') -Message 'Runtime UI minimum width relaxed for RDP and smaller screens'
Assert-Pass -Condition ($uiText -match 'HorizontalScrollBarVisibility="Auto"') -Message 'Runtime action footer supports horizontal overflow'
Assert-Pass -Condition ($uiText -match '<WrapPanel HorizontalAlignment="Left">') -Message 'Runtime action footer wraps command tiles'
Assert-Pass -Condition ($uiText -match 'TextWrapping="Wrap" MaxWidth="118"') -Message 'Launch button text wraps long profile names'
Assert-Pass -Condition ($uiText -notmatch 'Substring\(0,19\)') -Message 'Launch button no longer truncates profile name'
Assert-Pass -Condition ($uiText -match 'Set-HybridLaunchButtonProfileLabel') -Message 'Launch button behavior moved behind UI launch helper'

foreach ($module in @($themeModule,$launchModule,$profileModule,$homeModule,$wizardModule,$dashboardModule,$statusModule)) {
    Assert-Pass -Condition (Test-Path $module) -Message "UI module exists: $([IO.Path]::GetFileName($module))"
}

$themeText = Get-Content -LiteralPath $themeModule -Raw
Assert-Pass -Condition ($themeText -match 'Resolve-HybridUiTheme') -Message 'Theme module exports runtime theme resolver'
Assert-Pass -Condition ($themeText -match 'RuntimeProfile\.Branding') -Message 'Theme module supports runtime profile branding overrides'
Assert-Pass -Condition ($themeText -match 'profiles\\\{0\}\\branding\.json') -Message 'Theme module supports organization branding files'
Assert-Pass -Condition ($themeText -match 'assets\\themes\\hap\.theme\.json') -Message 'Theme module supports repository-level theme override'
Assert-Pass -Condition ($themeText -match 'Set-HybridUiThemeToXaml') -Message 'Theme module can set theme tokens on XAML'
Assert-Pass -Condition (Test-Path (Join-Path $root 'assets\themes\hap.theme.example.json')) -Message 'Theme example file exists'

$coreThemeText = Get-Content -LiteralPath $coreThemeModule -Raw
Assert-Pass -Condition ($coreThemeText -match 'SurfaceColor') -Message 'Core theme model exposes surface color'
Assert-Pass -Condition ($coreThemeText -match 'PanelColor') -Message 'Core theme model exposes panel color'
Assert-Pass -Condition ($coreThemeText -match 'BorderColor') -Message 'Core theme model exposes border color'

Assert-Pass -Condition ((Get-Content -LiteralPath $runtimeModule -Raw) -match "Version = 'v0.8.3'") -Message 'Runtime context reports AD readiness hotfix version'
Assert-Pass -Condition ((Get-Content -LiteralPath $profileManagerModule -Raw) -match "v0.8.3") -Message 'Runtime profile manager reports AD readiness hotfix version'

Import-Module $themeModule -Force
$theme = Resolve-HybridUiTheme -RepositoryRoot $root -ProfileName 'Simulation'
Assert-Pass -Condition ($theme.PSTypeName -eq 'Hybrid.UI.Theme') -Message 'Resolved UI theme has expected type name'
Assert-Pass -Condition (-not [string]::IsNullOrWhiteSpace($theme.AccentColor)) -Message 'Resolved UI theme includes accent color'
Assert-Pass -Condition (-not [string]::IsNullOrWhiteSpace($theme.BackgroundColor)) -Message 'Resolved UI theme includes background color'
$sampleXaml = '<Border Background="#0B1220" BorderBrush="#38BDF8" />'
$themedXaml = Set-HybridUiThemeToXaml -Xaml $sampleXaml -Theme $theme
Assert-Pass -Condition ($themedXaml -notmatch '#38BDF8' -or $theme.AccentColor -eq '#38BDF8') -Message 'Theme token application is functional'

Import-Module $profileManagerModule -Force
$profiles = @(Get-HybridRuntimeProfileSummary -RepositoryRoot $root)
Assert-Pass -Condition ($profiles.Count -gt 0) -Message 'Runtime profiles are discoverable'
$selected = Get-HybridRuntimeProfileSelection -RepositoryRoot $root
Assert-Pass -Condition ($null -ne $selected) -Message 'Runtime profile selection resolves'

Write-Host 'Milestone 8.1 runtime hardening tests passed.'
