Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'src\Application\Application.RuntimeProfileManager.psm1'
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$docPath = Join-Path $repoRoot 'docs\Milestones\MILESTONE_8_PHASE_8_1.md'
$applyPath = Join-Path $repoRoot 'tools\Apply-Milestone8Phase8_1.ps1'

Assert-Pass -Condition (Test-Path $modulePath) -Message 'Runtime Profile Manager module exists'
Import-Module $modulePath -Force -Global

$exports = (Get-Module Application.RuntimeProfileManager).ExportedFunctions.Keys
Assert-Pass -Condition ($exports -contains 'Get-HybridRuntimeProfileSummary') -Message 'Get-HybridRuntimeProfileSummary exported'
Assert-Pass -Condition ($exports -contains 'Get-HybridRuntimeProfileSelection') -Message 'Get-HybridRuntimeProfileSelection exported'
Assert-Pass -Condition ($exports -contains 'Set-HybridRuntimeProfileSelection') -Message 'Set-HybridRuntimeProfileSelection exported'
Assert-Pass -Condition ($exports -contains 'Update-HybridRuntimeProfileManager') -Message 'Update-HybridRuntimeProfileManager exported'

$profiles = @(Get-HybridRuntimeProfileSummary -RepositoryRoot $repoRoot)
Assert-Pass -Condition ($profiles.Count -gt 0) -Message 'Runtime Profile Manager discovers runtime profiles'
Assert-Pass -Condition (@($profiles | Where-Object { $_.ProfileName -eq 'Simulation' -or $_.FileName -eq 'Simulation.json' }).Count -gt 0) -Message 'Runtime Profile Manager discovers Simulation profile'
Assert-Pass -Condition ($profiles[0].PSTypeName -eq 'Hybrid.RuntimeProfileSummary') -Message 'Profile summaries expose canonical type marker'
Assert-Pass -Condition ($profiles[0].TypeName -eq 'Hybrid.RuntimeProfileSummary') -Message 'Profile summaries expose canonical type name'
Assert-Pass -Condition ($profiles[0].PSObject.Properties.Name -contains 'CloudEnvironment') -Message 'Profile summaries expose cloud environment'
Assert-Pass -Condition ($profiles[0].PSObject.Properties.Name -contains 'RuntimeMode') -Message 'Profile summaries expose runtime mode'
Assert-Pass -Condition ($profiles[0].PSObject.Properties.Name -contains 'EnabledProviderCount') -Message 'Profile summaries expose enabled provider count'
Assert-Pass -Condition ($profiles[0].PSObject.Properties.Name -contains 'Path') -Message 'Profile summaries expose source path'

$selection = Get-HybridRuntimeProfileSelection -RepositoryRoot $repoRoot
Assert-Pass -Condition ($null -ne $selection) -Message 'Runtime Profile Manager resolves an initial profile selection'
Assert-Pass -Condition ($selection.PSTypeName -eq 'Hybrid.RuntimeProfileSummary') -Message 'Initial profile selection is a profile summary'
Assert-Pass -Condition ($selection.IsValid) -Message 'Initial profile selection is valid'

$simulation = @($profiles | Where-Object { $_.ProfileName -eq 'Simulation' -or $_.FileName -eq 'Simulation.json' } | Select-Object -First 1)[0]
$selected = Set-HybridRuntimeProfileSelection -RepositoryRoot $repoRoot -ProfilePath $simulation.Path
Assert-Pass -Condition ($selected.ProfileName -eq $simulation.ProfileName) -Message 'Runtime Profile Manager can persist selected profile'
$selectionAfterSet = Get-HybridRuntimeProfileSelection -RepositoryRoot $repoRoot
Assert-Pass -Condition ($selectionAfterSet.ProfileName -eq $simulation.ProfileName) -Message 'Runtime Profile Manager resolves last-used selection'

$state = Update-HybridRuntimeProfileManager -RepositoryRoot $repoRoot
Assert-Pass -Condition ($state.PSTypeName -eq 'Hybrid.RuntimeProfileManagerState') -Message 'Runtime Profile Manager state exposes canonical type marker'
Assert-Pass -Condition ($state.ProfileCount -eq $profiles.Count) -Message 'Runtime Profile Manager state includes profile count'
Assert-Pass -Condition ($null -ne $state.SelectedProfile) -Message 'Runtime Profile Manager state includes selected profile'

Assert-Pass -Condition (Test-Path $uiPath) -Message 'Hybrid Admin Console UI script exists'
$ui = Get-Content -LiteralPath $uiPath -Raw
Assert-Pass -Condition ($ui -match 'Application.RuntimeProfileManager.psm1') -Message 'Startup shell imports Runtime Profile Manager'
Assert-Pass -Condition ($ui -match 'RuntimeProfileListBox') -Message 'Startup shell contains runtime profile list'
Assert-Pass -Condition ($ui -match 'Initialize-HybridRuntimeProfileList') -Message 'Startup shell initializes runtime profile list'
Assert-Pass -Condition ($ui -match 'Select-HybridRuntimeProfileFromList') -Message 'Startup shell handles runtime profile selection'
Assert-Pass -Condition ($ui -match 'Set-HybridRuntimeProfileSelection') -Message 'Startup shell persists runtime profile selection'
Assert-Pass -Condition ($ui -match 'Initialize-HybridRuntime -ProfilePath') -Message 'Launch workflow bootstraps selected profile path'
Assert-Pass -Condition ($ui -match 'Home - select a runtime profile before launch') -Message 'Startup shell is labeled as runtime profile home'
Assert-Pass -Condition ($ui -match 'RefreshRuntimeProfilesButton') -Message 'Startup shell includes profile refresh action'
Assert-Pass -Condition ($ui -match 'NewRuntimeProfileButton') -Message 'Startup shell includes new profile action'

Assert-Pass -Condition ($ui -match 'Load-HybridRuntimeProfileIntoWizard') -Message 'Edit workflow loads selected profile into wizard'
Assert-Pass -Condition ($ui -match 'Show-HybridRuntimeProfileWizardForSelectedProfile') -Message 'Edit button opens wizard for selected profile'
Assert-Pass -Condition ($ui -match 'Show-HybridRuntimeProfileWizardForNew') -Message 'New button opens blank wizard profile'
Assert-Pass -Condition ($ui -match 'HybridRuntimeProfileWizardSourcePath') -Message 'Wizard tracks source path for edit saves'
Assert-Pass -Condition ($ui -match 'Get-Content -LiteralPath \$ProfileSummary.Path') -Message 'Wizard reads selected profile JSON before editing'
Assert-Pass -Condition ($ui -notmatch 'Device\s*Code|DeviceCode') -Message 'Phase 8.1 does not introduce Device Code authentication'

Assert-Pass -Condition (Test-Path $applyPath) -Message 'Phase 8.1 apply script exists'
Assert-Pass -Condition (Test-Path $docPath) -Message 'Phase 8.1 milestone document exists'

Write-Host ''
Write-Host 'Milestone 8 Phase 8.1 Runtime Profile Discovery tests passed.'
