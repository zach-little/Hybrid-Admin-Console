$ErrorActionPreference = 'Stop'
$testRoot = $PSScriptRoot
& (Join-Path $testRoot 'Test-Milestone8_9DnOuDisplay.ps1')
& (Join-Path $testRoot 'Test-Milestone8_9RuntimeNavigation.ps1')
& (Join-Path $testRoot 'Test-Milestone8_9SearchProgress.ps1')
& (Join-Path $testRoot 'Test-Milestone8_9DuplicateUserChooser.ps1')
& (Join-Path $testRoot 'Test-Milestone8_9ExchangeOnPremisesProvider.ps1')
Write-Host 'Milestone 8.9 live runtime stabilization cumulative tests passed.'
