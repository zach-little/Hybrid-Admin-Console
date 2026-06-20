Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot

function Assert-Pass {
    param(
        [Parameter(Mandatory=$true)][bool]$Condition,
        [Parameter(Mandatory=$true)][string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Assert-Throws {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory=$true)][string]$Message
    )

    $threw = $false

    try {
        & $ScriptBlock
    }
    catch {
        $threw = $true
    }

    Assert-Pass -Condition $threw -Message $Message
}

$cloudModulePath = Join-Path $RepoRoot 'src\Core\Core.CloudEnvironment.psm1'
$tenantModulePath = Join-Path $RepoRoot 'src\Core\Core.TenantContext.psm1'
$organizationModulePath = Join-Path $RepoRoot 'src\Core\Core.OrganizationContext.psm1'
$authenticationModulePath = Join-Path $RepoRoot 'src\Core\Core.Authentication.psm1'
$httpResponseModulePath = Join-Path $RepoRoot 'src\Core\Core.HttpResponse.psm1'
$httpRetryModulePath = Join-Path $RepoRoot 'src\Core\Core.HttpRetry.psm1'
$httpPipelineModulePath = Join-Path $RepoRoot 'src\Core\Core.HttpPipeline.psm1'

Import-Module $cloudModulePath -Force
Import-Module $tenantModulePath -Force
Import-Module $organizationModulePath -Force
Import-Module $authenticationModulePath -Force
Import-Module $httpResponseModulePath -Force
Import-Module $httpRetryModulePath -Force
Import-Module $httpPipelineModulePath -Force

$cloudExports = Get-Command -Module Core.CloudEnvironment | Select-Object -ExpandProperty Name
$tenantExports = Get-Command -Module Core.TenantContext | Select-Object -ExpandProperty Name
$organizationExports = Get-Command -Module Core.OrganizationContext | Select-Object -ExpandProperty Name
$authenticationExports = Get-Command -Module Core.Authentication | Select-Object -ExpandProperty Name
$httpResponseExports = Get-Command -Module Core.HttpResponse | Select-Object -ExpandProperty Name
$httpRetryExports = Get-Command -Module Core.HttpRetry | Select-Object -ExpandProperty Name
$httpPipelineExports = Get-Command -Module Core.HttpPipeline | Select-Object -ExpandProperty Name

Assert-Pass -Condition ($cloudExports -contains 'New-HybridCloudEnvironment') -Message 'New-HybridCloudEnvironment exported'
Assert-Pass -Condition ($cloudExports -contains 'Register-HybridCloudEnvironment') -Message 'Register-HybridCloudEnvironment exported'
Assert-Pass -Condition ($cloudExports -contains 'Get-HybridCloudEnvironment') -Message 'Get-HybridCloudEnvironment exported'
Assert-Pass -Condition ($cloudExports -contains 'Get-HybridCloudEnvironmentNames') -Message 'Get-HybridCloudEnvironmentNames exported'
Assert-Pass -Condition ($cloudExports -contains 'Get-HybridCloudEnvironmentEndpoint') -Message 'Get-HybridCloudEnvironmentEndpoint exported'
Assert-Pass -Condition ($cloudExports -contains 'Resolve-HybridCloudEndpoint') -Message 'Resolve-HybridCloudEndpoint exported'
Assert-Pass -Condition ($cloudExports -contains 'Test-HybridCloudEnvironment') -Message 'Test-HybridCloudEnvironment exported'

Assert-Pass -Condition ($tenantExports -contains 'New-HybridTenantContext') -Message 'New-HybridTenantContext exported'
Assert-Pass -Condition ($tenantExports -contains 'Test-HybridTenantContext') -Message 'Test-HybridTenantContext exported'
Assert-Pass -Condition ($tenantExports -contains 'Get-HybridTenantDefaultDomain') -Message 'Get-HybridTenantDefaultDomain exported'
Assert-Pass -Condition ($tenantExports -contains 'Get-HybridTenantCloudEnvironment') -Message 'Get-HybridTenantCloudEnvironment exported'

