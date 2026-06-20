#region Module Information
# Name: Core.TenantContext
# Purpose: Tenant identity metadata for Hybrid Admin Console cloud operations.
# Dependencies: Core.CloudEnvironment
# Exports: New-HybridTenantContext, Test-HybridTenantContext,
#          Get-HybridTenantDefaultDomain, Get-HybridTenantCloudEnvironment
#endregion

Set-StrictMode -Version Latest

function New-HybridTenantContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$TenantId,
        [Parameter(Mandatory=$true)][string]$TenantName,
        [Parameter(Mandatory=$true)][object]$CloudEnvironment,
        [string[]]$VerifiedDomains = @(),
        [string]$DefaultDomain = '',
        [hashtable]$Attributes = @{}
    )

    if ([string]::IsNullOrWhiteSpace($TenantId)) {
        throw 'TenantId cannot be empty.'
    }

    if ([string]::IsNullOrWhiteSpace($TenantName)) {
        throw 'TenantName cannot be empty.'
    }

    if ($null -eq $CloudEnvironment) {
        throw 'CloudEnvironment is required.'
    }

    if ($CloudEnvironment.PSObject.Properties.Name -notcontains 'Name') {
        throw 'CloudEnvironment must include a Name property.'
    }

    $normalizedDomains = @()
    foreach ($domain in @($VerifiedDomains)) {
        if (-not [string]::IsNullOrWhiteSpace($domain)) {
            $normalizedDomains += ([string]$domain).Trim().ToLowerInvariant()
        }
    }

    $resolvedDefaultDomain = $DefaultDomain
    if ([string]::IsNullOrWhiteSpace($resolvedDefaultDomain) -and $normalizedDomains.Count -gt 0) {
        $resolvedDefaultDomain = $normalizedDomains[0]
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedDefaultDomain)) {
        $resolvedDefaultDomain = $resolvedDefaultDomain.Trim().ToLowerInvariant()

        if ($normalizedDomains.Count -gt 0 -and $normalizedDomains -notcontains $resolvedDefaultDomain) {
            throw "Default domain '$resolvedDefaultDomain' is not present in VerifiedDomains."
        }
    }

    [pscustomobject]@{
        PSTypeName        = 'Hybrid.TenantContext'
        TenantId          = $TenantId.Trim()
        TenantName        = $TenantName.Trim()
        CloudEnvironment  = $CloudEnvironment
        VerifiedDomains   = @($normalizedDomains)
        DefaultDomain     = $resolvedDefaultDomain
        Attributes        = $Attributes
    }
}

function Test-HybridTenantContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$TenantContext
    )

    $requiredProperties = @(
        'TenantId',
        'TenantName',
        'CloudEnvironment',
        'VerifiedDomains',
        'DefaultDomain'
    )

    foreach ($property in $requiredProperties) {
        if ($TenantContext.PSObject.Properties.Name -notcontains $property) {
            return $false
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$TenantContext.TenantId)) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace([string]$TenantContext.TenantName)) {
        return $false
    }

    if ($null -eq $TenantContext.CloudEnvironment) {
        return $false
    }

    if ($TenantContext.CloudEnvironment.PSObject.Properties.Name -notcontains 'Name') {
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$TenantContext.DefaultDomain)) {
        if (@($TenantContext.VerifiedDomains).Count -gt 0 -and @($TenantContext.VerifiedDomains) -notcontains $TenantContext.DefaultDomain) {
            return $false
        }
    }

    return $true
}

function Get-HybridTenantDefaultDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$TenantContext
    )

    if (-not (Test-HybridTenantContext -TenantContext $TenantContext)) {
        throw 'Invalid tenant context.'
    }

    return $TenantContext.DefaultDomain
}

function Get-HybridTenantCloudEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$TenantContext
    )

    if (-not (Test-HybridTenantContext -TenantContext $TenantContext)) {
        throw 'Invalid tenant context.'
    }

    return $TenantContext.CloudEnvironment
}

Export-ModuleMember -Function @(
    'New-HybridTenantContext',
    'Test-HybridTenantContext',
    'Get-HybridTenantDefaultDomain',
    'Get-HybridTenantCloudEnvironment'
)
