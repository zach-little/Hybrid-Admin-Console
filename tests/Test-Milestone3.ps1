[CmdletBinding()]
param(
    [string]$Profile = 'Atlas'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $Root 'src'

function Assert-True {
    param([bool]$Condition,[string]$Message)

    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

Import-Module (Join-Path $Source 'Core\Core.Paths.psm1') -Force -Global
Import-Module (Join-Path $Source 'Core\Core.ModuleLoader.psm1') -Force -Global

$Context = New-HybridHostContext
Initialize-HybridPaths -Context $Context -RootPath $Root | Out-Null
$loaded = Import-HybridModuleTree -SourcePath $Source -Refresh -Global

Initialize-HybridEnvironment -Context $Context -NoNet | Out-Null
Initialize-HybridLogging -Context $Context -Level Debug -NoConsole | Out-Null
Initialize-HybridCache -Context $Context | Out-Null
Initialize-HybridServiceRegistry -Context $Context | Out-Null
Initialize-HybridPluginRegistry -Context $Context | Out-Null
Initialize-HybridConfiguration -Context $Context -ProfileName $Profile | Out-Null
Initialize-HybridTheme -Context $Context | Out-Null
Initialize-HybridApplicationServices -Context $Context | Out-Null

Assert-True (($loaded | Where-Object { $_.Name -eq 'Hybrid.Models' } | Measure-Object).Count -eq 1) 'Hybrid model module loaded'
Assert-True (($loaded | Where-Object { $_.Name -eq 'Application.UserService' } | Measure-Object).Count -eq 1) 'User service module loaded'
Assert-True (Test-HybridService -Name 'Directory') 'Directory service registered'
Assert-True (Test-HybridService -Name 'User') 'User service registered'

$plainAlex = Get-HybridUser -Identity 'amorgan@atlas-tech.com'
Assert-True ($null -ne $plainAlex) 'Plain user lookup returns Alex Morgan'
Assert-True ($plainAlex.PSObject.TypeNames -contains 'Hybrid.User') 'Plain user is Hybrid.User'
Assert-True ($plainAlex.Groups.Count -eq 0) 'Plain user is not group-hydrated'
Assert-True ($null -eq $plainAlex.Mailbox) 'Plain user is not mailbox-hydrated'
Assert-True ($plainAlex.Devices.Count -eq 0) 'Plain user is not device-hydrated'
Assert-True ($plainAlex.Licenses.Count -eq 0) 'Plain user is not license-hydrated'
Assert-True (-not [bool]$plainAlex.Hydration.Groups) 'Plain user hydration metadata tracks groups as false'

$hydratedAlex = Get-HybridUser -Identity 'amorgan@atlas-tech.com' -IncludeRelated
Assert-True ($null -ne $hydratedAlex) 'Hydrated user lookup returns Alex Morgan'
Assert-True ($hydratedAlex.Groups.Count -ge 4) 'Hydrated user has groups'
Assert-True ($null -ne $hydratedAlex.Mailbox) 'Hydrated user has mailbox'
Assert-True ($hydratedAlex.Devices.Count -ge 1) 'Hydrated user has devices'
Assert-True ($hydratedAlex.Licenses.Count -ge 1) 'Hydrated user has licenses'
Assert-True ([bool]$hydratedAlex.Hydration.Groups) 'Hydrated user metadata tracks groups as true'
Assert-True ([bool]$hydratedAlex.Hydration.Mailbox) 'Hydrated user metadata tracks mailbox as true'
Assert-True ([bool]$hydratedAlex.Hydration.Devices) 'Hydrated user metadata tracks devices as true'
Assert-True ([bool]$hydratedAlex.Hydration.Licenses) 'Hydrated user metadata tracks licenses as true'

$plainAlexAgain = Get-HybridUser -Identity 'amorgan@atlas-tech.com'
Assert-True ($plainAlexAgain.Groups.Count -eq 0) 'Hydration does not mutate stored mock user groups'
Assert-True ($null -eq $plainAlexAgain.Mailbox) 'Hydration does not mutate stored mock user mailbox'
Assert-True ($plainAlexAgain.Devices.Count -eq 0) 'Hydration does not mutate stored mock user devices'
Assert-True ($plainAlexAgain.Licenses.Count -eq 0) 'Hydration does not mutate stored mock user licenses'

$overview = Get-HybridUserOverview -Identity 'amorgan@atlas-tech.com'
Assert-True ($null -ne $overview) 'User overview returns a model'
Assert-True ($overview.PSObject.TypeNames -contains 'Hybrid.UserOverview') 'Overview is Hybrid.UserOverview'
Assert-True ($overview.User.PSObject.TypeNames -contains 'Hybrid.User') 'Overview contains Hybrid.User'
Assert-True ($overview.DisplayName -eq 'Alex Morgan') 'Overview display name populated'
Assert-True ($overview.GroupCount -eq $hydratedAlex.Groups.Count) 'Overview group count matches hydration'
Assert-True ($overview.DeviceCount -eq $hydratedAlex.Devices.Count) 'Overview device count matches hydration'
Assert-True ($overview.LicenseCount -eq $hydratedAlex.Licenses.Count) 'Overview license count matches hydration'
Assert-True ($overview.HasMailbox) 'Overview reports mailbox present'
Assert-True ($overview.Cards.Count -ge 5) 'Overview exposes card-ready models'
Assert-True (($overview.Cards | Where-Object { $_.Name -eq 'Identity' } | Measure-Object).Count -eq 1) 'Overview contains identity card'
Assert-True (($overview.Cards | Where-Object { $_.Name -eq 'Groups' } | Measure-Object).Count -eq 1) 'Overview contains groups card'
Assert-True (($overview.Cards | Where-Object { $_.Name -eq 'Mailbox' } | Measure-Object).Count -eq 1) 'Overview contains mailbox card'
Assert-True (($overview.Cards | Where-Object { $_.Name -eq 'Devices' } | Measure-Object).Count -eq 1) 'Overview contains devices card'
Assert-True (($overview.Cards | Where-Object { $_.Name -eq 'Licenses' } | Measure-Object).Count -eq 1) 'Overview contains licenses card'

$missingOverview = Get-HybridUserOverview -Identity 'doesnotexist'
Assert-True ($null -eq $missingOverview) 'Missing user overview returns null'

Write-Host ''
Write-Host 'Milestone 3 domain hydration tests passed.' -ForegroundColor Cyan