Assert-Pass -Condition ($organizationExports -contains 'New-HybridOrganizationContext') -Message 'New-HybridOrganizationContext exported'
Assert-Pass -Condition ($organizationExports -contains 'Set-HybridOrganizationContext') -Message 'Set-HybridOrganizationContext exported'
Assert-Pass -Condition ($organizationExports -contains 'Get-HybridOrganizationContext') -Message 'Get-HybridOrganizationContext exported'
Assert-Pass -Condition ($organizationExports -contains 'Clear-HybridOrganizationContext') -Message 'Clear-HybridOrganizationContext exported'
Assert-Pass -Condition ($organizationExports -contains 'Register-HybridOrganizationProvider') -Message 'Register-HybridOrganizationProvider exported'
Assert-Pass -Condition ($organizationExports -contains 'Register-HybridOrganizationCapability') -Message 'Register-HybridOrganizationCapability exported'
Assert-Pass -Condition ($organizationExports -contains 'Get-HybridOrganizationProvider') -Message 'Get-HybridOrganizationProvider exported'
Assert-Pass -Condition ($organizationExports -contains 'Get-HybridOrganizationCapability') -Message 'Get-HybridOrganizationCapability exported'
Assert-Pass -Condition ($organizationExports -contains 'Test-HybridOrganizationContext') -Message 'Test-HybridOrganizationContext exported'

Assert-Pass -Condition ($authenticationExports -contains 'New-HybridAuthenticationPolicy') -Message 'New-HybridAuthenticationPolicy exported'
Assert-Pass -Condition ($authenticationExports -contains 'Get-HybridAuthenticationPolicy') -Message 'Get-HybridAuthenticationPolicy exported'
Assert-Pass -Condition ($authenticationExports -contains 'Set-HybridAuthenticationPolicy') -Message 'Set-HybridAuthenticationPolicy exported'
Assert-Pass -Condition ($authenticationExports -contains 'Register-HybridAuthenticationMethod') -Message 'Register-HybridAuthenticationMethod exported'
Assert-Pass -Condition ($authenticationExports -contains 'Get-HybridAuthenticationMethod') -Message 'Get-HybridAuthenticationMethod exported'
Assert-Pass -Condition ($authenticationExports -contains 'Get-HybridAuthenticationMethodNames') -Message 'Get-HybridAuthenticationMethodNames exported'
Assert-Pass -Condition ($authenticationExports -contains 'New-HybridAuthenticationRequest') -Message 'New-HybridAuthenticationRequest exported'
Assert-Pass -Condition ($authenticationExports -contains 'New-HybridAuthenticationSession') -Message 'New-HybridAuthenticationSession exported'
Assert-Pass -Condition ($authenticationExports -contains 'New-HybridTokenDescriptor') -Message 'New-HybridTokenDescriptor exported'
Assert-Pass -Condition ($authenticationExports -contains 'Test-HybridTokenDescriptor') -Message 'Test-HybridTokenDescriptor exported'
Assert-Pass -Condition ($authenticationExports -contains 'New-HybridAuthenticationResult') -Message 'New-HybridAuthenticationResult exported'
Assert-Pass -Condition ($authenticationExports -contains 'Get-HybridAuthenticationSessionState') -Message 'Get-HybridAuthenticationSessionState exported'
Assert-Pass -Condition ($authenticationExports -contains 'New-HybridAuthenticationCacheKey') -Message 'New-HybridAuthenticationCacheKey exported'
Assert-Pass -Condition ($authenticationExports -contains 'New-HybridAuthenticationCacheEntry') -Message 'New-HybridAuthenticationCacheEntry exported'
Assert-Pass -Condition ($authenticationExports -contains 'Test-HybridAuthenticationSession') -Message 'Test-HybridAuthenticationSession exported'

Assert-Pass -Condition ($httpResponseExports -contains 'New-HybridHttpResponse') -Message 'New-HybridHttpResponse exported'
Assert-Pass -Condition ($httpResponseExports -contains 'New-HybridHttpError') -Message 'New-HybridHttpError exported'
Assert-Pass -Condition ($httpResponseExports -contains 'Test-HybridHttpResponse') -Message 'Test-HybridHttpResponse exported'
Assert-Pass -Condition ($httpRetryExports -contains 'New-HybridHttpRetryPolicy') -Message 'New-HybridHttpRetryPolicy exported'
Assert-Pass -Condition ($httpRetryExports -contains 'Test-HybridHttpRetryPolicy') -Message 'Test-HybridHttpRetryPolicy exported'
Assert-Pass -Condition ($httpRetryExports -contains 'Get-HybridHttpRetryDelay') -Message 'Get-HybridHttpRetryDelay exported'
Assert-Pass -Condition ($httpRetryExports -contains 'Invoke-HybridHttpRetry') -Message 'Invoke-HybridHttpRetry exported'
Assert-Pass -Condition ($httpPipelineExports -contains 'New-HybridHttpRequest') -Message 'New-HybridHttpRequest exported'
Assert-Pass -Condition ($httpPipelineExports -contains 'New-HybridHttpPipeline') -Message 'New-HybridHttpPipeline exported'
Assert-Pass -Condition ($httpPipelineExports -contains 'Invoke-HybridHttpPipeline') -Message 'Invoke-HybridHttpPipeline exported'
Assert-Pass -Condition ($httpPipelineExports -contains 'New-HybridHttpPipelineDiagnostic') -Message 'New-HybridHttpPipelineDiagnostic exported'
Assert-Pass -Condition ($httpPipelineExports -contains 'New-HybridHttpPaginationState') -Message 'New-HybridHttpPaginationState exported'



