#region Module Information
# Name: Infrastructure.Mock
# Purpose: Offline mock infrastructure provider for development and testing.
# Dependencies: Core.ServiceRegistry, Hybrid.Models recommended.
# Exports: Initialize-HybridMockProvider, Search-HybridMockUser, Get-HybridMockUser
#endregion

Set-StrictMode -Version Latest

$script:State = @{
    Users = @()
}

#region Private
function Get-DefaultHybridMockUsers {
    @(
        New-HybridUser -DisplayName 'Alex Morgan' -SamAccountName 'amorgan' -UserPrincipalName 'amorgan@atlas-tech.com' -Mail 'amorgan@atlas-tech.com' -Department 'Information Technology' -Title 'Systems Administrator'
        New-HybridUser -DisplayName 'Jordan Lee' -SamAccountName 'jlee' -UserPrincipalName 'jlee@atlas-tech.com' -Mail 'jlee@atlas-tech.com' -Department 'Operations' -Title 'Project Manager'
        New-HybridUser -DisplayName 'Taylor Smith' -SamAccountName 'tsmith' -UserPrincipalName 'tsmith@atlas-tech.com' -Mail 'tsmith@atlas-tech.com' -Department 'Security' -Title 'Security Analyst'
    )
}
#endregion

#region Public
function Initialize-HybridMockProvider {
    <#.SYNOPSIS Registers mock services for offline development.#>
    [CmdletBinding()] param([Parameter(Mandatory=$true)][object]$Context)

    $script:State.Users = @(Get-DefaultHybridMockUsers)

    $directoryService = [pscustomobject]@{
        PSTypeName = 'Hybrid.MockDirectoryService'
        SearchUser = {
            param([string]$Query)
            Search-HybridMockUser -Query $Query
        }
        GetUser = {
            param([string]$Identity)
            Get-HybridMockUser -Identity $Identity
        }
    }

    if (Get-Command Register-HybridService -ErrorAction SilentlyContinue) {
        Register-HybridService -Name 'Directory' -Instance $directoryService -Description 'Mock directory service for offline development.' -Provider 'Mock' -Force | Out-Null
    }

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        Write-HybridLog -Level Information -Module 'Infrastructure.Mock' -Message 'Mock provider initialized.' | Out-Null
    }

    return $directoryService
}

function Search-HybridMockUser {
    <#.SYNOPSIS Searches mock users.#>
    [CmdletBinding()] param([string]$Query='')
    if ([string]::IsNullOrWhiteSpace($Query)) { return @($script:State.Users) }
    return @($script:State.Users | Where-Object {
        $_.DisplayName -like "*$Query*" -or $_.SamAccountName -like "*$Query*" -or $_.UserPrincipalName -like "*$Query*"
    })
}

function Get-HybridMockUser {
    <#.SYNOPSIS Gets one mock user by identity.#>
    [CmdletBinding()] param([Parameter(Mandatory=$true)][string]$Identity)
    return ($script:State.Users | Where-Object { $_.SamAccountName -eq $Identity -or $_.UserPrincipalName -eq $Identity -or $_.Mail -eq $Identity } | Select-Object -First 1)
}
#endregion

#region Initialization
Export-ModuleMember -Function Initialize-HybridMockProvider, Search-HybridMockUser, Get-HybridMockUser
#endregion
