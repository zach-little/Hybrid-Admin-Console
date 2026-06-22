[CmdletBinding()]
param()

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
Assert-Pass -Condition ($content -match 'Runtime Profile Wizard') -Message 'Runtime Profile Wizard UI exists'
Assert-Pass -Condition ($content -match 'RuntimeProfileWizardView') -Message 'Wizard is hosted in overlay region'
Assert-Pass -Condition ($content -match 'Show-HybridRuntimeProfileWizard') -Message 'Wizard open function exists'
Assert-Pass -Condition ($content -match 'Hide-HybridRuntimeProfileWizard') -Message 'Wizard close function exists'
Assert-Pass -Condition ($content -match 'New-HybridRuntimeProfileFromWizard') -Message 'Wizard profile builder exists'
Assert-Pass -Condition ($content -match 'Test-HybridRuntimeProfileWizardInput') -Message 'Wizard validation function exists'
Assert-Pass -Condition ($content -match 'Save-HybridRuntimeProfileFromWizard') -Message 'Wizard save function exists'
Assert-Pass -Condition ($content -match 'WizardValidateButton') -Message 'Wizard validation button exists'
Assert-Pass -Condition ($content -match 'WizardSaveButton') -Message 'Wizard save button exists'
Assert-Pass -Condition ($content -match 'WizardCancelButton') -Message 'Wizard cancel button exists'
Assert-Pass -Condition ($content -match 'WizardCloudComboBox') -Message 'Cloud environment selector exists'
Assert-Pass -Condition ($content -match 'WizardModeComboBox') -Message 'Runtime mode selector exists'
Assert-Pass -Condition ($content -match 'WizardDirectorySimulatorEnabledCheckBox') -Message 'Directory Simulator provider selector exists'
Assert-Pass -Condition ($content -match 'WizardActiveDirectoryEnabledCheckBox') -Message 'Active Directory provider selector exists'
Assert-Pass -Condition ($content -match 'WizardMicrosoftGraphEnabledCheckBox') -Message 'Microsoft Graph provider selector exists'
Assert-Pass -Condition ($content -match 'WizardExchangeOnlineEnabledCheckBox') -Message 'Exchange Online provider selector exists'
Assert-Pass -Condition ($content -match 'profiles\\Runtime') -Message 'Wizard saves profiles under profiles\Runtime'
Assert-Pass -Condition ($content -match 'ConvertTo-Json -Depth 10') -Message 'Wizard writes runtime profile JSON'
Assert-Pass -Condition ($content -match 'EditRuntimeProfileButton.Add_Click') -Message 'Start screen edit button opens wizard'
Assert-Pass -Condition ($content -match 'IsEnabled="True"') -Message 'Edit Runtime Profile button is enabled'

foreach ($marker in @('StartupRegion','MainRegion','StatusBarRegion','OverlayRegion','MainDashboardGrid','Show-HybridConsoleView','Update-HybridStartupView')) {
    Assert-Pass -Condition ($content -match [regex]::Escape($marker)) -Message "Existing shell marker retained: $marker"
}

$windowCount = ([regex]::Matches($content, '<Window ')).Count
Assert-Pass -Condition ($windowCount -eq 1) -Message 'Wizard preserves single WPF shell window'
Assert-Pass -Condition ($content -notmatch 'Start-Sleep') -Message 'Wizard does not introduce blocking delays'
Assert-Pass -Condition ($content -notmatch 'Device Code') -Message 'Wizard does not introduce Device Code authentication'

$xamlMatch = [regex]::Match($content, '(?s)\$xaml = @"(?<xaml>.*?)"@')
Assert-Pass -Condition ($xamlMatch.Success) -Message 'XAML block was found'
[xml]$null = $xamlMatch.Groups['xaml'].Value
Assert-Pass -Condition $true -Message 'Runtime Profile Wizard XAML is well-formed XML'

Write-Host "`nMilestone 8 Phase 6 Runtime Profile Wizard tests passed."
