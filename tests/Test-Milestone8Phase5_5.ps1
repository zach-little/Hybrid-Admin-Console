[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
Assert-Pass -Condition (Test-Path $uiPath) -Message 'Hybrid Admin Console UI script exists'

$content = Get-Content -LiteralPath $uiPath -Raw
Assert-Pass -Condition ($content -match 'ShellRoot') -Message 'Shell root region exists'
Assert-Pass -Condition ($content -match 'StartupRegion') -Message 'Startup region exists'
Assert-Pass -Condition ($content -match 'MainRegion') -Message 'Main region exists'
Assert-Pass -Condition ($content -match 'StatusBarRegion') -Message 'Status bar region exists'
Assert-Pass -Condition ($content -match 'OverlayRegion') -Message 'Overlay region exists'
Assert-Pass -Condition ($content -match 'OverlayHost') -Message 'Overlay host placeholder exists'
Assert-Pass -Condition ($content -match 'MainDashboardGrid') -Message 'Dashboard foundation grid exists'
Assert-Pass -Condition ($content -match 'UserIdentityColumn') -Message 'User identity dashboard column exists'
Assert-Pass -Condition ($content -match 'OperationsColumn') -Message 'Operations dashboard column exists'
Assert-Pass -Condition ($content -match 'RuntimeColumn') -Message 'Runtime dashboard column exists'
Assert-Pass -Condition ($content -match 'Directory Facts') -Message 'Directory facts section replaces raw AD section label'
Assert-Pass -Condition ($content -match 'Search drives all dashboard cards') -Message 'Search behavior is described in dashboard layout'
Assert-Pass -Condition ($content -match 'Dashboard layout foundation') -Message 'Phase 5.5 dashboard marker exists'

foreach ($name in @(
    'StartupView','ConsoleView','LaunchConsoleButton','EditRuntimeProfileButton','ExitButton',
    'SearchBox','SearchButton','ResultHeader','StatusText','DisplayNameText','UpnText','SamText',
    'ExchangeMailboxCard','AggregationStatusCard','MicrosoftGraphCard','AuthenticationPostureCard',
    'GroupsList','DirectReportsList','MailboxDelegationList','DistributionGroupsList','AuthMethodsList'
)) {
    Assert-Pass -Condition ($content -match [regex]::Escape($name)) -Message "Existing UI control retained: $name"
}

$windowCount = ([regex]::Matches($content, '<Window ')).Count
Assert-Pass -Condition ($windowCount -eq 1) -Message 'Layout foundation still uses a single WPF window'
Assert-Pass -Condition ($content -match 'ConsoleView" Margin="22" Visibility="Collapsed"') -Message 'Console remains hidden until launch'
Assert-Pass -Condition ($content -match 'Show-HybridConsoleView') -Message 'Launch transition remains intact'
Assert-Pass -Condition ($content -match 'Update-HybridStartupView') -Message 'Startup runtime binding remains intact'
Assert-Pass -Condition ($content -notmatch 'Start-Sleep') -Message 'Layout foundation does not introduce blocking delays'

$xamlMatch = [regex]::Match($content, '(?s)\$xaml = @"(?<xaml>.*?)"@')
Assert-Pass -Condition ($xamlMatch.Success) -Message 'XAML block was found'
[xml]$null = $xamlMatch.Groups['xaml'].Value
Assert-Pass -Condition $true -Message 'Layout foundation XAML is well-formed XML'

Write-Host "`nMilestone 8 Phase 5.5 shell and dashboard layout foundation tests passed."
