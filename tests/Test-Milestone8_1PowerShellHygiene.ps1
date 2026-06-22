Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$root = Split-Path -Parent $PSScriptRoot
$uiThemeModule = Join-Path $root 'src\UI\UI.Theme.psm1'
$runtimeUi = Join-Path $root 'src\UI\Start-HybridAdminConsole.ps1'
$hardeningTest = Join-Path $root 'tests\Test-Milestone8_1Hardening.ps1'

Assert-Pass -Condition (Test-Path -LiteralPath $uiThemeModule -PathType Leaf) -Message 'UI theme module exists'
Assert-Pass -Condition (Test-Path -LiteralPath $runtimeUi -PathType Leaf) -Message 'Runtime UI exists'
Assert-Pass -Condition (Test-Path -LiteralPath $hardeningTest -PathType Leaf) -Message 'Hardening test exists'

$themeText = Get-Content -LiteralPath $uiThemeModule -Raw
$uiText = Get-Content -LiteralPath $runtimeUi -Raw
$testText = Get-Content -LiteralPath $hardeningTest -Raw

Assert-Pass -Condition ($themeText -match 'function Set-HybridUiThemeOnXaml') -Message 'Theme XAML command uses approved Set verb'
Assert-Pass -Condition ($themeText -match "'Set-HybridUiThemeOnXaml'") -Message 'Theme module exports approved XAML command'
Assert-Pass -Condition ($themeText -notmatch "'Apply-HybridUiThemeToXaml'") -Message 'Theme module does not export unapproved Apply verb'
Assert-Pass -Condition ($uiText -match 'Set-HybridUiThemeOnXaml') -Message 'Runtime UI calls approved theme XAML command'
Assert-Pass -Condition ($testText -match 'Set-HybridUiThemeOnXaml') -Message 'Hardening test validates approved theme XAML command'

Import-Module $uiThemeModule -Force -WarningAction Stop
$commands = @(Get-Command -Module UI.Theme)
Assert-Pass -Condition ($commands.Name -contains 'Set-HybridUiThemeOnXaml') -Message 'Approved theme XAML command imports successfully'
Assert-Pass -Condition ($commands.Name -notcontains 'Apply-HybridUiThemeToXaml') -Message 'Unapproved theme XAML command is not exported'

$approvedVerbs = @(Get-Verb | Select-Object -ExpandProperty Verb)
$unapproved = @(
    foreach ($command in $commands) {
        $verb = ($command.Name -split '-', 2)[0]
        if ($approvedVerbs -notcontains $verb) { $command.Name }
    }
)
Assert-Pass -Condition ($unapproved.Count -eq 0) -Message 'UI.Theme exports only approved PowerShell verbs'

$theme = Resolve-HybridUiTheme -RepositoryRoot $root -ProfileName 'Simulation'
$sampleXaml = '<Border Background="#0B1220" BorderBrush="#38BDF8" />'
$themedXaml = Set-HybridUiThemeOnXaml -Xaml $sampleXaml -Theme $theme
Assert-Pass -Condition (-not [string]::IsNullOrWhiteSpace($themedXaml)) -Message 'Approved theme XAML command returns themed XAML'

Write-Host 'Milestone 8.1 PowerShell hygiene tests passed.'
