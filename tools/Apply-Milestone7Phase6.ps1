[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Get-Location).Path
$timestamp = Get-Date -Format 'yyyyMMddHHmmss'

function Backup-File {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$Tag)
    if (Test-Path $Path) {
        Copy-Item -LiteralPath $Path -Destination "$Path.$Tag.$timestamp.bak" -Force
    }
}

function Write-TextFile {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$Content)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-PackageFileText {
    param([Parameter(Mandatory=$true)][string]$RelativePath)
    $packageRoot = Split-Path -Parent $PSScriptRoot
    $path = Join-Path $packageRoot $RelativePath
    if (-not (Test-Path $path)) { throw "Package file missing: $RelativePath" }
    return [System.IO.File]::ReadAllText($path)
}

# Copy additive modules and tests/docs from the package.
foreach ($relative in @(
    'src\Models\Hybrid.AuthenticationProfile.psm1',
    'src\Application\Application.AuthenticationProfileService.psm1',
    'src\Infrastructure\DirectorySimulator\DirectorySimulator.AuthenticationVertical.psm1',
    'tests\Test-Milestone7Phase6.ps1',
    'tests\Test-Milestone7Phase6AuthenticationCard.ps1',
    'docs\Milestones\MILESTONE_7_PHASE_6.md'
)) {
    $target = Join-Path $repoRoot $relative
    if (Test-Path $target) { Backup-File -Path $target -Tag 'm7p6' }
    Write-TextFile -Path $target -Content (Get-PackageFileText -RelativePath $relative)
}

# Update active docs if present.
$roadmap = Join-Path $repoRoot 'docs\ROADMAP.md'
if (Test-Path $roadmap) {
    Backup-File -Path $roadmap -Tag 'm7p6'
    $text = [System.IO.File]::ReadAllText($roadmap)
    $text = $text -replace 'Current Phase:\*\* Phase 5 - Microsoft Graph Vertical','Current Phase:** Phase 6 - Authentication Vertical'
    $text = $text -replace '\| Phase 5 \| Microsoft Graph Vertical \| In Progress \|','| Phase 5 | Microsoft Graph Vertical | Complete |'
    $text = $text -replace '\| Phase 6 \| Authentication Vertical \| Pending \|','| Phase 6 | Authentication Vertical | In Progress |'
    if ($text -notmatch 'Phase 6 Goal') {
        $text += "`r`n## Phase 6 Goal`r`n`r`nExpose authentication posture as a live dashboard card through service-layer and provider abstractions. The card loads automatically when a user is searched and is backed by the Directory Simulator in mock mode.`r`n"
    }
    [System.IO.File]::WriteAllText($roadmap, $text, [System.Text.UTF8Encoding]::new($false))
}

$status = Join-Path $repoRoot 'docs\PROJECT_STATUS.md'
if (Test-Path $status) {
    Backup-File -Path $status -Tag 'm7p6'
    $text = [System.IO.File]::ReadAllText($status)
    $text = $text -replace 'Current Phase:\*\* Phase 5 - Microsoft Graph Vertical','Current Phase:** Phase 6 - Authentication Vertical'
    $text = $text -replace 'Phase 4 - Exchange Vertical stable','Milestone 7 Phase 5 - Microsoft Graph Vertical stable'
    $text = $text -replace '(?s)## Active Work.*?## Stability Rule', "## Active Work`r`n`r`nPhase 6 adds an authentication posture vertical as a live card:`r`n`r`n- Service-layer authentication profile retrieval`r`n- Canonical ``Hybrid.AuthenticationProfile`` model`r`n- Directory Simulator authentication posture data`r`n- UI authentication card that updates automatically after search`r`n- Phase 6 cumulative validation tests`r`n`r`n## Stability Rule"
    [System.IO.File]::WriteAllText($status, $text, [System.Text.UTF8Encoding]::new($false))
}

# Patch HybridUserService with Authentication vertical function/export.
$servicePath = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
if (-not (Test-Path $servicePath)) { throw "Hybrid user service not found: $servicePath" }
Backup-File -Path $servicePath -Tag 'm7p6'
$service = [System.IO.File]::ReadAllText($servicePath)

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
[System.IO.File]::WriteAllText($servicePath, $service, [System.Text.UTF8Encoding]::new($false))

