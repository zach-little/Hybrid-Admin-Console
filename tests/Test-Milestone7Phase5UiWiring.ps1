Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src/UI/Start-HybridAdminConsole.ps1'

Assert-Pass -Condition (Test-Path $uiPath) -Message 'UI entry point exists'

$content = Get-Content -LiteralPath $uiPath -Raw
Assert-Pass -Condition ($content -match 'function\s+Add-Milestone7Phase5GraphUiWiring') -Message 'Graph UI wiring function present'
Assert-Pass -Condition ($content -match 'function\s+Get-Milestone7Phase5CurrentUserIdentity') -Message 'Graph UI discovers current populated user identity'
Assert-Pass -Condition ($content -match 'function\s+Show-Milestone7Phase5GraphProfile') -Message 'Graph UI renders profile details'
Assert-Pass -Condition ($content -match 'Get-HybridUserGraphProfile\s+-Identity\s+\$identity') -Message 'Graph UI calls service layer with current identity'
Assert-Pass -Condition ($content -match 'Graph Object ID:') -Message 'Graph UI exposes Graph Object ID field'
Assert-Pass -Condition ($content -match 'Authentication Methods:') -Message 'Graph UI exposes authentication methods field'
Assert-Pass -Condition ($content -match 'MFA Registered:') -Message 'Graph UI exposes MFA registration field'
Assert-Pass -Condition ($content -match 'Milestone7Phase5GraphButton') -Message 'Graph UI button identity present'
Assert-Pass -Condition ($content -match 'Microsoft Graph') -Message 'Graph UI visible label present'
Assert-Pass -Condition ($content -match 'Add-Milestone7Phase5GraphUiWiring\s+-Window\s+\$window') -Message 'Graph UI wiring invoked before display'

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($uiPath, [ref]$tokens, [ref]$errors) | Out-Null
Assert-Pass -Condition (@($errors).Count -eq 0) -Message 'UI script parses after Graph wiring patch'

Write-Host ''
Write-Host 'Milestone 7 Phase 5 UI wiring tests passed.' -ForegroundColor Cyan
