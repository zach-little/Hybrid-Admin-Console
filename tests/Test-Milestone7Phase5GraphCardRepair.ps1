Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Assert-Pass { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } Write-Host "PASS: $Message" }
$ui = Join-Path (Get-Location) 'src\UI\Start-HybridAdminConsole.ps1'
$content = Get-Content -LiteralPath $ui -Raw
Assert-Pass -Condition ($content -match 'function Add-HybridGraphCardToUserDetails') -Message 'Graph card runtime function present'
Assert-Pass -Condition ($content -match 'Update-HybridGraphCard') -Message 'Graph card update hook present'
Assert-Pass -Condition (($content -split 'Graph profile loads automatically with the current user\.').Count -le 1) -Message 'Old duplicate placeholder cards removed'
Assert-Pass -Condition ($content -notmatch 'Add-Milestone7Phase5UiWiring') -Message 'No old button wiring script reference remains'
$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($ui,[ref]$tokens,[ref]$errors)
Assert-Pass -Condition (@($errors).Count -eq 0) -Message 'UI script parses after repair'
Write-Host "`nMilestone 7 Phase 5 Graph card repair tests passed."
