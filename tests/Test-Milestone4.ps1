[CmdletBinding()]
param(
    [string]$Profile = 'Atlas'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $Root 'src'

function Assert-True {
    param([bool]$Condition, [string]$Message)
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

Assert-True (($loaded | Where-Object { $_.Name -eq 'Infrastructure.ActiveDirectory' } | Measure-Object).Count -eq 1) 'Active Directory provider module loaded'
Assert-True ($null -ne (Get-Command Initialize-HybridActiveDirectoryProvider -ErrorAction SilentlyContinue)) 'Initialize-HybridActiveDirectoryProvider exported'
Assert-True ($null -ne (Get-Command ConvertTo-HybridADUser -ErrorAction SilentlyContinue)) 'ConvertTo-HybridADUser exported'
Assert-True ($null -ne (Get-Command Search-HybridADUser -ErrorAction SilentlyContinue)) 'Search-HybridADUser exported'
Assert-True ($null -ne (Get-Command Reset-HybridADUserPassword -ErrorAction SilentlyContinue)) 'Password reset command exported'
Assert-True ($null -ne (Get-Command Set-HybridADUserEnabled -ErrorAction SilentlyContinue)) 'Enable disable command exported'
Assert-True ($null -ne (Get-Command Unlock-HybridADUser -ErrorAction SilentlyContinue)) 'Unlock command exported'
Assert-True ($null -ne (Get-Command Move-HybridADUserOU -ErrorAction SilentlyContinue)) 'OU move command exported'

$adService = Initialize-HybridActiveDirectoryProvider -Context $Context -NoNet
Assert-True ($adService.PSObject.TypeNames -contains 'Hybrid.ActiveDirectoryService') 'NoNet initialization returns Active Directory service object'
Assert-True ($adService.ProviderAvailable -eq $false) 'NoNet initialization does not require RSAT or domain access'
Assert-True (Test-HybridService -Name 'Directory') 'Existing mock Directory service remains registered during NoNet AD initialization'

$rawAdUser = [pscustomobject]@{
    ObjectGUID = [guid]'11111111-1111-1111-1111-111111111111'
    Name = 'Alex Morgan'
    GivenName = 'Alex'
    Surname = 'Morgan'
    SamAccountName = 'amorgan'
    UserPrincipalName = 'amorgan@atlas-tech.com'
    Mail = 'amorgan@atlas-tech.com'
    EmployeeID = '10001'
    EmployeeNumber = 'A1001'
    extensionAttribute1 = 'A1001'
    Department = 'Information Technology'
    Title = 'Systems Administrator'
    Company = 'Atlas Tech'
    physicalDeliveryOfficeName = 'Hybrid Admin Lab'
    Manager = 'CN=Morgan Rivera,OU=Users,DC=atlas-tech,DC=com'
    DirectReports = @('CN=Taylor Smith,OU=Users,DC=atlas-tech,DC=com')
    Enabled = $true
    LockedOut = $false
    DistinguishedName = 'CN=Alex Morgan,OU=Users,DC=atlas-tech,DC=com'
}

$hybridUser = ConvertTo-HybridADUser -InputObject $rawAdUser
Assert-True ($hybridUser.PSObject.TypeNames -contains 'Hybrid.User') 'AD user converts to Hybrid.User'
Assert-True ($hybridUser.Source -eq 'ActiveDirectory') 'Converted user source is ActiveDirectory'
Assert-True ($hybridUser.DisplayName -eq 'Alex Morgan') 'Display name mapped'
Assert-True ($hybridUser.SamAccountName -eq 'amorgan') 'SAM account mapped'
Assert-True ($hybridUser.UserPrincipalName -eq 'amorgan@atlas-tech.com') 'UPN mapped'
Assert-True ($hybridUser.EmployeeId -eq '10001') 'Employee ID mapped'
Assert-True ($hybridUser.BadgeId -eq 'A1001') 'Badge ID mapped'
Assert-True ($hybridUser.Attributes.DistinguishedName -eq 'CN=Alex Morgan,OU=Users,DC=atlas-tech,DC=com') 'Distinguished name preserved in attributes'
Assert-True ($hybridUser.Attributes.ManagerDn -eq 'CN=Morgan Rivera,OU=Users,DC=atlas-tech,DC=com') 'Manager DN preserved in attributes'
Assert-True (@($hybridUser.Attributes.DirectReportDns).Count -eq 1) 'Direct report DNs preserved in attributes'

Write-Host ''
Write-Host 'Milestone 4 Active Directory provider foundation tests passed.' -ForegroundColor Cyan
