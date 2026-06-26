Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $repoRoot 'src\Application\Application.UserAdministrationService.psm1'
$runtimePath = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$graphServicePath = Join-Path $repoRoot 'src\Application\Application.GraphProfileService.psm1'
$graphModelPath = Join-Path $repoRoot 'src\Models\Hybrid.GraphProfile.psm1'
$adProviderPath = Join-Path $repoRoot 'src\Infrastructure\Infrastructure.ActiveDirectory.psm1'

foreach ($path in @($servicePath,$runtimePath,$uiPath,$graphServicePath,$graphModelPath,$adProviderPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file missing: $path" }
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "Parser errors in $path`: $($errors[0].Message)" }
}

Import-Module $servicePath -Force

$calls = New-Object System.Collections.Generic.List[string]
$adProvider = [pscustomobject]@{
    SetUserAttributes = {
        param([string]$Identity, [hashtable]$Attributes)
        $calls.Add("SetUserAttributes:${Identity}:$($Attributes['title'])") | Out-Null
        [pscustomobject]@{ Success = $true }
    }.GetNewClosure()
    SetUserManager = {
        param([string]$Identity, [string]$ManagerIdentity)
        $calls.Add("SetUserManager:${Identity}:$ManagerIdentity") | Out-Null
        [pscustomobject]@{ Success = $true }
    }.GetNewClosure()
    GetUserDirectReports = {
        param([string]$Identity)
        @([pscustomobject]@{ SamAccountName = 'report1' }, [pscustomobject]@{ SamAccountName = 'report2' })
    }.GetNewClosure()
}

$exchangeProvider = [pscustomobject]@{}
$adminService = Initialize-HybridUserAdministrationService -ActiveDirectoryProvider $adProvider -ExchangeOnlineProvider $exchangeProvider -MicrosoftGraphProvider $null
if ($adminService.PSTypeNames[0] -ne 'Hybrid.UserAdministrationService') { throw 'User administration service type name mismatch.' }

$attributeResult = Set-HybridUserDirectoryAttributes -Identity 'zlittle' -Attributes @{ title = 'Engineer'; department = 'IT' }
if ($attributeResult.Status -ne 'Completed') { throw "Expected directory attribute update to complete; got $($attributeResult.Status)." }

$managerResult = Set-HybridUserManager -Identity 'zlittle' -ManagerIdentity 'manager1'
if ($managerResult.Status -ne 'Completed') { throw "Expected manager update to complete; got $($managerResult.Status)." }

$moveResult = Move-HybridUserDirectReports -Identity 'zlittle' -NewManagerIdentity 'manager2'
if ($moveResult.Status -ne 'Completed' -or @($moveResult.Data).Count -ne 2) { throw 'Expected two direct reports to move.' }

$forwardingResult = Set-HybridUserMailboxForwarding -Identity 'zlittle' -ForwardingSmtpAddress 'target@example.com'
if ($forwardingResult.Status -ne 'Unsupported') { throw 'Exchange write action should report Unsupported when provider lacks the operation.' }

$callText = ($calls -join '|')
foreach ($expected in @('SetUserAttributes:zlittle:Engineer','SetUserManager:zlittle:manager1','SetUserManager:report1:manager2','SetUserManager:report2:manager2')) {
    if ($callText -notlike "*$expected*") { throw "Expected call missing: $expected" }
}

$runtimeText = Get-Content -LiteralPath $runtimePath -Raw
foreach ($expected in @('Application.UserAdministrationService.psm1','Initialize-HybridUserAdministrationService','UserAdministration')) {
    if ($runtimeText -notlike "*$expected*") { throw "Runtime wiring missing: $expected" }
}

$adText = Get-Content -LiteralPath $adProviderPath -Raw
foreach ($expected in @('Set-HybridADUserAttributes','SetUserAttributes','Set-ADUser')) {
    if ($adText -notlike "*$expected*") { throw "AD provider attribute support missing: $expected" }
}

$uiText = Get-Content -LiteralPath $uiPath -Raw
foreach ($expected in @('EditSelectedUserButton','Show-HybridSelectedUserEditDialog','Attribute Editor','ChangeManagerButton','MoveSubordinatesButton','MailboxDelegationButton','DistributionGroupsButton','MailboxForwardingButton','GalVisibilityButton','GraphLicensesList','GraphPimRolesList')) {
    if ($uiText -notlike "*$expected*") { throw "UI wiring missing: $expected" }
}

$graphServiceText = Get-Content -LiteralPath $graphServicePath -Raw
$graphModelText = Get-Content -LiteralPath $graphModelPath -Raw
foreach ($expected in @('AssignedLicenses','PimRoles')) {
    if ($graphServiceText -notlike "*$expected*" -or $graphModelText -notlike "*$expected*") { throw "Graph profile field missing: $expected" }
}

Write-Host 'Milestone 9B user administration tests passed.'
