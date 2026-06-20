#region Module Information
# Name: Core.Security
# Purpose: Security helper functions for safe defaults and local secret boundaries.
# Dependencies: None
# Exports: Protect-HybridString, Unprotect-HybridString, Test-HybridSecretPlaceholder
#endregion

Set-StrictMode -Version Latest

#region Private
#endregion

#region Public
function Protect-HybridString {
    <#.SYNOPSIS Protects a string using Windows DPAPI when available.#>
    [CmdletBinding()] param([Parameter(Mandatory=$true)][string]$Value)
    $secure = ConvertTo-SecureString -String $Value -AsPlainText -Force
    return ConvertFrom-SecureString -SecureString $secure
}
function Unprotect-HybridString {
    <#.SYNOPSIS Unprotects a DPAPI-protected string.#>
    [CmdletBinding()] param([Parameter(Mandatory=$true)][string]$ProtectedValue)
    $secure = ConvertTo-SecureString -String $ProtectedValue
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) } }
}
function Test-HybridSecretPlaceholder {
    <#.SYNOPSIS Tests whether a value appears to be a placeholder rather than a real secret.#>
    [CmdletBinding()] param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    return ($Value -match 'CHANGE_ME|PLACEHOLDER|EXAMPLE|REDACTED')
}
#endregion

#region Initialization
Export-ModuleMember -Function Protect-HybridString, Unprotect-HybridString, Test-HybridSecretPlaceholder
#endregion
