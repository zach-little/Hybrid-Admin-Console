Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$root = Split-Path -Parent $PSScriptRoot
$themeModule = Join-Path $root 'src\UI\UI.Theme.psm1'
Import-Module $themeModule -Force -WarningAction SilentlyContinue
$commands = @(Get-Command -Module UI.Theme | Select-Object -ExpandProperty Name)
$approvedVerbs = @(Get-Verb | Select-Object -ExpandProperty Verb)
$nonApproved = @($commands | Where-Object { ($_.Split('-')[0]) -notin $approvedVerbs })
Assert-Pass -Condition ($nonApproved.Count -eq 0) -Message 'UI.Theme exports only approved PowerShell verbs'
Assert-Pass -Condition ($commands -contains 'Set-HybridUiThemeToXaml') -Message 'Theme XAML application uses approved Set verb'
Assert-Pass -Condition ($commands -notcontains 'Apply-HybridUiThemeToXaml') -Message 'Legacy unapproved Apply verb is not exported'

Write-Host 'Milestone 8.1 PowerShell hygiene tests passed.'