$commercial = Get-HybridCloudEnvironment -Name 'Commercial'
$gccHigh = Get-HybridCloudEnvironment -Name 'GccHigh'
$dod = Get-HybridCloudEnvironment -Name 'DoD'

Assert-Pass -Condition ($null -ne $commercial) -Message 'Commercial cloud environment registered'
Assert-Pass -Condition ($null -ne $gccHigh) -Message 'GCC High cloud environment registered'
Assert-Pass -Condition ($null -ne $dod) -Message 'DoD cloud environment registered'
Assert-Pass -Condition ((Get-HybridCloudEnvironmentEndpoint -Name 'GccHigh' -EndpointName 'Graph') -eq 'https://graph.microsoft.us') -Message 'GCC High Graph endpoint resolves'
Assert-Pass -Condition ((Get-HybridCloudEnvironment -Name 'USGov').Name -eq 'GccHigh') -Message 'GCC High alias resolves'
Assert-Pass -Condition ((Resolve-HybridCloudEndpoint -Name 'GccHigh' -EndpointName 'Graph' -Path '/v1.0/users') -eq 'https://graph.microsoft.us/v1.0/users') -Message 'Graph path resolves without duplicate slashes'

$custom = New-HybridCloudEnvironment -Name 'CustomGov' -DisplayName 'Custom Government Cloud' -Aliases @('CustomAlias') -Endpoints @{
    Graph = 'https://graph.contoso.example/'
    Login = 'https://login.contoso.example/'
}
Register-HybridCloudEnvironment -Environment $custom -Force | Out-Null
Assert-Pass -Condition (Test-HybridCloudEnvironment -Environment $custom -RequiredEndpoints @('Graph', 'Login')) -Message 'Custom cloud environment validates'
Assert-Pass -Condition ((Get-HybridCloudEnvironmentEndpoint -Name 'CustomAlias' -EndpointName 'Graph') -eq 'https://graph.contoso.example') -Message 'Custom cloud alias resolves and trims trailing slash'
Assert-Pass -Condition (-not (Test-HybridCloudEnvironment -Environment $custom -RequiredEndpoints @('Graph', 'Login', 'Portal'))) -Message 'Invalid environment fails validation when Portal endpoint is missing'

$tenant = New-HybridTenantContext -TenantId '11111111-1111-1111-1111-111111111111' -TenantName 'Atlas Tech' -CloudEnvironment $gccHigh -VerifiedDomains @('atlas-tech.com', 'atlas.onmicrosoft.us') -DefaultDomain 'atlas-tech.com'
Assert-Pass -Condition ($tenant.PSTypeNames -contains 'Hybrid.TenantContext') -Message 'Tenant context has provider-specific type name'
Assert-Pass -Condition ($tenant.TenantId -eq '11111111-1111-1111-1111-111111111111') -Message 'Tenant context preserves tenant id'
Assert-Pass -Condition ($tenant.TenantName -eq 'Atlas Tech') -Message 'Tenant context preserves tenant name'
Assert-Pass -Condition ($tenant.CloudEnvironment.Name -eq 'GccHigh') -Message 'Tenant context attaches cloud environment'
Assert-Pass -Condition ($tenant.VerifiedDomains -contains 'atlas-tech.com') -Message 'Tenant context stores verified domains'
Assert-Pass -Condition ((Get-HybridTenantDefaultDomain -TenantContext $tenant) -eq 'atlas-tech.com') -Message 'Tenant default domain resolves'
Assert-Pass -Condition ((Get-HybridTenantCloudEnvironment -TenantContext $tenant).Name -eq 'GccHigh') -Message 'Tenant cloud environment resolves'
Assert-Pass -Condition (Test-HybridTenantContext -TenantContext $tenant) -Message 'Tenant context validates'

$tenantWithImplicitDefault = New-HybridTenantContext -TenantId '22222222-2222-2222-2222-222222222222' -TenantName 'Implicit Default' -CloudEnvironment $commercial -VerifiedDomains @('example.com')
Assert-Pass -Condition ($tenantWithImplicitDefault.DefaultDomain -eq 'example.com') -Message 'Tenant context defaults to first verified domain'
Assert-Throws -ScriptBlock { New-HybridTenantContext -TenantId '33333333-3333-3333-3333-333333333333' -TenantName 'Invalid Default' -CloudEnvironment $commercial -VerifiedDomains @('example.com') -DefaultDomain 'invalid.example' | Out-Null } -Message 'Tenant context rejects default domain outside verified domains'

