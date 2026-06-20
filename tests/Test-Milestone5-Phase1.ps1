Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'src/Core/Core.CloudEnvironment.psm1'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "FAIL: $Message"
    }

    Write-Host "PASS: $Message"
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "FAIL: $Message. Expected '$Expected' but got '$Actual'."
    }

    Write-Host "PASS: $Message"
}

Import-Module $modulePath -Force

$requiredCommands = @(
    'New-HybridCloudEnvironment',
    'Register-HybridCloudEnvironment',
    'Get-HybridCloudEnvironment',
    'Get-HybridCloudEnvironmentNames',
    'Get-HybridCloudEnvironmentEndpoint',
    'Resolve-HybridCloudEndpoint',
    'Test-HybridCloudEnvironment'
)

foreach ($commandName in $requiredCommands) {
    Assert-True -Condition ([bool](Get-Command $commandName -ErrorAction SilentlyContinue)) -Message "$commandName exported"
}

$names = Get-HybridCloudEnvironmentNames
Assert-True -Condition ($names -contains 'Commercial') -Message 'Commercial cloud environment registered'
Assert-True -Condition ($names -contains 'GCCHigh') -Message 'GCC High cloud environment registered'
Assert-True -Condition ($names -contains 'DoD') -Message 'DoD cloud environment registered'

$gccHighGraph = Get-HybridCloudEnvironmentEndpoint -EnvironmentName 'GCCHigh' -EndpointName 'Graph'
Assert-Equal -Actual $gccHighGraph -Expected 'https://graph.microsoft.us' -Message 'GCC High Graph endpoint resolves'

$gccHighAliasGraph = Get-HybridCloudEnvironmentEndpoint -EnvironmentName 'AzureUSGovernment' -EndpointName 'Graph'
Assert-Equal -Actual $gccHighAliasGraph -Expected 'https://graph.microsoft.us' -Message 'GCC High alias resolves'

$resolvedUserEndpoint = Resolve-HybridCloudEndpoint -EnvironmentName 'GCCHigh' -EndpointName 'Graph' -Path '/v1.0/users'
Assert-Equal -Actual $resolvedUserEndpoint -Expected 'https://graph.microsoft.us/v1.0/users' -Message 'Graph path resolves without duplicate slashes'

$customEnvironment = New-HybridCloudEnvironment `
    -Name 'UnitTestCloud' `
    -DisplayName 'Unit Test Cloud' `
    -Aliases @('UTCLOUD') `
    -Endpoints @{
        Graph = 'https://graph.unit.test/'
        Login = 'https://login.unit.test/'
    }

$validation = Test-HybridCloudEnvironment -Environment $customEnvironment
Assert-True -Condition $validation.IsValid -Message 'Custom cloud environment validates'

Register-HybridCloudEnvironment -Environment $customEnvironment -Force | Out-Null
Assert-Equal -Actual (Get-HybridCloudEnvironmentEndpoint -EnvironmentName 'UTCLOUD' -EndpointName 'Graph') -Expected 'https://graph.unit.test' -Message 'Custom cloud alias resolves and trims trailing slash'

$invalidEnvironment = [pscustomobject]@{
    Name = 'InvalidCloud'
    DisplayName = 'Invalid Cloud'
    Endpoints = @{
        Graph = 'https://graph.invalid.test'
    }
}

$invalidResult = Test-HybridCloudEnvironment -Environment $invalidEnvironment
Assert-True -Condition (-not $invalidResult.IsValid) -Message 'Invalid environment fails validation when Login endpoint is missing'

Write-Host ''
Write-Host 'Milestone 5 Phase 1 cloud environment tests passed.'
