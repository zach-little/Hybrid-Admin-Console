Set-StrictMode -Version Latest

function Get-HybridRuntimeProfileAuthLabel {
    [CmdletBinding()]
    param([AllowNull()][object]$Profile)

    if ($null -eq $Profile) { return '-' }
    if ([string]$Profile.RuntimeMode -eq 'Simulation') { return 'None' }
    return 'Delegated/App-only on launch'
}

function Format-HybridRuntimeStatusLine {
    [CmdletBinding()]
    param([AllowNull()][object]$Profile)

    if ($null -eq $Profile) { return 'No runtime profile selected' }
    $auth = Get-HybridRuntimeProfileAuthLabel -Profile $Profile
    return ('Profile: {0}   Cloud: {1}   Mode: {2}   Auth: {3}   Health: {4}' -f $Profile.ProfileName, $Profile.CloudEnvironment, $Profile.RuntimeMode, $auth, $Profile.HealthLabel)
}

Export-ModuleMember -Function @('Get-HybridRuntimeProfileAuthLabel','Format-HybridRuntimeStatusLine')