$organization = New-HybridOrganizationContext -Name 'Atlas Tech' -TenantContext $tenant -Branding @{ Theme = 'DarkTeal' }
Assert-Pass -Condition ($organization.PSTypeNames -contains 'Hybrid.OrganizationContext') -Message 'Organization context has provider-specific type name'
Assert-Pass -Condition ($organization.Name -eq 'Atlas Tech') -Message 'Organization context preserves organization name'
Assert-Pass -Condition ($organization.Tenant.TenantId -eq $tenant.TenantId) -Message 'Organization context attaches tenant context'
Assert-Pass -Condition ($organization.Tenant.CloudEnvironment.Name -eq 'GccHigh') -Message 'Organization context exposes current cloud'
Assert-Pass -Condition ($organization.Branding.Theme -eq 'DarkTeal') -Message 'Organization context stores branding metadata'
Assert-Pass -Condition (Test-HybridOrganizationContext -OrganizationContext $organization) -Message 'Organization context validates'

Clear-HybridOrganizationContext
Assert-Pass -Condition ($null -eq (Get-HybridOrganizationContext)) -Message 'Organization context clears singleton state'
Set-HybridOrganizationContext -OrganizationContext $organization | Out-Null
Assert-Pass -Condition ((Get-HybridOrganizationContext).Name -eq 'Atlas Tech') -Message 'Organization context registers singleton state'

$provider = [pscustomobject]@{ Name = 'MicrosoftGraph'; Source = 'CloudFoundation' }
Register-HybridOrganizationProvider -Name 'Graph' -Provider $provider | Out-Null
Assert-Pass -Condition ((Get-HybridOrganizationProvider -Name 'Graph').Name -eq 'MicrosoftGraph') -Message 'Organization context registers provider'

$capability = [pscustomobject]@{ Name = 'CloudEndpointResolution'; Enabled = $true }
Register-HybridOrganizationCapability -Name 'CloudEndpointResolution' -Capability $capability | Out-Null
Assert-Pass -Condition ((Get-HybridOrganizationCapability -Name 'CloudEndpointResolution').Enabled -eq $true) -Message 'Organization context registers capability'
Assert-Pass -Condition ($null -eq (Get-HybridOrganizationProvider -Name 'MissingProvider')) -Message 'Organization provider lookup returns null for missing provider'
Assert-Pass -Condition ($null -eq (Get-HybridOrganizationCapability -Name 'MissingCapability')) -Message 'Organization capability lookup returns null for missing capability'


$authPolicy = Get-HybridAuthenticationPolicy
Assert-Pass -Condition ($authPolicy.PSTypeNames -contains 'Hybrid.AuthenticationPolicy') -Message 'Authentication policy has platform type name'
Assert-Pass -Condition ($authPolicy.AllowDeviceCode -eq $false) -Message 'Authentication policy disables Device Code Flow'
Assert-Pass -Condition ($authPolicy.AllowedMethods -contains 'Interactive') -Message 'Authentication policy allows interactive method'
Assert-Pass -Condition ($authPolicy.AllowedMethods -contains 'AppOnlyClientCredentials') -Message 'Authentication policy allows app-only method'
Assert-Pass -Condition ($authPolicy.DefaultMethod -eq 'Interactive') -Message 'Authentication policy defaults to interactive method'

$authMethods = Get-HybridAuthenticationMethodNames
Assert-Pass -Condition ($authMethods -contains 'Interactive') -Message 'Interactive authentication method registered'
Assert-Pass -Condition ($authMethods -contains 'InteractiveBrowser') -Message 'Interactive browser authentication method registered'
Assert-Pass -Condition ($authMethods -contains 'AppOnlyClientCredentials') -Message 'App-only authentication method registered'
Assert-Pass -Condition ($authMethods -contains 'ManagedIdentity') -Message 'Managed identity authentication method registered'
Assert-Pass -Condition (-not ($authMethods -contains 'DeviceCode')) -Message 'Device Code authentication method not registered'

$interactiveMethod = Get-HybridAuthenticationMethod -Name 'Interactive'
Assert-Pass -Condition ($interactiveMethod.Mode -eq 'Delegated') -Message 'Interactive method reports delegated mode'
Assert-Pass -Condition ($interactiveMethod.RequiresUserInteraction -eq $true) -Message 'Interactive method requires user interaction'

$appOnlyMethod = Get-HybridAuthenticationMethod -Name 'AppOnlyClientCredentials'
Assert-Pass -Condition ($appOnlyMethod.Mode -eq 'Application') -Message 'App-only method reports application mode'
Assert-Pass -Condition ($appOnlyMethod.RequiresClientSecret -eq $true) -Message 'App-only method records client secret requirement'