# Patch Directory Simulator with Authentication provider support.
$simPath = Join-Path $repoRoot 'src\Infrastructure\Mock\Infrastructure.DirectorySimulator.psm1'
if (-not (Test-Path $simPath)) { throw "Directory Simulator not found: $simPath" }
Backup-File -Path $simPath -Tag 'm7p6'
$sim = [System.IO.File]::ReadAllText($simPath)

if ($sim -notmatch 'function Get-HybridDirectorySimulatorAuthenticationProfile') {
    $simFunction = @'

function Get-HybridDirectorySimulatorAuthenticationProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Identity)

    $user = Get-HybridDirectorySimulatorUser -Identity $Identity
    $seed = $user.SamAccountName.ToLowerInvariant()
    $hash = [Math]::Abs($seed.GetHashCode())
    $methodSets = @(
        @('password','microsoftAuthenticatorPush','fido2SecurityKey'),
        @('password','microsoftAuthenticatorPush','softwareOath'),
        @('password','sms','voiceMobile'),
        @('password')
    )
    $methods = @($methodSets[$hash % $methodSets.Count])
    $strongMethodCount = @($methods | Where-Object { $_ -ne 'password' -and $_ -ne 'sms' -and $_ -ne 'voiceMobile' }).Count
    $mfaMethodCount = @($methods | Where-Object { $_ -ne 'password' }).Count
    $passwordlessMethodCount = @($methods | Where-Object { $_ -in @('fido2SecurityKey','windowsHelloForBusiness','temporaryAccessPass') }).Count

    [pscustomobject]@{
        PSTypeName = 'Hybrid.AuthenticationProfile'
        UserPrincipalName = $user.UserPrincipalName
        DisplayName = $user.DisplayName
        DefaultMethod = if ($methods.Count -gt 1) { [string]$methods[1] } else { 'password' }
        AuthenticationMethods = @($methods)
        MfaRegistered = [bool]($mfaMethodCount -gt 0)
        MfaCapable = [bool]($mfaMethodCount -gt 0)
        PasswordlessRegistered = [bool]($passwordlessMethodCount -gt 0)
        TemporaryAccessPassEligible = [bool]($hash % 3 -ne 0)
        AuthenticationStrength = if ($strongMethodCount -gt 0) { 'Phishing-resistant capable' } elseif ($mfaMethodCount -gt 0) { 'Multifactor capable' } else { 'Single-factor only' }
        ConditionalAccessState = if ($mfaMethodCount -gt 0) { 'Satisfied' } else { 'Requires registration' }
        SignInRiskState = @('none','low','none','none','medium')[$hash % 5]
        LastMfaRegistrationDateTime = if ($mfaMethodCount -gt 0) { (Get-Date).Date.AddDays(-1 * (($hash % 120) + 3)) } else { $null }
        LastSuccessfulSignInDateTime = (Get-Date).AddHours(-1 * (($hash % 72) + 1))
        PasswordLastChangedDateTime = (Get-Date).Date.AddDays(-1 * (($hash % 90) + 10))
        Source = 'DirectorySimulator.MicrosoftGraph.Authentication'
        RetrievedOn = [datetime]::UtcNow
    }
}
'@
    $providerIndex = $sim.IndexOf('function New-HybridDirectorySimulatorProviders')
    if ($providerIndex -lt 0) { throw 'Could not find New-HybridDirectorySimulatorProviders in Directory Simulator.' }
    $sim = $sim.Insert($providerIndex, $simFunction + "`r`n")
}
if ($sim -notmatch 'GetAuthenticationProfile =') {
    $sim = $sim -replace "(GetUser = \{ param\(\[string\]\$Identity\) Get-HybridDirectorySimulatorUser -Identity \$Identity \}\.GetNewClosure\(\)\s*)", "`$1        GetAuthenticationProfile = { param([string]`$Identity) Get-HybridDirectorySimulatorAuthenticationProfile -Identity `$Identity }.GetNewClosure()`r`n        GetUserAuthenticationProfile = { param([string]`$Identity) Get-HybridDirectorySimulatorAuthenticationProfile -Identity `$Identity }.GetNewClosure()`r`n"
}
if ($sim -notmatch "'Get-HybridDirectorySimulatorAuthenticationProfile'") {
    $sim = $sim -replace "('Get-HybridDirectorySimulatorExchangeHealth'\s*)", "`$1,`r`n    'Get-HybridDirectorySimulatorAuthenticationProfile'"
}
[System.IO.File]::WriteAllText($simPath, $sim, [System.Text.UTF8Encoding]::new($false))

