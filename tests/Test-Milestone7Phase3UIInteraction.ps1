Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$content = Get-Content -Path $uiPath -Raw

Assert-True ($content -match 'function\s+Invoke-UserSearch') 'UI has a single manual search flow'
Assert-True ($content -match '\$controls\.SearchButton\.Add_Click\(\{\s*Invoke-UserSearch -Query \$controls\.SearchBox\.Text') 'Search button reads current textbox value'
Assert-True ($content -match '\$controls\.SearchBox\.Add_KeyDown') 'Enter key handler is wired'
Assert-True ($content -match '\$eventArgs\.Handled\s*=\s*\$true') 'Enter key handler marks event handled'
Assert-True ($content -match '\$script:CurrentSearchQuery\s*=\s*\$effectiveQuery') 'Search flow tracks current query'
Assert-True ($content -match '\$script:SelectedHybridUser\s*=\s*\$null') 'Search flow clears selected user before a new search'
Assert-True ($content -match 'New-HybridMockUserRecord') 'Mock user records are generated from query input'
Assert-True ($content -match 'SearchUser\s*=\s*\{\s*param\(\[string\]\$Query\)\s*@\(New-HybridMockUserRecord -Query \$Query\)') 'Mock search provider is not pinned to initial Alex record'
Assert-True ($content -match 'Search complete: \$effectiveQuery') 'Status reflects the current search query'

Write-Host "`nMilestone 7 Phase 3 UI interaction tests passed."