Assert-Throws -ScriptBlock { Register-HybridAuthenticationMethod -Name 'DeviceCode' -Mode Delegated | Out-Null } -Message 'Device Code method registration is rejected'
Assert-Throws -ScriptBlock { New-HybridAuthenticationPolicy -AllowedMethods @('Interactive', 'DeviceCode') -DefaultMethod 'Interactive' | Out-Null } -Message 'Authentication policy rejects Device Code Flow'

$customPolicy = New-HybridAuthenticationPolicy -AllowedMethods @('InteractiveBrowser') -DefaultMethod 'InteractiveBrowser' -RequiredScopes @('https://graph.microsoft.us/.default')
Set-HybridAuthenticationPolicy -Policy $customPolicy | Out-Null
Assert-Pass -Condition ((Get-HybridAuthenticationPolicy).DefaultMethod -eq 'InteractiveBrowser') -Message 'Authentication policy can be replaced'
Assert-Pass -Condition ((Get-HybridAuthenticationPolicy).RequiredScopes -contains 'https://graph.microsoft.us/.default') -Message 'Authentication policy stores required scopes'

$authRequest = New-HybridAuthenticationRequest -TenantContext $tenant -ClientId '00000000-0000-0000-0000-000000000000'
Assert-Pass -Condition ($authRequest.PSTypeNames -contains 'Hybrid.AuthenticationRequest') -Message 'Authentication request has platform type name'
Assert-Pass -Condition ($authRequest.MethodName -eq 'InteractiveBrowser') -Message 'Authentication request uses policy default method'
Assert-Pass -Condition ($authRequest.TenantContext.TenantId -eq $tenant.TenantId) -Message 'Authentication request attaches tenant context'
Assert-Pass -Condition ($authRequest.CloudEnvironment.Name -eq 'GccHigh') -Message 'Authentication request attaches cloud environment'
Assert-Pass -Condition ($authRequest.Authority -eq 'https://login.microsoftonline.us/11111111-1111-1111-1111-111111111111') -Message 'Authentication request resolves sovereign authority'
Assert-Pass -Condition ($authRequest.Scopes -contains 'https://graph.microsoft.us/.default') -Message 'Authentication request inherits policy scopes'

$explicitRequest = New-HybridAuthenticationRequest -TenantContext $tenant -MethodName 'InteractiveBrowser' -Scopes @('User.Read')
Assert-Pass -Condition ($explicitRequest.Scopes -contains 'User.Read') -Message 'Authentication request accepts explicit scopes'

$session = New-HybridAuthenticationSession -AuthenticationRequest $explicitRequest -AccessToken 'mock-token' -ExpiresOn ([datetime]::UtcNow.AddHours(1))
Assert-Pass -Condition ($session.PSTypeNames -contains 'Hybrid.AuthenticationSession') -Message 'Authentication session has platform type name'
Assert-Pass -Condition (-not [string]::IsNullOrWhiteSpace($session.SessionId)) -Message 'Authentication session receives session id'
Assert-Pass -Condition ($session.IsAuthenticated -eq $true) -Message 'Authentication session reports authenticated when token exists'
Assert-Pass -Condition ($session.TokenType -eq 'Bearer') -Message 'Authentication session defaults to bearer token type'
Assert-Pass -Condition ($session.CloudEnvironment.Name -eq 'GccHigh') -Message 'Authentication session preserves cloud environment'
Assert-Pass -Condition (Test-HybridAuthenticationSession -Session $session) -Message 'Authentication session validates'

$expiredSession = New-HybridAuthenticationSession -AuthenticationRequest $explicitRequest -AccessToken 'expired-token' -ExpiresOn ([datetime]::UtcNow.AddMinutes(-5))
Assert-Pass -Condition (-not (Test-HybridAuthenticationSession -Session $expiredSession)) -Message 'Expired authentication session fails validation'


$tokenDescriptor = New-HybridTokenDescriptor -AccessToken 'descriptor-token' -ExpiresOn ([datetime]::UtcNow.AddHours(2)) -Scopes @('User.Read', 'Group.Read.All') -Claims @{ tid = $tenant.TenantId }
Assert-Pass -Condition ($tokenDescriptor.PSTypeNames -contains 'Hybrid.TokenDescriptor') -Message 'Token descriptor has platform type name'
Assert-Pass -Condition ($tokenDescriptor.TokenType -eq 'Bearer') -Message 'Token descriptor defaults to bearer token type'
Assert-Pass -Condition ($tokenDescriptor.Scopes -contains 'User.Read') -Message 'Token descriptor stores scopes'
Assert-Pass -Condition ($tokenDescriptor.Claims.tid -eq $tenant.TenantId) -Message 'Token descriptor stores claims'
Assert-Pass -Condition (Test-HybridTokenDescriptor -TokenDescriptor $tokenDescriptor) -Message 'Token descriptor validates'

