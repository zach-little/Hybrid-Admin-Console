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

Assert-True (Test-Path -LiteralPath $uiPath) 'Hybrid Admin Console UI script exists'
Assert-True (Test-Path -LiteralPath $servicePath) 'New User Wizard application service exists'

$ui = Get-Content -LiteralPath $uiPath -Raw
$service = Get-Content -LiteralPath $servicePath -Raw

Assert-True ($ui -match 'v0\.9C WorkflowSelector') 'UI declares v0.9C workflow selector marker'
Assert-True ($ui -match 'WorkflowSelectorView') 'UI contains workflow selector view'
Assert-True ($ui -match 'WorkflowUserLookupButton') 'Workflow selector exposes User Lookup button'
Assert-True ($ui -match 'WorkflowNewUserWizardButton') 'Workflow selector exposes New User Wizard button'
Assert-True ($ui -match 'Show-HybridWorkflowSelector') 'Runtime launch routes to workflow selector'
Assert-True ($ui -match 'NewUserWizardView') 'UI contains New User Wizard shell'
Assert-True ($ui -match 'NewUserValidateButton') 'New User Wizard supports validate preview action'
Assert-True ($ui -match 'Execution disabled in v0\.9C') 'New User Wizard execution is disabled for v0.9C'
Assert-True ($ui -match 'Application\.NewUserWizardService\.psm1') 'UI imports New User Wizard service'

foreach ($export in @('New-HybridNewUserRequest','Test-HybridNewUserRequest','Get-HybridNewUserPreviewPlan','Get-HybridNewUserMappings','ConvertTo-HybridNewUserAccountName')) {
    Assert-True ($service -match $export) "New User Wizard service includes $export"
}

Assert-True ($service -match 'OU=Service Accounts') 'Service preserves legacy service-account OU mapping'
Assert-True ($service -match 'CAC_Holders') 'Service preserves legacy CAC group mapping'
Assert-True ($service -match 'TEEntry') 'Service preserves legacy TEEntry group mapping'
Assert-True ($service -match 'atlastechcloud\.mail\.onmicrosoft\.com') 'Service preserves legacy remote routing domain preview'

Write-Host ''
Write-Host 'Milestone 9C workflow framework tests passed.'
