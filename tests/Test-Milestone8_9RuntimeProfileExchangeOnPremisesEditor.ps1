$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$coreProfilePath = Join-Path $repoRoot 'src\Core\Core.RuntimeProfile.psm1'
$coreRuntimePath = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'

function Assert-ContainsText {
    param([string]$Content, [string]$Needle, [string]$Message)
    if ($Content -notlike "*$Needle*") { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$ui = Get-Content -LiteralPath $uiPath -Raw
$coreProfile = Get-Content -LiteralPath $coreProfilePath -Raw
$coreRuntime = Get-Content -LiteralPath $coreRuntimePath -Raw

Assert-ContainsText $ui 'WizardExchangeOnPremisesEnabledCheckBox' 'Runtime profile wizard exposes Exchange On-Premises enable checkbox'
Assert-ContainsText $ui 'WizardExchangeOnPremisesServerTextBox' 'Runtime profile wizard exposes Exchange On-Premises server textbox'
Assert-ContainsText $ui 'WizardExchangeOnPremisesConnectionUriTextBox' 'Runtime profile wizard exposes Exchange On-Premises connection URI textbox'
Assert-ContainsText $ui 'WizardExchangeOnPremisesAuthenticationComboBox' 'Runtime profile wizard exposes Exchange On-Premises authentication selector'
Assert-ContainsText $ui 'ExchangeOnPremises = @{' 'Runtime profile wizard saves Exchange On-Premises provider settings'
Assert-ContainsText $ui 'Exchange On-Premises requires a server name or connection URI' 'Runtime profile wizard validates Exchange On-Premises live settings'
Assert-ContainsText $ui 'Set-HybridWizardProviderControls -ProviderName ''ExchangeOnPremises''' 'Runtime profile wizard loads existing Exchange On-Premises provider settings'
Assert-ContainsText $coreProfile "ConvertTo-HybridProviderRuntimeSettings -Name 'ExchangeOnPremises'" 'Runtime profile parser includes Exchange On-Premises provider'
Assert-ContainsText $coreProfile 'Server = [string](Get-HybridObjectPropertyValue' 'Runtime profile parser preserves provider server setting'
Assert-ContainsText $coreProfile 'ConnectionUri = [string](Get-HybridObjectPropertyValue' 'Runtime profile parser preserves provider connection URI setting'
Assert-ContainsText $coreRuntime 'Initialize-HybridRuntimeLiveExchangeOnPremisesProvider' 'Runtime bootstrap can initialize Exchange On-Premises provider'
Assert-ContainsText $coreRuntime 'Infrastructure.ExchangeOnPremises.psm1' 'Runtime bootstrap imports Exchange On-Premises provider module'
Assert-ContainsText $coreRuntime '-ExchangeOnPremisesProvider $exchangeOnPremisesProvider' 'Runtime application service receives Exchange On-Premises provider'
Assert-ContainsText $ui 'Style="{StaticResource GlassCommandButton}"' 'Runtime console search and Back / Start buttons use glass command styling'
Assert-ContainsText $ui 'x:Name="SearchBox" Grid.Column="0" Height="43"' 'Runtime console search box height is increased to avoid clipped text'

Write-Host 'Milestone 8.9 runtime profile Exchange On-Premises editor tests passed.'
