Set-StrictMode -Version Latest

$script:HybridRuntimeProfileManagerVersion = 'v0.8.1'

function Add-HybridRuntimeProfileManagerTypeMetadata {
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string]$TypeName
    )

    if ($InputObject.PSObject.TypeNames[0] -ne $TypeName) {
        $InputObject.PSObject.TypeNames.Insert(0, $TypeName)
    }

    if (-not $InputObject.PSObject.Properties.Match('PSTypeName').Count) {
        $InputObject | Add-Member -MemberType NoteProperty -Name PSTypeName -Value $TypeName -Force
    }

    if (-not $InputObject.PSObject.Properties.Match('TypeName').Count) {
        $InputObject | Add-Member -MemberType NoteProperty -Name TypeName -Value $TypeName -Force
    }

    return $InputObject
}

function Resolve-HybridRuntimeProfileManagerRoot {
    [CmdletBinding()]
    param([string]$RepositoryRoot)

    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return (Get-Location).Path
    }

    return (Resolve-Path -Path $RepositoryRoot).Path
}

function Get-HybridRuntimeProfileManagerFolder {
    [CmdletBinding()]
    param([string]$RepositoryRoot)

    $root = Resolve-HybridRuntimeProfileManagerRoot -RepositoryRoot $RepositoryRoot
    return (Join-Path $root 'profiles\Runtime')
}

function Get-HybridRuntimeProfileManagerStatePath {
    [CmdletBinding()]
    param([string]$RepositoryRoot)

    $root = Resolve-HybridRuntimeProfileManagerRoot -RepositoryRoot $RepositoryRoot
    return (Join-Path $root 'profiles\Runtime\.profile-manager-state')
}

function Read-HybridRuntimeProfileManagerState {
    [CmdletBinding()]
    param([string]$RepositoryRoot)

    $statePath = Get-HybridRuntimeProfileManagerStatePath -RepositoryRoot $RepositoryRoot
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return [pscustomobject]@{
            LastUsedProfile = ''
            LastUsedPath    = ''
            UpdatedAtUtc    = $null
        }
    }

    try {
        $state = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{
            LastUsedProfile = [string]($state.LastUsedProfile)
            LastUsedPath    = [string]($state.LastUsedPath)
            UpdatedAtUtc    = $state.UpdatedAtUtc
        }
    }
    catch {
        return [pscustomobject]@{
            LastUsedProfile = ''
            LastUsedPath    = ''
            UpdatedAtUtc    = $null
        }
    }
}

function Get-HybridRuntimeProfileJsonProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string[]]$Names,
        [AllowNull()][object]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }

    foreach ($name in $Names) {
        $property = $InputObject.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return $property.Value
        }
    }

    return $Default
}

