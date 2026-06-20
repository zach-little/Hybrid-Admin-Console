#region Module Information
# Name: Core.ServiceRegistry
# Purpose: Runtime registry for services, providers, and shared framework components.
# Dependencies: Core.Logging recommended.
# Exports: Initialize-HybridServiceRegistry, Register-HybridService, Get-HybridService, Get-HybridServices, Test-HybridService, Remove-HybridService
#endregion

Set-StrictMode -Version Latest

$script:State = @{
    Services = @{}
}

#region Private
function New-HybridServiceRecord {
    param(
        [string]$Name,
        [object]$Instance,
        [string]$Description,
        [string]$Provider
    )

    [pscustomobject]@{
        PSTypeName    = 'Hybrid.ServiceRecord'
        Name          = $Name
        Instance      = $Instance
        Description   = $Description
        Provider      = $Provider
        RegisteredUtc = [datetime]::UtcNow
    }
}
#endregion

#region Public
function Initialize-HybridServiceRegistry {
    <#
    .SYNOPSIS
    Initializes an empty service registry on the host context.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Context
    )

    $script:State.Services = @{}
    $Context.Services = $script:State.Services

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        Write-HybridLog -Level Information -Module 'Core.ServiceRegistry' -Message 'Service registry initialized.' | Out-Null
    }

    return $Context.Services
}

function Register-HybridService {
    <#
    .SYNOPSIS
    Registers a named service instance.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory=$true)]
        [object]$Instance,

        [string]$Description = '',

        [string]$Provider = 'Core',

        [switch]$Force
    )

    if ($script:State.Services.ContainsKey($Name) -and -not $Force) {
        throw "Service '$Name' is already registered. Use -Force to replace it."
    }

    $record = New-HybridServiceRecord -Name $Name -Instance $Instance -Description $Description -Provider $Provider
    $script:State.Services[$Name] = $record

    if (Get-Command Write-HybridLog -ErrorAction SilentlyContinue) {
        Write-HybridLog -Level Debug -Module 'Core.ServiceRegistry' -Message "Registered service '$Name' from provider '$Provider'." | Out-Null
    }

    return $record
}

function Get-HybridService {
    <#
    .SYNOPSIS
    Returns a registered service instance by name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [switch]$Record
    )

    if (-not $script:State.Services.ContainsKey($Name)) {
        throw "Service '$Name' is not registered."
    }

    if ($Record) { return $script:State.Services[$Name] }
    return $script:State.Services[$Name].Instance
}

function Get-HybridServices {
    <#
    .SYNOPSIS
    Lists registered services.
    #>
    [CmdletBinding()]
    param()

    return @($script:State.Services.Values | Sort-Object Name)
}

function Test-HybridService {
    <#
    .SYNOPSIS
    Checks whether a service is registered.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Name)

    return $script:State.Services.ContainsKey($Name)
}

function Remove-HybridService {
    <#
    .SYNOPSIS
    Removes a registered service.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Name)

    if ($script:State.Services.ContainsKey($Name)) {
        $script:State.Services.Remove($Name)
        return $true
    }
    return $false
}
#endregion

#region Initialization
Export-ModuleMember -Function Initialize-HybridServiceRegistry, Register-HybridService, Get-HybridService, Get-HybridServices, Test-HybridService, Remove-HybridService
#endregion
