Set-StrictMode -Version Latest

$script:HapProviderSdkVersion = '1.0.0'

function New-HapProviderResult {
    [CmdletBinding()]
    param(
        [switch]$Succeeded,
        [AllowNull()][object]$Data = $null,
        [object[]]$Warnings = @(),
        [object[]]$Errors = @()
    )

    [pscustomobject]@{
        succeeded = [bool]$Succeeded
        data = $Data
        warnings = @($Warnings)
        errors = @($Errors)
    }
}

function New-HapProviderError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Target = '',
        [string]$DiagnosticDetail = ''
    )

    [pscustomobject]@{
        code = $Code
        message = $Message
        target = $Target
        diagnosticDetail = $DiagnosticDetail
    }
}

function New-HapProviderWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Target = ''
    )

    [pscustomobject]@{
        code = $Code
        message = $Message
        target = $Target
    }
}

Export-ModuleMember -Function New-HapProviderResult, New-HapProviderError, New-HapProviderWarning
