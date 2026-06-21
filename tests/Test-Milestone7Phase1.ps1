Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param(
        [Parameter(Mandatory=$true)][bool]$Condition,
        [Parameter(Mandatory=$true)][string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

Import-Module $servicePath -Force

Assert-Pass -Condition ([bool](Get-Command Initialize-HybridUserService -ErrorAction SilentlyContinue)) -Message 'Hybrid user service initializer exported'
Assert-Pass -Condition ([bool](Get-Command Search-HybridUser -ErrorAction SilentlyContinue)) -Message 'Hybrid user search command exported'
Assert-Pass -Condition ([bool](Get-Command Get-HybridUser -ErrorAction SilentlyContinue)) -Message 'Hybrid user get command exported'
Assert-Pass -Condition ([bool](Get-Command Get-HybridUserServiceHealth -ErrorAction SilentlyContinue)) -Message 'Hybrid user service health command exported'

$mockAd = [pscustomobject]@{
    SearchUser = { param([string]$Query)
        @([pscustomobject]@{
            PSTypeName = 'Hybrid.User'
            DisplayName = 'Alex Morgan'
            SamAccountName = 'amorgan'
            UserPrincipalName = 'amorgan@atlas-tech.com'
            Mail = 'amorgan@atlas-tech.com'
            Department = 'Information Technology'
            Title = 'Systems Administrator'
            Manager = 'CN=Taylor Reed,OU=Users,DC=atlas-tech,DC=com'
            Source = 'ActiveDirectory'
        })
    }.GetNewClosure()
    GetUser = { param([string]$Identity)
        [pscustomobject]@{
            PSTypeName = 'Hybrid.User'
            DisplayName = 'Alex Morgan'
            SamAccountName = 'amorgan'
            UserPrincipalName = 'amorgan@atlas-tech.com'
            Mail = 'amorgan@atlas-tech.com'
            Department = 'Information Technology'
            Title = 'Systems Administrator'
            Manager = 'CN=Taylor Reed,OU=Users,DC=atlas-tech,DC=com'
            Source = 'ActiveDirectory'
        }
    }.GetNewClosure()
}

$mockGraph = [pscustomobject]@{
    SearchUser = { param([string]$Query)
        @([pscustomobject]@{
            PSTypeName = 'Hybrid.User'
            DisplayName = 'Alex Morgan'
            UserPrincipalName = 'amorgan@atlas-tech.com'
            Mail = 'amorgan@atlas-tech.com'
            Department = 'Information Technology'
            JobTitle = 'Systems Administrator'
            Source = 'MicrosoftGraph'
        })
    }.GetNewClosure()
    GetUser = { param([string]$Identity)
        [pscustomobject]@{
            PSTypeName = 'Hybrid.User'
            DisplayName = 'Alex Morgan'
            UserPrincipalName = 'amorgan@atlas-tech.com'
            Mail = 'amorgan@atlas-tech.com'
            Department = 'Information Technology'
            JobTitle = 'Systems Administrator'
            Source = 'MicrosoftGraph'
        }
    }.GetNewClosure()
}

$mockExchange = [pscustomobject]@{
    GetMailbox = { param([string]$Identity)
        [pscustomobject]@{
            PSTypeName = 'Hybrid.Mailbox'
            DisplayName = 'Alex Morgan'
            PrimarySmtpAddress = 'amorgan@atlas-tech.com'
            RecipientTypeDetails = 'UserMailbox'
            Source = 'ExchangeOnline'
        }
    }.GetNewClosure()
}

$service = Initialize-HybridUserService -ActiveDirectoryProvider $mockAd -MicrosoftGraphProvider $mockGraph -ExchangeOnlineProvider $mockExchange

Assert-Pass -Condition ($service.PSObject.TypeNames -contains 'Hybrid.UserService') -Message 'Hybrid user service has platform type name'
Assert-Pass -Condition ($service.Providers.ActiveDirectory -eq $true) -Message 'Hybrid user service records Active Directory provider'
Assert-Pass -Condition ($service.Providers.MicrosoftGraph -eq $true) -Message 'Hybrid user service records Microsoft Graph provider'
Assert-Pass -Condition ($service.Providers.ExchangeOnline -eq $true) -Message 'Hybrid user service records Exchange Online provider'

$results = @(Search-HybridUser -Query 'Alex')
Assert-Pass -Condition ($results.Count -eq 1) -Message 'Hybrid user search returns one composite user'
$user = $results[0]

Assert-Pass -Condition ($user.PSObject.TypeNames -contains 'Hybrid.User.VerticalSlice') -Message 'Hybrid user result has vertical slice type name'
Assert-Pass -Condition ($user.PSObject.TypeNames -contains 'Hybrid.User') -Message 'Hybrid user result preserves canonical Hybrid.User type'
Assert-Pass -Condition ($user.DisplayName -eq 'Alex Morgan') -Message 'Hybrid user result preserves display name'
Assert-Pass -Condition ($user.UserPrincipalName -eq 'amorgan@atlas-tech.com') -Message 'Hybrid user result preserves UPN'
Assert-Pass -Condition ($user.SamAccountName -eq 'amorgan') -Message 'Hybrid user result includes AD SAM account'
Assert-Pass -Condition ($user.Mailbox.PrimarySmtpAddress -eq 'amorgan@atlas-tech.com') -Message 'Hybrid user result includes Exchange mailbox'
Assert-Pass -Condition (@($user.Sources).Count -eq 3) -Message 'Hybrid user result records three provider sources'

$cached = Get-HybridUser -Identity 'amorgan@atlas-tech.com'
Assert-Pass -Condition ([object]::ReferenceEquals($user, $cached)) -Message 'Hybrid user service returns stable cached user result'

$health = Get-HybridUserServiceHealth
Assert-Pass -Condition ($health.PSObject.TypeNames -contains 'Hybrid.UserServiceHealth') -Message 'Hybrid user service health has platform type name'
Assert-Pass -Condition ($health.Initialized -eq $true) -Message 'Hybrid user service health reports initialized'
Assert-Pass -Condition ($health.CacheEntries -eq 1) -Message 'Hybrid user service health reports cache entries'

$tokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($uiPath, [ref]$tokens, [ref]$parseErrors)
Assert-Pass -Condition (@($parseErrors).Count -eq 0) -Message 'Vertical slice UI script parses successfully'

Write-Host ''
Write-Host 'Milestone 7 Phase 1 vertical slice service tests passed.'
