Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
$coreRuntimePath = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'

Assert-Pass -Condition (Test-Path $servicePath) -Message 'Hybrid user service module exists'

$content = Get-Content -LiteralPath $servicePath -Raw

Assert-Pass -Condition ($content -match 'function Get-HybridActiveDirectoryStableIdentity') -Message 'Stable AD identity resolver exists'
Assert-Pass -Condition ($content -match 'DistinguishedName'',\s*''DN') -Message 'Stable AD identity prioritizes distinguished name'
Assert-Pass -Condition ($content -match 'ObjectGuid'',\s*''ObjectGUID'',\s*''Guid') -Message 'Stable AD identity supports object GUID fallback'
Assert-Pass -Condition ($content -match 'ObjectSid'',\s*''SID'',\s*''Sid') -Message 'Stable AD identity supports SID fallback'
Assert-Pass -Condition ($content -match 'SamAccountName'',\s*''SAMAccountName'',\s*''sAMAccountName') -Message 'Stable AD identity supports SAM fallback'
Assert-Pass -Condition ($content -match 'ActiveDirectoryIdentity') -Message 'Composite users expose ActiveDirectoryIdentity'
Assert-Pass -Condition ($content -match 'ActiveDirectoryDistinguishedName') -Message 'Composite users expose ActiveDirectoryDistinguishedName'
Assert-Pass -Condition ($content -match 'ActiveDirectorySamAccountName') -Message 'Composite users expose ActiveDirectorySamAccountName'
Assert-Pass -Condition ($content -match 'Using stable Active Directory identity') -Message 'AD detail hydration logs stable identity selection'
Assert-Pass -Condition ($content -match "GetUserGroups'.*Arguments @\(\`$adIdentity\)") -Message 'Group hydration uses stable AD identity'
Assert-Pass -Condition ($content -match "GetUserDirectReports'.*Arguments @\(\`$adIdentity\)") -Message 'Direct report hydration uses stable AD identity'
Assert-Pass -Condition ($content -match "GetUserManager'.*Arguments @\(\`$adIdentity\)") -Message 'Manager hydration uses stable AD identity'
Assert-Pass -Condition ($content -notmatch "GetUserGroups'.*Arguments @\(\`$identity\)") -Message 'Group hydration no longer uses UPN-first transient identity'
Assert-Pass -Condition ($content -match 'Group hydration failed for stable AD identity') -Message 'Group hydration failures are isolated and logged'
Assert-Pass -Condition ($content -match 'Manager hydration failed for stable AD identity') -Message 'Manager hydration failures are isolated and logged'

if (Test-Path $coreRuntimePath) {
    $runtimeContent = Get-Content -LiteralPath $coreRuntimePath -Raw
    Assert-Pass -Condition ($runtimeContent -match "ServiceRegistry\['HybridUser'\]") -Message 'Runtime service registry stores HybridUser service'
    Assert-Pass -Condition ($runtimeContent -match "ServiceRegistry\['GraphProfile'\]") -Message 'Runtime service registry stores GraphProfile service'
    Assert-Pass -Condition ($runtimeContent -match "ServiceRegistry\['AuthenticationProfile'\]") -Message 'Runtime service registry stores AuthenticationProfile service'
    Assert-Pass -Condition ($runtimeContent -match "ServiceRegistry\['UserAggregation'\]") -Message 'Runtime service registry stores UserAggregation service'
}

Write-Host ''
Write-Host 'Milestone 8.7 Runtime Service AD Identity tests passed.'