$expiredTokenDescriptor = New-HybridTokenDescriptor -AccessToken 'expired-descriptor-token' -ExpiresOn ([datetime]::UtcNow.AddMinutes(-1))
Assert-Pass -Condition (-not (Test-HybridTokenDescriptor -TokenDescriptor $expiredTokenDescriptor)) -Message 'Expired token descriptor fails validation'

$authResult = New-HybridAuthenticationResult -AuthenticationRequest $explicitRequest -TokenDescriptor $tokenDescriptor -Succeeded $true
Assert-Pass -Condition ($authResult.PSTypeNames -contains 'Hybrid.AuthenticationResult') -Message 'Authentication result has platform type name'
Assert-Pass -Condition ($authResult.Succeeded -eq $true) -Message 'Authentication result records success state'
Assert-Pass -Condition ($authResult.Status -eq 'Succeeded') -Message 'Authentication result defaults success status'
Assert-Pass -Condition ($authResult.TokenDescriptor.AccessToken -eq 'descriptor-token') -Message 'Authentication result attaches token descriptor'
Assert-Pass -Condition ($authResult.TenantContext.TenantId -eq $tenant.TenantId) -Message 'Authentication result preserves tenant context'

$failedAuthResult = New-HybridAuthenticationResult -AuthenticationRequest $explicitRequest -Succeeded $false -ErrorCode 'MockFailure' -ErrorMessage 'Mock authentication failure'
Assert-Pass -Condition ($failedAuthResult.Status -eq 'Failed') -Message 'Authentication result defaults failed status'
Assert-Pass -Condition ($failedAuthResult.ErrorCode -eq 'MockFailure') -Message 'Authentication result stores failure code'

$descriptorSession = New-HybridAuthenticationSession -AuthenticationRequest $explicitRequest -TokenDescriptor $tokenDescriptor
Assert-Pass -Condition ($descriptorSession.TokenDescriptor.AccessToken -eq 'descriptor-token') -Message 'Authentication session accepts token descriptor'
Assert-Pass -Condition ($descriptorSession.Scopes -contains 'Group.Read.All') -Message 'Authentication session inherits descriptor scopes'
Assert-Pass -Condition ((Get-HybridAuthenticationSessionState -Session $descriptorSession) -eq 'Valid') -Message 'Authentication session state reports valid session'

$refreshSession = New-HybridAuthenticationSession -AuthenticationRequest $explicitRequest -AccessToken 'refresh-token' -ExpiresOn ([datetime]::UtcNow.AddMinutes(2))
Assert-Pass -Condition ((Get-HybridAuthenticationSessionState -Session $refreshSession -RefreshWindowMinutes 5) -eq 'RefreshRequired') -Message 'Authentication session state reports refresh required'

$unauthenticatedSession = New-HybridAuthenticationSession -AuthenticationRequest $explicitRequest
Assert-Pass -Condition ((Get-HybridAuthenticationSessionState -Session $unauthenticatedSession) -eq 'Unauthenticated') -Message 'Authentication session state reports unauthenticated session'

$cacheKey = New-HybridAuthenticationCacheKey -AuthenticationRequest $explicitRequest
Assert-Pass -Condition ($cacheKey.PSTypeNames -contains 'Hybrid.AuthenticationCacheKey') -Message 'Authentication cache key has platform type name'
Assert-Pass -Condition ($cacheKey.TenantId -eq $tenant.TenantId) -Message 'Authentication cache key includes tenant id'
Assert-Pass -Condition ($cacheKey.CloudEnvironment -eq 'GccHigh') -Message 'Authentication cache key includes cloud environment'
Assert-Pass -Condition ($cacheKey.MethodName -eq 'InteractiveBrowser') -Message 'Authentication cache key includes method name'
Assert-Pass -Condition ($cacheKey.ScopeKey -eq 'User.Read') -Message 'Authentication cache key normalizes scopes'

$cacheEntry = New-HybridAuthenticationCacheEntry -CacheKey $cacheKey -Session $descriptorSession
Assert-Pass -Condition ($cacheEntry.PSTypeNames -contains 'Hybrid.AuthenticationCacheEntry') -Message 'Authentication cache entry has platform type name'
Assert-Pass -Condition ($cacheEntry.Key -eq $cacheKey.Key) -Message 'Authentication cache entry preserves key'
Assert-Pass -Condition ($cacheEntry.Session.SessionId -eq $descriptorSession.SessionId) -Message 'Authentication cache entry attaches session'
Assert-Pass -Condition ($cacheEntry.State -eq 'Valid') -Message 'Authentication cache entry records session state'

