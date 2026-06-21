Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

Assert-Pass -Condition (Test-Path $uiPath) -Message 'Hybrid Admin Console UI script exists'

$content = Get-Content -LiteralPath $uiPath -Raw

Assert-Pass -Condition ($content -match 'Step 1: Profile') -Message 'Wizard uses ASCII-safe Step 1 label'
Assert-Pass -Condition ($content -match 'Step 2: Environment') -Message 'Wizard uses ASCII-safe Step 2 label'
Assert-Pass -Condition ($content -match 'Step 3: Runtime Mode') -Message 'Wizard uses ASCII-safe Step 3 label'
Assert-Pass -Condition ($content -match 'Step 4: Providers') -Message 'Wizard uses ASCII-safe Step 4 label'
Assert-Pass -Condition ($content -match 'Step 5: Validation') -Message 'Wizard uses ASCII-safe Step 5 label'
Assert-Pass -Condition ($content -match 'Step 6: Summary') -Message 'Wizard uses ASCII-safe Step 6 label'
Assert-Pass -Condition ($content -notmatch 'â') -Message 'Wizard source does not contain mojibake characters'
Assert-Pass -Condition ($content -notmatch [char]0x2014) -Message 'Wizard source avoids em dash punctuation'

foreach ($marker in @(
    'WizardStepProfilePanel',
    'WizardStepEnvironmentPanel',
    'WizardStepRuntimePanel',
    'WizardStepProvidersPanel',
    'WizardStepValidationPanel',
    'WizardStepSummaryPanel',
    'WizardBackButton',
    'WizardNextButton',
    'WizardCloseButton',
    'WizardStepStatusText',
    'Set-HybridRuntimeProfileWizardStep',
    'Move-HybridRuntimeProfileWizardNext',
    'Move-HybridRuntimeProfileWizardBack'
)) {
    Assert-Pass -Condition ($content.Contains($marker)) -Message "Wizard UX marker exists: $marker"
}

foreach ($marker in @(
    'WizardProfileNameTextBox',
    'WizardOrganizationTextBox',
    'WizardTenantIdTextBox',
    'WizardCloudComboBox',
    'WizardModeComboBox',
    'WizardDirectorySimulatorEnabledCheckBox',
    'WizardActiveDirectoryEnabledCheckBox',
    'WizardMicrosoftGraphEnabledCheckBox',
    'WizardExchangeOnlineEnabledCheckBox',
    'WizardValidateButton',
    'WizardSaveButton',
    'WizardCancelButton',
    'New-HybridRuntimeProfileFromWizard',
    'Test-HybridRuntimeProfileWizardInput',
    'Save-HybridRuntimeProfileFromWizard'
)) {
    Assert-Pass -Condition ($content.Contains($marker)) -Message "Existing wizard contract retained: $marker"
}

Assert-Pass -Condition ($content -match 'OverlayRegion') -Message 'Wizard remains hosted in overlay region'
Assert-Pass -Condition ($content -match 'RuntimeProfileWizardView') -Message 'Wizard view retained'
Assert-Pass -Condition ($content -match 'profiles\\Runtime') -Message 'Wizard still saves profiles under profiles\Runtime'
Assert-Pass -Condition ($content -notmatch 'Device Code') -Message 'Wizard does not introduce Device Code authentication'

$match = [regex]::Match($content, '(?s)\$xaml\s*=\s*@"\r?\n(?<xaml>.*?)\r?\n"@')
Assert-Pass -Condition $match.Success -Message 'XAML block was found'
[xml]$null = $match.Groups['xaml'].Value
Assert-Pass -Condition $true -Message 'Wizard UX XAML is well-formed XML'

Write-Host ""
Write-Host 'Milestone 8 Phase 6.1 Runtime Profile Wizard UX tests passed.'
