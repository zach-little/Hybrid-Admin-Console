$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

function Assert-ContainsText {
    param([string]$Content, [string]$Needle, [string]$Message)
    if ($Content -notlike "*$Needle*") { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$ui = Get-Content -LiteralPath $uiPath -Raw
Assert-ContainsText $ui 'Text="RUNTIME PREVIEW"' 'Bootstrap Preview is renamed to Runtime Preview'
Assert-ContainsText $ui 'Text="PROVIDER STATUS"' 'Provider card is labeled Provider Status'
Assert-ContainsText $ui 'Get-HapRuntimePreviewModel' 'Runtime Preview model helper exists'
Assert-ContainsText $ui 'Get-HapProviderStatusPreviewModel' 'Provider Status model helper exists'
Assert-ContainsText $ui 'Update-HapRuntimePreviewCard -Profile $selectedProfile' 'Runtime Preview refreshes from selected profile'
Assert-ContainsText $ui 'Update-HapProviderStatusCard -Profile $selectedProfile' 'Provider Status refreshes from selected profile'
Assert-True (-not ($ui -match 'BOOTSTRAP PLAN PREVIEW')) 'Old Bootstrap Plan Preview static label is removed'

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($uiPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw ($errors | ForEach-Object { $_.Message } | Out-String) }

$requiredFunctions = @(
    'Get-HybridProviderDisplayName',
    'Get-HapProfileObjectValue',
    'Get-HapSelectedRuntimeProfileRaw',
    'Get-HapRuntimeProfileProviderMap',
    'Test-HapCloudAppOnlyConfigured',
    'Get-HapAuthenticationPreviewLines',
    'Get-HapProviderConnectionHint',
    'Get-HapProviderStatusPreviewItem',
    'Get-HapProviderStatusPreviewModel',
    'Get-HapRuntimePreviewModel'
)

$functionAsts = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $requiredFunctions -contains $node.Name }, $true))
foreach ($name in $requiredFunctions) {
    $fn = @($functionAsts | Where-Object { $_.Name -eq $name })
    Assert-True ($fn.Count -eq 1) "Helper function $name is present"
}
foreach ($name in $requiredFunctions) {
    $fn = @($functionAsts | Where-Object { $_.Name -eq $name } | Select-Object -First 1)
    Invoke-Expression $fn.Extent.Text
}

$liveProfile = [pscustomobject]@{
    ProfileName = 'Live - GCC High'
    Mode = 'Live'
    Cloud = 'GCCHigh'
    Domain = 'atlas-tech.com'
    Authentication = [pscustomobject]@{
        Cloud = 'GCCHigh'
        AppOnly = [pscustomobject]@{
            Enabled = $true
            TenantId = 'tenant-id'
            ClientId = 'client-id'
            CredentialMode = 'Certificate'
            CertificateThumbprint = 'ABC123'
            CertificatePath = ''
            SecretReference = ''
        }
        Delegated = [pscustomobject]@{
            Enabled = $true
            PromptWhenRequired = $true
        }
    }
    Providers = [pscustomobject]@{
        ActiveDirectory = [pscustomobject]@{ Enabled = $true; Mode = 'Live'; Authentication = 'Integrated'; Domain = 'atlas-tech.com' }
        MicrosoftGraph = [pscustomobject]@{ Enabled = $true; Mode = 'Live'; Authentication = 'AppOnly' }
        ExchangeOnline = [pscustomobject]@{ Enabled = $true; Mode = 'Live'; Authentication = 'AppOnly' }
        ExchangeOnPremises = [pscustomobject]@{ Enabled = $true; Mode = 'Live'; Authentication = 'Kerberos'; Server = 'exchange01.atlas-tech.com'; ConnectionUri = '' }
    }
}

$missingOnPremProfile = [pscustomobject]@{
    ProfileName = 'Missing OnPrem'
    Mode = 'Live'
    Cloud = 'Commercial'
    Authentication = $liveProfile.Authentication
    Providers = [pscustomobject]@{
        ExchangeOnPremises = [pscustomobject]@{ Enabled = $true; Mode = 'Live'; Authentication = ''; Server = ''; ConnectionUri = '' }
    }
}

$missingExoProfile = [pscustomobject]@{
    ProfileName = 'Missing EXO Auth'
    Mode = 'Live'
    Cloud = 'Commercial'
    Authentication = [pscustomobject]@{
        AppOnly = [pscustomobject]@{ Enabled = $true; TenantId = ''; ClientId = ''; CredentialMode = 'Certificate'; CertificateThumbprint = ''; CertificatePath = ''; SecretReference = '' }
        Delegated = [pscustomobject]@{ Enabled = $false; ClientId = ''; PromptWhenRequired = $true }
    }
    Providers = [pscustomobject]@{
        ExchangeOnline = [pscustomobject]@{ Enabled = $true; Mode = 'Live'; Authentication = 'AppOnly' }
    }
}

