#region Module Information
# Name: Graph.Provider
# Purpose: Microsoft Graph provider foundation for HAP.
# Dependencies: Core.OrganizationContext, Graph.Client
# Exports: Initialize-HybridGraphProvider, Get-HybridGraphProviderHealth,
#          Get-HybridGraphProviderCapability, Get-HybridGraphProviderCapabilities,
#          Register-HybridGraphProvider
#endregion

Set-StrictMode -Version Latest

$script:HybridGraphProvider = $null
$script:HybridGraphCapabilities = @{
    Users        = @{ Name = 'Users';        Description = 'Microsoft Graph user read operations';        Enabled = $true }
    Groups       = @{ Name = 'Groups';       Description = 'Microsoft Graph group read operations';       Enabled = $true }
    Organization = @{ Name = 'Organization'; Description = 'Microsoft Graph organization read operations'; Enabled = $true }
    HttpPipeline = @{ Name = 'HttpPipeline'; Description = 'Uses shared HAP HTTP pipeline';               Enabled = $true }
    CloudAware   = @{ Name = 'CloudAware';   Description = 'Resolves sovereign Microsoft Graph endpoints'; Enabled = $true }
}

function Get-HybridGraphProviderCapabilities {
    [CmdletBinding()]
    param()

    return $script:HybridGraphCapabilities.Values | ForEach-Object { [pscustomobject]@{ PSTypeName = 'Hybrid.ProviderCapability'; Name = $_.Name; Description = $_.Description; Enabled = $_.Enabled } } | Sort-Object Name
}

function Get-HybridGraphProviderCapability {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Name)

    if (-not $script:HybridGraphCapabilities.ContainsKey($Name)) { return $null }
    $capability = $script:HybridGraphCapabilities[$Name]
    return [pscustomobject]@{ PSTypeName = 'Hybrid.ProviderCapability'; Name = $capability.Name; Description = $capability.Description; Enabled = $capability.Enabled }
}

function Initialize-HybridGraphProvider {
    [CmdletBinding()]
    param(
        [object]$Client = $null,
        [hashtable]$Attributes = @{}
    )

    $script:HybridGraphProvider = [pscustomobject]@{
        PSTypeName   = 'Hybrid.GraphProvider'
        Name         = 'MicrosoftGraph'
        DisplayName  = 'Microsoft Graph'
        Version      = '0.5.0-dev'
        Client       = $Client
        Capabilities = @(Get-HybridGraphProviderCapabilities)
        Health       = 'Unknown'
        Attributes   = $Attributes
        CreatedOn    = [datetime]::UtcNow
    }

    return $script:HybridGraphProvider
}

function Register-HybridGraphProvider {
    [CmdletBinding()]
    param(
        [object]$OrganizationContext = $null,
        [object]$Provider = $null
    )

    $resolvedProvider = $Provider
    if ($null -eq $resolvedProvider) {
        if ($null -eq $script:HybridGraphProvider) { $resolvedProvider = Initialize-HybridGraphProvider }
        else { $resolvedProvider = $script:HybridGraphProvider }
    }

    if ($null -ne $OrganizationContext -and (Get-Command -Name Register-HybridOrganizationProvider -ErrorAction SilentlyContinue)) {
        Register-HybridOrganizationProvider -OrganizationContext $OrganizationContext -Name 'MicrosoftGraph' -Provider $resolvedProvider | Out-Null
        foreach ($capability in $resolvedProvider.Capabilities) {
            Register-HybridOrganizationCapability -OrganizationContext $OrganizationContext -Name ("MicrosoftGraph.$($capability.Name)") -Capability $capability | Out-Null
        }
    }

    return $resolvedProvider
}

function Get-HybridGraphProviderHealth {
    [CmdletBinding()]
    param([object]$Provider = $null)

    $resolvedProvider = $Provider
    if ($null -eq $resolvedProvider) { $resolvedProvider = $script:HybridGraphProvider }

    $clientValid = $false
    if ($null -ne $resolvedProvider -and $resolvedProvider.PSObject.Properties.Name -contains 'Client' -and $null -ne $resolvedProvider.Client) {
        if (Get-Command -Name Test-HybridGraphClient -ErrorAction SilentlyContinue) {
            $clientValid = Test-HybridGraphClient -Client $resolvedProvider.Client
        }
    }

    [pscustomobject]@{
        PSTypeName    = 'Hybrid.GraphProviderHealth'
        ProviderName  = 'MicrosoftGraph'
        Status        = if ($clientValid) { 'Ready' } else { 'NotConfigured' }
        ClientValid   = $clientValid
        Capabilities  = @(Get-HybridGraphProviderCapabilities)
        CheckedOn     = [datetime]::UtcNow
    }
}

Export-ModuleMember -Function @(
    'Initialize-HybridGraphProvider',
    'Get-HybridGraphProviderHealth',
    'Get-HybridGraphProviderCapability',
    'Get-HybridGraphProviderCapabilities',
    'Register-HybridGraphProvider'
)
