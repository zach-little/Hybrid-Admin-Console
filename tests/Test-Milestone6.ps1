Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Pass {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    Write-Host "PASS: $Message"
}

function New-TestAuthenticationRequest {
    param(
        [Parameter(Mandatory)]$Tenant,
        [Parameter(Mandatory)][string]$MethodName,
        [string[]]$Scopes = @('User.Read')
    )

    $command = Get-Command New-HybridAuthenticationRequest
    $params = @{}

    if ($command.Parameters.ContainsKey('TenantContext')) {
        $params['TenantContext'] = $Tenant
    }
    elseif ($command.Parameters.ContainsKey('Tenant')) {
        $params['Tenant'] = $Tenant
    }

    if ($command.Parameters.ContainsKey('MethodName')) {
        $params['MethodName'] = $MethodName
    }
    elseif ($command.Parameters.ContainsKey('AuthenticationMethod')) {
        $params['AuthenticationMethod'] = $MethodName
    }
    elseif ($command.Parameters.ContainsKey('Method')) {
        $params['Method'] = $MethodName
    }

    if ($command.Parameters.ContainsKey('Scopes')) {
        $params['Scopes'] = $Scopes
    }
    elseif ($command.Parameters.ContainsKey('RequiredScopes')) {
        $params['RequiredScopes'] = $Scopes
    }

    if ($command.Parameters.ContainsKey('CloudEnvironment')) {
        $params['CloudEnvironment'] = $Tenant.CloudEnvironment
    }

    return New-HybridAuthenticationRequest @params
}

function New-TestAuthenticationCacheKey {
    param([Parameter(Mandatory)]$Request)

    $command = Get-Command New-HybridAuthenticationCacheKey

    if ($command.Parameters.ContainsKey('AuthenticationRequest')) {
        $keyObject = New-HybridAuthenticationCacheKey -AuthenticationRequest $Request
        if ($keyObject.PSObject.Properties.Name -contains 'Key') {
            return [string]$keyObject.Key
        }
        return [string]$keyObject
    }

    $params = @{}

    if ($command.Parameters.ContainsKey('TenantContext')) {
        $params['TenantContext'] = $Request.TenantContext
    }
    elseif ($command.Parameters.ContainsKey('Tenant')) {
        $params['Tenant'] = $Request.TenantContext
    }

    if ($command.Parameters.ContainsKey('CloudEnvironment')) {
        $params['CloudEnvironment'] = $Request.CloudEnvironment
    }

    if ($command.Parameters.ContainsKey('MethodName')) {
        $params['MethodName'] = $Request.MethodName
    }

    if ($command.Parameters.ContainsKey('Scopes')) {
        $params['Scopes'] = $Request.Scopes
    }

    $keyObject = New-HybridAuthenticationCacheKey @params

    if ($keyObject.PSObject.Properties.Name -contains 'Key') {
        return [string]$keyObject.Key
    }

    return [string]$keyObject
}

$root = Split-Path -Parent $PSScriptRoot

Import-Module (Join-Path $root 'src\Core\Core.CloudEnvironment.psm1') -Force
Import-Module (Join-Path $root 'src\Core\Core.TenantContext.psm1') -Force
Import-Module (Join-Path $root 'src\Core\Core.Authentication.psm1') -Force
Import-Module (Join-Path $root 'src\Core\Core.Authentication.Manager.psm1') -Force
Import-Module (Join-Path $root 'src\Core\Core.Authentication.MSAL.psm1') -Force

