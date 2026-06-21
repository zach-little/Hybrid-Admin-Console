Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'

function Assert-True {
    param(
        [Parameter(Mandatory=$true)][bool]$Condition,
        [Parameter(Mandatory=$true)][string]$Message
    )
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Assert-Equal {
    param(
        [AllowNull()]$Actual,
        [AllowNull()]$Expected,
        [Parameter(Mandatory=$true)][string]$Message
    )
    if ($Actual -ne $Expected) {
        throw "FAIL: $Message. Expected '$Expected' but got '$Actual'."
    }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

Remove-Module Application.HybridUserService -Force -ErrorAction SilentlyContinue
Import-Module $servicePath -Force

$liveAdProvider = [pscustomobject]@{
    PSTypeName = 'Hybrid.ActiveDirectoryService'
    ProviderName = 'ActiveDirectory'
    ProviderAvailable = $true
    ProviderConnected = $true
    SearchUser = {
        param([string]$Query)
        @(
            [pscustomobject]@{
                PSTypeName = 'Hybrid.User.ActiveDirectory'
                Identity = 'amorgan'
                DisplayName = 'Alex Morgan'
                SamAccountName = 'amorgan'
                UserPrincipalName = 'amorgan@atlas-tech.com'
                Mail = 'amorgan@atlas-tech.com'
                Department = 'Information Technology'
                Title = 'Systems Administrator'
                Company = 'Atlas'
                Office = 'Charleston'
                EmployeeId = '1001'
                DistinguishedName = 'CN=Alex Morgan,OU=Users,DC=atlas-tech,DC=com'
                Enabled = $true
                LockedOut = $false
                Manager = 'CN=Jordan Lee,OU=Users,DC=atlas-tech,DC=com'
            }
        ) | Where-Object { $_.DisplayName -like "*$Query*" -or $_.SamAccountName -like "*$Query*" -or $_.UserPrincipalName -like "*$Query*" }
    }
    GetUser = {
        param([string]$Identity)
        [pscustomobject]@{
            PSTypeName = 'Hybrid.User.ActiveDirectory'
            Identity = 'amorgan'
            DisplayName = 'Alex Morgan'
            SamAccountName = 'amorgan'
            UserPrincipalName = 'amorgan@atlas-tech.com'
            Mail = 'amorgan@atlas-tech.com'
            Department = 'Information Technology'
            Title = 'Systems Administrator'
            Company = 'Atlas'
            Office = 'Charleston'
            EmployeeId = '1001'
            DistinguishedName = 'CN=Alex Morgan,OU=Users,DC=atlas-tech,DC=com'
            Enabled = $true
            LockedOut = $false
            Manager = 'CN=Jordan Lee,OU=Users,DC=atlas-tech,DC=com'
        }
    }
    GetHealth = {
        [pscustomobject]@{
            PSTypeName = 'Hybrid.ActiveDirectoryProviderHealth'
            Name = 'ActiveDirectory'
            Initialized = $true
            Available = $true
            Connected = $true
            LastError = $null
            CacheEntries = 0
            CommandCount = 2
        }
    }
}

$service = Initialize-HybridUserService -ActiveDirectoryProvider $liveAdProvider
Assert-True -Condition $service.Initialized -Message 'Hybrid user service initializes with live AD provider'
Assert-True -Condition $service.Providers.ActiveDirectory -Message 'Active Directory provider is registered in service state'

$result = @(Search-HybridUser -Query 'Alex')
Assert-Equal -Actual $result.Count -Expected 1 -Message 'Live AD search returns one Hybrid.User result'
Assert-Equal -Actual $result[0].DisplayName -Expected 'Alex Morgan' -Message 'DisplayName is populated from Active Directory'
Assert-Equal -Actual $result[0].SamAccountName -Expected 'amorgan' -Message 'SamAccountName is populated from Active Directory'
Assert-Equal -Actual $result[0].UserPrincipalName -Expected 'amorgan@atlas-tech.com' -Message 'UPN is populated from Active Directory'
Assert-Equal -Actual $result[0].Department -Expected 'Information Technology' -Message 'Department is populated from Active Directory'
Assert-Equal -Actual $result[0].Title -Expected 'Systems Administrator' -Message 'Title is populated from Active Directory'
Assert-Equal -Actual $result[0].Company -Expected 'Atlas' -Message 'Company is populated from Active Directory'
Assert-Equal -Actual $result[0].Office -Expected 'Charleston' -Message 'Office is populated from Active Directory'
Assert-Equal -Actual $result[0].EmployeeId -Expected '1001' -Message 'EmployeeId is populated from Active Directory'
Assert-True -Condition ([bool]$result[0].Enabled) -Message 'Enabled state is preserved from Active Directory'
Assert-True -Condition (-not [bool]$result[0].LockedOut) -Message 'LockedOut state is preserved from Active Directory'
Assert-True -Condition ($result[0].Sources.Name -contains 'ActiveDirectory') -Message 'Composite user includes Active Directory source status'

$adStatus = @($result[0].Sources | Where-Object Name -eq 'ActiveDirectory' | Select-Object -First 1)[0]
Assert-True -Condition $adStatus.Available -Message 'Active Directory source status reports available'
Assert-True -Condition $adStatus.Connected -Message 'Active Directory source status reports connected'
Assert-Equal -Actual $adStatus.Health.Name -Expected 'ActiveDirectory' -Message 'Active Directory provider health is attached to source status'

$health = Get-HybridUserServiceHealth
Assert-True -Condition $health.Initialized -Message 'Service health reports initialized'
Assert-True -Condition $health.Providers.ActiveDirectory -Message 'Service health reports Active Directory provider present'
Assert-True -Condition $health.ProviderHealth.ActiveDirectory.Available -Message 'Service health includes Active Directory availability'
Assert-True -Condition $health.ProviderHealth.ActiveDirectory.Connected -Message 'Service health includes Active Directory connectivity'
Assert-Equal -Actual $health.LastQuery -Expected 'Alex' -Message 'Service health tracks last query'

$cached = Get-HybridUser -Identity 'amorgan@atlas-tech.com'
Assert-Equal -Actual $cached.DisplayName -Expected 'Alex Morgan' -Message 'Get-HybridUser returns live AD composite user'

Clear-HybridUserService | Out-Null
$clearedHealth = Get-HybridUserServiceHealth
Assert-True -Condition (-not $clearedHealth.Initialized) -Message 'Service clear resets initialized state'

Write-Host ''
Write-Host 'Milestone 7 Phase 2 live Active Directory service-layer tests passed.' -ForegroundColor Cyan
