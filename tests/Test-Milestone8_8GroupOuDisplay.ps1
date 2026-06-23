Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

Assert-Pass -Condition (Test-Path $uiPath) -Message 'Runtime UI script exists'

$content = Get-Content -LiteralPath $uiPath -Raw

Assert-Pass -Condition ($content -match 'function\s+Format-HybridGroupDisplay') -Message 'Runtime UI has group display formatter'
Assert-Pass -Condition ($content -like '*Get-DisplayValue -InputObject $Group -Names*') -Message 'Group formatter reads object Name property instead of object ToString output'
Assert-Pass -Condition ($content -match "'Name'") -Message 'Group formatter prefers Name value'
Assert-Pass -Condition ($content -like '*Format-HybridGroupDisplay -Group $group*') -Message 'Runtime UI calls group display formatter for AD groups'
Assert-Pass -Condition ($content -notmatch '\@\{Id=.*Name=') -Message 'Runtime UI does not hard-code object-style group display'

Assert-Pass -Condition ($content -match 'function\s+Resolve-HybridUserDistinguishedName') -Message 'Runtime UI has DN resolver'
Assert-Pass -Condition ($content -match "'DistinguishedName'") -Message 'DN resolver checks DistinguishedName'
Assert-Pass -Condition ($content -match "'DistinguishedName'\s*,\s*'DN'") -Message 'DN resolver checks DN fallback names'
Assert-Pass -Condition ($content -match 'Attributes') -Message 'DN resolver can read from Attributes bag'
Assert-Pass -Condition ($content -like '*$controls.DistinguishedNameText.Text = Resolve-HybridUserDistinguishedName -User $details*') -Message 'AD details panel writes resolved DN'

Assert-Pass -Condition ($content -match 'function\s+Resolve-HybridUserOrganizationalUnit') -Message 'Runtime UI has OU resolver'
Assert-Pass -Condition ($content -like '*$controls.OrganizationalUnitText.Text = Resolve-HybridUserOrganizationalUnit -User $details*') -Message 'Runtime UI calls OU resolver from AD details panel'
Assert-Pass -Condition ($content -match 'Split\(') -Message 'OU resolver can derive OU from distinguished name'
Assert-Pass -Condition ($content -match 'OU=') -Message 'OU resolver recognizes OU components'

Write-Host 'Milestone 8.8 group and OU display tests passed.' -ForegroundColor Cyan
