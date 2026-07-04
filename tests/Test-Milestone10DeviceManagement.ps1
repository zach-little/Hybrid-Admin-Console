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

Assert-True (Test-Path -LiteralPath $servicePath) 'Device Management application service exists'

$runtime = Get-Content -LiteralPath $runtimePath -Raw
$ui = Get-Content -LiteralPath $uiPath -Raw

Assert-True ($runtime -match 'Application\.DeviceManagementService\.psm1') 'Runtime imports Device Management service'
Assert-True ($runtime -match "Register-HybridService -Name 'DeviceManagement'") 'Runtime registers DeviceManagement service'
Assert-True ($ui -match 'WorkflowDeviceManagementButton') 'Workflow selector exposes Device Management'
Assert-True ($ui -match 'DeviceManagementView') 'UI contains Device Management workflow view'
Assert-True ($ui -match 'Invoke-HybridDeviceManagementSearchFromUi') 'UI wires Device Management lookup action'
Assert-True ($ui -match 'Milestone10DeviceManagement') 'UI declares Milestone 10 Device Management marker'

Remove-Module Application.DeviceManagementService -ErrorAction SilentlyContinue
Import-Module $servicePath -Force

$mockDirectory = [pscustomobject]@{
    GetUserDevices = {
        param([string]$Identity)
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
}

$service = Initialize-HybridDeviceManagementService -DirectoryProvider $mockDirectory
$summary = Get-HybridManagedDeviceSummary -Identity 'amorgan'

Assert-True ($service.PSObject.TypeNames -contains 'Hybrid.DeviceManagement.Service') 'Device Management initializer returns service object'
Assert-True ($summary.PSObject.TypeNames -contains 'Hybrid.DeviceManagement.Summary') 'Device Management returns summary object'
Assert-True ($summary.DeviceCount -eq 2) 'Device Management summary counts devices'
Assert-True ($summary.NonCompliantCount -eq 1) 'Device Management summary counts non-compliant devices'
Assert-True ($summary.StaleCheckInCount -eq 1) 'Device Management summary counts stale devices'
Assert-True ($summary.Status -eq 'Warning') 'Device Management summary warns on non-compliant or stale devices'
Assert-True (@($summary.Devices | Where-Object { $_.PSObject.TypeNames -contains 'Hybrid.Device' }).Count -eq 2) 'Device Management normalizes devices to Hybrid.Device'

Write-Host ''
Write-Host 'Milestone 10 Device Management tests passed.'
