Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
Assert-Pass -Condition (Test-Path $uiPath) -Message 'Runtime UI script exists'

$content = Get-Content -LiteralPath $uiPath -Raw
Assert-Pass -Condition ($content.Contains('function Format-HybridGroupDisplay')) -Message 'Runtime UI has group display formatter'
Assert-Pass -Condition ($content.Contains("@('Name','DisplayName','SamAccountName','Identity','DistinguishedName','Id')")) -Message 'Group formatter prefers group name properties'
Assert-Pass -Condition ($content.Contains('Format-HybridGroupDisplay -Group $group')) -Message 'Groups lists use group display formatter'
Assert-Pass -Condition ($content.Contains('function Resolve-HybridUserDistinguishedName')) -Message 'Runtime UI has DN resolver'
Assert-Pass -Condition ($content.Contains('function Resolve-HybridUserOrganizationalUnit')) -Message 'Runtime UI has OU resolver'
Assert-Pass -Condition ($content.Contains("@('DistinguishedName','DN')")) -Message 'DN resolver checks direct DN properties'
Assert-Pass -Condition ($content.Contains("PSObject.Properties.Name -contains 'Attributes'")) -Message 'Display resolver can read Attributes bag values'
Assert-Pass -Condition ($content.Contains('Where-Object { $_ -like ''OU=*'' }')) -Message 'OU resolver derives OU from DN when needed'
Assert-Pass -Condition ($content.Contains('Search-HybridUser -Query $effectiveQuery')) -Message 'Search execution path is preserved'

Write-Host 'Milestone 8.8 group and OU display tests passed.' -ForegroundColor Cyan
