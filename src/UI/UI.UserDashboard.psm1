Set-StrictMode -Version Latest

function Format-HybridDashboardEmptyState {
    [CmdletBinding()]
    param([string]$Query = '')

    if ([string]::IsNullOrWhiteSpace($Query)) { return 'Search for a user to populate the dashboard cards.' }
    return "No user data returned for '$Query'."
}

Export-ModuleMember -Function @('Format-HybridDashboardEmptyState')
