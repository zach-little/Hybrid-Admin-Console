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

$root = Split-Path -Parent $PSScriptRoot

Import-Module (Join-Path $root 'src\Core\Core.CloudEnvironment.psm1') -Force
Import-Module (Join-Path $root 'src\Core\Core.TenantContext.psm1') -Force
Import-Module (Join-Path $root 'src\Core\Core.Authentication.psm1') -Force
Import-Module (Join-Path $root 'src\Core\Core.Authentication.Manager.psm1') -Force
Import-Module (Join-Path $root 'src\Core\Core.Authentication.MSAL.psm1') -Force

Assert-Pass -Condition ([bool](Get-Command Test-HybridMsalRuntimeAvailable -ErrorAction SilentlyContinue)) -Message 'MSAL runtime availability helper exported'
Assert-Pass -Condition ([bool](Get-Command New-HybridMsalTokenRequest -ErrorAction SilentlyContinue)) -Message 'MSAL token request helper exported'
Assert-Pass -Condition ([bool](Get-Command New-HybridMsalAuthenticationSession -ErrorAction SilentlyContinue)) -Message 'MSAL session helper exported'

$gccHighCloud = Get-HybridCloudEnvironment -Name 'GccHigh'
$tenant = New-HybridTenantContext `
    -TenantId '00000000-0000-0000-0000-000000000001' `
    -TenantName 'Atlas Test' `
    -CloudEnvironment $gccHighCloud `
    -VerifiedDomains @('atlas-test.onmicrosoft.us')

$request = New-HybridAuthenticationRequest `
    -TenantContext $tenant `
    -MethodName 'Interactive' `
    -ClientId '11111111-1111-1111-1111-111111111111' `
    -Scopes @('User.Read','Group.Read.All')

$tokenRequest = New-HybridMsalTokenRequest -AuthenticationRequest $request -MethodName 'Interactive'
Assert-Pass -Condition ($tokenRequest.PSTypeNames -contains 'Hybrid.MsalTokenRequest') -Message 'MSAL token request has platform type name'
Assert-Pass -Condition ($tokenRequest.TenantId -eq $tenant.TenantId) -Message 'MSAL token request preserves tenant id'
Assert-Pass -Condition ($tokenRequest.CloudEnvironmentName -eq 'GccHigh') -Message 'MSAL token request preserves cloud environment'
Assert-Pass -Condition ($tokenRequest.Authority -like 'https://login.microsoftonline.us/*') -Message 'MSAL token request uses GCC High authority'
Assert-Pass -Condition ($tokenRequest.IsInteractive -eq $true) -Message 'Interactive token request is marked interactive'
Assert-Pass -Condition (@($tokenRequest.Scopes).Count -eq 2) -Message 'MSAL token request preserves scopes'

$runtime = Test-HybridMsalRuntimeAvailable
Assert-Pass -Condition ($runtime.PSTypeNames -contains 'Hybrid.MsalRuntimeStatus') -Message 'MSAL runtime status has platform type name'
Assert-Pass -Condition ($runtime.Runtime -eq 'MSAL') -Message 'MSAL runtime status reports runtime'

$script:CapturedTokenRequests = @()
$tokenScript = {
    param($TokenRequest)
    $script:CapturedTokenRequests += $TokenRequest
    [pscustomobject]@{
        AccessToken = ('live-msal-test-token-{0}' -f ([guid]::NewGuid().ToString('N')))
        TokenType   = 'Bearer'
        ExpiresOn   = [datetime]::UtcNow.AddHours(2)
        Claims      = @{ source = 'phase2-test' }
    }
}

Clear-HybridAuthenticationSessionCache
Register-HybridMsalAuthenticationAdapters -Force -RuntimeMode Live -TokenAcquisitionScript $tokenScript | Out-Null

$session = Get-HybridAuthenticationSession -Request $request
Assert-Pass -Condition ($session.PSTypeNames -contains 'Hybrid.AuthenticationSession') -Message 'Live-capable MSAL adapter returns platform session'
Assert-Pass -Condition ($session.AccessToken -like 'live-msal-test-token-*') -Message 'Live-capable MSAL adapter consumes token acquisition boundary'
Assert-Pass -Condition ($session.TokenDescriptor.PSTypeNames -contains 'Hybrid.TokenDescriptor') -Message 'MSAL token result is normalized to token descriptor'
Assert-Pass -Condition ($session.Attributes.Runtime -eq 'MSAL') -Message 'MSAL session records runtime attribute'
Assert-Pass -Condition ($session.Attributes.TokenRequest.PSTypeNames -contains 'Hybrid.MsalTokenRequest') -Message 'MSAL session records token request diagnostics'
Assert-Pass -Condition ($script:CapturedTokenRequests.Count -eq 1) -Message 'Token acquisition boundary invoked once for first session'

$cached = Get-HybridAuthenticationSession -Request $request
Assert-Pass -Condition ($cached.SessionId -eq $session.SessionId) -Message 'Authentication manager caches live-capable MSAL session'
Assert-Pass -Condition ($script:CapturedTokenRequests.Count -eq 1) -Message 'Cached MSAL session does not reacquire token'

$refreshed = Get-HybridAuthenticationSession -Request $request -ForceRefresh
Assert-Pass -Condition ($refreshed.SessionId -ne $session.SessionId) -Message 'Force refresh reacquires MSAL session'
Assert-Pass -Condition ($script:CapturedTokenRequests.Count -eq 2) -Message 'Force refresh invokes token acquisition boundary'

$blocked = $false
try {
    New-HybridMsalAuthenticationAdapter -MethodName 'DeviceCode' | Out-Null
} catch {
    $blocked = $true
}
Assert-Pass -Condition $blocked -Message 'MSAL adapter factory rejects Device Code flow'

Write-Host ''
Write-Host 'Milestone 6 Phase 2 live-capable MSAL adapter tests passed.'
