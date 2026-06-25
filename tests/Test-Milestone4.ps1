[CmdletBinding()]
param(
    [string]$Profile = 'Atlas'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $Root 'src'

function Assert-True {
    param($Condition, [string]$Message)

    $value = $Condition
    if ($null -ne $value -and $value -is [array]) {
        if ($value.Count -eq 0) { $value = $false }
        elseif ($value.Count -eq 1) { $value = [bool]$value[0] }
        else { throw "ASSERT ERROR: $Message returned multiple values instead of one Boolean." }
    }

    if (-not [bool]$value) { throw "ASSERT FAILED: $Message" }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

function New-TestADUser {
    param(
        [string]$Name,
        [string]$GivenName,
        [string]$Surname,
        [string]$SamAccountName,
        [string]$UserPrincipalName,
        [string]$Mail,
        [string]$EmployeeID,
        [string]$EmployeeNumber,
        [string]$Department,
        [string]$Title,
        [string]$Manager,
        [string[]]$DirectReports = @(),
        [bool]$Enabled = $true,
        [bool]$LockedOut = $false,
        [string]$DistinguishedName
    )

    [pscustomobject]@{
        ObjectGUID = [guid]::NewGuid()
        Name = $Name
        GivenName = $GivenName
        Surname = $Surname
        SamAccountName = $SamAccountName
        UserPrincipalName = $UserPrincipalName
        Mail = $Mail
        EmployeeID = $EmployeeID
        BadgeID = $EmployeeNumber
        EmployeeNumber = $EmployeeNumber
        extensionAttribute1 = $EmployeeNumber
        Department = $Department
        Title = $Title
        Company = 'Atlas Tech'
        physicalDeliveryOfficeName = 'Hybrid Admin Lab'
        Manager = $Manager
        DirectReports = @($DirectReports)
        Enabled = $Enabled
        LockedOut = $LockedOut
        DistinguishedName = $DistinguishedName
    }
}

function Initialize-TestActiveDirectoryModule {
    param([Parameter(Mandatory=$true)][string]$Path)

    $moduleRoot = Join-Path $Path 'ActiveDirectory'
    New-Item -Path $moduleRoot -ItemType Directory -Force | Out-Null
    $modulePath = Join-Path $moduleRoot 'ActiveDirectory.psm1'

@'
function Find-TestADUser {
    param([string]$Identity)
    foreach ($user in $global:HybridADTestUsers) {
        if ($user.SamAccountName -eq $Identity -or $user.UserPrincipalName -eq $Identity -or $user.Mail -eq $Identity -or $user.EmployeeID -eq $Identity -or $user.Name -eq $Identity -or $user.DistinguishedName -eq $Identity) {
            return $user
        }
    }
    return $null
}

function Get-ADUser {
    param(
        [string]$Identity,
        [string]$Filter,
        [string[]]$Properties,
        [int]$ResultSetSize,
        [string]$SearchBase,
        [string]$Server,
        [pscredential]$Credential
    )

    $global:HybridADTestOperations += [pscustomobject]@{ Name = 'Get-ADUser'; Identity = $(if ($PSBoundParameters.ContainsKey('Identity')) { $Identity } else { $Filter }); Detail = 'Read' }

    if ($PSBoundParameters.ContainsKey('Identity')) {
        if ($Identity -eq 'denied') { throw 'Access is denied' }
        return Find-TestADUser -Identity $Identity
    }

    if ($Filter -match 'denied') { throw 'Access is denied' }

    if ([string]::IsNullOrWhiteSpace($Filter) -or $Filter -eq '*') {
        return @($global:HybridADTestUsers | Select-Object -First $(if ($ResultSetSize -gt 0) { $ResultSetSize } else { 100 }))
    }

    if ($Filter -match "'([^']+)'") {
        $term = $Matches[1].Trim('*')
        return @($global:HybridADTestUsers | Where-Object {
            $_.SamAccountName -like "*$term*" -or $_.UserPrincipalName -like "*$term*" -or $_.Mail -like "*$term*" -or $_.EmployeeID -like "*$term*" -or $_.Name -like "*$term*" -or $_.Department -like "*$term*"
        } | Select-Object -First $(if ($ResultSetSize -gt 0) { $ResultSetSize } else { 100 }))
    }

    return @()
}

function Get-ADPrincipalGroupMembership {
    param(
        [string]$Identity,
        [string]$Server,
        [pscredential]$Credential
    )

    $global:HybridADTestOperations += [pscustomobject]@{ Name = 'Get-ADPrincipalGroupMembership'; Identity = $Identity; Detail = 'Read' }
    return @($global:HybridADTestGroups[$Identity])
}

function Set-ADAccountPassword {
    param(
        [string]$Identity,
        [switch]$Reset,
        [securestring]$NewPassword,
        [string]$Server,
        [pscredential]$Credential
    )
    $global:HybridADTestOperations += [pscustomobject]@{ Name = 'Set-ADAccountPassword'; Identity = $Identity; Detail = 'Reset' }
}

function Set-ADUser {
    param(
        [string]$Identity,
        [bool]$ChangePasswordAtLogon,
        [string]$Manager,
        [string]$Server,
        [pscredential]$Credential
    )
    if ($PSBoundParameters.ContainsKey('Manager')) {
        $global:HybridADTestOperations += [pscustomobject]@{ Name = 'Set-ADUserManager'; Identity = $Identity; Detail = $Manager }
    }
    elseif ($PSBoundParameters.ContainsKey('ChangePasswordAtLogon')) {
        $global:HybridADTestOperations += [pscustomobject]@{ Name = 'Set-ADUserChangePasswordAtLogon'; Identity = $Identity; Detail = [string]$ChangePasswordAtLogon }
    }
}

function Enable-ADAccount {
    param([string]$Identity, [string]$Server, [pscredential]$Credential)
    $global:HybridADTestOperations += [pscustomobject]@{ Name = 'Enable-ADAccount'; Identity = $Identity; Detail = '' }
}

function Disable-ADAccount {
    param([string]$Identity, [string]$Server, [pscredential]$Credential)
    $global:HybridADTestOperations += [pscustomobject]@{ Name = 'Disable-ADAccount'; Identity = $Identity; Detail = '' }
}

function Unlock-ADAccount {
    param([string]$Identity, [string]$Server, [pscredential]$Credential)
    $global:HybridADTestOperations += [pscustomobject]@{ Name = 'Unlock-ADAccount'; Identity = $Identity; Detail = '' }
}

function Move-ADObject {
    param([string]$Identity, [string]$TargetPath, [string]$Server, [pscredential]$Credential)
    $global:HybridADTestOperations += [pscustomobject]@{ Name = 'Move-ADObject'; Identity = $Identity; Detail = $TargetPath }
}

function Add-ADGroupMember {
    param([string]$Identity, [string]$Members, [string]$Server, [pscredential]$Credential)
    $global:HybridADTestOperations += [pscustomobject]@{ Name = 'Add-ADGroupMember'; Identity = $Members; Detail = $Identity }
}

function Remove-ADGroupMember {
    param([string]$Identity, [string]$Members, [switch]$Confirm, [string]$Server, [pscredential]$Credential)
    $global:HybridADTestOperations += [pscustomobject]@{ Name = 'Remove-ADGroupMember'; Identity = $Members; Detail = $Identity }
}

function Get-ADOrganizationalUnit {
    param(
        [string]$Filter,
        [string[]]$Properties,
        [int]$ResultSetSize,
        [string]$SearchBase,
        [string]$Server,
        [pscredential]$Credential
    )

    $global:HybridADTestOperations += [pscustomobject]@{ Name = 'Get-ADOrganizationalUnit'; Identity = $Filter; Detail = 'Read' }
    if ([string]::IsNullOrWhiteSpace($Filter) -or $Filter -eq '*') { return @($global:HybridADTestOUs) }
    if ($Filter -match "'([^']+)'") {
        $term = $Matches[1].Trim('*')
        return @($global:HybridADTestOUs | Where-Object { $_.Name -like "*$term*" -or $_.DistinguishedName -like "*$term*" })
    }
    return @()
}

Export-ModuleMember -Function *
'@ | Set-Content -Path $modulePath -Encoding UTF8

    $env:PSModulePath = "$Path$([IO.Path]::PathSeparator)$env:PSModulePath"
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

Assert-True (($loaded | Where-Object { $_.Name -eq 'Core.ProviderBase' } | Measure-Object).Count -eq 1) 'Provider base module loaded'
Assert-True (($loaded | Where-Object { $_.Name -eq 'Infrastructure.ActiveDirectory' } | Measure-Object).Count -eq 1) 'Active Directory provider module loaded'
Assert-True ($null -ne (Get-Command New-HybridProviderState -ErrorAction SilentlyContinue)) 'Provider state factory exported'
Assert-True ($null -ne (Get-Command New-HybridProviderService -ErrorAction SilentlyContinue)) 'Provider service factory exported'
Assert-True ($null -ne (Get-Command Get-HybridProviderHealth -ErrorAction SilentlyContinue)) 'Provider health helper exported'
Assert-True ($null -ne (Get-Command Initialize-HybridActiveDirectoryProvider -ErrorAction SilentlyContinue)) 'Initialize-HybridActiveDirectoryProvider exported'
Assert-True ($null -ne (Get-Command ConvertTo-HybridADUser -ErrorAction SilentlyContinue)) 'ConvertTo-HybridADUser exported'
Assert-True ($null -ne (Get-Command Search-HybridADUser -ErrorAction SilentlyContinue)) 'Search-HybridADUser exported'
Assert-True ($null -ne (Get-Command Get-HybridADUserGroups -ErrorAction SilentlyContinue)) 'Group read command exported'
Assert-True ($null -ne (Get-Command Get-HybridADUserManager -ErrorAction SilentlyContinue)) 'Manager read command exported'
Assert-True ($null -ne (Get-Command Get-HybridADUserDirectReports -ErrorAction SilentlyContinue)) 'Direct reports read command exported'
Assert-True ($null -ne (Get-Command Reset-HybridADUserPassword -ErrorAction SilentlyContinue)) 'Password reset command exported'
Assert-True ($null -ne (Get-Command Set-HybridADUserEnabled -ErrorAction SilentlyContinue)) 'Enable disable command exported'
Assert-True ($null -ne (Get-Command Unlock-HybridADUser -ErrorAction SilentlyContinue)) 'Unlock command exported'
Assert-True ($null -ne (Get-Command Move-HybridADUserOU -ErrorAction SilentlyContinue)) 'OU move command exported'
Assert-True ($null -ne (Get-Command Set-HybridADUserManager -ErrorAction SilentlyContinue)) 'Manager write command exported'
Assert-True ($null -ne (Get-Command Add-HybridADUserGroupMembership -ErrorAction SilentlyContinue)) 'Group add command exported'
Assert-True ($null -ne (Get-Command Remove-HybridADUserGroupMembership -ErrorAction SilentlyContinue)) 'Group remove command exported'
Assert-True ($null -ne (Get-Command Search-HybridADOrganizationalUnit -ErrorAction SilentlyContinue)) 'OU search command exported'
Assert-True ($null -ne (Get-Command Clear-HybridADProviderCache -ErrorAction SilentlyContinue)) 'AD provider cache clear command exported'
Assert-True ($null -ne (Get-Command Get-HybridADProviderHealth -ErrorAction SilentlyContinue)) 'AD provider health command exported'
Assert-True ($null -ne (Get-Command Test-HybridADProviderCapability -ErrorAction SilentlyContinue)) 'AD provider capability command exported'
Assert-True ($null -ne (Get-Command Get-HybridADProviderCapabilities -ErrorAction SilentlyContinue)) 'AD provider capabilities command exported'

$adService = Initialize-HybridActiveDirectoryProvider -Context $Context -NoNet
Assert-True ($adService.PSObject.TypeNames -contains 'Hybrid.ActiveDirectoryService') 'NoNet initialization returns Active Directory service object'
Assert-True ($adService.PSObject.TypeNames -contains 'Hybrid.ProviderService') 'AD service extends common provider service contract'
Assert-True ($adService.ProviderAvailable -eq $false) 'NoNet initialization does not require RSAT or domain access'
Assert-True ($adService.Supports.Invoke('ProviderHealth') -eq $true) 'AD service supports provider health capability'
Assert-True ($adService.Supports.Invoke('CapabilityDiscovery') -eq $true) 'AD service supports capability discovery'
$noNetHealth = @($adService.GetHealth.Invoke())[0]
Assert-True ($noNetHealth.PSObject.TypeNames -contains 'Hybrid.ActiveDirectoryProviderHealth') 'AD health object has provider-specific type name'
Assert-True ($noNetHealth.Name -eq 'ActiveDirectory') 'AD health reports provider name'
Assert-True ($noNetHealth.Available -eq $false) 'NoNet AD health reports unavailable runtime provider'
Assert-True (Test-HybridService -Name 'Directory') 'Existing mock Directory service remains registered during NoNet AD initialization'

$rawAdUser = New-TestADUser `
    -Name 'Alex Morgan' `
    -GivenName 'Alex' `
    -Surname 'Morgan' `
    -SamAccountName 'amorgan' `
    -UserPrincipalName 'amorgan@atlas-tech.com' `
    -Mail 'amorgan@atlas-tech.com' `
    -EmployeeID '10001' `
    -EmployeeNumber 'A1001' `
    -Department 'Information Technology' `
    -Title 'Systems Administrator' `
    -Manager 'CN=Morgan Rivera,OU=Users,DC=atlas-tech,DC=com' `
    -DirectReports @('CN=Taylor Smith,OU=Users,DC=atlas-tech,DC=com') `
    -DistinguishedName 'CN=Alex Morgan,OU=Users,DC=atlas-tech,DC=com'

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

$tempModulePath = Join-Path ([IO.Path]::GetTempPath()) ("HybridADTest_" + [guid]::NewGuid().ToString('N'))
Initialize-TestActiveDirectoryModule -Path $tempModulePath
Import-Module ActiveDirectory -Force

$global:HybridADTestOperations = @()
$global:HybridADTestUsers = @(
    $rawAdUser,
    (New-TestADUser -Name 'Morgan Rivera' -GivenName 'Morgan' -Surname 'Rivera' -SamAccountName 'mrivera' -UserPrincipalName 'mrivera@atlas-tech.com' -Mail 'mrivera@atlas-tech.com' -EmployeeID '10000' -EmployeeNumber 'A1000' -Department 'Information Technology' -Title 'IT Manager' -Manager '' -DistinguishedName 'CN=Morgan Rivera,OU=Users,DC=atlas-tech,DC=com'),
    (New-TestADUser -Name 'Taylor Smith' -GivenName 'Taylor' -Surname 'Smith' -SamAccountName 'tsmith' -UserPrincipalName 'tsmith@atlas-tech.com' -Mail 'tsmith@atlas-tech.com' -EmployeeID '10002' -EmployeeNumber 'A1002' -Department 'Information Technology' -Title 'Technician' -Manager 'CN=Alex Morgan,OU=Users,DC=atlas-tech,DC=com' -DistinguishedName 'CN=Taylor Smith,OU=Users,DC=atlas-tech,DC=com')
)
$global:HybridADTestGroups = @{
    amorgan = @(
        [pscustomobject]@{ ObjectGUID = [guid]::NewGuid(); Name = 'Domain Users'; SamAccountName = 'Domain Users'; GroupScope = 'Global'; DistinguishedName = 'CN=Domain Users,CN=Users,DC=atlas-tech,DC=com' },
        [pscustomobject]@{ ObjectGUID = [guid]::NewGuid(); Name = 'IT Admins'; SamAccountName = 'IT Admins'; GroupScope = 'Global'; DistinguishedName = 'CN=IT Admins,OU=Groups,DC=atlas-tech,DC=com' }
    )
}
$global:HybridADTestOUs = @(
    [pscustomobject]@{ Name = 'Users'; DistinguishedName = 'OU=Users,DC=atlas-tech,DC=com'; Description = 'Standard users' },
    [pscustomobject]@{ Name = 'Disabled Users'; DistinguishedName = 'OU=Disabled Users,DC=atlas-tech,DC=com'; Description = 'Disabled accounts' }
)

$adService = Initialize-HybridActiveDirectoryProvider -Context $Context -RegisterAsDirectory
Assert-True ($adService.ProviderAvailable -eq $true) 'Mocked ActiveDirectory module makes provider available'
Assert-True ((Get-HybridService -Name 'Directory').ProviderName -eq 'ActiveDirectory') 'AD provider can register as Directory service'
Assert-True ($null -ne $adService.SetUserManager) 'Directory service exposes manager write operation'
Assert-True ($null -ne $adService.AddUserToGroup) 'Directory service exposes group add operation'
Assert-True ($null -ne $adService.RemoveUserFromGroup) 'Directory service exposes group remove operation'
Assert-True ($null -ne $adService.SearchOU) 'Directory service exposes OU search operation'
Assert-True ($adService.Capabilities -contains 'CommandWrapper') 'Directory service declares command wrapper capability'
Assert-True ($adService.Capabilities -contains 'StructuredErrors') 'Directory service declares structured error capability'
Assert-True ($adService.Capabilities -contains 'Caching') 'Directory service declares caching capability'
Assert-True ($adService.Capabilities -contains 'ProviderHealth') 'Directory service declares provider health capability'
Assert-True ($adService.Capabilities -contains 'CapabilityDiscovery') 'Directory service declares capability discovery capability'
Assert-True ($adService.Supports.Invoke('Unlock') -eq $true) 'Directory service Supports reports enabled capabilities'
$unsupportedCapability = [bool](@($adService.Supports.Invoke('Autopilot'))[0])
Assert-True (-not $unsupportedCapability) 'Directory service Supports rejects unsupported capabilities'

$searchResults = @(Search-HybridADUser -Query 'Alex')
Assert-True ($searchResults.Count -eq 1) 'AD search returns matching user'
Assert-True ($searchResults[0].SamAccountName -eq 'amorgan') 'AD search maps result to Hybrid.User'

$hydrated = Get-HybridADUser -Identity 'amorgan' -IncludeRelated
Assert-True ($hydrated.DisplayName -eq 'Alex Morgan') 'AD user retrieval returns Alex Morgan'
Assert-True (@($hydrated.Groups).Count -eq 2) 'AD user retrieval hydrates groups'
Assert-True ($hydrated.ManagerSamAccountName -eq 'mrivera') 'AD user retrieval hydrates manager'
Assert-True (@($hydrated.Attributes.DirectReports).Count -eq 1) 'AD user retrieval hydrates direct reports'

$groups = @(Get-HybridADUserGroups -Identity 'amorgan')
Assert-True (($groups | Where-Object { $_.Name -eq 'Domain Users' }).IsDefault -eq $true) 'Domain Users group is marked default'
Assert-True (($groups | Where-Object { $_.Name -eq 'IT Admins' }).Source -eq 'ActiveDirectory') 'AD group source is ActiveDirectory'
$groupsAgain = @(Get-HybridADUserGroups -Identity 'amorgan')
Assert-True ($groupsAgain.Count -eq 2) 'Cached group lookup returns groups'
Assert-True (($global:HybridADTestOperations | Where-Object { $_.Name -eq 'Get-ADPrincipalGroupMembership' -and $_.Identity -eq 'amorgan' } | Measure-Object).Count -eq 1) 'Group lookup is served from provider cache on repeated reads'

$manager = Get-HybridADUserManager -Identity 'amorgan'
Assert-True ($manager.SamAccountName -eq 'mrivera') 'Manager lookup returns expected manager'

$reports = @(Get-HybridADUserDirectReports -Identity 'amorgan')
Assert-True ($reports.Count -eq 1) 'Direct reports lookup returns expected count'
Assert-True ($reports[0].SamAccountName -eq 'tsmith') 'Direct reports lookup returns expected report'

$ous = @(Search-HybridADOrganizationalUnit -Query 'Disabled')
Assert-True ($ous.Count -eq 1) 'OU search returns matching OU'
Assert-True ($ous[0].DistinguishedName -eq 'OU=Disabled Users,DC=atlas-tech,DC=com') 'OU search preserves distinguished name'

$password = ConvertTo-SecureString 'TempPassword123!' -AsPlainText -Force
Reset-HybridADUserPassword -Identity 'amorgan' -NewPassword $password -ChangeAtLogon | Out-Null
Set-HybridADUserEnabled -Identity 'amorgan' -Enabled $false | Out-Null
Set-HybridADUserEnabled -Identity 'amorgan' -Enabled $true | Out-Null
Unlock-HybridADUser -Identity 'amorgan' | Out-Null
Set-HybridADUserManager -Identity 'amorgan' -ManagerIdentity 'mrivera' | Out-Null
Add-HybridADUserGroupMembership -Identity 'amorgan' -GroupIdentity 'IT Admins' | Out-Null
Remove-HybridADUserGroupMembership -Identity 'amorgan' -GroupIdentity 'IT Admins' | Out-Null
Move-HybridADUserOU -Identity 'amorgan' -TargetPath 'OU=Disabled Users,DC=atlas-tech,DC=com' | Out-Null

Assert-True (($global:HybridADTestOperations | Where-Object { $_.Name -eq 'Set-ADAccountPassword' -and $_.Identity -eq 'amorgan' } | Measure-Object).Count -eq 1) 'Password reset calls AD password cmdlet'
Assert-True (($global:HybridADTestOperations | Where-Object { $_.Name -eq 'Set-ADUserChangePasswordAtLogon' -and $_.Identity -eq 'amorgan' } | Measure-Object).Count -eq 1) 'Password reset can require change at logon'
Assert-True (($global:HybridADTestOperations | Where-Object { $_.Name -eq 'Disable-ADAccount' -and $_.Identity -eq 'amorgan' } | Measure-Object).Count -eq 1) 'Disable calls AD disable cmdlet'
Assert-True (($global:HybridADTestOperations | Where-Object { $_.Name -eq 'Enable-ADAccount' -and $_.Identity -eq 'amorgan' } | Measure-Object).Count -eq 1) 'Enable calls AD enable cmdlet'
Assert-True (($global:HybridADTestOperations | Where-Object { $_.Name -eq 'Unlock-ADAccount' -and $_.Identity -eq 'amorgan' } | Measure-Object).Count -eq 1) 'Unlock calls AD unlock cmdlet'
Assert-True (($global:HybridADTestOperations | Where-Object { $_.Name -eq 'Set-ADUserManager' -and $_.Identity -eq 'amorgan' -and $_.Detail -eq 'mrivera' } | Measure-Object).Count -eq 1) 'Manager write calls AD set user cmdlet'
Assert-True (($global:HybridADTestOperations | Where-Object { $_.Name -eq 'Add-ADGroupMember' -and $_.Identity -eq 'amorgan' -and $_.Detail -eq 'IT Admins' } | Measure-Object).Count -eq 1) 'Group add calls AD group cmdlet'
Assert-True (($global:HybridADTestOperations | Where-Object { $_.Name -eq 'Remove-ADGroupMember' -and $_.Identity -eq 'amorgan' -and $_.Detail -eq 'IT Admins' } | Measure-Object).Count -eq 1) 'Group remove calls AD group cmdlet'
Get-HybridADUserGroups -Identity 'amorgan' | Out-Null
Assert-True (($global:HybridADTestOperations | Where-Object { $_.Name -eq 'Get-ADPrincipalGroupMembership' -and $_.Identity -eq 'amorgan' } | Measure-Object).Count -eq 2) 'Write operations invalidate provider cache'
Assert-True (($global:HybridADTestOperations | Where-Object { $_.Name -eq 'Move-ADObject' -and $_.Identity -eq 'CN=Alex Morgan,OU=Users,DC=atlas-tech,DC=com' -and $_.Detail -eq 'OU=Disabled Users,DC=atlas-tech,DC=com' } | Measure-Object).Count -eq 1) 'OU move calls AD object move cmdlet'

$health = Get-HybridADProviderHealth
Assert-True ($health.Available -eq $true) 'AD health reports runtime provider availability'
Assert-True ($health.Connected -eq $true) 'AD health reports connected state when provider is available'
Assert-True ($health.CommandCount -gt 0) 'AD health reports command history'
Assert-True ($health.CacheEntries -ge 0) 'AD health reports cache entry count'
Assert-True (@($health.Capabilities) -contains 'PasswordReset') 'AD health includes provider capabilities'

$structuredErrorThrown = $false
try {
    Get-HybridADUser -Identity 'denied' | Out-Null
}
catch {
    $structuredErrorThrown = $true
    Assert-True ($_.Exception.Data['HybridErrorCode'] -eq 'AccessDenied') 'AD command wrapper maps access denied to structured error code'
}
Assert-True $structuredErrorThrown 'AD command wrapper throws structured provider exception'

Write-Host ''
Write-Host 'Milestone 4 Active Directory provider tests passed.' -ForegroundColor Cyan
