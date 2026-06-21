Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$userServicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
$aggregationServicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserAggregationService.psm1'
$simulatorPath = Join-Path $repoRoot 'src\Infrastructure\Mock\Infrastructure.DirectorySimulator.psm1'
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

Remove-Module Application.HybridUserAggregationService,Application.HybridUserService,Infrastructure.DirectorySimulator -Force -ErrorAction SilentlyContinue
Import-Module $userServicePath -Force
Import-Module $aggregationServicePath -Force
Import-Module $simulatorPath -Force

Assert-Pass -Condition ([bool](Get-Command Initialize-HybridUserAggregationService -ErrorAction SilentlyContinue)) -Message 'Aggregation service initializer exported'
Assert-Pass -Condition ([bool](Get-Command Get-HybridUserAggregateProfile -ErrorAction SilentlyContinue)) -Message 'Aggregate profile getter exported'
Assert-Pass -Condition ([bool](Get-Command Get-HybridUserAggregationServiceHealth -ErrorAction SilentlyContinue)) -Message 'Aggregation service health exported'

$providers = New-HybridDirectorySimulatorProviders
Initialize-HybridUserService -ActiveDirectoryProvider $providers.ActiveDirectory -MicrosoftGraphProvider $providers.MicrosoftGraph -ExchangeOnlineProvider $providers.ExchangeOnline | Out-Null
$aggregationService = Initialize-HybridUserAggregationService
Assert-Pass -Condition ($aggregationService.PSTypeName -eq 'Hybrid.UserAggregationService') -Message 'Aggregation service has platform type name'

$alex = Get-HybridUserAggregateProfile -Identity 'amorgan@atlas-tech.com'
Assert-Pass -Condition ($null -ne $alex) -Message 'Aggregate profile returned for Alex Morgan'
Assert-Pass -Condition ($alex.PSTypeName -eq 'Hybrid.UserAggregateProfile') -Message 'Aggregate profile has canonical type name'
Assert-Pass -Condition ($alex.PSObject.TypeNames -contains 'Hybrid.UserAggregateProfile.Milestone7Phase7') -Message 'Aggregate profile has phase type name'
Assert-Pass -Condition ($alex.UserPrincipalName -eq 'amorgan@atlas-tech.com') -Message 'Aggregate profile preserves UPN'
Assert-Pass -Condition ($null -ne $alex.User) -Message 'Aggregate includes base/detail user'
Assert-Pass -Condition ($null -ne $alex.MailboxDetails) -Message 'Aggregate includes Exchange mailbox details'
Assert-Pass -Condition ($null -ne $alex.GraphProfile) -Message 'Aggregate includes Microsoft Graph profile'
Assert-Pass -Condition ($null -ne $alex.AuthenticationProfile) -Message 'Aggregate includes authentication posture'
Assert-Pass -Condition ($alex.TotalVerticalCount -ge 5) -Message 'Aggregate tracks expected vertical count'
Assert-Pass -Condition ($alex.LoadedVerticalCount -ge 5) -Message 'Aggregate reports loaded verticals'
Assert-Pass -Condition ($alex.Complete -eq $true) -Message 'Aggregate reports complete vertical profile'

$verticalNames = @($alex.Verticals | ForEach-Object { $_.Name })
Assert-Pass -Condition ($verticalNames -contains 'BaseUser') -Message 'Aggregate tracks base user vertical'
Assert-Pass -Condition ($verticalNames -contains 'ActiveDirectoryDetails') -Message 'Aggregate tracks AD detail vertical'
Assert-Pass -Condition ($verticalNames -contains 'ExchangeMailbox') -Message 'Aggregate tracks Exchange vertical'
Assert-Pass -Condition ($verticalNames -contains 'MicrosoftGraph') -Message 'Aggregate tracks Graph vertical'
Assert-Pass -Condition ($verticalNames -contains 'AuthenticationPosture') -Message 'Aggregate tracks authentication vertical'

$cached = Get-HybridUserAggregateProfile -Identity 'amorgan@atlas-tech.com'
Assert-Pass -Condition ([object]::ReferenceEquals($alex, $cached)) -Message 'Aggregate profile returns stable cached result'

$health = Get-HybridUserAggregationServiceHealth
Assert-Pass -Condition ($health.Initialized -eq $true) -Message 'Aggregation service health reports initialized'
Assert-Pass -Condition ($health.CacheEntries -ge 1) -Message 'Aggregation service health reports cache entries'
Assert-Pass -Condition ($health.LastIdentity -eq 'amorgan@atlas-tech.com') -Message 'Aggregation service health tracks last identity'

$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $uiPath -Raw), [ref]$null)
Assert-Pass -Condition $true -Message 'UI script parses successfully'

Write-Host "`nMilestone 7 Phase 7 aggregation layer tests passed."
