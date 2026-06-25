Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Content,[string]$Expected,[string]$Message)
    if ($Content -notlike "*$Expected*") { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$ui = Get-Content -LiteralPath (Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1') -Raw

Assert-Contains -Content $ui -Expected 'x:Name="SearchProgressPanel"' -Message 'Bottom status bar declares search progress panel'
Assert-Contains -Content $ui -Expected 'x:Name="SearchProgressStageText"' -Message 'Search progress has stage label'
Assert-Contains -Content $ui -Expected 'x:Name="CancelSearchButton"' -Message 'Search progress includes cancel button'
Assert-Contains -Content $ui -Expected 'function Set-HybridSearchProgressStage' -Message 'Search progress stage function exists'
Assert-Contains -Content $ui -Expected 'function Cancel-HybridUserSearch' -Message 'Search cancellation handler exists'
Assert-Contains -Content $ui -Expected 'function Start-HybridHydrationStageQueue' -Message 'Hydration uses staged queue starter'
Assert-Contains -Content $ui -Expected 'function Invoke-HybridHydrationStageQueueTick' -Message 'Hydration queue has dispatcher tick handler'
Assert-Contains -Content $ui -Expected '[System.Windows.Threading.DispatcherTimer]' -Message 'Hydration stages yield through WPF dispatcher timer'
Assert-Contains -Content $ui -Expected 'Publish-HybridUiRuntimeEvent' -Message 'Search and hydration publish runtime events'
Assert-Contains -Content $ui -Expected "'Search.Cancelled'" -Message 'Search cancellation publishes runtime event'
Assert-Contains -Content $ui -Expected "'Hydration.Completed'" -Message 'Hydration completion publishes runtime event'
foreach ($stage in @('Search','Base User','Active Directory Details','Microsoft Graph','Exchange Online','Authentication Posture','Aggregation','Complete')) {
    if ($ui -notlike "*Set-HybridSearchProgressStage -Stage '$stage'*" -and $ui -notlike "*ProgressStage = '$stage'*") {
        throw "FAIL: Search progress includes $stage stage"
    }
    Write-Host "PASS: Search progress includes $stage stage"
}
Assert-Contains -Content $ui -Expected "Exchange Online mailbox not loaded. Showing AD mail attribute only where available." -Message 'Exchange panel distinguishes AD mail from Exchange Online mailbox data'

Write-Host 'Milestone 8.9 search progress tests passed.'
