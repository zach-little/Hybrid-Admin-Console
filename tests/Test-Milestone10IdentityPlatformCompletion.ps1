Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$userServicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
$graphServicePath = Join-Path $repoRoot 'src\Application\Application.GraphProfileService.psm1'
$graphModelPath = Join-Path $repoRoot 'src\Models\Hybrid.GraphProfile.psm1'
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

foreach ($path in @($userServicePath,$graphServicePath,$graphModelPath,$uiPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file missing: $path" }
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "Parser errors in $path`: $($errors[0].Message)" }
}

Remove-Module Application.HybridUserService,Application.GraphProfileService,Hybrid.GraphProfile -Force -ErrorAction SilentlyContinue
Import-Module $userServicePath -Force
Import-Module $graphServicePath -Force
Import-Module $graphModelPath -Force

$newRichGraphUser = {
    param([string]$Identity)
    [pscustomobject]@{
        Id = 'graph-rich-1'
        DisplayName = 'Rich Graph User'
        UserPrincipalName = $Identity
        UserType = 'Member'
        UsageLocation = 'US'
        PreferredLanguage = 'en-US'
        AuthenticationMethods = @('Microsoft Authenticator','FIDO2 security key')
        AuthenticationMethodDetails = @(
            [pscustomobject]@{ DisplayName = 'Microsoft Authenticator'; Id = 'method-1' }
        )
        MfaRegistered = $true
        MfaCapable = $true
        Licenses = @(
            [pscustomobject]@{ DisplayName = 'Microsoft 365 E5'; SkuPartNumber = 'SPE_E5'; AssignmentSource = 'Group' }
        )
        AssignedLicenses = @(
            [pscustomobject]@{ SkuPartNumber = 'SPE_E5'; SkuId = 'sku-e5' }
        )
        LicenseAssignmentStates = @(
            [pscustomobject]@{ SkuPartNumber = 'SPE_E5'; State = 'Active'; AssignedByGroup = 'group-e5' }
        )
        LicenseDiagnostics = 'license diagnostics preserved'
        PimRoles = @(
            [pscustomobject]@{ RoleName = 'Global Reader'; AssignmentSource = 'Eligible' }
        )
        DirectoryRoles = @(
            [pscustomobject]@{ RoleName = 'User Administrator'; AssignmentSource = 'Active' }
        )
        PimDiagnostics = 'pim diagnostics preserved'
        RiskState = 'low'
        UserRiskState = 'atRisk'
        SignInRiskState = 'medium'
        RiskDetails = @(
            [pscustomobject]@{ DisplayName = 'Anonymous IP'; RiskState = 'medium' }
        )
        Source = 'MicrosoftGraph'
    }
}

$richGraphProvider = [pscustomobject]@{
    GetGraphProfile = $newRichGraphUser.GetNewClosure()
    GetUser = $newRichGraphUser.GetNewClosure()
}

Initialize-HybridUserService -MicrosoftGraphProvider $richGraphProvider | Out-Null
$userProfile = Get-HybridUserGraphProfile -Identity 'rich.user@atlas.test'
$compositeUser = Get-HybridUser -Identity 'rich.user@atlas.test'

Assert-True (@($userProfile.Licenses).Count -eq 1) 'User Graph profile preserves Licenses'
Assert-True (@($userProfile.AssignedLicenses).Count -eq 1) 'User Graph profile preserves AssignedLicenses separately'
Assert-True (@($userProfile.LicenseAssignmentStates).Count -eq 1) 'User Graph profile preserves LicenseAssignmentStates'
Assert-True ($userProfile.LicenseDiagnostics -eq 'license diagnostics preserved') 'User Graph profile preserves license diagnostics'
Assert-True (@($userProfile.PimRoles).Count -eq 1) 'User Graph profile preserves PIM roles'
Assert-True (@($userProfile.DirectoryRoles).Count -eq 1) 'User Graph profile preserves directory roles'
Assert-True ($userProfile.PimDiagnostics -eq 'pim diagnostics preserved') 'User Graph profile preserves PIM diagnostics'
Assert-True (@($userProfile.AuthenticationMethodDetails).Count -eq 1) 'User Graph profile preserves authentication method details'
Assert-True ($userProfile.UserRiskState -eq 'atRisk' -and $userProfile.SignInRiskState -eq 'medium' -and @($userProfile.RiskDetails).Count -eq 1) 'User Graph profile preserves richer risk fields'

Assert-True (@($compositeUser.Licenses).Count -eq 1) 'HybridCompositeUser preserves Licenses'
Assert-True (@($compositeUser.AssignedLicenses).Count -eq 1) 'HybridCompositeUser preserves AssignedLicenses'
Assert-True (@($compositeUser.LicenseAssignmentStates).Count -eq 1) 'HybridCompositeUser preserves LicenseAssignmentStates'
Assert-True (@($compositeUser.PimRoles).Count -eq 1) 'HybridCompositeUser preserves PIM roles'
Assert-True ($compositeUser.PimDiagnostics -eq 'pim diagnostics preserved') 'HybridCompositeUser preserves PIM diagnostics'

Initialize-HybridGraphProfileService -MicrosoftGraphProvider $richGraphProvider | Out-Null
$serviceProfile = Get-HybridGraphProfile -Identity 'rich.user@atlas.test'
Assert-True (@($serviceProfile.AssignedLicenses).Count -eq 1 -and @($serviceProfile.LicenseAssignmentStates).Count -eq 1) 'Graph profile service preserves assigned license and assignment-state fields'
Assert-True (@($serviceProfile.DirectoryRoles).Count -eq 1 -and $serviceProfile.PimDiagnostics -eq 'pim diagnostics preserved') 'Graph profile service preserves PIM/directory role diagnostics'

$modelProfile = New-HybridGraphProfile -ObjectId 'model-1' -UserPrincipalName 'model@atlas.test' -DisplayName 'Model User' -Licenses @('SPE_E5') -LicenseAssignmentStates @('Active') -PimRoles @('Global Reader') -LicenseDiagnostic 'license model diagnostic' -PimRoleDiagnostic 'pim model diagnostic'
Assert-True (@($modelProfile.LicenseAssignmentStates).Count -eq 1) 'Graph profile model exposes LicenseAssignmentStates'
Assert-True ($modelProfile.LicenseDiagnostics -eq 'license model diagnostic' -and $modelProfile.PimDiagnostics -eq 'pim model diagnostic') 'Graph profile model exposes license and PIM diagnostics'

$ui = Get-Content -LiteralPath $uiPath -Raw
Assert-True (($ui.IndexOf('Get-HybridUserGraphProfile') -lt $ui.IndexOf('Get-HybridGraphProfile')) -and $ui -match 'LicenseAssignmentStates' -and $ui -match 'PimDiagnostics') 'User Lookup UI keeps identity facts in the Graph panel path'
Assert-True ($ui -notmatch 'WorkflowLicensingButton|LicensingView') 'User license facts are not split into a standalone Licensing workflow'

Write-Host ''
Write-Host 'Milestone 10 identity platform completion tests passed.'
