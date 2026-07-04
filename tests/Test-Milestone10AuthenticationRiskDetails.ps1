Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$authServicePath = Join-Path $repoRoot 'src\Application\Application.AuthenticationProfileService.psm1'
$userServicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
$authModelPath = Join-Path $repoRoot 'src\Models\Hybrid.AuthenticationProfile.psm1'
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

foreach ($path in @($authServicePath,$userServicePath,$authModelPath,$uiPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file missing: $path" }
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "Parser errors in $path`: $($errors[0].Message)" }
}

Remove-Module Application.AuthenticationProfileService,Application.HybridUserService,Hybrid.AuthenticationProfile -Force -ErrorAction SilentlyContinue
Import-Module $authServicePath -Force
Import-Module $userServicePath -Force
Import-Module $authModelPath -Force

$newAuthProfile = {
    param([string]$Identity)
    [pscustomobject]@{
        UserPrincipalName = $Identity
        DisplayName = 'Risky User'
        DefaultMethod = 'Microsoft Authenticator'
        AuthenticationMethods = @('Microsoft Authenticator','FIDO2 security key')
        AuthenticationMethodDetails = @(
            [pscustomobject]@{ DisplayName = 'Microsoft Authenticator'; MethodType = 'microsoftAuthenticator' }
            [pscustomobject]@{ DisplayName = 'FIDO2 security key'; MethodType = 'fido2' }
        )
        MfaRegistered = $true
        MfaCapable = $true
        PasswordlessRegistered = $true
        AuthenticationStrength = 'Phishing-resistant capable'
        ConditionalAccessState = 'failure'
        ConditionalAccessDetails = @(
            [pscustomobject]@{ DisplayName = 'Require phishing-resistant MFA'; Status = 'failure' }
        )
        SignInRiskState = 'medium'
        UserRiskState = 'atRisk'
        RiskLevel = 'high'
        RiskDetails = @(
            [pscustomobject]@{ DisplayName = 'Anonymous IP address'; RiskState = 'medium' }
            [pscustomobject]@{ DisplayName = 'Impossible travel'; RiskState = 'high' }
        )
        LastSuccessfulSignInDateTime = [datetime]'2026-07-01T12:00:00Z'
        PasswordLastChangedDateTime = [datetime]'2026-06-01T12:00:00Z'
        Source = 'MicrosoftGraph'
    }
}

$graphProvider = [pscustomobject]@{
    GetAuthenticationProfile = $newAuthProfile.GetNewClosure()
    GetUserAuthenticationProfile = $newAuthProfile.GetNewClosure()
    GetGraphProfile = $newAuthProfile.GetNewClosure()
    GetUser = $newAuthProfile.GetNewClosure()
}

Initialize-HybridAuthenticationProfileService -MicrosoftGraphProvider $graphProvider | Out-Null
$serviceProfile = Get-HybridAuthenticationProfile -Identity 'risk.user@atlas.test'
Assert-True (@($serviceProfile.AuthenticationMethodDetails).Count -eq 2) 'Authentication profile service preserves method detail objects'
Assert-True ($serviceProfile.ConditionalAccessState -eq 'failure' -and @($serviceProfile.ConditionalAccessDetails).Count -eq 1) 'Authentication profile service preserves Conditional Access details'
Assert-True ($serviceProfile.SignInRiskState -eq 'medium' -and $serviceProfile.UserRiskState -eq 'atRisk' -and $serviceProfile.RiskLevel -eq 'high') 'Authentication profile service preserves separate risk states'
Assert-True (@($serviceProfile.RiskDetails).Count -eq 2) 'Authentication profile service preserves risk detail objects'

Initialize-HybridUserService -MicrosoftGraphProvider $graphProvider | Out-Null
$userProfile = Get-HybridUserAuthenticationProfile -Identity 'risk.user@atlas.test'
Assert-True (@($userProfile.AuthenticationMethodDetails).Count -eq 2) 'User authentication profile preserves method details'
Assert-True (@($userProfile.RiskDetails).Count -eq 2 -and @($userProfile.ConditionalAccessDetails).Count -eq 1) 'User authentication profile preserves risk and Conditional Access details'

$modelProfile = New-HybridAuthenticationProfile -UserPrincipalName 'model@atlas.test' -DisplayName 'Model User' -RiskDetails @('risky sign-in') -ConditionalAccessDetails @('failed policy') -AuthenticationMethodDetails @('authenticator')
Assert-True (@($modelProfile.RiskDetails).Count -eq 1) 'Authentication profile model exposes RiskDetails'
Assert-True (@($modelProfile.ConditionalAccessDetails).Count -eq 1) 'Authentication profile model exposes ConditionalAccessDetails'
Assert-True (@($modelProfile.AuthenticationMethodDetails).Count -eq 1) 'Authentication profile model exposes AuthenticationMethodDetails'

$ui = Get-Content -LiteralPath $uiPath -Raw
Assert-True ($ui -match 'AuthRiskDetailsList') 'Authentication posture card includes risk/Conditional Access detail list'
Assert-True ($ui -match 'RiskDetails' -and $ui -match 'ConditionalAccessDetails') 'Authentication posture UI reads richer risk and Conditional Access details'
Assert-True ($ui -notmatch 'WorkflowRisk|RiskView|AuthenticationRiskView') 'Risk remains inside the User Lookup authentication posture card'

Write-Host ''
Write-Host 'Milestone 10 authentication risk detail tests passed.'
