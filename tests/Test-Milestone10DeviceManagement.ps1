Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$servicePath = Join-Path $repoRoot 'src\Application\Application.DeviceManagementService.psm1'
$runtimePath = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
$simulatorPath = Join-Path $repoRoot 'src\Infrastructure\Mock\Infrastructure.DirectorySimulator.psm1'
$adProviderPath = Join-Path $repoRoot 'src\Infrastructure\Infrastructure.ActiveDirectory.psm1'

Assert-True (Test-Path -LiteralPath $servicePath) 'Device Management application service exists'
Assert-True (Test-Path -LiteralPath $simulatorPath) 'Directory Simulator provider exists'
Assert-True (Test-Path -LiteralPath $adProviderPath) 'Active Directory provider exists'

$runtime = Get-Content -LiteralPath $runtimePath -Raw
$ui = Get-Content -LiteralPath $uiPath -Raw
$serviceSource = Get-Content -LiteralPath $servicePath -Raw
$simulatorSource = Get-Content -LiteralPath $simulatorPath -Raw
$adProviderSource = Get-Content -LiteralPath $adProviderPath -Raw

Assert-True ($runtime -match 'Application\.DeviceManagementService\.psm1') 'Runtime imports Device Management service'
Assert-True ($runtime -match "Register-HybridService -Name 'DeviceManagement'") 'Runtime registers DeviceManagement service'
Assert-True ($ui -match 'WorkflowDeviceManagementButton') 'Workflow selector exposes Device Management'
Assert-True ($ui -match 'DeviceManagementView') 'UI contains Device Management workflow view'
Assert-True ($ui -match 'OverlayHost" Style="\{StaticResource Card\}" MaxWidth="1320"') 'Overlay host is wide enough for enterprise workflow panels'
Assert-True ($ui -match 'DeviceManagementView" Width="1240"') 'Device Management panel uses wider layout'
Assert-True ($ui -match 'Invoke-HybridDeviceManagementSearchFromUi') 'UI wires Device Management lookup action'
Assert-True ($ui -match 'Milestone10DeviceManagement') 'UI declares Milestone 10 Device Management marker'
Assert-True ($ui -match 'Enter a user''s SamAccountName, UPN, mail address, device name, or device ID') 'Device Management search accepts user or device identity'
foreach ($buttonName in @('DeviceManagementCloseButton','DeviceManagementSearchButton','DeviceManagementBackToWorkflowButton','DeviceManagementOpenLookupButton')) {
    Assert-True ($ui -match "$buttonName.*Style=""\{StaticResource GlassCommandButton\}""") "Device Management $buttonName uses themed command button style"
}
Assert-True ($ui -match '<DataGrid x:Name="DeviceManagementDevicesList"') 'Device Management renders devices in a structured grid'
foreach ($column in @('Device','OS','Compliance','Last Check-In','Source')) {
    Assert-True ($ui -match [regex]::Escape(("Header=""{0}""" -f $column))) "Device Management grid includes $column column"
}
Assert-True ($ui -match 'ItemsSource = @\(\$deviceRows\)') 'Device Management binds structured device rows instead of plain text lines'
Assert-True ($ui -match 'Get-HybridWorkflowFriendlySource') 'Device Management normalizes long provider source labels for grid display'
Assert-True ($simulatorSource -match 'Get-HybridDirectorySimulatorDevices') 'Directory Simulator exposes device lookup'
Assert-True ($simulatorSource -match 'GetUserDevices') 'Directory Simulator provider advertises user device operation'
Assert-True ($simulatorSource -match 'Search-HybridDirectorySimulatorDevices') 'Directory Simulator supports direct device search'
Assert-True ($adProviderSource -match 'function Search-HybridADDevice') 'Active Directory provider supports direct computer device search'
Assert-True ($adProviderSource -match "Get-ADComputer") 'Active Directory device search queries AD computer objects'
Assert-True ($serviceSource -match 'Search-HybridManagedDevices') 'Device Management service supports direct device search'

Remove-Module Application.DeviceManagementService -ErrorAction SilentlyContinue
Remove-Module Infrastructure.DirectorySimulator -ErrorAction SilentlyContinue
Import-Module $servicePath -Force
Import-Module $simulatorPath -Force