Set-HybridAuthenticationPolicy -Policy (New-HybridAuthenticationPolicy) | Out-Null


$httpResponse = New-HybridHttpResponse -StatusCode 200 -Headers @{ 'request-id' = 'mock-request' } -Body @{ value = 'ok' } -CorrelationId 'corr-001' -AttemptCount 1 -RequestUri 'https://graph.microsoft.us/v1.0/me'
Assert-Pass -Condition ($httpResponse.PSTypeNames -contains 'Hybrid.HttpResponse') -Message 'HTTP response has platform type name'
Assert-Pass -Condition ($httpResponse.Succeeded -eq $true) -Message 'HTTP response reports success for 2xx status'
Assert-Pass -Condition ($httpResponse.Headers['request-id'] -eq 'mock-request') -Message 'HTTP response stores headers'
Assert-Pass -Condition (Test-HybridHttpResponse -Response $httpResponse) -Message 'HTTP response validates'

$httpError = New-HybridHttpError -Code 'MockError' -Message 'Mock failure' -StatusCode 500
Assert-Pass -Condition ($httpError.PSTypeNames -contains 'Hybrid.HttpError') -Message 'HTTP error has platform type name'
Assert-Pass -Condition ($httpError.Code -eq 'MockError') -Message 'HTTP error stores code'

$failedHttpResponse = New-HybridHttpResponse -StatusCode 500 -Error $httpError -CorrelationId 'corr-002'
Assert-Pass -Condition ($failedHttpResponse.Succeeded -eq $false) -Message 'HTTP response reports failure for error state'

$retryPolicy = New-HybridHttpRetryPolicy -MaxAttempts 3 -BaseDelayMilliseconds 10 -ExponentialBackoff -DisableDelay
Assert-Pass -Condition ($retryPolicy.PSTypeNames -contains 'Hybrid.HttpRetryPolicy') -Message 'HTTP retry policy has platform type name'
Assert-Pass -Condition ($retryPolicy.RetryStatusCodes -contains 429) -Message 'HTTP retry policy includes throttling status'
Assert-Pass -Condition (Test-HybridHttpRetryPolicy -Policy $retryPolicy) -Message 'HTTP retry policy validates'
Assert-Pass -Condition ((Get-HybridHttpRetryDelay -Policy $retryPolicy -Attempt 2) -eq 0) -Message 'HTTP retry delay honors disabled delay'

$retryAttemptCount = 0
$retryResult = Invoke-HybridHttpRetry -Policy $retryPolicy -Operation {
    param($Attempt)
    $script:retryAttemptCount = $Attempt
    if ($Attempt -lt 3) {
        return [pscustomobject]@{ StatusCode = 429; Body = @{ retry = $Attempt } }
    }
    return [pscustomobject]@{ StatusCode = 200; Body = @{ ok = $true } }
}
Assert-Pass -Condition ($retryResult.StatusCode -eq 200) -Message 'HTTP retry returns successful final response'
Assert-Pass -Condition ($retryAttemptCount -eq 3) -Message 'HTTP retry attempts until success'

$httpRequest = New-HybridHttpRequest -Uri 'https://graph.microsoft.us/v1.0/users' -Method GET -Headers @{ ConsistencyLevel = 'eventual' } -AuthenticationSession $descriptorSession
Assert-Pass -Condition ($httpRequest.PSTypeNames -contains 'Hybrid.HttpRequest') -Message 'HTTP request has platform type name'
Assert-Pass -Condition ($httpRequest.Method -eq 'GET') -Message 'HTTP request normalizes method'
Assert-Pass -Condition (-not [string]::IsNullOrWhiteSpace($httpRequest.CorrelationId)) -Message 'HTTP request generates correlation id'

$capturedPreparedRequest = $null
$pipeline = New-HybridHttpPipeline -AuthenticationSession $descriptorSession -RetryPolicy $retryPolicy -DefaultHeaders @{ 'Accept' = 'application/json' } -Transport {
    param($PreparedRequest, $Attempt)
    $script:capturedPreparedRequest = $PreparedRequest
    return [pscustomobject]@{
        StatusCode = 200
        Headers = @{ 'request-id' = 'pipeline-request' }
        Body = @{ value = @('one', 'two') }
    }
}
Assert-Pass -Condition ($pipeline.PSTypeNames -contains 'Hybrid.HttpPipeline') -Message 'HTTP pipeline has platform type name'

