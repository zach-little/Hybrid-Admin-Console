$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$servicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'

function Assert-ContainsText {
    param([string]$Content,[string]$Needle,[string]$Message)
    if ($Content -notlike "*$Needle*") { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$ui = Get-Content -LiteralPath $uiPath -Raw
$service = Get-Content -LiteralPath $servicePath -Raw

Assert-ContainsText $ui 'function Select-HybridUserFromSearchResults' 'UI has duplicate search result selection function'
Assert-ContainsText $ui 'function Show-HybridUserSelectionDialog' 'UI has user match chooser dialog'
Assert-ContainsText $ui 'Multiple users matched' 'Chooser explains multiple matches before hydration'
Assert-ContainsText $ui 'Display Name' 'Chooser includes display name column'
Assert-ContainsText $ui 'SamAccountName' 'Chooser includes SAM account information'
Assert-ContainsText $ui 'UserPrincipalName' 'Chooser includes UPN information'
Assert-ContainsText $ui 'DisambiguationPath' 'Chooser includes OU/DN disambiguation path'
Assert-ContainsText $ui 'Invoke-HybridSelectedUserHydration' 'Hydration is separated from raw search'
Assert-ContainsText $service '$candidateUsers' 'Service keeps all candidate users instead of collapsing to first result'
Assert-ContainsText $service 'return @($results)' 'Service returns all search candidates to the UI'

Write-Host 'Milestone 8.9 duplicate user chooser tests passed.'
