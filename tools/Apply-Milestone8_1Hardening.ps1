<#
.SYNOPSIS
Applies Milestone 8.1 Runtime Platform Hardening changed files into the repository.
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dropRoot = Split-Path -Parent $PSScriptRoot
$files = @(
    'Start-AtlasHybridAdminConsole.ps1',
    'src\UI\Start-HybridAdminConsole.ps1',
    'src\UI\UI.Theme.psm1',
    'src\UI\UI.RuntimeHome.psm1',
    'src\UI\UI.RuntimeLaunch.psm1',
    'src\UI\UI.RuntimeProfileManager.psm1',
    'src\UI\UI.RuntimeProfileWizard.psm1',
    'src\UI\UI.UserDashboard.psm1',
    'src\UI\UI.StatusBar.psm1',
    'src\Core\Core.Theme.psm1',
    'src\Core\Core.Runtime.psm1',
    'src\Core\Core.Deployment.psm1',
    'src\Application\Application.RuntimeProfileManager.psm1',
    'assets\themes\hap.theme.example.json',
    'tests\Test-Milestone8_1Hardening.ps1',
    'tests\Test-Milestone8Phase2.ps1',
    'tests\Test-Milestone8Phase7.ps1',
    'docs\VERSION.md',
    'docs\PROJECT_STATUS.md',
    'docs\ROADMAP.md',
    'docs\CHANGELOG.md',
    'docs\Milestones\MILESTONE_8_COMPLETE.md',
    'docs\Milestones\MILESTONE_8_1_HARDENING.md'
)

foreach ($relativePath in $files) {
    $source = Join-Path $dropRoot $relativePath
    $target = Join-Path $RepositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Drop file missing: $relativePath"
    }
    $targetDirectory = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
        New-Item -Path $targetDirectory -ItemType Directory -Force | Out-Null
    }
    Copy-Item -LiteralPath $source -Destination $target -Force
    Write-Host "Applied $relativePath"
}

Write-Host 'Milestone 8.1 Runtime Platform Hardening files applied.'
Write-Host 'Run: .\tests\Test-Milestone8_1Hardening.ps1'
