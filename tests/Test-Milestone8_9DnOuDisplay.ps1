Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param(
        [Parameter(Mandatory=$true)][string]$Content,
        [Parameter(Mandatory=$true)][string]$Expected,
        [Parameter(Mandatory=$true)][string]$Message
    )
    if ($Content -notlike "*$Expected*") { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$adPath = Join-Path $repoRoot 'src\Infrastructure\Infrastructure.ActiveDirectory.psm1'
$servicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

$ad = Get-Content -LiteralPath $adPath -Raw
$service = Get-Content -LiteralPath $servicePath -Raw
$ui = Get-Content -LiteralPath $uiPath -Raw

Assert-Contains -Content $ad -Expected 'NotePropertyName DistinguishedName' -Message 'AD conversion exposes direct DistinguishedName property'
Assert-Contains -Content $ad -Expected 'ActiveDirectoryDistinguishedName = $distinguishedName' -Message 'AD conversion stores AD distinguished name in Attributes bag'
Assert-Contains -Content $ad -Expected 'ActiveDirectoryOrganizationalUnit = $organizationalUnit' -Message 'AD conversion stores OU in Attributes bag'

Assert-Contains -Content $service -Expected 'System.Collections.IDictionary' -Message 'Hybrid user service reads hashtable attributes'
Assert-Contains -Content $service -Expected 'Resolved Active Directory DN and OU metadata for composite user.' -Message 'Hybrid user service logs DN/OU object shape'
Assert-Contains -Content $service -Expected 'ActiveDirectoryDistinguishedName = $user.ActiveDirectoryDistinguishedName' -Message 'Composite user carries ActiveDirectoryDistinguishedName diagnostics'

Assert-Contains -Content $ui -Expected "Resolve-HybridUserDistinguishedName" -Message 'UI has DN resolver'
Assert-Contains -Content $ui -Expected "Resolve-HybridUserOrganizationalUnit" -Message 'UI has OU resolver'
Assert-Contains -Content $ui -Expected "InputObject.Attributes" -Message 'UI display resolver reads Attributes bag'
Assert-Contains -Content $ui -Expected "Resolved Active Directory DN and OU display values." -Message 'UI logs resolved DN/OU values'

Write-Host 'Milestone 8.9 DN/OU display tests passed.'
