#region Module Information
# Name: Graph.Models
# Purpose: Microsoft Graph to Hybrid model conversion contracts.
# Dependencies: None
# Exports: ConvertFrom-HybridGraphUser, ConvertFrom-HybridGraphGroup, ConvertFrom-HybridGraphOrganization
#endregion

Set-StrictMode -Version Latest

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
    'ConvertFrom-HybridGraphOrganization'
)