$simulationProfile = [pscustomobject]@{
    ProfileName = 'Simulation'
    Mode = 'Simulation'
    Cloud = 'Commercial'
    Providers = [pscustomobject]@{
        DirectorySimulator = [pscustomobject]@{ Enabled = $true; Mode = 'Simulation'; Authentication = 'None' }
        ActiveDirectory = [pscustomobject]@{ Enabled = $false; Mode = 'Disabled'; Authentication = 'Integrated' }
        MicrosoftGraph = [pscustomobject]@{ Enabled = $false; Mode = 'Disabled'; Authentication = 'Interactive' }
    }
}

$livePreview = Get-HapRuntimePreviewModel -Profile $liveProfile
$simPreview = Get-HapRuntimePreviewModel -Profile $simulationProfile
Assert-True ($livePreview.ProfileName -eq 'Live - GCC High') 'Runtime Preview displays selected live profile name'
Assert-True ($livePreview.Mode -eq 'Live') 'Runtime Preview displays selected live profile mode'
Assert-True ($livePreview.Cloud -eq 'GCCHigh') 'Runtime Preview displays selected live profile cloud'
Assert-True (($livePreview.ProviderLines -join '|') -match 'Exchange On-Premises: enabled') 'Runtime Preview displays Exchange On-Premises when enabled'
Assert-True (($livePreview.ProviderLines -join '|') -match 'Exchange Online: enabled') 'Runtime Preview displays Exchange Online when enabled'
Assert-True (($livePreview.ConnectionLines -join '|') -match 'exchange01\.atlas-tech\.com') 'Runtime Preview displays Exchange On-Premises connection hint'
Assert-True ($simPreview.ProfileName -eq 'Simulation' -and $simPreview.Mode -eq 'Simulation') 'Runtime Preview changes when selected profile changes'
Assert-True (($simPreview.AuthenticationLines -join '|') -match 'Mock/simulation') 'Simulation profile renders mock authentication posture'
Assert-True (($livePreview.AuthenticationLines -join '|') -match 'Delegated Graph: available on demand') 'Delegated authentication preview only requires on/off'

$liveStatus = Get-HapProviderStatusPreviewModel -Profile $liveProfile
$missingOnPremStatus = Get-HapProviderStatusPreviewModel -Profile $missingOnPremProfile
$missingExoStatus = Get-HapProviderStatusPreviewModel -Profile $missingExoProfile
$simStatus = Get-HapProviderStatusPreviewModel -Profile $simulationProfile

$onPremLive = @($liveStatus.Items | Where-Object { $_.Name -eq 'ExchangeOnPremises' } | Select-Object -First 1)
$onPremMissing = @($missingOnPremStatus.Items | Where-Object { $_.Name -eq 'ExchangeOnPremises' } | Select-Object -First 1)
$exoLive = @($liveStatus.Items | Where-Object { $_.Name -eq 'ExchangeOnline' } | Select-Object -First 1)
$exoMissing = @($missingExoStatus.Items | Where-Object { $_.Name -eq 'ExchangeOnline' } | Select-Object -First 1)
$simExo = @($simStatus.Items | Where-Object { $_.Name -eq 'ExchangeOnline' } | Select-Object -First 1)
$simAd = @($simStatus.Items | Where-Object { $_.Name -eq 'DirectorySimulator' } | Select-Object -First 1)
$authLive = @($liveStatus.Items | Where-Object { $_.Name -eq 'Authentication' } | Select-Object -First 1)

Assert-True ($onPremLive[0].State -eq 'Enabled/configured') 'Provider Status displays Exchange On-Premises enabled/configured when server/auth are present'
Assert-True ($onPremMissing[0].State -eq 'Enabled but missing required settings') 'Provider Status displays Exchange On-Premises missing settings'
Assert-True ($exoLive[0].State -eq 'Enabled/configured') 'Provider Status displays Exchange Online configured only when app-only auth is present'
Assert-True ($exoMissing[0].State -eq 'Enabled but missing required settings') 'Provider Status displays Exchange Online missing auth settings'
Assert-True ($simExo[0].State -eq 'Disabled/not present') 'Provider Status displays absent Exchange Online as disabled/not present'
Assert-True ($simAd[0].State -eq 'Simulation/mock') 'Provider Status renders simulation/mock status without live connections'
Assert-True ($authLive[0].Detail -match 'Device Code: prohibited') 'Provider Status identifies Device Code as prohibited'

Write-Host 'Milestone 8.9 Runtime Home preview/status tests passed.'
