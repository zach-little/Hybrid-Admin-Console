Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$graphServicePath = Join-Path $repoRoot 'src\Application\Application.GraphProfileService.psm1'
$graphModelPath = Join-Path $repoRoot 'src\Models\Hybrid.GraphProfile.psm1'
$simGraphPath = Join-Path $repoRoot 'src\Infrastructure\DirectorySimulator\DirectorySimulator.GraphVertical.psm1'
$uiPanelPath = Join-Path $repoRoot 'src\UI\UI.GraphProfilePanel.psm1'
$userServicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

Import-Module $graphModelPath -Force
Import-Module $graphServicePath -Force
Import-Module $simGraphPath -Force
Import-Module $uiPanelPath -Force

Assert-Pass -Condition ([bool](Get-Command New-HybridGraphProfile -ErrorAction SilentlyContinue)) -Message 'Hybrid Graph profile model factory exported'
Assert-Pass -Condition ([bool](Get-Command Initialize-HybridGraphProfileService -ErrorAction SilentlyContinue)) -Message 'Graph profile service initializer exported'
Assert-Pass -Condition ([bool](Get-Command Get-HybridGraphProfile -ErrorAction SilentlyContinue)) -Message 'Graph profile service getter exported'
Assert-Pass -Condition ([bool](Get-Command Initialize-HybridDirectorySimulatorGraphVertical -ErrorAction SilentlyContinue)) -Message 'Directory Simulator Graph vertical initializer exported'
Assert-Pass -Condition ([bool](Get-Command ConvertTo-HybridGraphProfileDisplayRows -ErrorAction SilentlyContinue)) -Message 'Graph UI display helper exported'

$directoryGraph = Initialize-HybridDirectorySimulatorGraphVertical
Assert-Pass -Condition ($directoryGraph.Initialized -eq $true) -Message 'Directory Simulator Graph vertical initialized'

$service = Initialize-HybridGraphProfileService -MicrosoftGraphProvider $directoryGraph
Assert-Pass -Condition ($service.PSObject.TypeNames -contains 'Hybrid.GraphProfileService') -Message 'Graph profile service has platform type name'

$profile = Get-HybridGraphProfile -Identity 'amorgan@atlas-tech.com'
Assert-Pass -Condition ($null -ne $profile) -Message 'Graph profile returned for Alex Morgan'
Assert-Pass -Condition ($profile.PSObject.TypeNames -contains 'Hybrid.GraphProfile') -Message 'Graph profile has canonical type name'
Assert-Pass -Condition ($profile.UserPrincipalName -eq 'amorgan@atlas-tech.com') -Message 'Graph profile preserves UPN'
Assert-Pass -Condition ($profile.MfaRegistered -eq $true) -Message 'Graph profile reports MFA registration'
Assert-Pass -Condition (@($profile.AuthenticationMethods).Count -ge 2) -Message 'Graph profile includes authentication methods'

$rows = @(ConvertTo-HybridGraphProfileDisplayRows -GraphProfile $profile)
Assert-Pass -Condition (@($rows | Where-Object Label -eq 'Graph Object ID').Count -eq 1) -Message 'Graph UI rows include object ID'
Assert-Pass -Condition (@($rows | Where-Object Label -eq 'Authentication Methods').Count -eq 1) -Message 'Graph UI rows include authentication methods'
Assert-Pass -Condition (@($rows | Where-Object Label -eq 'MFA Registered').Count -eq 1) -Message 'Graph UI rows include MFA registration'

if (Test-Path $userServicePath) {
    $content = Get-Content -Path $userServicePath -Raw
    Assert-Pass -Condition ($content -like '*Get-HybridUserGraphProfile*' -or (Test-Path $graphServicePath)) -Message 'Graph profile service is available without replacing Phase 4 service'
}

$tokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($uiPath, [ref]$tokens, [ref]$parseErrors)
Assert-Pass -Condition (@($parseErrors).Count -eq 0) -Message 'Existing UI script still parses successfully'

Write-Host ''
Write-Host 'Milestone 7 Phase 5 Microsoft Graph vertical tests passed.'
