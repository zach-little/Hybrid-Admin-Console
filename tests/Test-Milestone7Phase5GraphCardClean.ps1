Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
Assert-Pass -Condition (Test-Path -LiteralPath $uiPath) -Message 'UI entry point exists'

$content = Get-Content -LiteralPath $uiPath -Raw
[void][scriptblock]::Create($content)
Assert-Pass -Condition $true -Message 'UI script parses successfully'

Assert-Pass -Condition ($content -match 'x:Name="GraphProfileCard"') -Message 'Graph profile card declared in XAML'
Assert-Pass -Condition ($content -match 'Update-HybridGraphCardForCurrentUser') -Message 'Graph card runtime update function present'
Assert-Pass -Condition ($content -match 'Update-HybridGraphCardForCurrentUser\s+-User\s+\$user\s+-Query\s+\$effectiveQuery') -Message 'Graph card updates during successful user search'
Assert-Pass -Condition ($content -notmatch 'Add_Click\(\{\s*Show-HybridGraph') -Message 'Old Graph button click workflow is absent'
Assert-Pass -Condition (([regex]::Matches($content, 'x:Name="GraphProfileCard"')).Count -eq 1) -Message 'Only one Graph profile card is declared'
Assert-Pass -Condition (([regex]::Matches($content, 'Text="Microsoft Graph"')).Count -eq 1) -Message 'Only one Microsoft Graph card heading is present'
Assert-Pass -Condition ($content -match 'Graph Object ID' -and $content -match 'Authentication Methods' -and $content -match 'MFA Registered') -Message 'Graph card exposes required Phase 5 fields'

Write-Host "`nMilestone 7 Phase 5 clean Graph card UI repair tests passed."
