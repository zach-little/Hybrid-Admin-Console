#region Module Information
# Name: Core.Cache
# Purpose: Lightweight in-memory cache with expiration.
# Dependencies: None
# Exports: Initialize-HybridCache, Set-HybridCacheItem, Get-HybridCacheItem, Remove-HybridCacheItem, Clear-HybridCache
#endregion

Set-StrictMode -Version Latest
$script:State = @{ Cache = @{} }

#region Private
function New-HybridCacheRecord {
    param([object]$Value,[datetime]$ExpiresUtc)
    [pscustomobject]@{ PSTypeName='Hybrid.CacheRecord'; Value=$Value; ExpiresUtc=$ExpiresUtc; CreatedUtc=[datetime]::UtcNow }
}
#endregion

#region Public
function Initialize-HybridCache {
    <#.SYNOPSIS Initializes cache storage.#>
    [CmdletBinding()] param([Parameter(Mandatory=$true)][object]$Context)
    $script:State.Cache = @{}
    $Context.Cache = $script:State.Cache
    return $Context.Cache
}
function Set-HybridCacheItem {
    <#.SYNOPSIS Sets a cache item.#>
    [CmdletBinding()] param([Parameter(Mandatory=$true)][string]$Key,[Parameter(Mandatory=$true)][object]$Value,[int]$TtlSeconds=300)
    $script:State.Cache[$Key] = New-HybridCacheRecord -Value $Value -ExpiresUtc ([datetime]::UtcNow.AddSeconds($TtlSeconds))
    return $Value
}
function Get-HybridCacheItem {
    <#.SYNOPSIS Gets a cache item if present and not expired.#>
    [CmdletBinding()] param([Parameter(Mandatory=$true)][string]$Key)
    if (-not $script:State.Cache.ContainsKey($Key)) { return $null }
    $record = $script:State.Cache[$Key]
    if ($record.ExpiresUtc -lt [datetime]::UtcNow) { $script:State.Cache.Remove($Key); return $null }
    return $record.Value
}
function Remove-HybridCacheItem {
    <#.SYNOPSIS Removes a cache item.#>
    [CmdletBinding()] param([Parameter(Mandatory=$true)][string]$Key)
    if ($script:State.Cache.ContainsKey($Key)) { $script:State.Cache.Remove($Key); return $true }
    return $false
}
function Clear-HybridCache {
    <#.SYNOPSIS Clears all cache items.#>
    [CmdletBinding()] param()
    $script:State.Cache.Clear()
}
#endregion

#region Initialization
Export-ModuleMember -Function Initialize-HybridCache, Set-HybridCacheItem, Get-HybridCacheItem, Remove-HybridCacheItem, Clear-HybridCache
#endregion
