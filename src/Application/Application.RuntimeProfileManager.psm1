Set-StrictMode -Version Latest

$script:HybridRuntimeProfileManagerVersion = 'v0.12.0'

function Add-HybridRuntimeProfileManagerTypeMetadata {
    param([Parameter(Mandatory)][object]$InputObject,[Parameter(Mandatory)][string]$TypeName)
    if ($InputObject.PSObject.TypeNames[0] -ne $TypeName) { $InputObject.PSObject.TypeNames.Insert(0,$TypeName) }
    if (-not $InputObject.PSObject.Properties.Match('PSTypeName').Count) { $InputObject | Add-Member -MemberType NoteProperty -Name PSTypeName -Value $TypeName -Force }
    if (-not $InputObject.PSObject.Properties.Match('TypeName').Count) { $InputObject | Add-Member -MemberType NoteProperty -Name TypeName -Value $TypeName -Force }
    return $InputObject
}

function Resolve-HybridRuntimeProfileManagerRoot {
    [CmdletBinding()]
    param([string]$RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { return (Get-Location).Path }
    return (Resolve-Path -LiteralPath $RepositoryRoot).Path
}

function Get-HybridRuntimeProfilesRoot {
    [CmdletBinding()]
    param([string]$RepositoryRoot)
    $root = Resolve-HybridRuntimeProfileManagerRoot -RepositoryRoot $RepositoryRoot
    return (Join-Path $root 'profiles')
}

function Get-HybridRuntimeActiveProfilePath {
    [CmdletBinding()]
    param([string]$RepositoryRoot)
    return (Join-Path (Get-HybridRuntimeProfilesRoot -RepositoryRoot $RepositoryRoot) 'active.json')
}

function Read-HybridRuntimeProfileManagerState {
    [CmdletBinding()]
    param([string]$RepositoryRoot)
    $activePath = Get-HybridRuntimeActiveProfilePath -RepositoryRoot $RepositoryRoot
    if (-not (Test-Path -LiteralPath $activePath -PathType Leaf)) {
        return [pscustomobject]@{ LastUsedProfile=''; LastUsedPath=''; UpdatedAtUtc=$null; ActiveProfile='' }
    }
    try {
        $state = Get-Content -LiteralPath $activePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $active = if ($state.PSObject.Properties.Name -contains 'ActiveProfile') { [string]$state.ActiveProfile } elseif ($state.PSObject.Properties.Name -contains 'LastUsedProfile') { [string]$state.LastUsedProfile } else { '' }
        return [pscustomobject]@{ LastUsedProfile=$active; LastUsedPath=''; UpdatedAtUtc=$state.UpdatedAtUtc; ActiveProfile=$active }
    }
    catch { return [pscustomobject]@{ LastUsedProfile=''; LastUsedPath=''; UpdatedAtUtc=$null; ActiveProfile='' } }
}

function Get-HybridRuntimeProfileJsonProperty {
    param([AllowNull()][object]$InputObject,[Parameter(Mandatory)][string[]]$Names,[AllowNull()][object]$Default=$null)
    if ($null -eq $InputObject) { return $Default }
    foreach ($name in $Names) {
        $property = $InputObject.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) { return $property.Value }
    }
    return $Default
}

function Get-HybridRuntimeProfileCandidateFiles {
    [CmdletBinding()]
    param([string]$RepositoryRoot)
    $profilesRoot = Get-HybridRuntimeProfilesRoot -RepositoryRoot $RepositoryRoot
    $files = New-Object System.Collections.Generic.List[object]
    if (Test-Path -LiteralPath $profilesRoot -PathType Container) {
        $excluded = @('Runtime','Runtime-Deprecated','Mock','Mock-Deprecated')
        foreach ($folder in @(Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $excluded -notcontains $_.Name -and -not $_.Name.EndsWith('.disabled') })) {
            $runtimePath = Join-Path $folder.FullName 'runtime.json'
            if (Test-Path -LiteralPath $runtimePath -PathType Leaf) { [void]$files.Add((Get-Item -LiteralPath $runtimePath)) }
        }
    }
    return @($files.ToArray() | Sort-Object FullName -Unique)
}

