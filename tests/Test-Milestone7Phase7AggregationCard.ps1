Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Assert-Pass { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } Write-Host "PASS: $Message" }
$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$aggregationServicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserAggregationService.psm1'

Assert-Pass -Condition (Test-Path $uiPath) -Message 'UI entry point exists'
Assert-Pass -Condition (Test-Path $aggregationServicePath) -Message 'Aggregation service module exists'
$ui = Get-Content -LiteralPath $uiPath -Raw
Assert-Pass -Condition ($ui -match 'Profile Aggregation') -Message 'Profile Aggregation card is present in XAML'
Assert-Pass -Condition ($ui -match 'x:Name="AggregationStatusCard"') -Message 'Aggregation status card has named control'
Assert-Pass -Condition ($ui -match 'x:Name="AggregationVerticalsText"') -Message 'Aggregation vertical count field is present'
Assert-Pass -Condition ($ui -match 'function Update-AggregationPanel') -Message 'Aggregation update function is present'
Assert-Pass -Condition ($ui -match 'Get-HybridUserAggregateProfile') -Message 'UI consumes aggregate profile service'
Assert-Pass -Condition ($ui -match 'Update-AggregationPanel -User \$user -Query \$effectiveQuery') -Message 'Aggregation card updates during user search'
Assert-Pass -Condition (([regex]::Matches($ui,'x:Name="AggregationStatusCard"')).Count -eq 1) -Message 'Only one aggregation card exists'
$tokens = $null
$parseErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize($ui, [ref]$parseErrors)
Assert-Pass -Condition (@($parseErrors).Count -eq 0) -Message 'UI script parses successfully'
Write-Host "`nMilestone 7 Phase 7 aggregation card UI tests passed."