$mockDirectory = [pscustomobject]@{
    GetUserDevices = {
        param([string]$Identity)
        if ($Identity -ne 'amorgan') { return @() }
        @(
            [pscustomobject]@{
                Id = 'device-1'
                Name = 'TEST-LAPTOP-01'
                OperatingSystem = 'Windows 11 Enterprise'
                ComplianceState = 'Compliant'
                PrimaryUser = $Identity
                LastCheckInUtc = [datetime]::UtcNow.AddHours(-1)
                Source = 'Mock'
            },
            [pscustomobject]@{
                Id = 'device-2'
                Name = 'TEST-LAPTOP-02'
                OperatingSystem = 'Windows 11 Enterprise'
                ComplianceState = 'NonCompliant'
                PrimaryUser = $Identity
                LastCheckInUtc = [datetime]::UtcNow.AddDays(-10)
                Source = 'Mock'
            }
        )
    }
    SearchDevices = {
        param([string]$Query)
        if ($Query -ne 'TEST-LAPTOP-02') { return @() }
        [pscustomobject]@{
            Id = 'device-2'
            Name = 'TEST-LAPTOP-02'
            OperatingSystem = 'Windows 11 Enterprise'
            ComplianceState = 'NonCompliant'
            PrimaryUser = 'amorgan'
            LastCheckInUtc = [datetime]::UtcNow.AddDays(-10)
            Source = 'Mock'
        }
    }
}

$service = Initialize-HybridDeviceManagementService -DirectoryProvider $mockDirectory
$summary = Get-HybridManagedDeviceSummary -Identity 'amorgan'
$directDeviceSummary = Get-HybridManagedDeviceSummary -Identity 'TEST-LAPTOP-02'

Assert-True ($service.PSObject.TypeNames -contains 'Hybrid.DeviceManagement.Service') 'Device Management initializer returns service object'
Assert-True ($summary.PSObject.TypeNames -contains 'Hybrid.DeviceManagement.Summary') 'Device Management returns summary object'
Assert-True ($summary.DeviceCount -eq 2) 'Device Management summary counts devices'
Assert-True ($summary.NonCompliantCount -eq 1) 'Device Management summary counts non-compliant devices'
Assert-True ($summary.StaleCheckInCount -eq 1) 'Device Management summary counts stale devices'
Assert-True ($summary.Status -eq 'Warning') 'Device Management summary warns on non-compliant or stale devices'
Assert-True (@($summary.Devices | Where-Object { $_.PSObject.TypeNames -contains 'Hybrid.Device' }).Count -eq 2) 'Device Management normalizes devices to Hybrid.Device'
Assert-True ($directDeviceSummary.DeviceCount -eq 1 -and $directDeviceSummary.Devices[0].Name -eq 'TEST-LAPTOP-02') 'Device Management searches direct device names when user lookup is not enough'

$simProviders = New-HybridDirectorySimulatorProviders
$simService = Initialize-HybridDeviceManagementService -DirectoryProvider $simProviders.ActiveDirectory -MicrosoftGraphProvider $simProviders.MicrosoftGraph
$simSummary = Get-HybridManagedDeviceSummary -Identity 'amorgan'
$simDeviceSummary = Get-HybridManagedDeviceSummary -Identity 'SIM-AMORGAN-LT01'

Assert-True ($simService.PSObject.TypeNames -contains 'Hybrid.DeviceManagement.Service') 'Device Management initializes against Directory Simulator providers'
Assert-True ($simSummary.DeviceCount -ge 1) 'Simulation data returns managed devices'
Assert-True (@($simSummary.Devices | Where-Object { $_.Name -match 'SIM-AMORGAN' }).Count -ge 1) 'Simulation device data includes named sample devices'
Assert-True ($simDeviceSummary.DeviceCount -ge 1 -and @($simDeviceSummary.Devices | Where-Object { $_.Name -eq 'SIM-AMORGAN-LT01' }).Count -ge 1) 'Simulation device data supports direct device-name lookup'

Write-Host ''
Write-Host 'Milestone 10 Device Management tests passed.'
