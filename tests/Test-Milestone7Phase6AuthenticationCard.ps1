Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } Write-Host "PASS: $Message" }

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$simPath = Join-Path $repoRoot 'src\Infrastructure\Mock\Infrastructure.DirectorySimulator.psm1'
$servicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'

Assert-Pass -Condition (Test-Path $uiPath) -Message 'UI entry point exists'
Assert-Pass -Condition (Test-Path $simPath) -Message 'Directory Simulator module exists'
Assert-Pass -Condition (Test-Path $servicePath) -Message 'Hybrid user service exists'

$ui = Get-Content -LiteralPath $uiPath -Raw
$service = Get-Content -LiteralPath $servicePath -Raw
$sim = Get-Content -LiteralPath $simPath -Raw

Assert-Pass -Condition ($ui -match 'x:Name="AuthenticationPostureCard"') -Message 'Authentication card is present in XAML'
Assert-Pass -Condition ($ui -match 'x:Name="AuthDefaultMethodText"') -Message 'Default auth method field is present'
Assert-Pass -Condition ($ui -match 'x:Name="AuthMethodsList"') -Message 'Authentication methods list is present'
Assert-Pass -Condition ($ui -match 'function Update-AuthenticationPanels') -Message 'Authentication card update function is present'
Assert-Pass -Condition ($ui -match 'Update-AuthenticationPanels -User \$user -Query \$effectiveQuery') -Message 'Authentication card is updated during user search'
Assert-Pass -Condition (([regex]::Matches($ui, 'x:Name="AuthenticationPostureCard"')).Count -eq 1) -Message 'Only one Authentication card exists'
Assert-Pass -Condition ($service -match 'function Get-HybridUserAuthenticationProfile') -Message 'Hybrid user service authentication function present'
Assert-Pass -Condition ($service -match "'Get-HybridUserAuthenticationProfile'") -Message 'Hybrid user service authentication function exported'
Assert-Pass -Condition ($sim -match 'function Get-HybridDirectorySimulatorAuthenticationProfile') -Message 'Directory Simulator authentication function present'
Assert-Pass -Condition ($sim -match 'GetAuthenticationProfile') -Message 'Directory Simulator provider exposes authentication operation'

Remove-Module Application.HybridUserService,Infrastructure.DirectorySimulator -Force -ErrorAction SilentlyContinue
Import-Module $servicePath -Force
Import-Module $simPath -Force
$providers = New-HybridDirectorySimulatorProviders
Initialize-HybridUserService -ActiveDirectoryProvider $providers.ActiveDirectory -MicrosoftGraphProvider $providers.MicrosoftGraph -ExchangeOnlineProvider $providers.ExchangeOnline | Out-Null

$alex = Get-HybridUserAuthenticationProfile -Identity 'Alex Morgan'
$jordan = Get-HybridUserAuthenticationProfile -Identity 'Jordan Lee'
Assert-Pass -Condition ($null -ne $alex) -Message 'Alex authentication profile returned'
Assert-Pass -Condition ($null -ne $jordan) -Message 'Jordan authentication profile returned'
Assert-Pass -Condition (@($alex.AuthenticationMethods).Count -gt 0) -Message 'Alex authentication methods populated'
Assert-Pass -Condition (-not [string]::IsNullOrWhiteSpace($alex.AuthenticationStrength)) -Message 'Alex authentication strength populated'
Assert-Pass -Condition ($alex.UserPrincipalName -ne $jordan.UserPrincipalName) -Message 'Authentication card data changes by user identity'

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($uiPath, [ref]$tokens, [ref]$errors) | Out-Null
Assert-Pass -Condition (@($errors).Count -eq 0) -Message 'UI script parses successfully'

Write-Host ''
Write-Host 'Milestone 7 Phase 6 live Authentication card tests passed.'
