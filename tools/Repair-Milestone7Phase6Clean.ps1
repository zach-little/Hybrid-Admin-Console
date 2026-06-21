[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Get-Location).Path
$packageRoot = Split-Path -Parent $PSScriptRoot
$timestamp = Get-Date -Format 'yyyyMMddHHmmss'

function Backup-File {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$Tag)
    if (Test-Path -LiteralPath $Path) {
        Copy-Item -LiteralPath $Path -Destination "$Path.$Tag.$timestamp.bak" -Force
    }
}

function Write-Utf8NoBom {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$Content)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Copy-PackageFile {
    param([Parameter(Mandatory=$true)][string]$RelativePath,[Parameter(Mandatory=$true)][string]$Tag)
    $source = Join-Path $packageRoot $RelativePath
    $target = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source)) { throw "Package file missing: $RelativePath" }
    Backup-File -Path $target -Tag $Tag
    Write-Utf8NoBom -Path $target -Content ([System.IO.File]::ReadAllText($source))
}

# Replace only the two files damaged by the previous repair/injection cycle.
Copy-PackageFile -RelativePath 'src\Infrastructure\Mock\Infrastructure.DirectorySimulator.psm1' -Tag 'm7p6clean'
Copy-PackageFile -RelativePath 'src\UI\Start-HybridAdminConsole.ps1' -Tag 'm7p6clean'

# Ensure the HybridUserService Phase 6 function/export exists without disturbing other service code.
$servicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
if (-not (Test-Path -LiteralPath $servicePath)) { throw "Hybrid user service not found: $servicePath" }
$service = [System.IO.File]::ReadAllText($servicePath)
Backup-File -Path $servicePath -Tag 'm7p6clean'

if ($service -notmatch 'function Get-HybridUserAuthenticationProfile') {
    $authFunction = @'

#region Milestone 7 Phase 6 - Authentication Profile Extension
function Get-HybridUserAuthenticationProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    if (-not $script:HybridUserServiceState.Initialized) { throw 'Hybrid user service has not been initialized.' }
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'User identity cannot be empty.' }

    $provider = $script:HybridUserServiceState.MicrosoftGraph
    $profile = @(Invoke-HybridServiceOperation -Service $provider -OperationNames @('GetAuthenticationProfile','GetUserAuthenticationProfile','GetGraphAuthenticationProfile','GetGraphProfile','GetUserGraphProfile','Get') -Arguments @($Identity) | Select-Object -First 1)
    if ($profile.Count -eq 0 -or $null -eq $profile[0]) { return $null }

    $raw = $profile[0]
    $methods = @(Get-HybridObjectValue -InputObject $raw -Names @('AuthenticationMethods','Methods') -Default @())
    $defaultMethod = [string](Get-HybridObjectValue -InputObject $raw -Names @('DefaultMethod','DefaultAuthenticationMethod') -Default '')
    if ([string]::IsNullOrWhiteSpace($defaultMethod)) { $defaultMethod = if ($methods.Count -gt 0) { [string]$methods[0] } else { 'password' } }

    $authProfile = [pscustomobject]@{
        PSTypeName = 'Hybrid.AuthenticationProfile'
        UserPrincipalName = [string](Get-HybridObjectValue -InputObject $raw -Names @('UserPrincipalName','UPN') -Default $Identity)
        DisplayName = [string](Get-HybridObjectValue -InputObject $raw -Names @('DisplayName','Name') -Default $Identity)
        DefaultMethod = $defaultMethod
        AuthenticationMethods = @($methods)
        MfaRegistered = [bool](Get-HybridObjectValue -InputObject $raw -Names @('MfaRegistered','MfaEnabled','IsMfaRegistered') -Default $false)
        MfaCapable = [bool](Get-HybridObjectValue -InputObject $raw -Names @('MfaCapable','IsMfaCapable') -Default $false)
        PasswordlessRegistered = [bool](Get-HybridObjectValue -InputObject $raw -Names @('PasswordlessRegistered','IsPasswordlessRegistered') -Default $false)
        TemporaryAccessPassEligible = [bool](Get-HybridObjectValue -InputObject $raw -Names @('TemporaryAccessPassEligible','TapEligible') -Default $false)
        AuthenticationStrength = [string](Get-HybridObjectValue -InputObject $raw -Names @('AuthenticationStrength','StrongAuthenticationRequirement') -Default 'Single-factor')
        ConditionalAccessState = [string](Get-HybridObjectValue -InputObject $raw -Names @('ConditionalAccessState','ConditionalAccess') -Default 'Not evaluated')
        SignInRiskState = [string](Get-HybridObjectValue -InputObject $raw -Names @('SignInRiskState','RiskState','UserRiskState') -Default 'none')
        LastMfaRegistrationDateTime = Get-HybridObjectValue -InputObject $raw -Names @('LastMfaRegistrationDateTime','MfaRegisteredOn') -Default $null
        LastSuccessfulSignInDateTime = Get-HybridObjectValue -InputObject $raw -Names @('LastSuccessfulSignInDateTime','LastSignInDateTime','LastSignIn') -Default $null
        PasswordLastChangedDateTime = Get-HybridObjectValue -InputObject $raw -Names @('PasswordLastChangedDateTime','PasswordLastChanged','LastPasswordChange') -Default $null
        Source = [string](Get-HybridObjectValue -InputObject $raw -Names @('Source') -Default 'MicrosoftGraph')
        RetrievedOn = [datetime]::UtcNow
    }
    $authProfile.PSObject.TypeNames.Insert(0, 'Hybrid.AuthenticationProfile.Milestone7Phase6')
    return $authProfile
}
#endregion
'@
    $exportIndex = $service.LastIndexOf('Export-ModuleMember -Function')
    if ($exportIndex -lt 0) { throw 'Could not find Export-ModuleMember block in HybridUserService.' }
    $service = $service.Insert($exportIndex, $authFunction + "`r`n")
}

if ($service -notmatch "'Get-HybridUserAuthenticationProfile'") {
    $service = $service -replace "('Get-HybridUserGraphProfile',\s*)", "`$1`r`n    'Get-HybridUserAuthenticationProfile',`r`n    "
    if ($service -notmatch "'Get-HybridUserAuthenticationProfile'") {
        $service = $service -replace "('Get-HybridUserMailboxDetails',\s*)", "`$1`r`n    'Get-HybridUserAuthenticationProfile',`r`n    "
    }
}
Write-Utf8NoBom -Path $servicePath -Content $service

# Parse-check repaired files before returning success.
foreach ($parsePath in @(
    (Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'),
    (Join-Path $repoRoot 'src\Infrastructure\Mock\Infrastructure.DirectorySimulator.psm1'),
    $servicePath
)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($parsePath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        $message = (@($errors) | Select-Object -First 5 | ForEach-Object { $_.Message }) -join '; '
        throw "Parser errors remain in $parsePath: $message"
    }
}

Write-Host 'Milestone 7 Phase 6 clean repair applied.'
Write-Host 'Run cumulative tests through Phase 6.'
