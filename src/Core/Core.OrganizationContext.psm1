#region Module Information
# Name: Core.OrganizationContext
# Purpose: Organization-wide runtime context for Hybrid Admin Console.
# Dependencies: Core.TenantContext
# Exports: New-HybridOrganizationContext, Set-HybridOrganizationContext,
#          Get-HybridOrganizationContext, Clear-HybridOrganizationContext,
#          Register-HybridOrganizationProvider, Register-HybridOrganizationCapability,
#          Get-HybridOrganizationProvider, Get-HybridOrganizationCapability,
#          Test-HybridOrganizationContext
#endregion

Set-StrictMode -Version Latest

$script:HybridOrganizationContext = $null

function New-HybridOrganizationContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][object]$TenantContext,
        [hashtable]$Branding = @{},
        [hashtable]$Providers = @{},
        [hashtable]$Capabilities = @{},
        [hashtable]$AuthenticationState = @{},
        [hashtable]$Attributes = @{}
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Organization name cannot be empty.'
    }

    if ($null -eq $TenantContext) {
        throw 'TenantContext is required.'
    }

    if ($TenantContext.PSObject.Properties.Name -notcontains 'TenantId') {
        throw 'TenantContext must include a TenantId property.'
    }

    if ($TenantContext.PSObject.Properties.Name -notcontains 'CloudEnvironment') {
        throw 'TenantContext must include a CloudEnvironment property.'
    }

    [pscustomobject]@{
        PSTypeName          = 'Hybrid.OrganizationContext'
        Name                = $Name.Trim()
        Tenant              = $TenantContext
        Branding            = $Branding
        Providers           = $Providers.Clone()
        Capabilities        = $Capabilities.Clone()
        AuthenticationState = $AuthenticationState.Clone()
        Attributes          = $Attributes.Clone()
    }
}

function Set-HybridOrganizationContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$OrganizationContext
    )

    if (-not (Test-HybridOrganizationContext -OrganizationContext $OrganizationContext)) {
        throw 'Invalid organization context.'
    }

    $script:HybridOrganizationContext = $OrganizationContext
    return $script:HybridOrganizationContext
}

function Get-HybridOrganizationContext {
    [CmdletBinding()]
    param()

    return $script:HybridOrganizationContext
}

function Clear-HybridOrganizationContext {
    [CmdletBinding()]
    param()

    $script:HybridOrganizationContext = $null
}

function Register-HybridOrganizationProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][object]$Provider,
        [object]$OrganizationContext = $script:HybridOrganizationContext
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Provider name cannot be empty.'
    }

    if ($null -eq $OrganizationContext) {
        throw 'Organization context has not been initialized.'
    }

    $OrganizationContext.Providers[$Name] = $Provider
    return $Provider
}

function Register-HybridOrganizationCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][object]$Capability,
        [object]$OrganizationContext = $script:HybridOrganizationContext
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Capability name cannot be empty.'
    }

    if ($null -eq $OrganizationContext) {
        throw 'Organization context has not been initialized.'
    }

    $OrganizationContext.Capabilities[$Name] = $Capability
    return $Capability
}

function Get-HybridOrganizationProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [object]$OrganizationContext = $script:HybridOrganizationContext
    )

    if ($null -eq $OrganizationContext) {
        return $null
    }

    if ($OrganizationContext.Providers.ContainsKey($Name)) {
        return $OrganizationContext.Providers[$Name]
    }

    return $null
}

function Get-HybridOrganizationCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [object]$OrganizationContext = $script:HybridOrganizationContext
    )

    if ($null -eq $OrganizationContext) {
        return $null
    }

    if ($OrganizationContext.Capabilities.ContainsKey($Name)) {
        return $OrganizationContext.Capabilities[$Name]
    }

    return $null
}

function Test-HybridOrganizationContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$OrganizationContext
    )

    $requiredProperties = @(
        'Name',
        'Tenant',
        'Branding',
        'Providers',
        'Capabilities',
        'AuthenticationState'
    )

    foreach ($property in $requiredProperties) {
        if ($OrganizationContext.PSObject.Properties.Name -notcontains $property) {
            return $false
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$OrganizationContext.Name)) {
        return $false
    }

    if ($null -eq $OrganizationContext.Tenant) {
        return $false
    }

    if ($OrganizationContext.Tenant.PSObject.Properties.Name -notcontains 'TenantId') {
        return $false
    }

    return $true
}

Export-ModuleMember -Function @(
    'New-HybridOrganizationContext',
    'Set-HybridOrganizationContext',
    'Get-HybridOrganizationContext',
    'Clear-HybridOrganizationContext',
    'Register-HybridOrganizationProvider',
    'Register-HybridOrganizationCapability',
    'Get-HybridOrganizationProvider',
    'Get-HybridOrganizationCapability',
    'Test-HybridOrganizationContext'
)