function Get-HybridRuntimeProfileSummary {
    [CmdletBinding()]
    param([string]$RepositoryRoot)
    $root = Resolve-HybridRuntimeProfileManagerRoot -RepositoryRoot $RepositoryRoot
    $state = Read-HybridRuntimeProfileManagerState -RepositoryRoot $root
    $files = @(Get-HybridRuntimeProfileCandidateFiles -RepositoryRoot $root | Sort-Object FullName)
    $summaries = foreach ($file in $files) {
        $status = 'Valid'; $errorMessage = ''; $content = $null
        $name = $file.Directory.Name; $mode=''; $cloud=''; $organization=$file.Directory.Name; $environment=''; $enabledProviders=@(); $providerModes=@(); $isDefault=$false; $warnings=@()
        try {
            $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $name = [string](Get-HybridRuntimeProfileJsonProperty -InputObject $content -Names @('ProfileName','Name') -Default $name)
            $mode = [string](Get-HybridRuntimeProfileJsonProperty -InputObject $content -Names @('RuntimeMode','Mode') -Default '')
            $cloud = [string](Get-HybridRuntimeProfileJsonProperty -InputObject $content -Names @('CloudEnvironment','Cloud') -Default '')
            $organization = [string](Get-HybridRuntimeProfileJsonProperty -InputObject $content -Names @('Organization') -Default $organization)
            $environment = [string](Get-HybridRuntimeProfileJsonProperty -InputObject $content -Names @('Environment') -Default '')
            $defaultValue = Get-HybridRuntimeProfileJsonProperty -InputObject $content -Names @('IsDefault','Default','DefaultProfile') -Default $false
            if ($defaultValue -is [bool]) { $isDefault = [bool]$defaultValue } elseif (-not [string]::IsNullOrWhiteSpace([string]$defaultValue)) { $isDefault = ([string]$defaultValue) -match '^(true|1|yes)$' }
            $providersProperty = $content.PSObject.Properties['Providers']
            if ($null -ne $providersProperty -and $null -ne $providersProperty.Value) {
                foreach ($provider in $providersProperty.Value.PSObject.Properties) {
                    $providerName = [string]$provider.Name; $providerEnabled = $false; $providerMode=''
                    if ($provider.Value.PSObject.Properties.Name -contains 'Enabled') { $providerEnabled = [bool]$provider.Value.Enabled }
                    if ($provider.Value.PSObject.Properties.Name -contains 'Mode') { $providerMode = [string]$provider.Value.Mode }
                    if ($providerEnabled) { $enabledProviders += $providerName }
                    if (-not [string]::IsNullOrWhiteSpace($providerMode)) { $providerModes += ('{0}:{1}' -f $providerName,$providerMode) }
                }
            }
            if (-not (Test-Path -LiteralPath (Join-Path $file.Directory.FullName 'config.json') -PathType Leaf)) { $warnings += 'config.json missing' }
            if (-not (Test-Path -LiteralPath (Join-Path $file.Directory.FullName 'branding.json') -PathType Leaf)) { $warnings += 'branding.json missing' }
        }
        catch { $status='Invalid'; $errorMessage=$_.Exception.Message }
        $isLastUsed = (-not [string]::IsNullOrWhiteSpace($state.ActiveProfile) -and ([string]::Equals($state.ActiveProfile,$file.Directory.Name,[System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($state.ActiveProfile,$name,[System.StringComparison]::OrdinalIgnoreCase)))
        $summary = [pscustomobject]@{
            TypeName='Hybrid.RuntimeProfileSummary'; Version=$script:HybridRuntimeProfileManagerVersion; Name=$name; ProfileName=$name; FolderName=$file.Directory.Name; FileName='runtime.json'; Path=$file.FullName; ProfileRoot=$file.Directory.FullName; ProfileLayout='OrganizationFolder'; RuntimeMode=$mode; Mode=$mode; CloudEnvironment=$cloud; Cloud=$cloud; Organization=$organization; Environment=$environment; Status=$status; IsValid=($status -eq 'Valid'); IsDefault=$isDefault; IsLastUsed=$isLastUsed; EnabledProviders=@($enabledProviders); EnabledProviderCount=@($enabledProviders).Count; ProviderModes=@($providerModes); WarningCount=@($warnings).Count; Warnings=@($warnings); ErrorMessage=$errorMessage; HealthLabel=if($status -eq 'Valid'){'Ready'}else{'Invalid'}; BadgeText=if($isDefault){'Default'}elseif($isLastUsed){'Active'}else{''}; SortWeight=if($isLastUsed){0}elseif($isDefault){1}else{2}; LastWriteTimeUtc=$file.LastWriteTimeUtc
        }
        Add-HybridRuntimeProfileManagerTypeMetadata -InputObject $summary -TypeName 'Hybrid.RuntimeProfileSummary'
    }
    return @($summaries | Sort-Object SortWeight, ProfileName, FolderName)
}

function Get-HybridRuntimeProfileSelection {
    [CmdletBinding()]
    param([string]$RepositoryRoot)
    $profiles = @(Get-HybridRuntimeProfileSummary -RepositoryRoot $RepositoryRoot)
    if ($profiles.Count -eq 0) { return $null }
    $active = @($profiles | Where-Object { $_.IsLastUsed -and $_.IsValid } | Select-Object -First 1); if ($active.Count -gt 0) { return $active[0] }
    $default = @($profiles | Where-Object { $_.IsDefault -and $_.IsValid } | Select-Object -First 1); if ($default.Count -gt 0) { return $default[0] }
    $simulation = @($profiles | Where-Object { $_.IsValid -and ($_.FolderName -eq 'Simulation' -or $_.ProfileName -eq 'Simulation') } | Select-Object -First 1); if ($simulation.Count -gt 0) { return $simulation[0] }
    $valid = @($profiles | Where-Object { $_.IsValid } | Select-Object -First 1); if ($valid.Count -gt 0) { return $valid[0] }
    return $profiles[0]
}

function Set-HybridRuntimeProfileSelection {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$RepositoryRoot,[string]$ProfileName,[string]$ProfilePath)
    $root = Resolve-HybridRuntimeProfileManagerRoot -RepositoryRoot $RepositoryRoot
    $profiles = @(Get-HybridRuntimeProfileSummary -RepositoryRoot $root)
    if ($profiles.Count -eq 0) { throw 'No runtime profiles are available under profiles\<ProfileName>\runtime.json.' }
    $selected = $null
    if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) { $selected = @($profiles | Where-Object { [string]::Equals($_.Path,$ProfilePath,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1) }
    elseif (-not [string]::IsNullOrWhiteSpace($ProfileName)) { $selected = @($profiles | Where-Object { [string]::Equals($_.ProfileName,$ProfileName,[System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($_.Name,$ProfileName,[System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($_.FolderName,$ProfileName,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1) }
    if ($null -eq $selected -or @($selected).Count -eq 0) { throw "Requested runtime profile '$ProfileName' was not found under profiles\<ProfileName>\runtime.json." }
    $selected = @($selected)[0]
    $activePath = Get-HybridRuntimeActiveProfilePath -RepositoryRoot $root
    $activeDir = Split-Path -Path $activePath -Parent
    if (-not (Test-Path -LiteralPath $activeDir -PathType Container)) { New-Item -Path $activeDir -ItemType Directory -Force | Out-Null }
    $state = [ordered]@{ ActiveProfile=$selected.FolderName; UpdatedAtUtc=[DateTimeOffset]::UtcNow.ToString('o') }
    if ($PSCmdlet.ShouldProcess($selected.ProfileName,'Set active profile')) { ($state | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $activePath -Encoding UTF8 }
    $selected.IsLastUsed = $true
    return $selected
}

function Update-HybridRuntimeProfileManager {
    [CmdletBinding()]
    param([string]$RepositoryRoot)
    $profiles = @(Get-HybridRuntimeProfileSummary -RepositoryRoot $RepositoryRoot)
    $selection = Get-HybridRuntimeProfileSelection -RepositoryRoot $RepositoryRoot
    $result = [pscustomobject]@{ TypeName='Hybrid.RuntimeProfileManagerState'; Version=$script:HybridRuntimeProfileManagerVersion; Profiles=@($profiles); SelectedProfile=$selection; ProfileCount=$profiles.Count; RefreshedAtUtc=[DateTimeOffset]::UtcNow }
    return (Add-HybridRuntimeProfileManagerTypeMetadata -InputObject $result -TypeName 'Hybrid.RuntimeProfileManagerState')
}

function Copy-HybridRuntimeProfile {
    [CmdletBinding()]
    param([string]$RepositoryRoot,[Parameter(Mandatory)][string]$ProfilePath,[string]$NewProfileName)
    $root = Resolve-HybridRuntimeProfileManagerRoot -RepositoryRoot $RepositoryRoot
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) { throw "Runtime profile not found: $ProfilePath" }
    if ([string]::IsNullOrWhiteSpace($NewProfileName)) { $NewProfileName = ((Split-Path -Path (Split-Path -Path $ProfilePath -Parent) -Leaf) + '-Copy') }
    $safeName = ($NewProfileName -replace '[^a-zA-Z0-9._-]','-')
    $targetRoot = Join-Path (Get-HybridRuntimeProfilesRoot -RepositoryRoot $root) $safeName
    $i=2; while (Test-Path -LiteralPath $targetRoot) { $targetRoot = Join-Path (Get-HybridRuntimeProfilesRoot -RepositoryRoot $root) ("{0}-{1}" -f $safeName,$i); $i++ }
    Copy-Item -LiteralPath (Split-Path -Path $ProfilePath -Parent) -Destination $targetRoot -Recurse -Force
    $target = Join-Path $targetRoot 'runtime.json'
    try { $json = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json; if ($json.PSObject.Properties.Name -contains 'ProfileName') { $json.ProfileName = $safeName }; if ($json.PSObject.Properties.Name -contains 'Organization') { $json.Organization = $safeName }; $json | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $target -Encoding UTF8 } catch { }
    return Get-HybridRuntimeProfileSummary -RepositoryRoot $root | Where-Object { [string]::Equals($_.Path,$target,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
}

function Remove-HybridRuntimeProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$RepositoryRoot,[Parameter(Mandatory)][string]$ProfilePath)
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) { return $false }
    $folder = Split-Path -Path $ProfilePath -Parent
    if ($PSCmdlet.ShouldProcess($folder,'Delete profile folder')) { Remove-Item -LiteralPath $folder -Recurse -Force }
    return $true
}

function Set-HybridRuntimeProfileDefault {
    [CmdletBinding()]
    param([string]$RepositoryRoot,[Parameter(Mandatory)][string]$ProfilePath)
    $root = Resolve-HybridRuntimeProfileManagerRoot -RepositoryRoot $RepositoryRoot
    foreach ($summary in @(Get-HybridRuntimeProfileSummary -RepositoryRoot $root)) {
        try { $json = Get-Content -LiteralPath $summary.Path -Raw | ConvertFrom-Json; if ($json.PSObject.Properties.Name -contains 'IsDefault') { $json.IsDefault = $false } else { $json | Add-Member -NotePropertyName IsDefault -NotePropertyValue $false -Force }; if ([string]::Equals($summary.Path,$ProfilePath,[System.StringComparison]::OrdinalIgnoreCase)) { $json.IsDefault = $true }; $json | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summary.Path -Encoding UTF8 } catch { }
    }
    return Get-HybridRuntimeProfileSelection -RepositoryRoot $root
}

function Export-HybridRuntimeProfile {
    [CmdletBinding()]
    param([string]$RepositoryRoot,[Parameter(Mandatory)][string]$ProfilePath,[string]$DestinationFolder)
    $root = Resolve-HybridRuntimeProfileManagerRoot -RepositoryRoot $RepositoryRoot
    if ([string]::IsNullOrWhiteSpace($DestinationFolder)) { $DestinationFolder = Join-Path $root 'build\RuntimeProfiles' }
    if (-not (Test-Path -LiteralPath $DestinationFolder -PathType Container)) { New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null }
    $sourceFolder = Split-Path -Path $ProfilePath -Parent
    $target = Join-Path $DestinationFolder (Split-Path -Path $sourceFolder -Leaf)
    Copy-Item -LiteralPath $sourceFolder -Destination $target -Recurse -Force
    return $target
}

Export-ModuleMember -Function @('Get-HybridRuntimeProfileSummary','Get-HybridRuntimeProfileSelection','Set-HybridRuntimeProfileSelection','Update-HybridRuntimeProfileManager','Copy-HybridRuntimeProfile','Remove-HybridRuntimeProfile','Set-HybridRuntimeProfileDefault','Export-HybridRuntimeProfile')
