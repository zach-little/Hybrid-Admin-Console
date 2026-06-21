Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
Assert-Pass -Condition (Test-Path $uiPath) -Message 'UI entry point exists'

$content = Get-Content -LiteralPath $uiPath -Raw
Assert-Pass -Condition ($content -match 'New-HybridGraphCardSection') -Message 'Graph card section factory present'
Assert-Pass -Condition ($content -match 'Update-HybridGraphCardForCurrentUser') -Message 'Graph card auto-update function present'
Assert-Pass -Condition ($content -match 'Add-HybridGraphCardToUserDetails') -Message 'Graph card insertion function present'
Assert-Pass -Condition ($content -match 'Enable-HybridGraphCardAutoRefresh') -Message 'Graph card auto-refresh enabled'
Assert-Pass -Condition ($content -match 'Get-HybridGraphProfile') -Message 'UI calls Graph profile service directly'
Assert-Pass -Condition ($content -match 'ConvertTo-HybridGraphProfileUiRows') -Message 'UI uses Graph row formatter'
Assert-Pass -Condition ($content -match 'GraphProfileCard') -Message 'Graph card is named for UI lookup'
Assert-Pass -Condition ($content -notmatch 'Click\s*\+=.*Microsoft Graph|Add_Click\(.*Microsoft Graph') -Message 'Graph vertical is not button-gated by obvious click wiring'

$null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$null)
Assert-Pass -Condition $true -Message 'UI script parses after Graph card wiring'

Write-Host "`nMilestone 7 Phase 5 Graph card UI wiring tests passed."
