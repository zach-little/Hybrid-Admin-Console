#region Module Information
# Name: Graph.Models
# Purpose: Microsoft Graph to Hybrid model conversion contracts.
# Dependencies: None
# Exports: ConvertFrom-HybridGraphUser, ConvertFrom-HybridGraphGroup, ConvertFrom-HybridGraphOrganization,
#          New-HybridGraphMapper, Invoke-HybridGraphMapper
#endregion

Set-StrictMode -Version Latest


function New-HybridGraphMapper {
    [CmdletBinding()]
    param(
        [hashtable]$Mappings = @{}
    )

    $resolved = @{}
    $resolved['User'] = { param($Object) ConvertFrom-HybridGraphUser -GraphUser $Object }
    $resolved['Group'] = { param($Object) ConvertFrom-HybridGraphGroup -GraphGroup $Object }
    $resolved['Organization'] = { param($Object) ConvertFrom-HybridGraphOrganization -GraphOrganization $Object }

    foreach ($key in $Mappings.Keys) { $resolved[$key] = $Mappings[$key] }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.GraphMapper'
        Mappings   = $resolved
        CreatedOn  = [datetime]::UtcNow
    }
}

function Invoke-HybridGraphMapper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$Mapper,
        [Parameter(Mandatory=$true)][string]$TypeName,
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$InputObject
    )

    if ($Mapper.PSObject.Properties.Name -notcontains 'Mappings') { throw 'Invalid Graph mapper. Missing Mappings property.' }
    if (-not $Mapper.Mappings.ContainsKey($TypeName)) { throw "Graph mapper does not contain mapping '$TypeName'." }

    return & $Mapper.Mappings[$TypeName] $InputObject
}

function ConvertFrom-HybridGraphUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$GraphUser
    )

    [pscustomobject]@{
        PSTypeName        = 'Hybrid.User'
        Id                = if ($GraphUser.PSObject.Properties.Name -contains 'id') { $GraphUser.id } else { '' }
        DisplayName       = if ($GraphUser.PSObject.Properties.Name -contains 'displayName') { $GraphUser.displayName } else { '' }
        UserPrincipalName = if ($GraphUser.PSObject.Properties.Name -contains 'userPrincipalName') { $GraphUser.userPrincipalName } else { '' }
        Mail              = if ($GraphUser.PSObject.Properties.Name -contains 'mail') { $GraphUser.mail } else { '' }
        Source            = 'MicrosoftGraph'
        Attributes        = @{ GraphObject = $GraphUser }
    }
}

function ConvertFrom-HybridGraphGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$GraphGroup
    )

    [pscustomobject]@{
        PSTypeName  = 'Hybrid.Group'
        Id          = if ($GraphGroup.PSObject.Properties.Name -contains 'id') { $GraphGroup.id } else { '' }
        DisplayName = if ($GraphGroup.PSObject.Properties.Name -contains 'displayName') { $GraphGroup.displayName } else { '' }
        Mail        = if ($GraphGroup.PSObject.Properties.Name -contains 'mail') { $GraphGroup.mail } else { '' }
        Source      = 'MicrosoftGraph'
        Attributes  = @{ GraphObject = $GraphGroup }
    }
}

function ConvertFrom-HybridGraphOrganization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()][object]$GraphOrganization
    )

    [pscustomobject]@{
        PSTypeName    = 'Hybrid.GraphOrganization'
        Id            = if ($GraphOrganization.PSObject.Properties.Name -contains 'id') { $GraphOrganization.id } else { '' }
        DisplayName   = if ($GraphOrganization.PSObject.Properties.Name -contains 'displayName') { $GraphOrganization.displayName } else { '' }
        VerifiedDomains = if ($GraphOrganization.PSObject.Properties.Name -contains 'verifiedDomains') { @($GraphOrganization.verifiedDomains) } else { @() }
        Source        = 'MicrosoftGraph'
        Attributes    = @{ GraphObject = $GraphOrganization }
    }
}

Export-ModuleMember -Function @(
    'ConvertFrom-HybridGraphUser',
    'ConvertFrom-HybridGraphGroup',
    'ConvertFrom-HybridGraphOrganization',
    'New-HybridGraphMapper',
    'Invoke-HybridGraphMapper'
)
