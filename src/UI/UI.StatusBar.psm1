Set-StrictMode -Version Latest

function Set-HybridStatusTextSafe {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$TextBlock,
        [string]$Text = ''
    )

    if ($null -ne $TextBlock) { $TextBlock.Text = $Text }
}

Export-ModuleMember -Function @('Set-HybridStatusTextSafe')
