$ErrorActionPreference = 'Stop'

function Assert-FileContains {
    param([string]$Path, [string]$Needle, [string]$Message)
    $Content = Get-Content -LiteralPath $Path -Raw
    if ($Content -notlike "*$Needle*") { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$uiPath = Join-Path $PSScriptRoot '..\src\UI\Start-HybridAdminConsole.ps1'

Assert-FileContains -Path $uiPath -Needle 'function Get-HybridRuntimeProfileProviderSummary' -Message 'Start page has dynamic runtime profile provider summary helper'
Assert-FileContains -Path $uiPath -Needle '$rawProfile.Providers.PSObject.Properties' -Message 'Start page reads provider names dynamically from profile JSON'
Assert-FileContains -Path $uiPath -Needle '$providerSummary = Get-HybridRuntimeProfileProviderSummary -Profile $selectedProfile' -Message 'Start page uses dynamic provider summary for selected profile'
Assert-FileContains -Path $uiPath -Needle '$providerSummary.Count, $providerSummary.Text' -Message 'Start page provider count and text come from dynamic profile providers'

Write-Host 'Milestone 8.9 dynamic runtime profile provider list tests passed.'
