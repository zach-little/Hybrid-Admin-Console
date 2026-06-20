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

Import-Module $cloudModulePath -Force
Import-Module $tenantModulePath -Force
Import-Module $organizationModulePath -Force

$cloudExports = Get-Command -Module Core.CloudEnvironment | Select-Object -ExpandProperty Name
$tenantExports = Get-Command -Module Core.TenantContext | Select-Object -ExpandProperty Name
$organizationExports = Get-Command -Module Core.OrganizationContext | Select-Object -ExpandProperty Name

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

Write-Host ''
Write-Host 'Milestone 5 Phase 2 tenant and organization context tests passed.' -ForegroundColor Cyan
