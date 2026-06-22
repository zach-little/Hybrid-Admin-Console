Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$managerPath = Join-Path $repoRoot 'src\Application\Application.RuntimeProfileManager.psm1'

Assert-Pass -Condition (Test-Path $uiPath) -Message 'Hybrid Admin Console UI script exists'
Assert-Pass -Condition (Test-Path $managerPath) -Message 'Runtime Profile Manager module exists'

$ui = Get-Content -LiteralPath $uiPath -Raw
$manager = Get-Content -LiteralPath $managerPath -Raw

Assert-Pass -Condition ($ui -match 'Phase 8\.2 RuntimeProfileCardView') -Message 'Phase 8.2 profile card marker exists'
Assert-Pass -Condition ($ui -match 'RuntimeProfileCard') -Message 'Runtime profile card template exists'
Assert-Pass -Condition ($ui -match 'ListBox\.ItemTemplate') -Message 'Runtime profile list uses an item template'
Assert-Pass -Condition ($ui -match 'BadgeText') -Message 'Runtime profile cards expose badge text'
Assert-Pass -Condition ($ui -match 'HealthLabel') -Message 'Runtime profile cards expose health label'
Assert-Pass -Condition ($ui -match 'Default/Last Used/Ready badges') -Message 'Profile cards document default last-used and health badges'
Assert-Pass -Condition ($ui -match 'Items\.Add\(\$profile\)') -Message 'Profile list binds profile summary objects instead of plain strings'
Assert-Pass -Condition ($ui -match "WizardProfileNameTextBox\.Text = ''") -Message 'New profile wizard clears profile name'
Assert-Pass -Condition ($ui -match "WizardOrganizationTextBox\.Text = ''") -Message 'New profile wizard clears organization'
Assert-Pass -Condition ($ui -notmatch 'WizardOrganizationTextBox" Text="Atlas"') -Message 'New profile wizard no longer pre-populates Atlas in XAML'
Assert-Pass -Condition ($ui -notmatch "WizardOrganizationTextBox\.Text = 'Atlas'") -Message 'New profile wizard no longer pre-populates Atlas in reset logic'
Assert-Pass -Condition ($ui -match 'Show-HybridRuntimeProfileWizardForSelectedProfile') -Message 'Edit selected profile workflow is retained'
Assert-Pass -Condition ($ui -match 'Load-HybridRuntimeProfileIntoWizard') -Message 'Selected profile loading workflow is retained'

Assert-Pass -Condition ($manager -match 'HealthLabel') -Message 'Runtime profile summaries expose health labels'
Assert-Pass -Condition ($manager -match 'BadgeText') -Message 'Runtime profile summaries expose badge text'
Assert-Pass -Condition ($manager -match 'SortWeight') -Message 'Runtime profile summaries expose sort weight'
Assert-Pass -Condition ($manager -match 'Sort-Object SortWeight, ProfileName, FileName') -Message 'Runtime profile discovery sorts default and last-used profiles first'

Import-Module $managerPath -Force
$profiles = @(Get-HybridRuntimeProfileSummary -RepositoryRoot $repoRoot)
Assert-Pass -Condition ($profiles.Count -gt 0) -Message 'Runtime profile discovery returns profiles'
Assert-Pass -Condition ($profiles[0].PSObject.Properties.Match('HealthLabel').Count -gt 0) -Message 'Discovered profile exposes HealthLabel property'
Assert-Pass -Condition ($profiles[0].PSObject.Properties.Match('BadgeText').Count -gt 0) -Message 'Discovered profile exposes BadgeText property'
Assert-Pass -Condition ($profiles[0].PSObject.Properties.Match('SortWeight').Count -gt 0) -Message 'Discovered profile exposes SortWeight property'

Write-Host ''
Write-Host 'Milestone 8 Phase 8.2 runtime profile card view tests passed.'