# Patch UI with live Authentication card.
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
if (-not (Test-Path $uiPath)) { throw "UI entry point not found: $uiPath" }
Backup-File -Path $uiPath -Tag 'm7p6'
$ui = [System.IO.File]::ReadAllText($uiPath)

if ($ui -notmatch 'AuthenticationPostureCard') {
    $authCard = @'
                    <Border x:Name="AuthenticationPostureCard" Style="{StaticResource Card}">
                        <StackPanel>
                            <TextBlock Text="Authentication Posture" Foreground="#F8FAFC" FontSize="18" FontWeight="SemiBold"/>
                            <TextBlock x:Name="AuthenticationSummaryText" Text="Authentication vertical slice waiting for a user search." Foreground="#38BDF8" FontSize="12" FontWeight="SemiBold" Margin="0,3,0,10" TextWrapping="Wrap"/>
                            <TextBlock Text="Default Method" Style="{StaticResource LabelText}"/><TextBlock x:Name="AuthDefaultMethodText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="MFA Registered" Style="{StaticResource LabelText}"/><TextBlock x:Name="AuthMfaRegisteredText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="Passwordless" Style="{StaticResource LabelText}"/><TextBlock x:Name="AuthPasswordlessText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="Authentication Strength" Style="{StaticResource LabelText}"/><TextBlock x:Name="AuthStrengthText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="Conditional Access" Style="{StaticResource LabelText}"/><TextBlock x:Name="AuthConditionalAccessText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="Sign-In Risk" Style="{StaticResource LabelText}"/><TextBlock x:Name="AuthRiskText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="Methods" Style="{StaticResource LabelText}"/><ListBox x:Name="AuthMethodsList" MinHeight="78"/>
                        </StackPanel>
                    </Border>
'@
    if ($ui -match '<Border x:Name="MicrosoftGraphCard"') {
        $ui = $ui -replace '(?s)(<Border x:Name="MicrosoftGraphCard".*?</Border>)', "`$1`r`n$authCard"
    } elseif ($ui -match '<Border x:Name="ExchangeMailboxCard"') {
        $ui = $ui -replace '(?s)(<Border x:Name="ExchangeMailboxCard".*?</Border>)', "`$1`r`n$authCard"
    } else {
        $ui = $ui -replace '(?s)(<ScrollViewer Grid.Column="1".*?<StackPanel>)', "`$1`r`n$authCard"
    }
}

$controlNames = @('AuthenticationSummaryText','AuthDefaultMethodText','AuthMfaRegisteredText','AuthPasswordlessText','AuthStrengthText','AuthConditionalAccessText','AuthRiskText','AuthMethodsList','AuthenticationPostureCard')
foreach ($name in $controlNames) {
    if ($ui -notmatch "'$name'") {
        $ui = $ui -replace "'ExchangeMailboxCard'", "'ExchangeMailboxCard','$name'"
    }
}

