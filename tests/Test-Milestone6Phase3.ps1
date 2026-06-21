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

$root = Split-Path -Parent $PSScriptRoot

Import-Module (Join-Path $root 'src\Core\Core.ProviderBase.psm1') -Force
Import-Module (Join-Path $root 'src\Core\Core.CloudEnvironment.psm1') -Force
Import-Module (Join-Path $root 'src\Core\Core.TenantContext.psm1') -Force
Import-Module (Join-Path $root 'src\Core\Core.Authentication.psm1') -Force
Import-Module (Join-Path $root 'src\Core\Core.Authentication.Manager.psm1') -Force
Import-Module (Join-Path $root 'src\Infrastructure\Graph\Graph.Models.psm1') -Force
Import-Module (Join-Path $root 'src\Core\Core.Provider.MicrosoftGraph.psm1') -Force

Assert-Pass -Condition ([bool](Get-Command New-HybridMicrosoftGraphProviderContext -ErrorAction SilentlyContinue)) -Message 'Microsoft Graph provider context helper exported'
Assert-Pass -Condition ([bool](Get-Command Initialize-HybridMicrosoftGraphProvider -ErrorAction SilentlyContinue)) -Message 'Microsoft Graph provider initializer exported'
Assert-Pass -Condition ([bool](Get-Command Search-HybridMicrosoftGraphUser -ErrorAction SilentlyContinue)) -Message 'Microsoft Graph user search command exported'
Assert-Pass -Condition ([bool](Get-Command Get-HybridMicrosoftGraphUser -ErrorAction SilentlyContinue)) -Message 'Microsoft Graph user get command exported'
Assert-Pass -Condition ([bool](Get-Command Get-HybridMicrosoftGraphProviderHealth -ErrorAction SilentlyContinue)) -Message 'Microsoft Graph provider health command exported'

Initialize-HybridMockAuthenticationAdapters -Force | Out-Null
Clear-HybridAuthenticationSessionCache

$gccHighCloud = Get-HybridCloudEnvironment -Name 'GccHigh'
$tenant = New-HybridTenantContext `
    -TenantId '00000000-0000-0000-0000-000000000001' `
    -TenantName 'Atlas Test' `
    -CloudEnvironment $gccHighCloud `
    -VerifiedDomains @('atlas-test.onmicrosoft.us')

$context = New-HybridMicrosoftGraphProviderContext `
    -TenantContext $tenant `
    -AuthenticationMethod 'Interactive' `
    -Scopes @('User.Read.All','Group.Read.All')

Assert-Pass -Condition ($context.PSTypeNames -contains 'Hybrid.MicrosoftGraphProviderContext') -Message 'Microsoft Graph provider context has platform type name'
Assert-Pass -Condition ($context.TenantContext.TenantId -eq $tenant.TenantId) -Message 'Microsoft Graph provider context preserves tenant'
Assert-Pass -Condition (@($context.Scopes).Count -eq 2) -Message 'Microsoft Graph provider context preserves scopes'

$mockUsers = @(
    [pscustomobject]@{
        id = 'graph-user-001'
        displayName = 'Alex Morgan'
        userPrincipalName = 'alex.morgan@atlas-test.onmicrosoft.us'
        mail = 'alex.morgan@atlas-test.onmicrosoft.us'
    },
    [pscustomobject]@{
        id = 'graph-user-002'
        displayName = 'Jordan Lee'
        userPrincipalName = 'jordan.lee@atlas-test.onmicrosoft.us'
        mail = 'jordan.lee@atlas-test.onmicrosoft.us'
    }
)

$service = Initialize-HybridMicrosoftGraphProvider -Context $context -MockUsers $mockUsers

Assert-Pass -Condition ($service.PSTypeNames -contains 'Hybrid.MicrosoftGraphProviderService') -Message 'Microsoft Graph provider service has platform type name'
Assert-Pass -Condition ($service.ProviderName -eq 'MicrosoftGraph') -Message 'Microsoft Graph provider service has provider name'
Assert-Pass -Condition ($service.AuthenticationSession.PSTypeNames -contains 'Hybrid.AuthenticationSession') -Message 'Microsoft Graph provider acquires platform authentication session'
Assert-Pass -Condition ($service.AuthenticationSession.AccessToken -like 'mock-token-*') -Message 'Microsoft Graph provider uses authentication manager adapter'
Assert-Pass -Condition (@($service.Supports.Invoke('Users')) -contains $true) -Message 'Microsoft Graph provider reports Users capability'
Assert-Pass -Condition (@($service.Supports.Invoke('AuthenticationSession')) -contains $true) -Message 'Microsoft Graph provider reports AuthenticationSession capability'

$searchResults = $service.SearchUser.Invoke('Alex')
Assert-Pass -Condition (@($searchResults).Count -eq 1) -Message 'Microsoft Graph provider search returns matching user'
Assert-Pass -Condition ($searchResults[0].PSTypeNames -contains 'Hybrid.User') -Message 'Microsoft Graph provider search returns Hybrid.User model'
Assert-Pass -Condition ($searchResults[0].Source -eq 'MicrosoftGraph') -Message 'Microsoft Graph user model records MicrosoftGraph source'
Assert-Pass -Condition ($searchResults[0].UserPrincipalName -eq 'alex.morgan@atlas-test.onmicrosoft.us') -Message 'Microsoft Graph user model preserves UPN'

$getResult = @($service.GetUser.Invoke('jordan.lee@atlas-test.onmicrosoft.us')) | Select-Object -First 1
Assert-Pass -Condition ($null -ne $getResult) -Message 'Microsoft Graph provider get returns a user result'
Assert-Pass -Condition ($getResult.PSTypeNames -contains 'Hybrid.User') -Message 'Microsoft Graph provider get returns Hybrid.User model'
Assert-Pass -Condition ($getResult.DisplayName -eq 'Jordan Lee') -Message 'Microsoft Graph provider get returns expected user'

$cachedResult = @($service.GetUser.Invoke('jordan.lee@atlas-test.onmicrosoft.us')) | Select-Object -First 1
Assert-Pass -Condition ($cachedResult.DisplayName -eq $getResult.DisplayName) -Message 'Microsoft Graph provider returns stable cached user result'

$health = @($service.GetHealth.Invoke()) | Select-Object -First 1
Assert-Pass -Condition ($health.PSTypeNames -contains 'Hybrid.MicrosoftGraphProviderHealth') -Message 'Microsoft Graph provider health has platform type name'
Assert-Pass -Condition ($health.Name -eq 'MicrosoftGraph') -Message 'Microsoft Graph provider health reports provider name'
Assert-Pass -Condition ($health.Available -eq $true) -Message 'Microsoft Graph provider health reports available'
Assert-Pass -Condition ($health.Connected -eq $true) -Message 'Microsoft Graph provider health reports connected after session acquisition'
Assert-Pass -Condition (@($health.Capabilities) -contains 'Users') -Message 'Microsoft Graph provider health includes capabilities'

Write-Host ''
Write-Host 'Milestone 6 Phase 3 Microsoft Graph provider tests passed.'
