Set-StrictMode -Version Latest

$script:HybridDeploymentVersion = 'v0.8.0-dev'

function Add-HybridDeploymentTypeMetadata {
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

function New-HybridDefaultSimulationRuntimeProfileJson {
    [CmdletBinding()]
    param()

    $profile = [ordered]@{
        ProfileName  = 'Simulation'
        Mode         = 'Simulation'
        Cloud        = 'Commercial'
        Environment  = 'Development'
        Organization = 'Demo'
        TenantId     = ''
        Providers    = [ordered]@{
            DirectorySimulator = [ordered]@{
                Enabled        = $true
                Mode           = 'Simulation'
                Required       = $true
                Authentication = 'None'
                Notes          = 'Deterministic enterprise simulator used for tests and local demos.'
            }
            ActiveDirectory = [ordered]@{
                Enabled        = $false
                Mode           = 'Disabled'
                Required       = $false
                Authentication = 'Integrated'
            }
            MicrosoftGraph = [ordered]@{
                Enabled        = $false
                Mode           = 'Disabled'
                Required       = $false
                Authentication = 'Interactive'
            }
            ExchangeOnline = [ordered]@{
                Enabled        = $false
                Mode           = 'Disabled'
                Required       = $false
                Authentication = 'Interactive'
            }
        }
    }

    return ($profile | ConvertTo-Json -Depth 10)
}

function Ensure-HybridDefaultSimulationRuntimeProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][object]$Layout,
        [Parameter()][AllowEmptyCollection()][System.Collections.Generic.List[string]]$CreatedDirectories
    )

    if ($null -eq $CreatedDirectories) {
        $CreatedDirectories = New-Object System.Collections.Generic.List[string]
    }

    if (-not (Test-Path -LiteralPath $Layout.RuntimeProfiles -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($Layout.RuntimeProfiles, 'Create runtime profile directory')) {
            New-Item -Path $Layout.RuntimeProfiles -ItemType Directory -Force | Out-Null
            $CreatedDirectories.Add($Layout.RuntimeProfiles) | Out-Null
        }
    }

    $simulationProfile = Join-Path $Layout.RuntimeProfiles 'Simulation.json'
    if (-not (Test-Path -LiteralPath $simulationProfile -PathType Leaf)) {
        if ($PSCmdlet.ShouldProcess($simulationProfile, 'Create default simulation runtime profile')) {
            New-HybridDefaultSimulationRuntimeProfileJson | Set-Content -LiteralPath $simulationProfile -Encoding UTF8
            $CreatedDirectories.Add($simulationProfile) | Out-Null
        }
    }
}


function New-HybridDeploymentResult {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][bool]$IsReady,
        [Parameter(Mandatory)][object[]]$Checks,
        [object[]]$Profiles = @(),
        [string[]]$CreatedDirectories = @(),
        [string]$PackagePath = $null
    )

    $errors = @($Checks | Where-Object { -not $_.Passed -and $_.Severity -eq 'Error' })
    $warnings = @($Checks | Where-Object { -not $_.Passed -and $_.Severity -eq 'Warning' })

    $result = [pscustomobject]@{
        TypeName            = 'Hybrid.DeploymentResult'
        Version             = $script:HybridDeploymentVersion
        RepositoryRoot      = $RepositoryRoot
        IsReady             = $IsReady
        Status              = $(if ($errors.Count -gt 0) { 'Error' } elseif ($warnings.Count -gt 0) { 'Warning' } else { 'Ready' })
        Checks              = @($Checks)
        ErrorCount          = $errors.Count
        WarningCount        = $warnings.Count
        Profiles            = @($Profiles)
        CreatedDirectories  = @($CreatedDirectories)
        PackagePath         = $PackagePath
        GeneratedAt         = [DateTimeOffset]::UtcNow
    }

    return (Add-HybridDeploymentTypeMetadata -InputObject $result -TypeName 'Hybrid.DeploymentResult')
}