if ($ui -notmatch 'function Update-AuthenticationPanels') {
    $authUpdate = @'

function Update-AuthenticationPanels {
    param([Parameter(Mandatory=$true)][object]$User, [Parameter(Mandatory=$true)][string]$Query)

    foreach ($name in @('AuthenticationSummaryText','AuthDefaultMethodText','AuthMfaRegisteredText','AuthPasswordlessText','AuthStrengthText','AuthConditionalAccessText','AuthRiskText')) {
        if ($controls.ContainsKey($name) -and $null -ne $controls[$name]) { $controls[$name].Text = 'Loading authentication...' }
    }
    if ($controls.ContainsKey('AuthMethodsList') -and $null -ne $controls.AuthMethodsList) { $controls.AuthMethodsList.Items.Clear() }

    try {
        if (-not (Get-Command Get-HybridUserAuthenticationProfile -ErrorAction SilentlyContinue)) {
            if ($controls.ContainsKey('AuthenticationSummaryText')) { $controls.AuthenticationSummaryText.Text = 'Authentication service unavailable.' }
            return
        }

        $identity = Get-DisplayValue -InputObject $User -Names @('UserPrincipalName','Mail','SamAccountName','Identity') -Default $Query
        if ([string]::IsNullOrWhiteSpace($identity) -or $identity -eq '—') { $identity = $Query }
        $profile = Get-HybridUserAuthenticationProfile -Identity $identity
        if ($null -eq $profile) {
            if ($controls.ContainsKey('AuthenticationSummaryText')) { $controls.AuthenticationSummaryText.Text = 'No authentication profile found.' }
            return
        }

        if ($controls.ContainsKey('AuthDefaultMethodText')) { $controls.AuthDefaultMethodText.Text = Get-DisplayValue -InputObject $profile -Names @('DefaultMethod') }
        if ($controls.ContainsKey('AuthMfaRegisteredText')) { $controls.AuthMfaRegisteredText.Text = Get-DisplayValue -InputObject $profile -Names @('MfaRegistered') }
        if ($controls.ContainsKey('AuthPasswordlessText')) { $controls.AuthPasswordlessText.Text = Get-DisplayValue -InputObject $profile -Names @('PasswordlessRegistered') }
        if ($controls.ContainsKey('AuthStrengthText')) { $controls.AuthStrengthText.Text = Get-DisplayValue -InputObject $profile -Names @('AuthenticationStrength') }
        if ($controls.ContainsKey('AuthConditionalAccessText')) { $controls.AuthConditionalAccessText.Text = Get-DisplayValue -InputObject $profile -Names @('ConditionalAccessState') }
        if ($controls.ContainsKey('AuthRiskText')) { $controls.AuthRiskText.Text = Get-DisplayValue -InputObject $profile -Names @('SignInRiskState') }

        $methods = @()
        if ($profile.PSObject.Properties.Name -contains 'AuthenticationMethods' -and $null -ne $profile.AuthenticationMethods) { $methods = @($profile.AuthenticationMethods) }
        foreach ($method in $methods) { [void]$controls.AuthMethodsList.Items.Add([string]$method) }
        if ($controls.AuthMethodsList.Items.Count -eq 0) { [void]$controls.AuthMethodsList.Items.Add('No authentication methods loaded') }

        if ($controls.ContainsKey('AuthenticationSummaryText')) {
            $controls.AuthenticationSummaryText.Text = "Authentication loaded: MFA=$($profile.MfaRegistered) | Strength=$($profile.AuthenticationStrength)"
        }
    }
    catch {
        if ($controls.ContainsKey('AuthenticationSummaryText')) { $controls.AuthenticationSummaryText.Text = "Authentication profile load failed: $($_.Exception.Message)" }
    }
}
'@
    $invokeIndex = $ui.IndexOf('function Invoke-UserSearch')
    if ($invokeIndex -lt 0) { throw 'Could not find Invoke-UserSearch in UI script.' }
    $ui = $ui.Insert($invokeIndex, $authUpdate + "`r`n")
}

if ($ui -notmatch 'Update-AuthenticationPanels -User \$user -Query \$effectiveQuery') {
    if ($ui -match 'Update-MicrosoftGraphPanel -User \$user -Query \$effectiveQuery') {
        $ui = $ui -replace '(Update-MicrosoftGraphPanel -User \$user -Query \$effectiveQuery)', "`$1`r`n        Update-AuthenticationPanels -User `$user -Query `$effectiveQuery"
    } else {
        $ui = $ui -replace '(Update-ExchangePanels -User \$user -Query \$effectiveQuery)', "`$1`r`n        Update-AuthenticationPanels -User `$user -Query `$effectiveQuery"
    }
}

if ($ui -notmatch "Authentication vertical slice loading") {
    $ui = $ui -replace "(Exchange vertical slice loading mailbox details\.\.\.')", "`$1`r`n    if (`$controls.ContainsKey('AuthenticationSummaryText')) { `$controls.AuthenticationSummaryText.Text = 'Authentication vertical slice loading authentication posture...' }`r`n    if (`$controls.ContainsKey('AuthMethodsList')) { `$controls.AuthMethodsList.Items.Clear() }"
}

[System.IO.File]::WriteAllText($uiPath, $ui, [System.Text.UTF8Encoding]::new($false))

Write-Host 'Milestone 7 Phase 6 Authentication vertical applied.'
Write-Host 'Run cumulative tests through .\tests\Test-Milestone7Phase6.ps1 and .\tests\Test-Milestone7Phase6AuthenticationCard.ps1.'
