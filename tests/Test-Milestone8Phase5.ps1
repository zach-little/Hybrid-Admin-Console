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
Assert-Pass -Condition ($content -match 'Initialize-HybridRuntime') -Message 'UI initializes through runtime bootstrap'
Assert-Pass -Condition ($content -match 'StartupView') -Message 'Startup shell view is present'
Assert-Pass -Condition ($content -match 'ConsoleView') -Message 'Console shell view is present'
Assert-Pass -Condition ($content -match 'LaunchConsoleButton') -Message 'Launch console button is present'
Assert-Pass -Condition ($content -match 'EditRuntimeProfileButton') -Message 'Runtime profile edit placeholder is present'
Assert-Pass -Condition ($content -match 'IsEnabled="False"') -Message 'Runtime profile edit button is disabled until Phase 6'
Assert-Pass -Condition ($content -match 'RuntimeProviderSummaryText') -Message 'Provider summary is displayed on start screen'
Assert-Pass -Condition ($content -match 'RuntimeDiagnosticsText') -Message 'Diagnostics summary is displayed on start screen'
Assert-Pass -Condition ($content -match 'Show-HybridConsoleView') -Message 'Launch transition function exists'
Assert-Pass -Condition ($content -match 'ConsoleView" Margin="22" Visibility="Collapsed"') -Message 'Main console is hidden until launch'
Assert-Pass -Condition ($content -match 'Update-HybridStartupView') -Message 'Startup view runtime binding function exists'
Assert-Pass -Condition ($content -notmatch 'Start-Sleep') -Message 'Start screen does not use blocking splash delays'

$windowCount = ([regex]::Matches($content, '<Window ')).Count
Assert-Pass -Condition ($windowCount -eq 1) -Message 'Startup shell uses a single WPF window'

$xamlMatch = [regex]::Match($content, '(?s)\$xaml = @"(?<xaml>.*?)"@')
Assert-Pass -Condition ($xamlMatch.Success) -Message 'XAML block was found'
[xml]$null = $xamlMatch.Groups['xaml'].Value
Assert-Pass -Condition $true -Message 'Startup shell XAML is well-formed XML'

$runtimeModule = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'
Assert-Pass -Condition (Test-Path $runtimeModule) -Message 'Runtime module exists for startup shell'

Import-Module $runtimeModule -Force
$runtime = Initialize-HybridRuntime -ProfileName 'Simulation' -RootPath $repoRoot -Force
Assert-Pass -Condition ($null -ne $runtime) -Message 'Runtime initializes for startup shell'
Assert-Pass -Condition ($runtime.PSTypeName -eq 'Hybrid.RuntimeContext') -Message 'Runtime context type is available to startup shell'
Assert-Pass -Condition ($null -ne $runtime.Diagnostics) -Message 'Runtime diagnostics are available to startup shell'
Assert-Pass -Condition ($null -ne $runtime.ProviderRegistry) -Message 'Runtime provider registry is available to startup shell'

Write-Host "`nMilestone 8 Phase 5 startup shell tests passed."
