Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Content,[string]$Expected,[string]$Message)
    if ($Content -notlike "*$Expected*") { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$ui = Get-Content -LiteralPath (Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1') -Raw

Assert-Contains -Content $ui -Expected 'x:Name="BackToStartButton"' -Message 'Main console declares Back/Start button'
Assert-Contains -Content $ui -Expected 'Show-HybridHomeView' -Message 'Runtime home view function exists'
Assert-Contains -Content $ui -Expected 'BackToStartButton.Add_Click({ Show-HybridHomeView })' -Message 'Back/Start button reopens Runtime Home'
Assert-Contains -Content $ui -Expected "Home view opened." -Message 'Runtime Home navigation updates status text'

Write-Host 'Milestone 8.9 runtime navigation tests passed.'