function New-HybridDeploymentCheck {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Severity,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Message,
        [string]$Path = $null
    )

    $check = [pscustomobject]@{
        TypeName   = 'Hybrid.DeploymentCheck'
        Name       = $Name
        Category   = $Category
        Severity   = $Severity
        Passed     = $Passed
        Message    = $Message
        Path       = $Path
    }

    return (Add-HybridDeploymentTypeMetadata -InputObject $check -TypeName 'Hybrid.DeploymentCheck')
}

function Resolve-HybridRepositoryRoot {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot
    )

    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return (Get-Location).Path
    }

    return (Resolve-Path -Path $RepositoryRoot).Path
}

function Get-HybridDeploymentLayout {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot
    )

    $root = Resolve-HybridRepositoryRoot -RepositoryRoot $RepositoryRoot

    $layout = [pscustomobject]@{
        TypeName        = 'Hybrid.DeploymentLayout'
        Version         = $script:HybridDeploymentVersion
        RepositoryRoot  = $root
        Source          = Join-Path $root 'src'
        Core            = Join-Path $root 'src/Core'
        Application     = Join-Path $root 'src/Application'
        Infrastructure  = Join-Path $root 'src/Infrastructure'
        UI              = Join-Path $root 'src/UI'
        Profiles        = Join-Path $root 'profiles'
        RuntimeProfiles = Join-Path $root 'profiles/Runtime'
        Logs            = Join-Path $root 'logs'
        Build           = Join-Path $root 'build'
        Docs            = Join-Path $root 'docs'
        Tests           = Join-Path $root 'tests'
        Tools           = Join-Path $root 'tools'
        EntryPoint      = Join-Path $root 'src/UI/Start-HybridAdminConsole.ps1'
    }

    return (Add-HybridDeploymentTypeMetadata -InputObject $layout -TypeName 'Hybrid.DeploymentLayout')
}

function Get-HybridDeploymentRuntimeProfile {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot
    )

    $layout = Get-HybridDeploymentLayout -RepositoryRoot $RepositoryRoot

    if (-not (Test-Path -LiteralPath $layout.RuntimeProfiles -PathType Container)) {
        return @()
    }

    $profiles = Get-ChildItem -LiteralPath $layout.RuntimeProfiles -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name
    $results = foreach ($profile in $profiles) {
        $content = $null
        $status = 'Readable'
        $mode = $null
        $cloud = $null
        $organization = $null

        try {
            $content = Get-Content -LiteralPath $profile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

            $runtimeModeProperty = $content.PSObject.Properties['RuntimeMode']
            $modeProperty = $content.PSObject.Properties['Mode']
            $cloudEnvironmentProperty = $content.PSObject.Properties['CloudEnvironment']
            $cloudProperty = $content.PSObject.Properties['Cloud']
            $organizationProperty = $content.PSObject.Properties['Organization']

            if ($null -ne $runtimeModeProperty -and -not [string]::IsNullOrWhiteSpace([string]$runtimeModeProperty.Value)) {
                $mode = [string]$runtimeModeProperty.Value
            }
            elseif ($null -ne $modeProperty -and -not [string]::IsNullOrWhiteSpace([string]$modeProperty.Value)) {
                $mode = [string]$modeProperty.Value
            }

            if ($null -ne $cloudEnvironmentProperty -and -not [string]::IsNullOrWhiteSpace([string]$cloudEnvironmentProperty.Value)) {
                $cloud = [string]$cloudEnvironmentProperty.Value
            }
            elseif ($null -ne $cloudProperty -and -not [string]::IsNullOrWhiteSpace([string]$cloudProperty.Value)) {
                $cloud = [string]$cloudProperty.Value
            }

            if ($null -ne $organizationProperty -and -not [string]::IsNullOrWhiteSpace([string]$organizationProperty.Value)) {
                $organization = [string]$organizationProperty.Value
            }
        }
        catch {
            $status = 'InvalidJson'
        }

        $profileResult = [pscustomobject]@{
            TypeName         = 'Hybrid.DeploymentRuntimeProfile'
            Name             = [IO.Path]::GetFileNameWithoutExtension($profile.Name)
            FileName         = $profile.Name
            Path             = $profile.FullName
            Status           = $status
            RuntimeMode      = $mode
            CloudEnvironment = $cloud
            Organization     = $organization
        }

        Add-HybridDeploymentTypeMetadata -InputObject $profileResult -TypeName 'Hybrid.DeploymentRuntimeProfile'
    }

    return @($results)
}

