Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$root = Split-Path -Parent $PSScriptRoot
$ui = Join-Path $root 'src\UI\Start-HybridAdminConsole.ps1'
$themeModule = Join-Path $root 'src\UI\UI.Theme.psm1'
$runtimeModule = Join-Path $root 'src\Core\Core.Runtime.psm1'
$profileManagerModule = Join-Path $root 'src\Application\Application.RuntimeProfileManager.psm1'
$brandExample = Join-Path $root 'assets\themes\hap.brand-package.example.json'

Assert-Pass -Condition (Test-Path $ui) -Message 'Runtime UI exists'
Assert-Pass -Condition (Test-Path $themeModule) -Message 'Theme module exists'
Assert-Pass -Condition (Test-Path $brandExample) -Message 'Brand package example exists'

$uiText = Get-Content -LiteralPath $ui -Raw
Assert-Pass -Condition ($uiText -match 'ManageRuntimeThemeButton') -Message 'Runtime Home exposes Branding & Theme action'
Assert-Pass -Condition ($uiText -match 'RuntimeThemeEditorView') -Message 'Runtime UI includes theme editor overlay'
Assert-Pass -Condition ($uiText -match 'ThemeAccentColorTextBox') -Message 'Theme editor exposes accent color'
Assert-Pass -Condition ($uiText -match 'ThemeBackgroundColorTextBox') -Message 'Theme editor exposes background color'
Assert-Pass -Condition ($uiText -match 'ThemeLogoPathTextBox') -Message 'Theme editor exposes logo path'
Assert-Pass -Condition ($uiText -match 'ThemeIconPathTextBox') -Message 'Theme editor exposes icon path'
Assert-Pass -Condition ($uiText -match 'ThemePreviewWindow') -Message 'Theme editor includes live preview surface'
Assert-Pass -Condition ($uiText -match 'Save-HybridRuntimeThemePackage') -Message 'Runtime UI can save brand package themes'
Assert-Pass -Condition ($uiText -match 'New-HybridUiBrandPackage') -Message 'Runtime UI delegates brand package creation to theme module'
Assert-Pass -Condition ($uiText -match 'Set-HybridUiThemeToXaml') -Message 'Runtime UI applies resolved theme to XAML with approved verb'
Assert-Pass -Condition ($uiText -notmatch 'Apply-HybridUiThemeToXaml') -Message 'Runtime UI no longer references unapproved Apply verb'

$themeText = Get-Content -LiteralPath $themeModule -Raw
Assert-Pass -Condition ($themeText -match 'Get-HybridUiBrandingPackagePath') -Message 'Theme module resolves profile brand package paths'
Assert-Pass -Condition ($themeText -match 'New-HybridUiBrandPackage') -Message 'Theme module can create brand packages'
Assert-Pass -Condition ($themeText -match 'BrandingPackagePath') -Message 'Theme model tracks package path'
Assert-Pass -Condition ($themeText -match 'WindowTitle') -Message 'Theme model exposes window title'
Assert-Pass -Condition ($themeText -match 'SplashPath') -Message 'Theme model exposes splash path'
Assert-Pass -Condition ($themeText -match 'profiles''?\s*\$safeOrg') -Message 'Theme module stores packages under profile organization folder'

Assert-Pass -Condition ((Get-Content -LiteralPath $runtimeModule -Raw) -match "Version = 'v0.8.3'") -Message 'Runtime context reports AD readiness hotfix version'
Assert-Pass -Condition ((Get-Content -LiteralPath $profileManagerModule -Raw) -match "v0.8.3") -Message 'Runtime profile manager reports AD readiness hotfix version'

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('hap-theme-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -Path (Join-Path $testRoot 'profiles\Runtime') -ItemType Directory -Force | Out-Null
@{
    ProfileName = 'Atlas'
    Organization = 'Atlas'
    CloudEnvironment = 'GCCHigh'
    RuntimeMode = 'Simulation'
    Branding = @{ Package = 'Branding' }
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $testRoot 'profiles\Runtime\Atlas.json') -Encoding UTF8

Import-Module $themeModule -Force -WarningAction SilentlyContinue
$package = New-HybridUiBrandPackage -RepositoryRoot $testRoot -OrganizationName 'Atlas' -PackageName 'Branding' -Theme ([pscustomobject]@{
    Name = 'Atlas Test'
    WindowTitle = 'Atlas HAP'
    AccentColor = '#112233'
    BackgroundColor = '#010203'
    SurfaceColor = '#111111'
    PanelColor = '#222222'
    BorderColor = '#333333'
    ForegroundColor = '#FFFFFF'
    TextColor = '#EEEEEE'
    MutedTextColor = '#999999'
})
Assert-Pass -Condition (Test-Path $package.ThemePath) -Message 'Brand package writes theme.json'
$theme = Resolve-HybridUiTheme -RepositoryRoot $testRoot -ProfileName 'Atlas'
Assert-Pass -Condition ($theme.AccentColor -eq '#112233') -Message 'Runtime profile resolves brand package accent color'
Assert-Pass -Condition ($theme.WindowTitle -eq 'Atlas HAP') -Message 'Runtime profile resolves brand package window title'
$themedXaml = Set-HybridUiThemeToXaml -Xaml '<Window Title="Hybrid Admin Platform"><Border Background="#0B1220" BorderBrush="#38BDF8" /></Window>' -Theme $theme
Assert-Pass -Condition ($themedXaml -match '#112233') -Message 'Theme token replacement applies brand package colors'
Assert-Pass -Condition ($themedXaml -match 'Atlas HAP') -Message 'Theme token replacement applies window title'

Remove-Item -LiteralPath $testRoot -Recurse -Force
Write-Host 'Milestone 8.2 branding and theme system tests passed.'
