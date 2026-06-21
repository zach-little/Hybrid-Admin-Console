Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot

Remove-Module Application.AuthenticationProfileService,Application.HybridUserService,Infrastructure.DirectorySimulator,DirectorySimulator.AuthenticationVertical,Hybrid.AuthenticationProfile -Force -ErrorAction SilentlyContinue

Import-Module (Join-Path $repoRoot 'src\Models\Hybrid.AuthenticationProfile.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\Application\Application.AuthenticationProfileService.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\Infrastructure\Mock\Infrastructure.DirectorySimulator.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\Infrastructure\DirectorySimulator\DirectorySimulator.AuthenticationVertical.psm1') -Force

Assert-Pass -Condition ([bool](Get-Command New-HybridAuthenticationProfile -ErrorAction SilentlyContinue)) -Message 'Hybrid Authentication profile model factory exported'
Assert-Pass -Condition ([bool](Get-Command Initialize-HybridAuthenticationProfileService -ErrorAction SilentlyContinue)) -Message 'Authentication profile service initializer exported'
Assert-Pass -Condition ([bool](Get-Command Get-HybridAuthenticationProfile -ErrorAction SilentlyContinue)) -Message 'Authentication profile service getter exported'
Assert-Pass -Condition ([bool](Get-Command New-HybridDirectorySimulatorAuthenticationProfile -ErrorAction SilentlyContinue)) -Message 'Directory Simulator authentication profile factory exported'
Assert-Pass -Condition ([bool](Get-Command Get-HybridUserAuthenticationProfile -ErrorAction SilentlyContinue)) -Message 'Hybrid user service authentication getter exported'

$providers = New-HybridDirectorySimulatorProviders
Assert-Pass -Condition ($providers.MicrosoftGraph.PSObject.Properties.Name -contains 'GetAuthenticationProfile') -Message 'Directory Simulator Graph provider exposes authentication operation'
Assert-Pass -Condition ($providers.MicrosoftGraph.PSObject.Properties.Name -contains 'GetUserAuthenticationProfile') -Message 'Directory Simulator Graph provider exposes user authentication operation'

$service = Initialize-HybridAuthenticationProfileService -MicrosoftGraphProvider $providers.MicrosoftGraph
Assert-Pass -Condition ($service.PSObject.TypeNames -contains 'Hybrid.AuthenticationProfileService') -Message 'Authentication profile service has platform type name'

$alexAuth = Get-HybridAuthenticationProfile -Identity 'Alex Morgan'
Assert-Pass -Condition ($null -ne $alexAuth) -Message 'Authentication profile returned for Alex Morgan'
Assert-Pass -Condition ($alexAuth.PSObject.TypeNames -contains 'Hybrid.AuthenticationProfile') -Message 'Authentication profile has canonical type name'
Assert-Pass -Condition ($alexAuth.UserPrincipalName -like '*@atlas-tech.com') -Message 'Authentication profile preserves UPN'
Assert-Pass -Condition (@($alexAuth.AuthenticationMethods).Count -gt 0) -Message 'Authentication profile includes authentication methods'
Assert-Pass -Condition (-not [string]::IsNullOrWhiteSpace($alexAuth.AuthenticationStrength)) -Message 'Authentication strength populated'
Assert-Pass -Condition (-not [string]::IsNullOrWhiteSpace($alexAuth.ConditionalAccessState)) -Message 'Conditional Access state populated'

Clear-HybridAuthenticationProfileService | Out-Null
Initialize-HybridUserService -ActiveDirectoryProvider $providers.ActiveDirectory -MicrosoftGraphProvider $providers.MicrosoftGraph -ExchangeOnlineProvider $providers.ExchangeOnline | Out-Null
$serviceAuth = Get-HybridUserAuthenticationProfile -Identity 'Alex Morgan'
Assert-Pass -Condition ($null -ne $serviceAuth) -Message 'Hybrid user service returns authentication profile'
Assert-Pass -Condition ($serviceAuth.PSObject.TypeNames -contains 'Hybrid.AuthenticationProfile') -Message 'Hybrid user service returns canonical authentication profile'
Assert-Pass -Condition (@($serviceAuth.AuthenticationMethods).Count -gt 0) -Message 'Hybrid user service authentication methods populated'

$jordanAuth = Get-HybridUserAuthenticationProfile -Identity 'Jordan Lee'
Assert-Pass -Condition ($null -ne $jordanAuth) -Message 'Authentication profile returned for second user'
Assert-Pass -Condition ($serviceAuth.UserPrincipalName -ne $jordanAuth.UserPrincipalName) -Message 'Different users receive distinct authentication profiles'

$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$ui = Get-Content -LiteralPath $uiPath -Raw
Assert-Pass -Condition ($ui -match 'Authentication Posture') -Message 'UI includes Authentication Posture card'
Assert-Pass -Condition ($ui -match 'Update-AuthenticationPanels') -Message 'UI includes authentication update function'
Assert-Pass -Condition ($ui -match 'Get-HybridUserAuthenticationProfile') -Message 'UI consumes authentication service getter'

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($uiPath, [ref]$tokens, [ref]$errors) | Out-Null
Assert-Pass -Condition (@($errors).Count -eq 0) -Message 'UI script parses successfully'

Write-Host ''
Write-Host 'Milestone 7 Phase 6 Authentication vertical tests passed.'