function Initialize-HybridDeployment {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RepositoryRoot
    )

    $layout = Get-HybridDeploymentLayout -RepositoryRoot $RepositoryRoot
    $requiredDirectories = @(
        $layout.Logs,
        $layout.Build,
        $layout.Profiles,
        $layout.RuntimeProfiles
    )

    $created = New-Object System.Collections.Generic.List[string]

    foreach ($directory in $requiredDirectories) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            if ($PSCmdlet.ShouldProcess($directory, 'Create deployment directory')) {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
                $created.Add($directory) | Out-Null
            }
        }
    }

    Ensure-HybridDefaultSimulationRuntimeProfile -Layout $layout -CreatedDirectories $created | Out-Null

    return Test-HybridDeploymentLayout -RepositoryRoot $layout.RepositoryRoot -CreatedDirectories $created.ToArray()
}

function Test-HybridDeploymentLayout {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot,
        [string[]]$CreatedDirectories = @()
    )

    $layout = Get-HybridDeploymentLayout -RepositoryRoot $RepositoryRoot
    $checks = New-Object System.Collections.Generic.List[object]

    $requiredPaths = @(
        @{ Name = 'Source root'; Category = 'Layout'; Path = $layout.Source; Type = 'Container' },
        @{ Name = 'Core modules'; Category = 'Layout'; Path = $layout.Core; Type = 'Container' },
        @{ Name = 'Application modules'; Category = 'Layout'; Path = $layout.Application; Type = 'Container' },
        @{ Name = 'Infrastructure modules'; Category = 'Layout'; Path = $layout.Infrastructure; Type = 'Container' },
        @{ Name = 'UI entry folder'; Category = 'Layout'; Path = $layout.UI; Type = 'Container' },
        @{ Name = 'Runtime profiles'; Category = 'Profiles'; Path = $layout.RuntimeProfiles; Type = 'Container' },
        @{ Name = 'Logs folder'; Category = 'Runtime'; Path = $layout.Logs; Type = 'Container' },
        @{ Name = 'Build folder'; Category = 'Packaging'; Path = $layout.Build; Type = 'Container' },
        @{ Name = 'Start-HybridAdminConsole entry point'; Category = 'EntryPoint'; Path = $layout.EntryPoint; Type = 'Leaf' }
    )

    foreach ($item in $requiredPaths) {
        $exists = if ($item.Type -eq 'Leaf') {
            Test-Path -LiteralPath $item.Path -PathType Leaf
        }
        else {
            Test-Path -LiteralPath $item.Path -PathType Container
        }

        $checks.Add((New-HybridDeploymentCheck -Name $item.Name -Category $item.Category -Severity 'Error' -Passed $exists -Message $(if ($exists) { 'Required deployment path exists.' } else { 'Required deployment path is missing.' }) -Path $item.Path)) | Out-Null
    }

    $profiles = @(Get-HybridDeploymentRuntimeProfile -RepositoryRoot $layout.RepositoryRoot)
    $hasReadableProfile = @($profiles | Where-Object { $_.Status -eq 'Readable' }).Count -gt 0
    $checks.Add((New-HybridDeploymentCheck -Name 'At least one runtime profile' -Category 'Profiles' -Severity 'Error' -Passed $hasReadableProfile -Message $(if ($hasReadableProfile) { 'At least one readable runtime profile is available.' } else { 'No readable runtime profile JSON files were found.' }) -Path $layout.RuntimeProfiles)) | Out-Null

    $simulationProfile = Join-Path $layout.RuntimeProfiles 'Simulation.json'
    $hasSimulationProfile = Test-Path -LiteralPath $simulationProfile -PathType Leaf
    $checks.Add((New-HybridDeploymentCheck -Name 'Simulation first-run profile' -Category 'Profiles' -Severity 'Error' -Passed $hasSimulationProfile -Message $(if ($hasSimulationProfile) { 'Simulation profile is available for first-run and offline validation.' } else { 'Simulation.json is missing from profiles/Runtime.' }) -Path $simulationProfile)) | Out-Null

    $uiText = $null
    if (Test-Path -LiteralPath $layout.EntryPoint -PathType Leaf) {
        $uiText = Get-Content -LiteralPath $layout.EntryPoint -Raw -ErrorAction SilentlyContinue
    }

    $hasDeviceCode = $false
    if ($null -ne $uiText) {
        $hasDeviceCode = $uiText -match 'Device\s*Code|DeviceCode'
    }

    $checks.Add((New-HybridDeploymentCheck -Name 'No Device Code authentication in UI entry point' -Category 'Security' -Severity 'Error' -Passed (-not $hasDeviceCode) -Message $(if ($hasDeviceCode) { 'Device Code authentication reference found in UI entry point.' } else { 'No Device Code authentication reference found in UI entry point.' }) -Path $layout.EntryPoint)) | Out-Null

    $errors = @($checks | Where-Object { -not $_.Passed -and $_.Severity -eq 'Error' })

    return New-HybridDeploymentResult -RepositoryRoot $layout.RepositoryRoot -IsReady ($errors.Count -eq 0) -Checks $checks.ToArray() -Profiles $profiles -CreatedDirectories $CreatedDirectories
}