function Get-HybridRuntimeProfileSummary {
    [CmdletBinding()]
    param([string]$RepositoryRoot)

    $root = Resolve-HybridRuntimeProfileManagerRoot -RepositoryRoot $RepositoryRoot
    $folder = Get-HybridRuntimeProfileManagerFolder -RepositoryRoot $root
    $state = Read-HybridRuntimeProfileManagerState -RepositoryRoot $root

    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        return @()
    }

    $files = Get-ChildItem -LiteralPath $folder -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name
    $summaries = foreach ($file in $files) {
        $content = $null
        $status = 'Valid'
        $errorMessage = ''
        $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $mode = ''
        $cloud = ''
        $organization = ''
        $environment = ''
        $enabledProviders = @()
        $providerModes = @()
        $isDefault = $false

        try {
            $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $name = [string](Get-HybridRuntimeProfileJsonProperty -InputObject $content -Names @('ProfileName','Name') -Default $name)
            $mode = [string](Get-HybridRuntimeProfileJsonProperty -InputObject $content -Names @('RuntimeMode','Mode') -Default '')
            $cloud = [string](Get-HybridRuntimeProfileJsonProperty -InputObject $content -Names @('CloudEnvironment','Cloud') -Default '')
            $organization = [string](Get-HybridRuntimeProfileJsonProperty -InputObject $content -Names @('Organization') -Default '')
            $environment = [string](Get-HybridRuntimeProfileJsonProperty -InputObject $content -Names @('Environment') -Default '')

            $defaultValue = Get-HybridRuntimeProfileJsonProperty -InputObject $content -Names @('IsDefault','Default','DefaultProfile') -Default $false
            if ($defaultValue -is [bool]) { $isDefault = [bool]$defaultValue }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$defaultValue)) { $isDefault = ([string]$defaultValue) -match '^(true|1|yes)$' }

            $providersProperty = $content.PSObject.Properties['Providers']
            if ($null -ne $providersProperty -and $null -ne $providersProperty.Value) {
                foreach ($provider in $providersProperty.Value.PSObject.Properties) {
                    $providerName = [string]$provider.Name
                    $providerEnabled = $false
                    $providerMode = ''
                    $enabledProperty = $provider.Value.PSObject.Properties['Enabled']
                    $modeProperty = $provider.Value.PSObject.Properties['Mode']
                    if ($null -ne $enabledProperty) { $providerEnabled = [bool]$enabledProperty.Value }
                    if ($null -ne $modeProperty -and $null -ne $modeProperty.Value) { $providerMode = [string]$modeProperty.Value }
                    if ($providerEnabled) { $enabledProviders += $providerName }
                    if (-not [string]::IsNullOrWhiteSpace($providerMode)) { $providerModes += ('{0}:{1}' -f $providerName, $providerMode) }
                }
            }
        }
        catch {
            $status = 'Invalid'
            $errorMessage = $_.Exception.Message
        }

        $isLastUsed = $false
        if (-not [string]::IsNullOrWhiteSpace($state.LastUsedPath)) {
            $isLastUsed = ([string]::Equals($state.LastUsedPath, $file.FullName, [System.StringComparison]::OrdinalIgnoreCase))
        }
        elseif (-not [string]::IsNullOrWhiteSpace($state.LastUsedProfile)) {
            $isLastUsed = ([string]::Equals($state.LastUsedProfile, $name, [System.StringComparison]::OrdinalIgnoreCase))
        }

        $summary = [pscustomobject]@{
            TypeName              = 'Hybrid.RuntimeProfileSummary'
            Version               = $script:HybridRuntimeProfileManagerVersion
            Name                  = $name
            ProfileName           = $name
            FileName              = $file.Name
            Path                  = $file.FullName
            RuntimeMode           = $mode
            Mode                  = $mode
            CloudEnvironment      = $cloud
            Cloud                 = $cloud
            Organization          = $organization
            Environment           = $environment
            Status                = $status
            IsValid               = ($status -eq 'Valid')
            IsDefault             = $isDefault
            IsLastUsed            = $isLastUsed
            EnabledProviders      = @($enabledProviders)
            EnabledProviderCount  = @($enabledProviders).Count
            ProviderModes         = @($providerModes)
            WarningCount          = 0
            ErrorMessage          = $errorMessage
            HealthLabel           = if ($status -eq 'Valid') { 'Ready' } else { 'Invalid' }
            BadgeText             = if ($isDefault) { 'Default' } elseif ($isLastUsed) { 'Last Used' } else { '' }
            SortWeight            = if ($isDefault) { 0 } elseif ($isLastUsed) { 1 } else { 2 }
            LastWriteTimeUtc      = $file.LastWriteTimeUtc
        }

        Add-HybridRuntimeProfileManagerTypeMetadata -InputObject $summary -TypeName 'Hybrid.RuntimeProfileSummary'
    }

    return @($summaries | Sort-Object SortWeight, ProfileName, FileName)
}

function Get-HybridRuntimeProfileSelection {
    [CmdletBinding()]
    param([string]$RepositoryRoot)

    $profiles = @(Get-HybridRuntimeProfileSummary -RepositoryRoot $RepositoryRoot)
    if ($profiles.Count -eq 0) { return $null }

    $lastUsed = @($profiles | Where-Object { $_.IsLastUsed -and $_.IsValid } | Select-Object -First 1)
    if ($lastUsed.Count -gt 0) { return $lastUsed[0] }

    $default = @($profiles | Where-Object { $_.IsDefault -and $_.IsValid } | Select-Object -First 1)
    if ($default.Count -gt 0) { return $default[0] }

    $simulation = @($profiles | Where-Object { $_.IsValid -and ($_.FileName -eq 'Simulation.json' -or $_.ProfileName -eq 'Simulation') } | Select-Object -First 1)
    if ($simulation.Count -gt 0) { return $simulation[0] }

    $valid = @($profiles | Where-Object { $_.IsValid } | Select-Object -First 1)
    if ($valid.Count -gt 0) { return $valid[0] }

    return $profiles[0]
}

