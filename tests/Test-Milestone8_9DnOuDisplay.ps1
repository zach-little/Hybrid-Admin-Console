Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

Assert-Pass -Condition (Test-Path -LiteralPath $uiPath) -Message 'Runtime UI script exists'
$content = Get-Content -LiteralPath $uiPath -Raw

Assert-Pass -Condition ($content.Contains('function Resolve-HybridUserDistinguishedName')) -Message 'Runtime UI has DN resolver'
Assert-Pass -Condition ($content.Contains('function Resolve-HybridUserOrganizationalUnit')) -Message 'Runtime UI has OU resolver'
Assert-Pass -Condition ($content.Contains("@('DistinguishedName','ActiveDirectoryDistinguishedName','DN')")) -Message 'DN resolver checks ActiveDirectoryDistinguishedName fallback'
Assert-Pass -Condition ($content.Contains("@('OrganizationalUnit','ActiveDirectoryOrganizationalUnit','OU')")) -Message 'OU resolver checks ActiveDirectoryOrganizationalUnit fallback'
Assert-Pass -Condition ($content.Contains("Resolve-HybridUserDistinguishedName -User `$user")) -Message 'Base search card uses DN resolver instead of direct property only'
Assert-Pass -Condition ($content.Contains("Resolved Active Directory DN and OU display values.")) -Message 'DN and OU display values are logged during AD detail hydration'
Assert-Pass -Condition ($content.Contains("Where-Object { `$_ -like 'OU=*' }")) -Message 'OU resolver derives OU from DN when explicit OU is missing'
Assert-Pass -Condition ($content.Contains("Get-DisplayValue -InputObject `$Group -Names @('Name','DisplayName','SamAccountName','Identity','DistinguishedName','Id')")) -Message 'Group display formatter remains intact'

Write-Host 'Milestone 8.9 DN/OU display tests passed.'