function New-HybridDeploymentPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RepositoryRoot,
        [string]$OutputPath,
        [switch]$Force
    )

    $layout = Get-HybridDeploymentLayout -RepositoryRoot $RepositoryRoot
    $validation = Initialize-HybridDeployment -RepositoryRoot $layout.RepositoryRoot

    if (-not $validation.IsReady) {
        throw 'Deployment layout is not ready. Run Test-HybridDeploymentLayout for details.'
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $fileName = 'HybridAdminPlatform-{0}.zip' -f $script:HybridDeploymentVersion.Replace('.', '_').Replace('-', '_')
        $OutputPath = Join-Path $layout.Build $fileName
    }

    $resolvedOutput = $OutputPath
    if (-not [IO.Path]::IsPathRooted($resolvedOutput)) {
        $resolvedOutput = Join-Path $layout.RepositoryRoot $resolvedOutput
    }

    $outputDirectory = Split-Path -Path $resolvedOutput -Parent
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
    }

    if ((Test-Path -LiteralPath $resolvedOutput -PathType Leaf) -and -not $Force) {
        throw "Package already exists: $resolvedOutput. Use -Force to replace it."
    }

    if (Test-Path -LiteralPath $resolvedOutput -PathType Leaf) {
        Remove-Item -LiteralPath $resolvedOutput -Force
    }

    $items = @('src', 'profiles', 'docs', 'tools', 'tests', 'README.md', 'ENGINEERING_GUIDE.md', 'Start-AtlasHybridAdminConsole.ps1', 'HybridAdminConsole.code-workspace')
    $existingItems = foreach ($item in $items) {
        $path = Join-Path $layout.RepositoryRoot $item
        if (Test-Path -LiteralPath $path) { $path }
    }

    if ($PSCmdlet.ShouldProcess($resolvedOutput, 'Create Hybrid Admin Platform deployment package')) {
        Compress-Archive -Path $existingItems -DestinationPath $resolvedOutput -Force
    }

    return New-HybridDeploymentResult -RepositoryRoot $layout.RepositoryRoot -IsReady $true -Checks $validation.Checks -Profiles $validation.Profiles -CreatedDirectories $validation.CreatedDirectories -PackagePath $resolvedOutput
}

Export-ModuleMember -Function @(
    'Get-HybridDeploymentLayout',
    'Get-HybridDeploymentRuntimeProfile',
    'Initialize-HybridDeployment',
    'Test-HybridDeploymentLayout',
    'New-HybridDeploymentPackage'
)
