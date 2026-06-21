Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
function Assert-Pass { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } Write-Host "PASS: $Message" }
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$managerPath = Join-Path $repoRoot 'src\Application\Application.RuntimeProfileManager.psm1'
Assert-Pass (Test-Path $uiPath) 'Hybrid Admin Console UI script exists'
Assert-Pass (Test-Path $managerPath) 'Runtime Profile Manager module exists'
Import-Module $managerPath -Force
foreach ($command in @('Get-HybridRuntimeProfileSummary','Get-HybridRuntimeProfileSelection','Set-HybridRuntimeProfileSelection','Update-HybridRuntimeProfileManager','Copy-HybridRuntimeProfile','Remove-HybridRuntimeProfile','Set-HybridRuntimeProfileDefault','Export-HybridRuntimeProfile')) {
    Assert-Pass ([bool](Get-Command $command -ErrorAction SilentlyContinue)) "Runtime Profile Manager exports $command"
}
$source = Get-Content -LiteralPath $uiPath -Raw
foreach ($marker in @(
    'Phase 8.3 RuntimeSummaryPanel',
    'Phase 8.4 ProfileOperations',
    'Phase 8.5 LaunchWorkflow',
    'Phase 8.6 PersistentRuntimeStatus',
    'LaunchProgressView',
    'LaunchProgressText',
    'DuplicateRuntimeProfileButton',
    'DeleteRuntimeProfileButton',
    'ImportRuntimeProfileButton',
    'ExportRuntimeProfileButton',
    'SetDefaultRuntimeProfileButton',
    'RuntimeAuthenticationText',
    'Update-HybridPersistentRuntimeStatus',
    'Invoke-HybridRuntimeProfileLaunch',
    'Copy-HybridSelectedRuntimeProfile',
    'Remove-HybridSelectedRuntimeProfile',
    'Export-HybridSelectedRuntimeProfile',
    'Set-HybridSelectedRuntimeProfileDefault'
)) {
    Assert-Pass ($source.Contains($marker)) "Final integration marker exists: $marker"
}
Assert-Pass (-not $source.Contains('Device Code authentication enabled')) 'UI source does not enable Device Code authentication'
Assert-Pass ($source.Contains('Device Code disabled')) 'Authentication posture explicitly reports Device Code disabled'
Assert-Pass ($source.Contains('Add-Type -AssemblyName System.Windows.Forms')) 'Launch workflow can pump UI progress updates'
$match = [regex]::Match($source, '(?s)\$xaml = @"\r?\n(.*?)\r?\n"@')
Assert-Pass $match.Success 'XAML block was found'
[xml]$null = $match.Groups[1].Value
Assert-Pass $true 'Final integration XAML is well-formed XML'
$profiles = @(Get-HybridRuntimeProfileSummary -RepositoryRoot $repoRoot)
Assert-Pass ($profiles.Count -gt 0) 'Runtime Profile Manager discovers profiles'
Assert-Pass ([bool](Get-HybridRuntimeProfileSelection -RepositoryRoot $repoRoot)) 'Runtime Profile Manager resolves startup selection'
Assert-Pass (Test-Path (Join-Path $repoRoot 'docs\Milestones\MILESTONE_8_FINAL_INTEGRATION.md')) 'Milestone 8 final integration document exists'
Write-Host ''
Write-Host 'Milestone 8 final runtime platform integration tests passed.'
