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

Assert-True (($loaded | Where-Object { $_.Name -eq 'Application.UserService' } | Measure-Object).Count -eq 1) 'User service module loaded'
Assert-True (Test-HybridService -Name 'Directory') 'Directory service registered'
Assert-True (Test-HybridService -Name 'User') 'User service registered'

$allUsers = @(Search-HybridUser)
Assert-True ($allUsers.Count -ge 5) 'Mock user search returns seeded users'
$firstUser = @($allUsers)[0]
Assert-True ($firstUser.PSObject.TypeNames -contains 'Hybrid.User') 'Search returns Hybrid.User models'

# Retrieve a fully hydrated user
$alex = Get-HybridUser -Identity "amorgan@atlas-tech.com"

Assert-True ($null -ne $alex) 'Get-HybridUser returns Alex Morgan'
Assert-True ($alex.DisplayName -eq 'Alex Morgan') 'Display name populated'
Assert-True ($alex.SamAccountName -eq 'amorgan') 'SAM account populated'
Assert-True ($alex.UserPrincipalName -eq 'amorgan@atlas-tech.com') 'UPN populated'

# User model
Assert-True ($alex.PSObject.TypeNames -contains 'Hybrid.User') 'Returned object is Hybrid.User'

Assert-True ($alex.PSObject.Properties.Name -contains 'Mailbox') 'User model exposes Mailbox property'
Assert-True ($alex.PSObject.Properties.Name -contains 'Groups') 'User model exposes Groups property'
Assert-True ($alex.PSObject.Properties.Name -contains 'Devices') 'User model exposes Devices property'
Assert-True ($alex.PSObject.Properties.Name -contains 'Licenses') 'User model exposes Licenses property'

Write-Host ""
Write-Host "Milestone 2 domain model tests passed." -ForegroundColor Green
return

$securityUsers = @(Search-HybridUser -Query 'Security')
Assert-True (($securityUsers | Where-Object { $_.SamAccountName -eq 'tsmith' }).Count -eq 1) 'Search supports department matching'

$missing = Get-HybridUser -Identity 'doesnotexist'
Assert-True ($null -eq $missing) 'Unknown user returns null'

Write-Host ''
Write-Host 'Milestone 2 user service tests passed.' -ForegroundColor Cyan
