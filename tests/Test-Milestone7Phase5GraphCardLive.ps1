Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$simPath = Join-Path $repoRoot 'src\Infrastructure\Mock\Infrastructure.DirectorySimulator.psm1'

Assert-Pass -Condition (Test-Path $uiPath) -Message 'UI entry point exists'
Assert-Pass -Condition (Test-Path $simPath) -Message 'Directory Simulator module exists'

$ui = Get-Content -Path $uiPath -Raw
$sim = Get-Content -Path $simPath -Raw

Assert-Pass -Condition ($ui -like '*MicrosoftGraphCard*') -Message 'Microsoft Graph card is present in XAML'
Assert-Pass -Condition ($ui -like '*GraphObjectIdText*') -Message 'Graph object ID field is present'
Assert-Pass -Condition ($ui -like '*GraphAuthenticationMethodsText*') -Message 'Graph authentication methods field is present'
Assert-Pass -Condition ($ui -like '*function Update-GraphPanels*') -Message 'Graph update function is present'
Assert-Pass -Condition ($ui -like '*Update-GraphPanels -User $user -Query $effectiveQuery*') -Message 'Graph card is updated during user search'
Assert-Pass -Condition ($ui -notlike '*Add-HybridMilestone7Phase5UiWiring*') -Message 'Old button wiring is absent'
Assert-Pass -Condition (($ui | Select-String -Pattern 'x:Name="MicrosoftGraphCard"' -AllMatches).Matches.Count -eq 1) -Message 'Only one Microsoft Graph card exists'

Assert-Pass -Condition ($sim -like '*Get-HybridDirectorySimulatorGraphProfile*') -Message 'Directory Simulator exposes Graph profile function'
Assert-Pass -Condition ($sim -like '*GetGraphProfile =*Get-HybridDirectorySimulatorGraphProfile*') -Message 'Directory Simulator Graph provider has GetGraphProfile operation'
Assert-Pass -Condition ($sim -like '*GetUserGraphProfile =*Get-HybridDirectorySimulatorGraphProfile*') -Message 'Directory Simulator Graph provider has GetUserGraphProfile operation'

Remove-Module Infrastructure.DirectorySimulator -Force -ErrorAction SilentlyContinue
Import-Module $simPath -Force
$providers = New-HybridDirectorySimulatorProviders
Assert-Pass -Condition ($providers.MicrosoftGraph.PSObject.Properties.Name -contains 'GetGraphProfile') -Message 'Graph provider object exposes GetGraphProfile'
$alex = & $providers.MicrosoftGraph.GetGraphProfile 'amorgan@atlas-tech.com'
$jordan = & $providers.MicrosoftGraph.GetGraphProfile 'jlee@atlas-tech.com'
Assert-Pass -Condition ($null -ne $alex) -Message 'Graph provider returns Alex profile'
Assert-Pass -Condition ($null -ne $jordan) -Message 'Graph provider returns Jordan profile'
Assert-Pass -Condition (-not [string]::IsNullOrWhiteSpace($alex.ObjectId)) -Message 'Alex Graph object ID populated'
Assert-Pass -Condition (@($alex.AuthenticationMethods).Count -gt 1) -Message 'Alex Graph authentication methods populated'
Assert-Pass -Condition ($alex.ObjectId -ne $jordan.ObjectId) -Message 'Different users receive different Graph object IDs'

$tokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($uiPath, [ref]$tokens, [ref]$parseErrors)
Assert-Pass -Condition (@($parseErrors).Count -eq 0) -Message 'UI script parses successfully'

Write-Host ''
Write-Host 'Milestone 7 Phase 5 live Microsoft Graph card tests passed.'