function Set-HybridRuntimeProfileSelection {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RepositoryRoot,
        [string]$ProfileName,
        [string]$ProfilePath
    )

    $root = Resolve-HybridRuntimeProfileManagerRoot -RepositoryRoot $RepositoryRoot
    $profiles = @(Get-HybridRuntimeProfileSummary -RepositoryRoot $root)
    if ($profiles.Count -eq 0) { throw 'No runtime profiles are available.' }

    $selected = $null
    if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
        $selected = @($profiles | Where-Object { [string]::Equals($_.Path, $ProfilePath, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ProfileName)) {
        $selected = @($profiles | Where-Object { [string]::Equals($_.ProfileName, $ProfileName, [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($_.Name, $ProfileName, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    }

    if ($null -eq $selected -or @($selected).Count -eq 0) { throw 'Requested runtime profile was not found.' }
    $selected = @($selected)[0]

    $statePath = Get-HybridRuntimeProfileManagerStatePath -RepositoryRoot $root
    $stateDirectory = Split-Path -Path $statePath -Parent
    if (-not (Test-Path -LiteralPath $stateDirectory -PathType Container)) {
        New-Item -Path $stateDirectory -ItemType Directory -Force | Out-Null
    }

    $state = [ordered]@{
        LastUsedProfile = $selected.ProfileName
        LastUsedPath    = $selected.Path
        UpdatedAtUtc    = [DateTimeOffset]::UtcNow.ToString('o')
    }

    if ($PSCmdlet.ShouldProcess($selected.ProfileName, 'Set selected runtime profile')) {
        ($state | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $statePath -Encoding UTF8
    }

    $selected.IsLastUsed = $true
    return $selected
}

function Update-HybridRuntimeProfileManager {
    [CmdletBinding()]
    param([string]$RepositoryRoot)

    $profiles = @(Get-HybridRuntimeProfileSummary -RepositoryRoot $RepositoryRoot)
    $selection = Get-HybridRuntimeProfileSelection -RepositoryRoot $RepositoryRoot

    $result = [pscustomobject]@{
        TypeName        = 'Hybrid.RuntimeProfileManagerState'
        Version         = $script:HybridRuntimeProfileManagerVersion
        Profiles        = @($profiles)
        SelectedProfile = $selection
        ProfileCount    = $profiles.Count
        RefreshedAtUtc  = [DateTimeOffset]::UtcNow
    }

    return (Add-HybridRuntimeProfileManagerTypeMetadata -InputObject $result -TypeName 'Hybrid.RuntimeProfileManagerState')
}


function Copy-HybridRuntimeProfile {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ProfilePath,
        [string]$NewProfileName
    )
    $root = Resolve-HybridRuntimeProfileManagerRoot -RepositoryRoot $RepositoryRoot
    $folder = Get-HybridRuntimeProfileManagerFolder -RepositoryRoot $root
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) { throw "Runtime profile not found: $ProfilePath" }
    if ([string]::IsNullOrWhiteSpace($NewProfileName)) { $NewProfileName = ([IO.Path]::GetFileNameWithoutExtension($ProfilePath) + '-Copy') }
    $safeName = ($NewProfileName -replace '[^a-zA-Z0-9._-]', '-')
    $target = Join-Path $folder ("$safeName.json")
    $i = 2
    while (Test-Path -LiteralPath $target) { $target = Join-Path $folder ("{0}-{1}.json" -f $safeName,$i); $i++ }
    Copy-Item -LiteralPath $ProfilePath -Destination $target -Force
    try {
        $json = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
        if ($json.PSObject.Properties.Name -contains 'ProfileName') { $json.ProfileName = [IO.Path]::GetFileNameWithoutExtension($target) }
        elseif ($json.PSObject.Properties.Name -contains 'Name') { $json.Name = [IO.Path]::GetFileNameWithoutExtension($target) }
        $json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $target -Encoding UTF8
    } catch { }
    return Get-HybridRuntimeProfileSummary -RepositoryRoot $root | Where-Object { [string]::Equals($_.Path,$target,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
}

function Remove-HybridRuntimeProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$RepositoryRoot,[Parameter(Mandatory)][string]$ProfilePath)
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) { return $false }
    if ($PSCmdlet.ShouldProcess($ProfilePath,'Delete runtime profile')) { Remove-Item -LiteralPath $ProfilePath -Force }
    return $true
}

function Set-HybridRuntimeProfileDefault {
    [CmdletBinding()]
    param([string]$RepositoryRoot,[Parameter(Mandatory)][string]$ProfilePath)
    $root = Resolve-HybridRuntimeProfileManagerRoot -RepositoryRoot $RepositoryRoot
    $folder = Get-HybridRuntimeProfileManagerFolder -RepositoryRoot $root
    Get-ChildItem -LiteralPath $folder -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $json = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            if ($json.PSObject.Properties.Name -contains 'IsDefault') { $json.IsDefault = $false } else { $json | Add-Member -NotePropertyName IsDefault -NotePropertyValue $false -Force }
            if ([string]::Equals($_.FullName,$ProfilePath,[System.StringComparison]::OrdinalIgnoreCase)) { $json.IsDefault = $true }
            $json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $_.FullName -Encoding UTF8
        } catch { }
    }
    return Get-HybridRuntimeProfileSelection -RepositoryRoot $root
}

function Export-HybridRuntimeProfile {
    [CmdletBinding()]
    param([string]$RepositoryRoot,[Parameter(Mandatory)][string]$ProfilePath,[string]$DestinationFolder)
    $root = Resolve-HybridRuntimeProfileManagerRoot -RepositoryRoot $RepositoryRoot
    if ([string]::IsNullOrWhiteSpace($DestinationFolder)) { $DestinationFolder = Join-Path $root 'build\RuntimeProfiles' }
    if (-not (Test-Path -LiteralPath $DestinationFolder -PathType Container)) { New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null }
    $target = Join-Path $DestinationFolder ([IO.Path]::GetFileName($ProfilePath))
    Copy-Item -LiteralPath $ProfilePath -Destination $target -Force
    return $target
}

Export-ModuleMember -Function @(
    'Get-HybridRuntimeProfileSummary',
    'Get-HybridRuntimeProfileSelection',
    'Set-HybridRuntimeProfileSelection',
    'Update-HybridRuntimeProfileManager',
    'Copy-HybridRuntimeProfile',
    'Remove-HybridRuntimeProfile',
    'Set-HybridRuntimeProfileDefault',
    'Export-HybridRuntimeProfile'
)