$pipelineResponse = Invoke-HybridHttpPipeline -Pipeline $pipeline -Request $httpRequest
Assert-Pass -Condition ($pipelineResponse.PSTypeNames -contains 'Hybrid.HttpResponse') -Message 'HTTP pipeline returns platform response'
Assert-Pass -Condition ($pipelineResponse.Succeeded -eq $true) -Message 'HTTP pipeline reports successful response'
Assert-Pass -Condition ($pipelineResponse.Body.value.Count -eq 2) -Message 'HTTP pipeline preserves response body'
Assert-Pass -Condition ($pipelineResponse.AttemptCount -eq 1) -Message 'HTTP pipeline records attempt count'
Assert-Pass -Condition ($capturedPreparedRequest.Headers['Authorization'] -eq 'Bearer descriptor-token') -Message 'HTTP pipeline injects bearer token'
Assert-Pass -Condition ($capturedPreparedRequest.Headers['Accept'] -eq 'application/json') -Message 'HTTP pipeline applies default headers'
Assert-Pass -Condition ($capturedPreparedRequest.Headers['ConsistencyLevel'] -eq 'eventual') -Message 'HTTP pipeline applies request headers'
Assert-Pass -Condition ($capturedPreparedRequest.Headers.ContainsKey('x-ms-client-request-id')) -Message 'HTTP pipeline injects correlation header'
Assert-Pass -Condition ($capturedPreparedRequest.Headers.ContainsKey('User-Agent')) -Message 'HTTP pipeline injects user agent'

$retryingPipelineAttempts = 0
$retryingPipeline = New-HybridHttpPipeline -AuthenticationSession $descriptorSession -RetryPolicy $retryPolicy -Transport {
    param($PreparedRequest, $Attempt)
    $script:retryingPipelineAttempts = $Attempt
    if ($Attempt -lt 2) {
        return [pscustomobject]@{ StatusCode = 503; Headers = @{}; Body = @{ transient = $true } }
    }
    return [pscustomobject]@{ StatusCode = 200; Headers = @{}; Body = @{ recovered = $true } }
}
$retryingPipelineResponse = Invoke-HybridHttpPipeline -Pipeline $retryingPipeline -Request $httpRequest
Assert-Pass -Condition ($retryingPipelineResponse.StatusCode -eq 200) -Message 'HTTP pipeline retries transient response'
Assert-Pass -Condition ($retryingPipelineResponse.AttemptCount -eq 2) -Message 'HTTP pipeline records retry attempt count'
Assert-Pass -Condition ($retryingPipelineAttempts -eq 2) -Message 'HTTP pipeline mock transport sees retry attempt'

$errorPipeline = New-HybridHttpPipeline -AuthenticationSession $descriptorSession -RetryPolicy (New-HybridHttpRetryPolicy -MaxAttempts 1 -DisableDelay) -Transport {
    param($PreparedRequest, $Attempt)
    return [pscustomobject]@{ StatusCode = 500; Headers = @{}; Body = @{ error = 'bad' } }
}
$errorPipelineResponse = Invoke-HybridHttpPipeline -Pipeline $errorPipeline -Request $httpRequest
Assert-Pass -Condition ($errorPipelineResponse.Succeeded -eq $false) -Message 'HTTP pipeline reports failed status response'
Assert-Pass -Condition ($errorPipelineResponse.Error.Code -eq 'HTTP500') -Message 'HTTP pipeline creates standardized HTTP error'

$paginationState = New-HybridHttpPaginationState -NextLink 'https://graph.microsoft.us/v1.0/users?$skiptoken=abc' -HasMore $true -PageNumber 2
Assert-Pass -Condition ($paginationState.PSTypeNames -contains 'Hybrid.HttpPaginationState') -Message 'HTTP pagination state has platform type name'
Assert-Pass -Condition ($paginationState.HasMore -eq $true) -Message 'HTTP pagination state records additional pages'

$diagnostic = New-HybridHttpPipelineDiagnostic -CorrelationId $httpRequest.CorrelationId -RequestUri $httpRequest.Uri -Method $httpRequest.Method -AttemptCount $pipelineResponse.AttemptCount -Duration $pipelineResponse.Duration -State 'Completed'
Assert-Pass -Condition ($diagnostic.PSTypeNames -contains 'Hybrid.HttpPipelineDiagnostic') -Message 'HTTP pipeline diagnostic has platform type name'
Assert-Pass -Condition ($diagnostic.State -eq 'Completed') -Message 'HTTP pipeline diagnostic records state'

Write-Host ''
Write-Host 'Milestone 5 Phase 5 shared HTTP pipeline tests passed.' -ForegroundColor Cyan
