Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$serviceModule = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
$uiScript = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

Import-Module $serviceModule -Force

$mockAd = [pscustomobject]@{
    SearchUser = { param([string]$Query)
        @([pscustomobject]@{
            DisplayName       = 'Alex Morgan'
            SamAccountName    = 'amorgan'
            UserPrincipalName = 'amorgan@atlas-tech.com'
            Mail              = 'amorgan@atlas-tech.com'
            Department        = 'Information Technology'
            Title             = 'Systems Administrator'
            Manager           = 'CN=Taylor Reed,OU=Managers,OU=Users,DC=atlas-tech,DC=com'
            DistinguishedName = 'CN=Alex Morgan,OU=Service Desk,OU=Users,DC=atlas-tech,DC=com'
            Enabled           = $true
            LockedOut         = $false
        })
    }.GetNewClosure()
    GetUser = { param([string]$Identity)
        [pscustomobject]@{
            DisplayName       = 'Alex Morgan'
            SamAccountName    = 'amorgan'
            UserPrincipalName = 'amorgan@atlas-tech.com'
            Mail              = 'amorgan@atlas-tech.com'
            Department        = 'Information Technology'
            Title             = 'Systems Administrator'
            Manager           = 'CN=Taylor Reed,OU=Managers,OU=Users,DC=atlas-tech,DC=com'
            DistinguishedName = 'CN=Alex Morgan,OU=Service Desk,OU=Users,DC=atlas-tech,DC=com'
            Enabled           = $true
            LockedOut         = $false
        }
    }.GetNewClosure()
    GetUserGroups = { param([string]$Identity)
        @(
            [pscustomobject]@{ Name = 'IT Helpdesk' }
            [pscustomobject]@{ Name = 'Hybrid Admin Console Operators' }
        )
    }.GetNewClosure()
    GetUserDirectReports = { param([string]$Identity)
        @([pscustomobject]@{ DisplayName = 'Jordan Blake'; SamAccountName = 'jblake' })
    }.GetNewClosure()
    GetUserManager = { param([string]$Identity)
        [pscustomobject]@{ DisplayName = 'Taylor Reed'; SamAccountName = 'treed' }
    }.GetNewClosure()
}

$mockGraph = [pscustomobject]@{
    SearchUser = { param([string]$Query)
        @([pscustomobject]@{
            DisplayName       = 'Alex Morgan'
            UserPrincipalName = 'amorgan@atlas-tech.com'
            Mail              = 'amorgan@atlas-tech.com'
            Department        = 'Information Technology'
            JobTitle          = 'Systems Administrator'
        })
    }.GetNewClosure()
    GetUser = { param([string]$Identity)
        [pscustomobject]@{
            DisplayName       = 'Alex Morgan'
            UserPrincipalName = 'amorgan@atlas-tech.com'
            Mail              = 'amorgan@atlas-tech.com'
            Department        = 'Information Technology'
            JobTitle          = 'Systems Administrator'
        }
    }.GetNewClosure()
}

$mockExchange = [pscustomobject]@{
    GetMailbox = { param([string]$Identity)
        [pscustomobject]@{ PrimarySmtpAddress = 'amorgan@atlas-tech.com'; RecipientTypeDetails = 'UserMailbox' }
    }.GetNewClosure()
}

Initialize-HybridUserService -ActiveDirectoryProvider $mockAd -MicrosoftGraphProvider $mockGraph -ExchangeOnlineProvider $mockExchange | Out-Null

$exports = (Get-Command -Module Application.HybridUserService).Name
Assert-True ($exports -contains 'Get-HybridUserDetails') 'Get-HybridUserDetails exported'

$user = Search-HybridUser -Query 'Alex' | Select-Object -First 1
Assert-True ($null -ne $user) 'Search returns a user'
Assert-True ($user.PSObject.Properties.Name -contains 'OrganizationalUnit') 'Composite user includes OrganizationalUnit'
Assert-True ($user.OrganizationalUnit -eq 'Users / Service Desk') 'OU is derived from distinguished name'
Assert-True ($user.PSObject.Properties.Name -contains 'Enabled') 'Composite user includes Enabled state'
Assert-True ($user.PSObject.Properties.Name -contains 'LockedOut') 'Composite user includes LockedOut state'

$detailedUser = Get-HybridUserDetails -Identity 'amorgan@atlas-tech.com'
Assert-True ($detailedUser.DetailsLoaded -eq $true) 'DetailsLoaded set after detail lookup'
Assert-True ($detailedUser.ManagerDisplayName -eq 'Taylor Reed') 'Manager display name enriched from provider'
Assert-True (@($detailedUser.Groups).Count -eq 2) 'Groups loaded through service layer'
Assert-True (@($detailedUser.DirectReports).Count -eq 1) 'Direct reports loaded through service layer'

$health = Get-HybridUserServiceHealth
Assert-True ($health.PSObject.Properties.Name -contains 'DetailCacheEntries') 'Health reports detail cache entries'
Assert-True ($health.DetailCacheEntries -ge 1) 'Detail cache populated'

$uiText = Get-Content -Path $uiScript -Raw
Assert-True ($uiText -match 'Get-HybridUserDetails') 'UI consumes user detail service'
Assert-True ($uiText -match 'GroupsList') 'UI includes groups list'
Assert-True ($uiText -match 'DirectReportsList') 'UI includes direct reports list'
Assert-True ($uiText -match 'ManagerText') 'UI includes manager card'
Assert-True ($uiText -match 'AccountStateText') 'UI includes account state badge'

Write-Host ''
Write-Host 'Milestone 7 Phase 3 user details vertical tests passed.'