Assert-Pass -Condition ([bool](Get-Command Register-HybridAuthenticationAdapter -ErrorAction SilentlyContinue)) -Message 'Register-HybridAuthenticationAdapter exported'
Assert-Pass -Condition ([bool](Get-Command Get-HybridAuthenticationSession -ErrorAction SilentlyContinue)) -Message 'Get-HybridAuthenticationSession exported'
Assert-Pass -Condition ([bool](Get-Command Initialize-HybridMockAuthenticationAdapters -ErrorAction SilentlyContinue)) -Message 'Initialize-HybridMockAuthenticationAdapters exported'
Assert-Pass -Condition ([bool](Get-Command Register-HybridMsalAuthenticationAdapters -ErrorAction SilentlyContinue)) -Message 'Register-HybridMsalAuthenticationAdapters exported'

$gccHighCloud = Get-HybridCloudEnvironment -Name 'GccHigh'

$tenant = New-HybridTenantContext `
    -TenantId '00000000-0000-0000-0000-000000000001' `
    -TenantName 'Atlas Test' `
    -CloudEnvironment $gccHighCloud `
    -VerifiedDomains @('atlas-test.onmicrosoft.us')

$request = New-TestAuthenticationRequest -Tenant $tenant -MethodName 'Interactive' -Scopes @('User.Read')

Clear-HybridAuthenticationSessionCache
Initialize-HybridMockAuthenticationAdapters -Force | Out-Null

Assert-Pass -Condition ((Get-HybridAuthenticationAdapterNames) -contains 'Interactive') -Message 'Interactive authentication adapter registered'
Assert-Pass -Condition ((Get-HybridAuthenticationAdapterNames) -contains 'AppOnly') -Message 'App-only authentication adapter registered'
Assert-Pass -Condition ((Get-HybridAuthenticationAdapterNames) -notcontains 'DeviceCode') -Message 'Device Code adapter not registered'

$session1 = Get-HybridAuthenticationSession -Request $request
Assert-Pass -Condition ($session1.PSTypeNames -contains 'Hybrid.AuthenticationSession') -Message 'Authentication manager returns platform session'
Assert-Pass -Condition ($session1.AccessToken -like 'mock-token-*') -Message 'Authentication manager acquires mock token'

$session2 = Get-HybridAuthenticationSession -Request $request
Assert-Pass -Condition ($session1.SessionId -eq $session2.SessionId) -Message 'Authentication manager returns cached session'

$expired = New-HybridAuthenticationSession -AuthenticationRequest $request -AccessToken 'expired' -ExpiresOn (Get-Date).AddMinutes(-1)
$cacheKey = New-TestAuthenticationCacheKey -Request $request

Set-HybridCachedAuthenticationSession -CacheKey $cacheKey -Session $expired | Out-Null
Assert-Pass -Condition (Test-HybridAuthenticationRefreshRequired -Session $expired) -Message 'Expired session requires refresh'

$refreshed = Get-HybridAuthenticationSession -Request $request
Assert-Pass -Condition ($refreshed.AccessToken -like 'refreshed-token-*') -Message 'Authentication manager refreshes expired session'

Clear-HybridAuthenticationSessionCache
Register-HybridMsalAuthenticationAdapters -Force | Out-Null
$msalSession = Get-HybridAuthenticationSession -Request $request
Assert-Pass -Condition ($msalSession.AccessToken -like 'msal-contract-token-*') -Message 'MSAL contract adapter returns platform session'

$msalAdapter = New-HybridMsalAuthenticationAdapter -MethodName 'Interactive'
Assert-Pass -Condition ($msalAdapter.PSTypeNames -contains 'Hybrid.MsalAuthenticationAdapter') -Message 'MSAL adapter has platform type name'
Assert-Pass -Condition ($msalAdapter.Runtime -eq 'MSAL') -Message 'MSAL adapter reports runtime'

$blocked = $false
try {
    Register-HybridAuthenticationAdapter -Name 'DeviceCode' -AcquireSession { param($Request) $null } -Force | Out-Null
}
catch {
    $blocked = $true
}

Assert-Pass -Condition $blocked -Message 'Authentication manager rejects Device Code adapter'

Write-Host ''
Write-Host 'Milestone 6 Phase 1 authentication manager tests passed.'
