Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$servicePath = Join-Path $repoRoot 'src\Application\Application.NewUserWizardService.psm1'
$graphProviderPath = Join-Path $repoRoot 'src\Core\Core.Provider.MicrosoftGraph.psm1'
$graphProfileServicePath = Join-Path $repoRoot 'src\Application\Application.GraphProfileService.psm1'
$runtimePath = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'
$adProviderPath = Join-Path $repoRoot 'src\Infrastructure\Infrastructure.ActiveDirectory.psm1'

Assert-True (Test-Path -LiteralPath $uiPath) 'Hybrid Admin Console UI script exists'
Assert-True (Test-Path -LiteralPath $servicePath) 'New User Wizard application service exists'

$ui = Get-Content -LiteralPath $uiPath -Raw
$service = Get-Content -LiteralPath $servicePath -Raw
$graphProvider = Get-Content -LiteralPath $graphProviderPath -Raw
$graphProfileService = Get-Content -LiteralPath $graphProfileServicePath -Raw
$runtime = Get-Content -LiteralPath $runtimePath -Raw
$adProvider = Get-Content -LiteralPath $adProviderPath -Raw

Assert-True ($ui -match 'v0\.9C WorkflowSelector') 'UI declares v0.9C workflow selector marker'
Assert-True ($ui -match 'WorkflowSelectorView') 'UI contains workflow selector view'
Assert-True ($ui -match 'WorkflowUserLookupButton') 'Workflow selector exposes User Lookup button'
Assert-True ($ui -match 'WorkflowNewUserWizardButton') 'Workflow selector exposes New User Wizard button'
Assert-True ($ui -match 'Show-HybridWorkflowSelector') 'Runtime launch routes to workflow selector'
Assert-True ($ui -match 'NewUserWizardView') 'UI contains New User Wizard shell'
Assert-True ($ui -match 'NewUserValidateButton') 'New User Wizard supports validate preview action'
Assert-True ($ui -match 'NewUserExecuteButton') 'New User Wizard exposes explicit create execution action'
Assert-True ($ui -match 'Confirm New User Creation') 'New User Wizard requires operator confirmation before execution'
Assert-True ($ui -match 'NewUserManagerComboBox') 'New User Wizard uses a manager picker'
Assert-True ($ui -match 'Update-HybridNewUserManagerOptions') 'New User Wizard refreshes manager options from the service'
Assert-True ($ui -match 'Application\.NewUserWizardService\.psm1') 'UI imports New User Wizard service'
Assert-True ($ui -notmatch 'New-ADUser|Add-ADGroupMember|Enable-RemoteMailbox') 'UI does not call AD or Exchange write commands directly'

foreach ($export in @('New-HybridNewUserRequest','Test-HybridNewUserRequest','Get-HybridNewUserPreviewPlan','Get-HybridNewUserMappings','ConvertTo-HybridNewUserAccountName','Get-HybridNewUserManagerOptions','Invoke-HybridNewUserCreation')) {
    Assert-True ($service -match $export) "New User Wizard service includes $export"
}

Assert-True ($service -match 'OU=Service Accounts') 'Service preserves legacy service-account OU mapping'
Assert-True ($service -match 'CAC_Holders') 'Service preserves legacy CAC group mapping'
Assert-True ($service -match 'TEEntry') 'Service preserves legacy TEEntry group mapping'
Assert-True ($service -match 'atlastechcloud\.mail\.onmicrosoft\.com') 'Service preserves legacy remote routing domain preview'
Assert-True ($service -match 'GetUsersWithDirectReports') 'Service manager lookup uses AD provider manager operation'
Assert-True ($service -match 'CreateUser') 'Service creates users through the AD provider'
Assert-True ($service -match 'AddUserToGroup') 'Service assigns groups through the AD provider'
Assert-True ($service -match 'EnableRemoteMailbox') 'Service enables mailbox through the Exchange provider'
Assert-True (($service.IndexOf('function Get-HybridNewUserPreviewPlan') -lt $service.IndexOf('function Invoke-HybridNewUserCreation')) -and ($service.Substring($service.IndexOf('function Get-HybridNewUserPreviewPlan'), $service.IndexOf('function Invoke-HybridNewUserCreation') - $service.IndexOf('function Get-HybridNewUserPreviewPlan')) -notmatch 'CreateUser|AddUserToGroup|EnableRemoteMailbox')) 'Preview planning contains no provider write operations'
Assert-True ($adProvider -match 'directReports -like "\*"') 'AD provider manager lookup filters users with direct reports'

foreach ($scope in @('User.Read.All','AuditLog.Read.All','UserAuthenticationMethod.Read.All','Directory.Read.All','RoleManagement.Read.Directory')) {
    Assert-True ($runtime -match [regex]::Escape($scope)) "Delegated Graph scopes include $scope"
}

Assert-True ($graphProvider -match '/licenseDetails') 'Graph provider prefers user licenseDetails endpoint'
Assert-True ($graphProvider -match 'subscribedSkus') 'Graph provider maps license SKU names through subscribedSkus'
Assert-True ($graphProvider -match 'licenseAssignmentStates') 'Graph provider preserves license assignment states fallback'
Assert-True ($graphProvider -match 'roleAssignmentScheduleInstances') 'Graph provider queries active PIM role schedules'
Assert-True ($graphProvider -match 'roleEligibilityScheduleInstances') 'Graph provider queries eligible PIM role schedules'
Assert-True ($graphProvider -match 'DirectoryRoles') 'Graph provider preserves directory role fallback values'
foreach ($property in @('Licenses','AssignedLicenses','LicenseAssignmentStates','PimRoles','DirectoryRoles','GraphDiagnostics','LicenseDiagnostics','PimDiagnostics')) {
    Assert-True ($graphProvider -match $property) "Graph provider preserves $property"
    Assert-True ($graphProfileService -match $property) "Graph profile service preserves $property"
}
Assert-True ($ui -match 'LicenseDiagnostic' -and $ui -match 'PimDiagnostics') 'UI displays Graph license/PIM diagnostic details'

Write-Host ''
Write-Host 'Milestone 9C workflow framework tests passed.'
