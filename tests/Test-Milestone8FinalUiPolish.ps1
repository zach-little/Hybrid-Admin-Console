Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
Assert-Pass -Condition (Test-Path $uiPath) -Message 'Hybrid Admin Console UI script exists'

$ui = Get-Content -LiteralPath $uiPath -Raw

Assert-Pass -Condition ($ui -match 'Milestone 8 Final UI Polish') -Message 'Final UI polish marker exists'
Assert-Pass -Condition ($ui -match 'Height="980"') -Message 'Default window height increased for polished Runtime Home'
Assert-Pass -Condition ($ui -match 'Width="1600"') -Message 'Default window width supports polished Runtime Home layout'
Assert-Pass -Condition ($ui -match 'MinHeight="900"') -Message 'Minimum height protects fixed action footer'
Assert-Pass -Condition ($ui -match 'Fixed action footer') -Message 'Fixed action footer marker exists'
Assert-Pass -Condition ($ui -match '<UniformGrid Columns="9"') -Message 'Profile action buttons use single-row uniform footer'
Assert-Pass -Condition ($ui -match 'LaunchActionButton') -Message 'Launch action button style exists'
Assert-Pass -Condition ($ui -match 'RuntimeActionButton') -Message 'Runtime action button style exists'
Assert-Pass -Condition ($ui -match 'PanelBrush') -Message 'Polished panel brush exists'
Assert-Pass -Condition ($ui -match 'ShellBackgroundBrush') -Message 'Polished shell background brush exists'
Assert-Pass -Condition ($ui -match 'RUNTIME SUMMARY') -Message 'Runtime Summary panel header exists'
Assert-Pass -Condition ($ui -match 'BOOTSTRAP PLAN PREVIEW') -Message 'Bootstrap plan preview exists'
Assert-Pass -Condition ($ui -match 'PROVIDERS') -Message 'Provider summary tile exists'
Assert-Pass -Condition ($ui -match 'AUTHENTICATION') -Message 'Authentication summary tile exists'
Assert-Pass -Condition ($ui -match 'RUNTIME HEALTH') -Message 'Runtime health tile exists'
Assert-Pass -Condition ($ui -match 'ScrollViewer\.VerticalScrollBarVisibility="Auto"') -Message 'Profile cards retain scrollable overflow'

foreach ($control in @(
    'RuntimeProfileListBox',
    'RefreshRuntimeProfilesButton',
    'LaunchConsoleButton',
    'NewRuntimeProfileButton',
    'EditRuntimeProfileButton',
    'DuplicateRuntimeProfileButton',
    'DeleteRuntimeProfileButton',
    'ImportRuntimeProfileButton',
    'ExportRuntimeProfileButton',
    'SetDefaultRuntimeProfileButton',
    'ExitButton',
    'RuntimeProfileText',
    'RuntimeCloudText',
    'RuntimeModeText',
    'RuntimeVersionText',
    'RuntimeProviderSummaryText',
    'RuntimeAuthenticationText',
    'RuntimeDiagnosticsText',
    'RuntimeStatusText'
)) {
    Assert-Pass -Condition ($ui -match [regex]::Escape(('x:Name="{0}"' -f $control))) -Message "Required UI control retained: $control"
}

$match = [regex]::Match($ui, '(?s)\$xaml = @"\r?\n(.*?)\r?\n"@')
Assert-Pass -Condition $match.Success -Message 'XAML block was found'
[xml]$null = $match.Groups[1].Value
Assert-Pass -Condition $true -Message 'Final UI polish XAML is well-formed XML'

Write-Host ''
Write-Host 'Milestone 8 final UI polish tests passed.'
