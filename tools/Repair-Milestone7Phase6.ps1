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

# Replace the damaged UI with a clean Phase 5 UI plus one integrated Authentication Posture card.
$uiSource = Join-Path $packageRoot 'src\UI\Start-HybridAdminConsole.ps1'
$uiTarget = Join-Path $repoRoot 'src\UI\Start-HybridAdminConsole.ps1'
if (-not (Test-Path -LiteralPath $uiSource)) { throw "Package UI file missing: $uiSource" }
if (-not (Test-Path -LiteralPath $uiTarget)) { throw "Repository UI file missing: $uiTarget" }
Backup-File -Path $uiTarget -Tag 'm7p6repair'
$ui = [System.IO.File]::ReadAllText($uiSource)
Write-Utf8NoBom -Path $uiTarget -Content $ui

# Repair Directory Simulator authentication provider aliases and strict-mode Count usage.
$simPath = Join-Path $repoRoot 'src\Infrastructure\Mock\Infrastructure.DirectorySimulator.psm1'
if (-not (Test-Path -LiteralPath $simPath)) { throw "Directory Simulator module not found: $simPath" }
Backup-File -Path $simPath -Tag 'm7p6repair'
$sim = [System.IO.File]::ReadAllText($simPath)

# Make any Graph-provider authentication operation use the authentication profile when available.
$sim = $sim -replace 'GetAuthenticationProfile = \{ param\(\[string\]\$Identity\) Get-HybridDirectorySimulatorGraphProfile -Identity \$Identity \}\.GetNewClosure\(\)', 'GetAuthenticationProfile = { param([string]$Identity) Get-HybridDirectorySimulatorAuthenticationProfile -Identity $Identity }.GetNewClosure()'

# Add the user-facing alias expected by the service/test contract.
if ($sim -notmatch 'GetUserAuthenticationProfile\s*=') {
    $sim = $sim -replace '(GetAuthenticationProfile = \{ param\(\[string\]\$Identity\) Get-HybridDirectorySimulatorAuthenticationProfile -Identity \$Identity \}\.GetNewClosure\(\))', "`$1`r`n        GetUserAuthenticationProfile = { param([string]`$Identity) Get-HybridDirectorySimulatorAuthenticationProfile -Identity `$Identity }.GetNewClosure()"
}

# Add a Graph-specific alias as a compatibility shim for service operation-name lists.
if ($sim -notmatch 'GetGraphAuthenticationProfile\s*=') {
    $sim = $sim -replace '(GetUserAuthenticationProfile = \{ param\(\[string\]\$Identity\) Get-HybridDirectorySimulatorAuthenticationProfile -Identity \$Identity \}\.GetNewClosure\(\))', "`$1`r`n        GetGraphAuthenticationProfile = { param([string]`$Identity) Get-HybridDirectorySimulatorAuthenticationProfile -Identity `$Identity }.GetNewClosure()"
}

# StrictMode-safe counts when a pipeline returns one object.
$sim = $sim -replace '\(\$methods \| Where-Object \{ \$_ -ne ''password'' \}\)\.Count', '@($methods | Where-Object { $_ -ne ''password'' }).Count'
$sim = $sim -replace '\(\$methods \| Where-Object \{ \$_ -ne ''password'' -and \$_ -ne ''sms'' -and \$_ -ne ''voiceMobile'' \}\)\.Count', '@($methods | Where-Object { $_ -ne ''password'' -and $_ -ne ''sms'' -and $_ -ne ''voiceMobile'' }).Count'
$sim = $sim -replace '\(\$methods \| Where-Object \{ \$_ -in @\(''fido2SecurityKey'',''windowsHelloForBusiness'',''temporaryAccessPass''\) \}\)\.Count', '@($methods | Where-Object { $_ -in @(''fido2SecurityKey'',''windowsHelloForBusiness'',''temporaryAccessPass'') }).Count'

Write-Utf8NoBom -Path $simPath -Content $sim

# Confirm the UI parses before returning success.
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($uiTarget, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    $message = ($errors | Select-Object -First 5 | ForEach-Object { $_.Message }) -join '; '
    throw "UI script still has parser errors: $message"
}

Write-Host 'Milestone 7 Phase 6 repair applied.'
Write-Host 'Run cumulative tests through Phase 6.'
