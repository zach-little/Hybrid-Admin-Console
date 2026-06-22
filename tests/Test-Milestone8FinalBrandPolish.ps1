Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$iconPath = Join-Path $repoRoot 'assets\icons\HAP_Icon.png'

Assert-Pass -Condition (Test-Path -LiteralPath $uiPath) -Message 'Hybrid Admin Console UI script exists'
Assert-Pass -Condition (Test-Path -LiteralPath $iconPath) -Message 'HAP application icon exists'
Assert-Pass -Condition ((Get-Item -LiteralPath $iconPath).Length -gt 0) -Message 'HAP application icon is not empty'

$ui = Get-Content -LiteralPath $uiPath -Raw

Assert-Pass -Condition (-not $ui.Contains('Icon="assets/icons/HAP_Icon.png"')) -Message 'Window does not declare PNG as XAML application icon'
Assert-Pass -Condition ($ui.Contains('Set-HybridWindowIcon')) -Message 'Window icon is assigned after XAML load'
Assert-Pass -Condition ($ui.Contains('HAP_Icon.ico')) -Message 'Window icon loader references ICO asset'
Assert-Pass -Condition ($ui.Contains('Resolve-HybridBrandAssetPath')) -Message 'Centralized brand asset resolver exists'
Assert-Pass -Condition ($ui.Contains('Set-HybridBrandIcons')) -Message 'Runtime PNG icon loader exists'
Assert-Pass -Condition ($ui.Contains('StartupBrandIcon')) -Message 'Startup header uses application icon'
Assert-Pass -Condition ($ui.Contains('ConsoleBrandIcon')) -Message 'Console header uses application icon'
Assert-Pass -Condition ($ui.Contains('SummaryBrandIcon')) -Message 'Runtime summary uses application icon'
Assert-Pass -Condition ($ui.Contains('assets/icons/HAP_Icon.png')) -Message 'UI references HAP icon asset'

Assert-Pass -Condition ($ui.Contains('Set-HybridLaunchButtonLabel')) -Message 'Launch button label updater exists'
Assert-Pass -Condition ($ui.Contains('Launch $label')) -Message 'Launch button includes selected profile name'
Assert-Pass -Condition ($ui.Contains('ToolTip = "Launch $name"')) -Message 'Launch button tooltip exposes full profile name'
Assert-Pass -Condition ($ui.Contains('MinWidth" Value="132"')) -Message 'Launch button no longer uses oversized minimum width'
Assert-Pass -Condition (-not $ui.Contains('MinWidth" Value="190"')) -Message 'Old oversized launch width removed'

Assert-Pass -Condition ($ui.Contains('DataTemplate.Triggers')) -Message 'Profile card selection trigger exists'
Assert-Pass -Condition ($ui.Contains('DropShadowEffect Color="#38BDF8"')) -Message 'Selected profile card has cyan glow'
Assert-Pass -Condition ($ui.Contains('BorderThickness" Value="3"')) -Message 'Selected profile card has stronger accent border'

Assert-Pass -Condition ($ui.Contains('StatusCloudText')) -Message 'Status bar exposes colorized cloud text'
Assert-Pass -Condition ($ui.Contains('StatusHealthText')) -Message 'Status bar exposes colorized health text'
Assert-Pass -Condition ($ui.Contains('Foreground="#A78BFA"')) -Message 'Cloud/status purple accent exists'
Assert-Pass -Condition ($ui.Contains('Foreground="#22C55E"')) -Message 'Health green accent exists'

foreach ($heading in @('PROFILE','ENVIRONMENT','COMPATIBILITY')) {
    Assert-Pass -Condition ($ui.Contains(('Text="{0}" Foreground="#93C5FD" FontSize="14"' -f $heading))) -Message "Runtime summary heading enlarged: $heading"
}

$match = [regex]::Match($ui, '(?s)\$xaml = @"\r?\n(.*?)\r?\n"@')
Assert-Pass -Condition $match.Success -Message 'XAML block was found'
[xml]$null = $match.Groups[1].Value
Assert-Pass -Condition $true -Message 'Final brand polish XAML is well-formed XML'

Write-Host ''
Write-Host 'Milestone 8 final brand polish tests passed.'
