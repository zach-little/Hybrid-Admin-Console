# =====================================================================
# ATLAS MASTER USER DASHBOARD
# Written by Zach Little
# =====================================================================

param(
    [switch]$Debug,
    [switch]$NoNet,
    [switch]$StaRelaunched
)

# =====================================================================
# STA RELAUNCH HANDLER (Required for WPF)
# =====================================================================
try { 
    [Environment]::SetEnvironmentVariable('MASTER_DASHBOARD_STA',$null,'Process') 
} catch {}

$HostArgs = [Environment]::GetCommandLineArgs()
$HostWasStartedWithSTA = @($HostArgs | Where-Object { $_ -match '^-STA$' }).Count -gt 0

if (-not $StaRelaunched -and -not $HostWasStartedWithSTA) {

    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }

    if (-not [String]::IsNullOrWhiteSpace($scriptPath)) {

        $winPs = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path $winPs)) { $winPs = 'powershell.exe' }

        $relaunchArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',$scriptPath)

        if ($Debug) { $relaunchArgs += '-Debug' }
        if ($NoNet) { $relaunchArgs += '-NoNet' }
        $relaunchArgs += '-StaRelaunched'

        & $winPs @relaunchArgs
        exit $LASTEXITCODE
    }
}

# =====================================================================
# LOAD WPF CORE
# =====================================================================
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ---------------------------------------------------------
# ENSURE WPF APPLICATION EXISTS *AFTER* WPF ASSEMBLIES LOAD
# ---------------------------------------------------------
if (-not [System.Windows.Application]::Current) {
    $script:App = New-Object System.Windows.Application
} else {
    $script:App = [System.Windows.Application]::Current
}

# Normalize switches into globals used throughout the dashboard.
$Global:NoNet = $NoNet.IsPresent

# =====================================================================
# UTILITY: Decrypt Sensitive data
# =====================================================================
#Load Config & Key for protected data
# In -NoNet mode, skip config/aes entirely so the UI can be opened offline/demo-only.
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if ([string]::IsNullOrWhiteSpace($ScriptRoot)) { $ScriptRoot = (Get-Location).Path }

$ConfigPath = Join-Path $ScriptRoot "config.json"
$KeyPath    = Join-Path $ScriptRoot "aes.key"

if (-not $Global:NoNet) {
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    if (-not (Test-Path $KeyPath)) {
        throw "AES key file not found: $KeyPath"
    }

    $AESKey = Get-Content $KeyPath
    $Config = Get-Content $ConfigPath | ConvertFrom-Json
}
else {
    
}

function Decrypt-Value {
    param(
        [string]$CipherText,
        [string]$Base64Key
    )

    $CipherText = $CipherText.Replace("ENCRYPTED:", "")
    $bytes = [System.Convert]::FromBase64String($CipherText)
    $Key   = [System.Convert]::FromBase64String($Base64Key)

    $IV = $bytes[0..15]
    $Cipher = $bytes[16..($bytes.Length-1)]

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode = 'CBC'
    $aes.Padding = 'PKCS7'
    $aes.Key = $Key
    $aes.IV = $IV

    $decryptor = $aes.CreateDecryptor()
    $plainBytes = $decryptor.TransformFinalBlock($Cipher, 0, $Cipher.Length)

    return [System.Text.Encoding]::UTF8.GetString($plainBytes)
}
if (-not $Global:NoNet) {
    try {
        $ClientSecretPlain = Decrypt-Value $Config.client_secret $AESKey
    }
    catch {
		$ClientSecretPlain = "TEST"
    }

    try {
        $TempPasswordPlain = Decrypt-Value $Config.temp_password $AESKey
    }
    catch {
		$TempPasswordPlain = "P@ssword123!"
    }
}

# =====================================================================
# UTILITY: Load XAML from string
# =====================================================================
function Load-XamlString {
    param([Parameter(Mandatory)][string]$Xaml)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Xaml)
    $stream = New-Object System.IO.MemoryStream
    $stream.Write($bytes,0,$bytes.Length)
    $stream.Position = 0
    return [Windows.Markup.XamlReader]::Load($stream)
}

# =====================================================================
# UTILITY: Allow UI to update during long operations
# =====================================================================
function Do-Events {
    try {
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
            [Action]{},
            [System.Windows.Threading.DispatcherPriority]::Render
        )
    }
    catch {
        try {
            [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
                [Action]{},
                [System.Windows.Threading.DispatcherPriority]::Background
            )
        } catch {}
    }
}

function Force-UIRender {
    try {
        $dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
        $dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
        $dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        if ($script:MainWindow) { $script:MainWindow.UpdateLayout() }
        if ($script:LoadingOverlay) { $script:LoadingOverlay.UpdateLayout() }
        if ($script:LoadingOverlayContent) { $script:LoadingOverlayContent.UpdateLayout() }
    }
    catch {
        Do-Events
    }
}


# =====================================================================
# UTILITY: Resolve WPF resources from the correct scope
# =====================================================================
function Get-AppResource {
    param([Parameter(Mandatory)][string]$Key)

    try {
        if ($script:MainWindow) {
            $value = $script:MainWindow.TryFindResource($Key)
            if ($null -ne $value) { return $value }
        }
    } catch {}

    try {
        if ([System.Windows.Application]::Current) {
            $value = [System.Windows.Application]::Current.TryFindResource($Key)
            if ($null -ne $value) { return $value }
        }
    } catch {}

    try {
        if ($script:App) {
            $value = $script:App.TryFindResource($Key)
            if ($null -ne $value) { return $value }
        }
    } catch {}

    return $null
}

# =====================================================================
# DEBUG SYSTEM
# =====================================================================
$Global:DebugMode = $Debug.IsPresent
$Global:DebugPaneExpanded = $false

$script:ADUserCache = @()
$script:ADUserCacheBySam = @{}
$script:ADUserCacheByMail = @{}
$script:ADUserCacheLoaded = $false
$script:LastLookupIdentity = $null
$script:LastLookupResults = $null
$script:GraphAccessToken = $null
$script:GraphAppAccessToken = $null
$script:GraphDelegatedAccessToken = $null
$script:GraphDelegatedModeEnabled = $false
$script:GraphDelegatedAdminUpn = $null
$script:ExchangeDelegatedAccessToken = $null
$script:ExchangeOnlineDelegatedConnected = $false
$script:ExchangeOnlineConnectAttempted = $false
$script:ExchangeOnlineConnectError = $null
$script:GraphTenantId = "ea26f921-331e-4244-948d-d4d13598bbf5"
$script:GraphClientId = "94e76399-fbd5-4aa3-9efd-b658efe42baf"
$script:GraphDelegatedClientId = $null
$script:DebugHeightAdded = $false
$script:ExchangeOnlineStartupSkipped = $true
$script:ExchangeOnlineDelegatedConnected = $false

function Write-DebugLog {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')]$Level='INFO'
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "[$timestamp][$Level] $Message"

    # Console output if Debug switch is present
    if ($Global:DebugMode) { Write-Host $line }

    # If debug window exists, append to it
    try {
        if ($script:DebugOutputBox) {
            $script:DebugOutputBox.Dispatcher.Invoke([Action]{
                $script:DebugOutputBox.AppendText($line + [Environment]::NewLine)
                $script:DebugOutputBox.ScrollToEnd()
            })
        }
    } catch {}
}


function Toggle-DebugMode {
    $Global:DebugMode = -not $Global:DebugMode

    $debugHeight = 240

    if ($script:DebugPanel) {
        if ($Global:DebugMode) {
            $script:DebugPanel.Visibility = "Visible"
        }
        else {
            $script:DebugPanel.Visibility = "Collapsed"
        }
    }

    if ($script:DebugRow) {
        if ($Global:DebugMode) {
            $script:DebugRow.Height = New-Object System.Windows.GridLength(220)

            # Expand the window instead of stealing vertical space from the body/action panels.
            if ($script:MainWindow -and -not $script:DebugHeightAdded) {
                $script:MainWindow.Height = $script:MainWindow.Height + $debugHeight
                $script:MainWindow.MinHeight = [Math]::Max($script:MainWindow.MinHeight, 850 + $debugHeight)
                $script:DebugHeightAdded = $true
            }
        }
        else {
            $script:DebugRow.Height = New-Object System.Windows.GridLength(0)

            if ($script:MainWindow -and $script:DebugHeightAdded) {
                $script:MainWindow.Height = [Math]::Max(850, $script:MainWindow.Height - $debugHeight)
                $script:MainWindow.MinHeight = 850
                $script:DebugHeightAdded = $false
$script:ExchangeOnlineStartupSkipped = $true
$script:ExchangeOnlineDelegatedConnected = $false
            }
        }
    }

    Write-DebugLog "Debug mode toggled to: $($Global:DebugMode)" "INFO"
}


# =====================================================================
# LOADING OVERLAY UPDATE CALLBACKS (NEW)
# =====================================================================

# Will be assigned after XAML loads
$script:LoadingOverlay      = $null
$script:LoadingCard         = $null
$script:LoadingOverlayContent = $null
$script:LoadingText         = $null
$script:LoadingProgress     = $null

function Set-LoadingStatus {
    param(
        [string]$Message,
        [int]$Percent
    )

    try {
        $pct = [Math]::Max(0, [Math]::Min(100, $Percent))

        if ($script:LoadingText) {
            $script:LoadingText.Dispatcher.Invoke([Action]{
                $script:LoadingText.Text = $Message
            }, [System.Windows.Threading.DispatcherPriority]::Send)
        }

        if ($script:LoadingProgress) {
            $script:LoadingProgress.Dispatcher.Invoke([Action]{
                $script:LoadingProgress.Value = $pct
            }, [System.Windows.Threading.DispatcherPriority]::Send)
        }

        Force-UIRender
    }
    catch {
        Do-Events
    }
}

function Show-LoadingOverlay {
    try {
        if ($script:LoadingOverlay) {
            $script:LoadingOverlay.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
            $script:LoadingOverlay.Opacity = 1
            $script:LoadingOverlay.Visibility = "Visible"
            $script:LoadingOverlay.IsHitTestVisible = $true
            [System.Windows.Controls.Panel]::SetZIndex($script:LoadingOverlay, 9999)
        }

        if ($script:LoadingOverlayContent) {
            $script:LoadingOverlayContent.Visibility = "Visible"
        }

        Set-LoadingStatus "Searching..." 0
        Force-UIRender
        Start-Sleep -Milliseconds 75
        Force-UIRender
    }
    catch {
        Write-DebugLog "Show-LoadingOverlay failed: $($_.Exception.Message)" "WARN"
        Do-Events
    }
}

function Hide-LoadingOverlay {
    if ($script:LoadingOverlayContent) {
        $script:LoadingOverlayContent.Visibility = "Collapsed"
    }

    if ($script:LoadingOverlay) {
        $script:LoadingOverlay.Visibility = "Collapsed"
    }

    Do-Events
}

# =====================================================================
# MODULE INITIALIZATION ENGINE (NEW STRUCTURE)
# This will run BEFORE dashboard becomes available.
# =====================================================================

function Initialize-ADUserCache {

    if ($Global:NoNet) {
        Write-DebugLog "NoNet mode: AD user cache skipped." "WARN"
        return
    }

    try {
        Set-LoadingStatus "Caching Active Directory users..." 22

        $props = @(
            'DisplayName','GivenName','Surname','SamAccountName','UserPrincipalName','Mail','DistinguishedName',
            'Enabled','Title','Department','Company','Office','physicalDeliveryOfficeName',
            'City','State','StreetAddress','PostalCode','Country','telephoneNumber','mobile',
            'EmployeeID','BadgeID','Manager'
        )

        $users = Get-ADUser -Filter * -Properties $props -ErrorAction Stop |
            Sort-Object DisplayName

        $script:ADUserCache = @($users)
        $script:ADUserCacheBySam = @{}
        $script:ADUserCacheByMail = @{}

        foreach ($u in $script:ADUserCache) {
            if (-not [string]::IsNullOrWhiteSpace($u.SamAccountName)) {
                $script:ADUserCacheBySam[$u.SamAccountName.ToLowerInvariant()] = $u
            }
            if (-not [string]::IsNullOrWhiteSpace($u.Mail)) {
                $script:ADUserCacheByMail[$u.Mail.ToLowerInvariant()] = $u
            }
            if (-not [string]::IsNullOrWhiteSpace($u.UserPrincipalName)) {
                $script:ADUserCacheByMail[$u.UserPrincipalName.ToLowerInvariant()] = $u
            }
        }

        $script:ADUserCacheLoaded = $true
        Write-DebugLog "Cached $($script:ADUserCache.Count) AD users." "SUCCESS"
    }
    catch {
        $script:ADUserCacheLoaded = $false
        Write-DebugLog "AD user cache failed: $($_.Exception.Message)" "WARN"
    }
}


function Initialize-GraphRest {

    if ($Global:NoNet) {
        Write-DebugLog "NoNet mode: Graph app-only connection skipped." "WARN"
        return
    }

    Set-LoadingStatus "Connecting to Microsoft Graph GCC High (app-only)..." 45

    try {
        $ClientSecret = $ClientSecretPlain
        if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
            throw "Client secret is empty or unavailable. Check config.json/aes.key."
        }

        # Optional delegated public client can be supplied in config.json as delegated_client_id.
        try {
            if ($Config -and $Config.delegated_client_id) {
                $script:GraphDelegatedClientId = [string]$Config.delegated_client_id
            }
        } catch {}

        $authority = "https://login.microsoftonline.us/$($script:GraphTenantId)/oauth2/v2.0/token"
        $tokenResponse = Invoke-RestMethod `
            -Method POST `
            -Uri $authority `
            -Body @{
                client_id     = $script:GraphClientId
                client_secret = $ClientSecret
                scope         = "https://graph.microsoft.us/.default"
                grant_type    = "client_credentials"
            } `
            -ContentType "application/x-www-form-urlencoded" `
            -ErrorAction Stop

        if (-not $tokenResponse.access_token) {
            throw "Token request completed but no access_token was returned."
        }

        $script:GraphAppAccessToken = $tokenResponse.access_token
        $script:GraphAccessToken = $script:GraphAppAccessToken
        Write-DebugLog "Graph app-only REST token acquired for graph.microsoft.us." "SUCCESS"
    }
    catch {
        $script:GraphAppAccessToken = $null
        $script:GraphAccessToken = $null
        Write-DebugLog "Microsoft Graph GCC High app-only authentication failed: $($_.Exception.Message)" "ERROR"
    }
}



function Get-DelegatedExchangeScopes {
    return @("https://outlook.office365.us/.default")
}

function Get-DelegatedExchangeAccessToken {
    param([string]$ClientId)

    if (-not (Get-Command Invoke-DelegatedGraphBrowserAuth -ErrorAction SilentlyContinue)) {
        throw "Browser PKCE auth helper is not loaded."
    }

    Add-Type -AssemblyName System.Web
    $scopes = Get-DelegatedExchangeScopes
    Write-DebugLog "Requesting delegated Exchange Online token with browser PKCE. WAM is bypassed." "INFO"
    $token = Invoke-DelegatedGraphBrowserAuth -ClientId $ClientId -Scopes $scopes
    if (-not $token.access_token) { throw "Exchange Online delegated token request returned no access_token." }
    $script:ExchangeDelegatedAccessToken = $token.access_token
    return $token.access_token
}

function Connect-ExchangeOnlineSafe {
    param(
        [string]$UserPrincipalName
    )

    if ($Global:NoNet) { throw "NoNet mode: Exchange Online connection disabled." }

    if (Test-ExchangeOnlineConnected) {
        $script:ExchangeOnlineDelegatedConnected = $true
        Write-DebugLog "Exchange Online already connected." "SUCCESS"
        return $true
    }

    if (:IsNullOrWhiteSpace($UserPrincipalName)) {
        if (-not [String]::IsNullOrWhiteSpace($script:GraphDelegatedAdminUpn)) {
            $UserPrincipalName = $script:GraphDelegatedAdminUpn
        }
        else {
            throw "Delegated admin UPN is unknown. Enable Delegated Admin Mode first."
        }
    }

    try {
        $script:ExchangeOnlineConnectAttempted = $true
        $script:ExchangeOnlineConnectError = $null

        Import-Module ExchangeOnlineManagement -ErrorAction Stop

        Write-DebugLog "Delegated token flow not supported for Exchange Online in GCC High. Using WAM interactive sign‑in." "WARN"
        Set-LoadingStatus "Connecting to Exchange Online (WAM)..." 25

        # Minimal cmdlets list stays the same
        $cmds = @(
            'Get-Mailbox','Get-MailboxPermission','Get-RecipientPermission',
            'Get-Recipient','Get-User','Get-DistributionGroup',
            'Get-DistributionGroupMember','Remove-DistributionGroupMember',
            'Set-DistributionGroup'
        )

        $params = @{
            UserPrincipalName       = $UserPrincipalName
            ExchangeEnvironmentName = 'O365USGovGCCHigh'
            CommandName             = $cmds
            ShowBanner              = $false
            SkipLoadingFormatData   = $true
            ErrorAction             = 'Stop'
        }

        $connectCommand = Get-Command Connect-ExchangeOnline -ErrorAction Stop
        if ($connectCommand.Parameters.ContainsKey('ShowProgress')) { $params['ShowProgress'] = $true }
        if ($connectCommand.Parameters.ContainsKey('UseMultithreading')) { $params['UseMultithreading'] = $false }

        Connect-ExchangeOnline @params

        if (-not (Test-ExchangeOnlineConnected)) {
            Write-DebugLog "Connect-ExchangeOnline completed, but connection state is unclear." "WARN"
        }

        $script:ExchangeOnlineDelegatedConnected = $true
        Write-DebugLog "Exchange Online WAM session established." "SUCCESS"
        return $true
    }
    catch {
        $script:ExchangeOnlineDelegatedConnected = $false
        $script:ExchangeOnlineConnectError = $_.Exception.Message
        Write-DebugLog "Exchange Online connection failed (WAM mode): $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Initialize-Modules {

    Write-DebugLog "Starting module pre-load..." "INFO"
    Show-LoadingOverlay

    Set-LoadingStatus "Loading Active Directory module..." 10
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-DebugLog "ActiveDirectory module loaded." "SUCCESS"
    }
    catch {
        Write-DebugLog "Failed loading ActiveDirectory: $($_.Exception.Message)" "ERROR"
    }

    Initialize-ADUserCache

    Set-LoadingStatus "Preparing Microsoft Graph GCC High connection..." 35
    Initialize-GraphRest

    Set-LoadingStatus "Skipping Exchange Online startup connection..." 65
    Write-DebugLog "Exchange Online startup connection skipped. Mailbox delegation lookups are disabled in this build because Connect-ExchangeOnline hangs before interactive login on some endpoints." "WARN"

    Set-LoadingStatus "Preparing interface..." 90
    Start-Sleep -Milliseconds 250
    Set-LoadingStatus "Ready." 100
    Start-Sleep -Milliseconds 150

    Write-DebugLog "Module initialization complete." "SUCCESS"
}



# =====================================================================
# XAML RESOURCE DICTIONARIES (GLASS THEME + CARD STYLE)
# =====================================================================

$XamlTheme = @'
<ResourceDictionary
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <!-- ===================== FONT ===================== -->
    <FontFamily x:Key="AppFont">Segoe UI Variable Display, Segoe UI</FontFamily>

    <!-- ===================== COLORS ===================== -->
    <SolidColorBrush x:Key="TextMain" Color="#FFF5F7FA"/>
    <SolidColorBrush x:Key="TextMuted" Color="#DDE6F2FF"/>
    <SolidColorBrush x:Key="TextSoft"  Color="#AFC8DAEF"/>

    <SolidColorBrush x:Key="Accent"        Color="#FE7A00"/>
    <SolidColorBrush x:Key="AccentBright"  Color="#FE5000"/>

    <SolidColorBrush x:Key="Success" Color="#4CFF66"/>
    <SolidColorBrush x:Key="Warning" Color="#FFC857"/>
    <SolidColorBrush x:Key="Error"   Color="#FF5C7A"/>

    <!-- ===================== MAIN GRADIENT ===================== -->
    <LinearGradientBrush x:Key="MainGradient" StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#061321" Offset="0"/>
        <GradientStop Color="#081B35" Offset="0.42"/>
        <GradientStop Color="#10193F" Offset="1"/>
    </LinearGradientBrush>

    <!-- ===================== CARD BACKGROUND ===================== -->
    <LinearGradientBrush x:Key="GlassCard" StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#5519344F" Offset="0"/>
        <GradientStop Color="#3315263F" Offset="0.5"/>
        <GradientStop Color="#663B4C7F" Offset="1"/>
    </LinearGradientBrush>

    <!-- ===================== ACCENT BUTTON ===================== -->
    <LinearGradientBrush x:Key="AccentGradient" StartPoint="0,0" EndPoint="1,0">
        <GradientStop Color="#FFEC8D4D" Offset="0"/>
        <GradientStop Color="#FFFE7A00" Offset="0.5"/>
        <GradientStop Color="#FFFE5000" Offset="1"/>
    </LinearGradientBrush>

    <!-- ===================== SHADOWS ===================== -->
    <DropShadowEffect x:Key="GlowOrange"
                      Color="#FE7A00"
                      BlurRadius="26"
                      ShadowDepth="0"
                      Opacity="0.85"/>

    <DropShadowEffect x:Key="GlowBlue"
                      Color="#4BB2FF"
                      BlurRadius="36"
                      ShadowDepth="0"
                      Opacity="0.55"/>

    <!-- ===================== SHELL ===================== -->
    <Style x:Key="GlassShell" TargetType="Border">
        <Setter Property="CornerRadius" Value="28"/>
        <Setter Property="Padding"      Value="18"/>
        <Setter Property="Background"   Value="{StaticResource MainGradient}"/>
        <Setter Property="BorderBrush"  Value="#446EA0C8"/>
        <Setter Property="BorderThickness" Value="1"/>
    </Style>

    <!-- ===================== GLASS PANEL ===================== -->
    <Style x:Key="GlassPanel" TargetType="Border">
        <Setter Property="CornerRadius" Value="22"/>
        <Setter Property="Padding"      Value="20"/>
        <Setter Property="Background"   Value="{StaticResource GlassCard}"/>
        <Setter Property="BorderBrush"  Value="#557FB8E8"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Effect"       Value="{StaticResource GlowBlue}"/>
    </Style>

    <!-- ===================== PRIMARY BUTTON ===================== -->
    <Style x:Key="PrimaryButton" TargetType="Button">
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="Foreground" Value="#001018"/>
        <Setter Property="FontSize"   Value="20"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Cursor"     Value="Hand"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Background"      Value="{StaticResource AccentGradient}"/>
        <Setter Property="Padding"         Value="18,10"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="Root"
                            CornerRadius="16"
                            Background="{TemplateBinding Background}"
                            Padding="{TemplateBinding Padding}"
                            BorderBrush="#55FFFFFF"
                            BorderThickness="1"
                            Effect="{StaticResource GlowOrange}">
                        <ContentPresenter HorizontalAlignment="Center"
                                          VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Root" Property="Opacity" Value="0.92"/>
                        </Trigger>
                        <Trigger Property="IsPressed" Value="True">
                            <Setter TargetName="Root" Property="Opacity" Value="0.75"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter TargetName="Root" Property="Opacity" Value="0.4"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- ===================== TEXT STYLES ===================== -->
    <Style x:Key="TitleText" TargetType="TextBlock">
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="FontSize"   Value="36"/>
        <Setter Property="FontWeight" Value="Bold"/>
        <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
    </Style>

    <Style x:Key="SectionHeader" TargetType="TextBlock">
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="FontSize"   Value="24"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Foreground" Value="White"/>
        <Setter Property="Effect"     Value="{StaticResource GlowOrange}"/>
        <Setter Property="Margin"     Value="0,0,0,8"/>
    </Style>
	
	<!-- ========================================================= -->
	<!-- ACTION CARD STYLE (Modern Glass Elevated Button)          -->
	<!-- ========================================================= -->
	<Style x:Key="ActionCard" TargetType="Button">
		<Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
		<Setter Property="Foreground" Value="White"/>
		<Setter Property="FontSize" Value="20"/>
		<Setter Property="FontWeight" Value="SemiBold"/>
		<Setter Property="Height" Value="58"/>
		<Setter Property="Margin" Value="0,0,0,14"/>
		<Setter Property="Padding" Value="18,10"/>
		<Setter Property="HorizontalContentAlignment" Value="Left"/>
		<Setter Property="Cursor" Value="Hand"/>

		<!-- Background Gradient -->
		<Setter Property="Background" Value="{StaticResource AccentGradient}"/>

		<Setter Property="BorderBrush" Value="#66FFFFFF"/>
		<Setter Property="BorderThickness" Value="1"/>

		<!-- Soft elevation shadow -->
		<Setter Property="Effect">
			<Setter.Value>
				<DropShadowEffect Color="#000000"
								  BlurRadius="26"
								  ShadowDepth="0"
								  Opacity="0.38"/>
			</Setter.Value>
		</Setter>

		<!-- Template with CornerRadius INSIDE the Border (VALID) -->
		<Setter Property="Template">
			<Setter.Value>
				<ControlTemplate TargetType="Button">
					<Border x:Name="CardRoot"
							Background="{TemplateBinding Background}"
							BorderBrush="{TemplateBinding BorderBrush}"
							BorderThickness="{TemplateBinding BorderThickness}"
							CornerRadius="14">

						<ContentPresenter VerticalAlignment="Center"
										  Margin="12,0,0,0"/>
					</Border>

					<ControlTemplate.Triggers>

						<!-- Hover -->
						<Trigger Property="IsMouseOver" Value="True">
							<Setter TargetName="CardRoot" Property="Opacity" Value="0.92"/>
							<Setter TargetName="CardRoot" Property="BorderBrush" Value="#88FFFFFF"/>
						</Trigger>

						<!-- Pressed -->
						<Trigger Property="IsPressed" Value="True">
							<Setter TargetName="CardRoot" Property="Opacity" Value="0.75"/>
						</Trigger>

						<!-- Disabled -->
						<Trigger Property="IsEnabled" Value="False">
							<Setter TargetName="CardRoot" Property="Opacity" Value="0.45"/>
						</Trigger>

					</ControlTemplate.Triggers>

				</ControlTemplate>
			</Setter.Value>
		</Setter>
	</Style>

</ResourceDictionary>
'@

# =====================================================================
# COLLAPSIBLE CARD CONTROL TEMPLATE
# =====================================================================

$XamlCollapsibleCard = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <Style x:Key="CollapsibleCardStyle" TargetType="Expander">
        <Setter Property="Foreground" Value="White"/>
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="BorderBrush" Value="#557FB8E8"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Expander">
                    <Border Background="{StaticResource GlassCard}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}"
                            CornerRadius="14"
                            Padding="12"
                            Margin="0,0,0,18">

                        <DockPanel>

                            <!-- HEADER BUTTON -->
                            <ToggleButton 
                                x:Name="ToggleButton"
                                DockPanel.Dock="Top"
                                Style="{x:Null}"
                                Background="Transparent"
                                BorderThickness="0"
                                Cursor="Hand">
                                
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="32"/>
                                    </Grid.ColumnDefinitions>

                                    <TextBlock Text="{TemplateBinding Header}"
                                               FontFamily="{StaticResource AppFont}"
                                               FontSize="18"
                                               FontWeight="SemiBold"
                                               Foreground="White"
                                               Effect="{StaticResource GlowOrange}"/>

                                    <!-- CHEVRON -->
                                    <TextBlock x:Name="Chevron"
                                               Grid.Column="1"
                                               Text="▸"
                                               FontSize="28"
                                               Foreground="{StaticResource AccentBright}"
                                               HorizontalAlignment="Center"
                                               VerticalAlignment="Center"/>
                                </Grid>

                            </ToggleButton>

                            <!-- CONTENT -->
                            <ContentPresenter x:Name="ContentSite"
                                              Margin="0,12,0,0"
                                              Visibility="Collapsed"/>

                        </DockPanel>

                        <ControlTemplate.Triggers>

                            <!-- Rotate Chevron -->
                            <Trigger Property="IsExpanded" Value="True">
                                <Setter TargetName="Chevron" Property="RenderTransform">
                                    <Setter.Value>
                                        <RotateTransform Angle="90"/>
                                    </Setter.Value>
                                </Setter>
                                <Setter TargetName="ContentSite" Property="Visibility" Value="Visible"/>
                            </Trigger>

                        </ControlTemplate.Triggers>

                    </Border>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

</ResourceDictionary>
'@

# =====================================================================
# MAIN WINDOW XAML (STRUCTURE + RESERVED LOADING OVERLAY LAYER)
# =====================================================================

$XamlMainWindow = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Atlas Master User Dashboard"
    Width="1600"
    Height="1000"
    MinWidth="1300"
    MinHeight="850"
    WindowStyle="None"
    ResizeMode="CanResizeWithGrip"
    Background="Transparent"
    AllowsTransparency="True"
    WindowStartupLocation="CenterScreen">

    <Grid>

        <!-- ========================================================= -->
        <!-- LAYER 1: MAIN APPLICATION SHELL -->
        <!-- ========================================================= -->
        <Border Style="{StaticResource GlassShell}">
            <Grid>

                <Grid.RowDefinitions>
                    <RowDefinition Height="120"/>   <!-- HEADER -->
                    <RowDefinition Height="*"/>     <!-- BODY -->
                    <RowDefinition Height="220"/>   <!-- DEBUG PANEL -->
                </Grid.RowDefinitions>

                <!-- ===================================================== -->
                <!-- HEADER PANEL -->
                <!-- ===================================================== -->
                <Border
                    Grid.Row="0"
                    Background="#2217263C"
                    CornerRadius="22"
                    BorderBrush="#3388AADD"
                    BorderThickness="1"
                    Padding="18">

                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="70"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="220"/>
                        </Grid.ColumnDefinitions>

                        <!-- HAMBURGER / DEBUG TOGGLE -->
                        <Button x:Name="HamburgerButton"
                                Grid.Column="0"
                                Content="☰"
                                Style="{StaticResource PrimaryButton}"
                                Width="54" Height="45"
                                Margin="0,0,14,0"
                                ToolTip="Menu"/>

                        <!-- SEARCH BAR -->
                        <Border Grid.Column="1"
                                CornerRadius="14"
                                Background="#330A1525"
                                BorderBrush="#557FB8E8"
                                BorderThickness="1"
                                Padding="12"
                                Effect="{StaticResource GlowBlue}">

                            <DockPanel>
                                <TextBlock Text="&#x1F50D;" 
										FontSize="24"
										Margin="4,12,8,0"
										Foreground="{StaticResource Accent}"/>								
                                <TextBox x:Name="SearchUserBox"
										FontFamily="{StaticResource AppFont}"
										FontSize="22"
										Background="Transparent"
										BorderThickness="0"
										Foreground="{StaticResource TextMain}"
										CaretBrush="{StaticResource Accent}"
										VerticalContentAlignment="Center"
										Padding="0"
										Margin="12,0,0,0" />
                            </DockPanel>
                        </Border>

                        <!-- WINDOW CONTROLS -->
                        <StackPanel Grid.Column="2"
                                    Orientation="Horizontal"
                                    HorizontalAlignment="Right"
                                    VerticalAlignment="Center">

                            <Button x:Name="MinButton"
                                    Content="−"
                                    Style="{StaticResource PrimaryButton}"
                                    Width="54" Height="45"
                                    Margin="0,0,8,0"/>

                            <Button x:Name="MaxButton"
                                    Content="□"
                                    Style="{StaticResource PrimaryButton}"
                                    Width="54" Height="45"
                                    Margin="0,0,8,0"/>

                            <Button x:Name="ExitButton"
                                    Content="×"
                                    Style="{StaticResource PrimaryButton}"
                                    Width="54" Height="45"/>
                        </StackPanel>
                    </Grid>
                </Border>

                <!-- ===================================================== -->
				<!-- MAIN BODY LAYOUT -->
				<!-- ===================================================== -->
				<Grid Grid.Row="1"
					  Margin="0">

					<Grid.ColumnDefinitions>
						<ColumnDefinition Width="360"/>    <!-- SUMMARY -->
						<ColumnDefinition Width="*"/>      <!-- RESULTS -->
						<ColumnDefinition Width="320"/>    <!-- ACTIONS -->
					</Grid.ColumnDefinitions>

					<!-- SUMMARY PANEL -->
					<Border Grid.Column="0"
							Style="{StaticResource GlassPanel}"
							Margin="16,32,16,0">
						<StackPanel>
							<TextBlock Text="User Summary"
									   Style="{StaticResource SectionHeader}" />
							<TextBlock Text="Display Name:"
									   Foreground="{StaticResource TextMuted}" />
							<TextBlock x:Name="SummaryDisplayName"
									   FontSize="18"
									   Foreground="White"
									   Margin="0,0,0,10" />
							<TextBlock Text="Username:"
									   Foreground="{StaticResource TextMuted}" />
							<TextBlock x:Name="SummarySam"
									   FontSize="18"
									   Foreground="White"
									   Margin="0,0,0,10" />
							<TextBlock Text="Email:"
									   Foreground="{StaticResource TextMuted}" />
							<TextBlock x:Name="SummaryEmail"
									   FontSize="18"
									   Foreground="White"
									   Margin="0,0,0,10" />
							<TextBlock Text="EmployeeID:"
									   Foreground="{StaticResource TextMuted}" />
							<TextBlock x:Name="SummaryEmployeeID"
									   FontSize="18"
									   Foreground="White"
									   Margin="0,0,0,10" />
							<TextBlock Text="BadgeID:"
									   Foreground="{StaticResource TextMuted}" />
							<TextBlock x:Name="SummaryBadgeID"
									   FontSize="18"
									   Foreground="White"
									   Margin="0,0,0,10" />
							<TextBlock Text="Manager:"
									   Foreground="{StaticResource TextMuted}" />
							<TextBlock x:Name="SummaryManager"
									   FontSize="18"
									   Foreground="White"
									   TextWrapping="Wrap"
									   Margin="0,0,0,10" />
							<TextBlock Text="Object DN:"
									   Foreground="{StaticResource TextMuted}" />
							<TextBlock x:Name="SummaryDN"
									   FontSize="16"
									   Foreground="White"
									   TextWrapping="Wrap"
									   Margin="0,0,0,10" />
						</StackPanel>
					</Border>

					<!-- RESULTS PANEL -->
					<Border Grid.Column="1"
							Style="{StaticResource GlassPanel}"
							Margin="16,32,16,0">
						<ScrollViewer VerticalScrollBarVisibility="Auto"
									  Margin="0">
							<StackPanel x:Name="ResultsPanel" />
						</ScrollViewer>
					</Border>

					<!-- ACTION PANEL -->
					<Border Grid.Column="2"
							Style="{StaticResource GlassPanel}"
							Margin="16,32,16,0">
						<StackPanel x:Name="ActionPanel"
									VerticalAlignment="Top" />
					</Border>

				</Grid>

                <!-- ===================================================== -->
                <!-- DEBUG PANEL (COLLAPSIBLE) -->
                <!-- ===================================================== -->
                <Border x:Name="DebugPanel"
                        Grid.Row="2"
                        Background="#AA0D1625"
                        BorderBrush="#88FE7A00"
                        BorderThickness="1"
                        CornerRadius="18"
                        Padding="12"
						Margin="0,12,0,0"
                        Visibility="Collapsed">

                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <DockPanel Grid.Row="0">
                            <TextBlock Text="Debug Output"
                                       FontFamily="{StaticResource AppFont}"
                                       FontSize="20"
                                       FontWeight="Bold"
                                       Foreground="{StaticResource Success}"
                                       DockPanel.Dock="Left"/>
                        </DockPanel>

                        <TextBox x:Name="DebugOutputBox"
                                 Grid.Row="1"
                                 FontFamily="Consolas"
                                 FontSize="13"
                                 Foreground="{StaticResource Success}"
                                 Background="#220A1525"
                                 BorderBrush="#557FB8E8"
                                 BorderThickness="1"
                                 IsReadOnly="True"
                                 AcceptsReturn="True"
                                 TextWrapping="Wrap"
                                 VerticalScrollBarVisibility="Auto"/>
                    </Grid>
                </Border>

            </Grid>
        </Border>

        <!-- ========================================================= -->
        <!-- LAYER 2: LOADING OVERLAY (PART 4 WILL FILL THIS IN) -->
        <!-- ========================================================= -->
        <Grid x:Name="LoadingOverlay"
              Background="Transparent"
              Visibility="Collapsed"
              Panel.ZIndex="9999"/>

    </Grid>
</Window>
'@

# =====================================================================
# LOADING OVERLAY (MODAL CARD + PROGRESSBAR + ANIMATIONS)
# =====================================================================
$XamlLoadingOverlay = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      Background="Transparent"
      Visibility="Visible">

    <Grid.Resources>

        <!-- Fade-Out Storyboard -->
        <Storyboard x:Key="FadeOutStoryboard">
            <DoubleAnimation Storyboard.TargetProperty="Opacity"
                             From="1.0" To="0.0"
                             Duration="0:0:0.35"/>
        </Storyboard>

    </Grid.Resources>

    <!-- CENTER MODAL CARD -->
    <Border x:Name="LoadingCard"
            Width="520"
            Height="120"
            HorizontalAlignment="Center"
            VerticalAlignment="Top"
            Margin="0,135,0,0"
            Background="#EE101B2F"
            BorderBrush="#55FFFFFF"
            BorderThickness="1"
            CornerRadius="18"
            Effect="{StaticResource GlowBlue}">
        
        <Grid Margin="20">

            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- STATUS HEADER -->
            <TextBlock x:Name="LoadingText"
                       Grid.Row="0"
                       Text="Initializing Atlas Dashboard…"
                       HorizontalAlignment="Center"
                       VerticalAlignment="Center"
                       FontFamily="{StaticResource AppFont}"
                       FontSize="22"
                       FontWeight="SemiBold"
                       Foreground="White"
                       TextWrapping="Wrap"
                       TextAlignment="Center"/>

            <!-- PROGRESS BAR -->
            <ProgressBar x:Name="LoadingProgress"
                         Grid.Row="1"
                         Height="16"
                         Minimum="0"
                         Maximum="100"
                         Value="0"
                         Margin="0,14,0,0"
                         Foreground="{StaticResource AccentBright}"
                         Background="#330A1525"
                         BorderBrush="#557FB8E8"
                         BorderThickness="1"/>

        </Grid>
    </Border>

</Grid>
'@

function Attach-LoadingOverlay {
    param([Parameter(Mandatory)]$Window)

    try {
        $overlayHost = $Window.FindName("LoadingOverlay")

        if ($overlayHost -eq $null) {
            Write-DebugLog "ERROR: LoadingOverlay host not found in XAML." "ERROR"
            return
        }

        # Load overlay XAML
        $overlayContent = Load-XamlString $XamlLoadingOverlay

        # Inject overlay inside placeholder grid
        $overlayHost.Children.Clear()
        $overlayHost.Children.Add($overlayContent)

        # Store references for status update functions
        $script:LoadingOverlay        = $overlayHost
        $script:LoadingOverlayContent = $overlayContent
        $script:LoadingCard           = $overlayContent.FindName("LoadingCard")
        $script:LoadingText           = $overlayContent.FindName("LoadingText")
        $script:LoadingProgress       = $overlayContent.FindName("LoadingProgress")

        Hide-LoadingOverlay

        Write-DebugLog "Loading overlay attached successfully." "SUCCESS"
    }
    catch {
        Write-DebugLog "Failed attaching loading overlay: $($_.Exception.Message)" "ERROR"
    }
}

# This function is used later to trigger the fade-out animation.
function Fade-OutLoadingOverlay {
    if ($script:LoadingOverlay -eq $null) { return }

    try {
        $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
        $fade.From = 1
        $fade.To = 0
        $fade.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(350))
        $script:LoadingOverlay.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
        Start-Sleep -Milliseconds 350
        Hide-LoadingOverlay
        $script:LoadingOverlay.Opacity = 1
        Write-DebugLog "Loading overlay hidden." "INFO"
    }
    catch {
        Write-DebugLog "Fade-out animation failed: $($_.Exception.Message)" "WARN"
        Hide-LoadingOverlay
    }
}

function New-CollapsibleCard {
    param(
        [Parameter(Mandatory)][string]$Header,
        [Parameter(Mandatory)][System.Collections.IEnumerable]$ContentLines
    )

    # Build the result card fully in code instead of relying on the custom Expander template.
    # This avoids name-scope/template issues that can make the ResultsPanel appear empty.
    $card = New-Object System.Windows.Controls.Border
    $card.CornerRadius = New-Object System.Windows.CornerRadius(14)
    $card.Padding = New-Object System.Windows.Thickness(14)
    $card.Margin = New-Object System.Windows.Thickness(0,0,0,16)
    $card.BorderThickness = New-Object System.Windows.Thickness(1)

    $glass = Get-AppResource "GlassCard"
    if ($glass) { $card.Background = $glass } else { $card.Background = [System.Windows.Media.Brushes]::Transparent }

    $borderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(0x66,0x7F,0xB8,0xE8))
    $card.BorderBrush = $borderBrush

    $outer = New-Object System.Windows.Controls.StackPanel

    $titleBlock = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text = $Header
    $titleBlock.FontSize = 22
    $titleBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
    $titleBlock.Foreground = [System.Windows.Media.Brushes]::White
    $titleBlock.Margin = New-Object System.Windows.Thickness(0,0,0,10)
    $titleBlock.TextWrapping = "Wrap"

    $glow = Get-AppResource "GlowOrange"
    if ($glow) { $titleBlock.Effect = $glow }

    [void]$outer.Children.Add($titleBlock)

    $lineList = @($ContentLines)
    if (-not $lineList -or $lineList.Count -eq 0) {
        $lineList = @("No data returned.")
    }

    foreach ($line in $lineList) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = [string]$line
        $brush = Get-AppResource "TextMain"
        if ($brush) { $tb.Foreground = $brush } else { $tb.Foreground = [System.Windows.Media.Brushes]::White }
        $tb.FontSize = 16
        $tb.Margin = New-Object System.Windows.Thickness(4,1,0,1)
        $tb.TextWrapping = "Wrap"
        [void]$outer.Children.Add($tb)
    }

    $card.Child = $outer
    return $card
}

# =====================================================================
# BACKEND LOOKUP FUNCTIONS (AD / EXCHANGE / GRAPH)
# =====================================================================
function _SafeLine {
    param([string]$Value)
    if ([String]::IsNullOrWhiteSpace($Value)) { return "-" }
    return $Value.Trim()
}

function Find-Element {
    param(
        $root,
        [string]$name
    )

    if ($root -eq $null) { return $null }

    # If this element has the Name property and it matches, return it
    if ($root.Name -eq $name) { return $root }

    # If this element is a Panel (StackPanel, Grid, etc.)
    if ($root -is [System.Windows.Controls.Panel]) {
        foreach ($child in $root.Children) {
            $found = Find-Element $child $name
            if ($found) { return $found }
        }
    }

    # If this element is a ContentControl (Border, Button, Window, etc.)
    if ($root -is [System.Windows.Controls.ContentControl]) {
        $child = $root.Content
        if ($child) {
            $found = Find-Element $child $name
            if ($found) { return $found }
        }
    }

    # If this element is a Decorator (e.g., ScrollViewer, Border)
    if ($root -is [System.Windows.Controls.Decorator]) {
        $child = $root.Child
        if ($child) {
            $found = Find-Element $child $name
            if ($found) { return $found }
        }
    }

    # If this element is an ItemsControl (ListBox, ListView, etc.)
    
	if ($root -is [System.Windows.Controls.ItemsControl]) {
		foreach ($child in $root.Items) {
			if ($child -is [System.Windows.DependencyObject]) {
				$found = Find-Element $child $name
				if ($found) { return $found }
			}
		}
	}


    return $null
}


function Format-ADValue {
    param($Value)
    if ($null -eq $Value) { return '-' }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return '-' }
    return $s.Trim()
}


function Select-ADUserMatch {
    param(
        [Parameter(Mandatory)][array]$Matches,
        [Parameter(Mandatory)][string]$SearchText
    )

    $list = @($Matches | Sort-Object Surname,GivenName,SamAccountName | Select-Object -First 50 | ForEach-Object {
        [PSCustomObject]@{
            FirstName      = Format-ADValue $_.GivenName
            LastName       = Format-ADValue $_.Surname
            SamAccountName = Format-ADValue $_.SamAccountName
            DisplayName    = Format-ADValue $_.DisplayName
            Mail           = Format-ADValue $_.Mail
            SourceObject   = $_
        }
    })

    if ($list.Count -eq 0) { return $null }
    if ($list.Count -eq 1) { return $list[0].SourceObject }

    try {
        $win = New-Object System.Windows.Window
        $win.Title = "Choose matching user"
        $win.Width = 720
        $win.Height = 430
        $win.WindowStartupLocation = "CenterOwner"
        $win.ResizeMode = "CanResize"
        $win.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x08,0x1B,0x35))
        $win.Foreground = [System.Windows.Media.Brushes]::White
        if ($script:MainWindow) { $win.Owner = $script:MainWindow }

        $root = New-Object System.Windows.Controls.Grid
        $root.Margin = New-Object System.Windows.Thickness(16)
        $row0 = New-Object System.Windows.Controls.RowDefinition
        $row0.Height = [System.Windows.GridLength]::Auto
        $row1 = New-Object System.Windows.Controls.RowDefinition
        $row1.Height = New-Object System.Windows.GridLength -ArgumentList 1, ([System.Windows.GridUnitType]::Star)
        $row2 = New-Object System.Windows.Controls.RowDefinition
        $row2.Height = [System.Windows.GridLength]::Auto
        $root.RowDefinitions.Add($row0)
        $root.RowDefinitions.Add($row1)
        $root.RowDefinitions.Add($row2)

        $header = New-Object System.Windows.Controls.TextBlock
        $header.Text = "Multiple users matched '$SearchText'. Select the correct user."
        $header.FontSize = 18
        $header.FontWeight = [System.Windows.FontWeights]::SemiBold
        $header.Foreground = [System.Windows.Media.Brushes]::White
        $header.Margin = New-Object System.Windows.Thickness(0,0,0,12)
        [System.Windows.Controls.Grid]::SetRow($header,0)
        [void]$root.Children.Add($header)

        $lv = New-Object System.Windows.Controls.ListView
        $lv.Margin = New-Object System.Windows.Thickness(0,0,0,12)
        $gv = New-Object System.Windows.Controls.GridView
        foreach ($c in @(
            @{ Header='First Name'; Binding='FirstName'; Width=150 },
            @{ Header='Last Name'; Binding='LastName'; Width=150 },
            @{ Header='SAM Account'; Binding='SamAccountName'; Width=160 },
            @{ Header='Display Name'; Binding='DisplayName'; Width=220 }
        )) {
            $col = New-Object System.Windows.Controls.GridViewColumn
            $col.Header = $c.Header
            $col.Width = $c.Width
            $col.DisplayMemberBinding = New-Object System.Windows.Data.Binding($c.Binding)
            [void]$gv.Columns.Add($col)
        }
        $lv.View = $gv
        foreach ($item in $list) { [void]$lv.Items.Add($item) }
        $lv.SelectedIndex = 0
        [System.Windows.Controls.Grid]::SetRow($lv,1)
        [void]$root.Children.Add($lv)

        $buttons = New-Object System.Windows.Controls.StackPanel
        $buttons.Orientation = 'Horizontal'
        $buttons.HorizontalAlignment = 'Right'
        $ok = New-Object System.Windows.Controls.Button
        $ok.Content = 'Use Selected User'
        $ok.Width = 150
        $ok.Height = 34
        $ok.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $cancel = New-Object System.Windows.Controls.Button
        $cancel.Content = 'Cancel'
        $cancel.Width = 90
        $cancel.Height = 34
        [void]$buttons.Children.Add($ok)
        [void]$buttons.Children.Add($cancel)
        [System.Windows.Controls.Grid]::SetRow($buttons,2)
        [void]$root.Children.Add($buttons)

        $ok.Add_Click({ if ($lv.SelectedItem) { $win.Tag = $lv.SelectedItem; $win.DialogResult = $true; $win.Close() } })
        $cancel.Add_Click({ $win.DialogResult = $false; $win.Close() })
        $lv.Add_MouseDoubleClick({ if ($lv.SelectedItem) { $win.Tag = $lv.SelectedItem; $win.DialogResult = $true; $win.Close() } })

        $win.Content = $root
        $result = $win.ShowDialog()
        if ($result -eq $true -and $win.Tag) { return $win.Tag.SourceObject }
        return $null
    }
    catch {
        Write-DebugLog "User match picker failed: $($_.Exception.Message). Falling back to first match." "WARN"
        return $list[0].SourceObject
    }
}

function Resolve-ADUserIdentity {
    param([string]$Identity)

    if ([string]::IsNullOrWhiteSpace($Identity)) { return $null }
    $q = $Identity.Trim()
    $ql = $q.ToLowerInvariant()

    if ($script:ADUserCacheLoaded) {
        if ($script:ADUserCacheBySam.ContainsKey($ql)) { return $script:ADUserCacheBySam[$ql] }
        if ($script:ADUserCacheByMail.ContainsKey($ql)) { return $script:ADUserCacheByMail[$ql] }

        $matches = @($script:ADUserCache | Where-Object {
            $_.DisplayName -like "*$q*" -or
            $_.GivenName -like "*$q*" -or
            $_.Surname -like "*$q*" -or
            $_.SamAccountName -like "*$q*" -or
            $_.Mail -like "*$q*" -or
            $_.UserPrincipalName -like "*$q*"
        })

        if ($matches.Count -eq 1) { return $matches[0] }
        if ($matches.Count -gt 1) { return (Select-ADUserMatch -Matches $matches -SearchText $q) }
    }

    try {
        return Get-ADUser -Identity $q -Properties DisplayName,GivenName,Surname,SamAccountName,UserPrincipalName,Mail,DistinguishedName -ErrorAction Stop
    }
    catch {
        try {
            $safe = $q.Replace("'","''")
            $matches = @(Get-ADUser -Filter "SamAccountName -like '*$safe*' -or GivenName -like '*$safe*' -or Surname -like '*$safe*' -or DisplayName -like '*$safe*' -or Mail -like '*$safe*' -or UserPrincipalName -like '*$safe*'" `
                -Properties DisplayName,GivenName,Surname,SamAccountName,UserPrincipalName,Mail,DistinguishedName `
                -ErrorAction Stop)
            if ($matches.Count -eq 1) { return $matches[0] }
            if ($matches.Count -gt 1) { return (Select-ADUserMatch -Matches $matches -SearchText $q) }
            return $null
        }
        catch { return $null }
    }
}

function Resolve-ManagerDisplayName {
    param($ManagerValue)

    if ($null -eq $ManagerValue -or [string]::IsNullOrWhiteSpace([string]$ManagerValue)) { return '-' }

    try {
        $mgr = Get-ADUser -Identity $ManagerValue -Properties DisplayName,SamAccountName -ErrorAction Stop
        if ($mgr.DisplayName) { return "$($mgr.DisplayName) ($($mgr.SamAccountName))" }
        return $mgr.SamAccountName
    }
    catch { return [string]$ManagerValue }
}

function Get-CurrentLookupIdentity {
    if (-not [string]::IsNullOrWhiteSpace($script:LastLookupIdentity)) { return $script:LastLookupIdentity }
    if ($script:SummarySam -and -not [string]::IsNullOrWhiteSpace($script:SummarySam.Text) -and $script:SummarySam.Text -ne '-') { return $script:SummarySam.Text }
    return $null
}


function Invoke-GraphGet {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [switch]$Delegated
    )

    $token = $script:GraphAppAccessToken
    $tokenType = "app-only"

    if ($Delegated) {
        $token = $script:GraphDelegatedAccessToken
        $tokenType = "delegated"
    }

    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Graph $tokenType token is not available. Enable delegated admin mode for PIM/Azure role lookups, or verify app-only Graph startup authentication."
    }

    return Invoke-RestMethod -Method GET -Uri $Uri -Headers @{
        Authorization    = "Bearer $token"
        ConsistencyLevel = "eventual"
    } -ErrorAction Stop
}



function Get-GraphPagedResults {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [switch]$Delegated
    )

    $items = @()
    $next = $Uri

    while (-not [string]::IsNullOrWhiteSpace($next)) {
        $resp = Invoke-GraphGet -Uri $next -Delegated:$Delegated
        if ($resp.value) { $items += @($resp.value) }
        $next = $resp.'@odata.nextLink'
    }

    return $items
}

function Get-GraphRoleDefinitionMap {
    param([switch]$Delegated)

    $map = @{}
    try {
        $defs = Get-GraphPagedResults -Uri "https://graph.microsoft.us/v1.0/roleManagement/directory/roleDefinitions?`$select=id,displayName" -Delegated:$Delegated
        foreach ($d in $defs) {
            if ($d.id -and -not $map.ContainsKey($d.id)) { $map[$d.id] = $d.displayName }
        }
    }
    catch {
        Write-DebugLog "Unable to build role definition map: $($_.Exception.Message)" "WARN"
    }
    return $map
}


$script:FriendlySkuNames = @{
    "M365_G3_GOV"        = "Microsoft 365 G3 for Government"
    "M365_E3_GOV"        = "Microsoft 365 E3 for Government"
    "M365_E5_GOV"        = "Microsoft 365 E5 for Government"
    "OFFICESUBSCRIPTION_GCC" = "Office GCC Subscription"
    "ENTERPRISEPACK_GOV" = "Office 365 E3 GCC"
    "ENTERPRISEPREMIUM_GOV" = "Office 365 E5 GCC"
    "SPE_E5_GOV"         = "Microsoft 365 E5 Security + Compliance (Gov)"
    "EMS_GOV"            = "Enterprise Mobility + Security GCC"
    "EMS_GOV_E5"         = "Enterprise Mobility + Security E5 GCC"
}


function Get-LicenseSkuMap {
    $map = @{}
    try {
        $skus = Get-GraphPagedResults -Uri "https://graph.microsoft.us/v1.0/subscribedSkus?`$select=skuId,skuPartNumber" 
        foreach ($sku in $skus) {
            if ($sku.skuId -and -not $map.ContainsKey([string]$sku.skuId)) {
                $map[[string]$sku.skuId] = $sku.skuPartNumber
            }
        }
    }
    catch {
        Write-DebugLog "Unable to retrieve subscribed SKUs: $($_.Exception.Message)" "WARN"
    }
    return $map
}

function Get-DelegatedGraphScopes {
    return "https://graph.microsoft.us/User.Read https://graph.microsoft.us/Directory.Read.All https://graph.microsoft.us/RoleManagement.Read.Directory https://graph.microsoft.us/PrivilegedAccess.Read.AzureAD"
}

function Get-DelegatedGraphScopeNames {
    return @(
        "User.Read",
        "Directory.Read.All",
        "RoleManagement.Read.Directory",
        "PrivilegedAccess.Read.AzureAD"
    )
}

function ConvertTo-Base64Url {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}

function New-PkceVerifier {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ConvertTo-Base64Url -Bytes $bytes
}

function New-PkceChallenge {
    param([Parameter(Mandatory)][string]$Verifier)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Verifier)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ConvertTo-Base64Url -Bytes $hash
}

function Invoke-DelegatedGraphBrowserAuth {
    param(
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string[]]$Scopes
    )

    $listener = $null
    $client = $null

    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $port = $listener.LocalEndpoint.Port
        $redirectUri = "http://localhost:$port/"

        $state = [guid]::NewGuid().ToString('N')
        $verifier = New-PkceVerifier
        $challenge = New-PkceChallenge -Verifier $verifier
        $scopeText = [string]::Join(' ', $Scopes)

        $authorizeUri = "https://login.microsoftonline.us/$($script:GraphTenantId)/oauth2/v2.0/authorize?" +
            "client_id=$([System.Uri]::EscapeDataString($ClientId))" +
            "&response_type=code" +
            "&redirect_uri=$([System.Uri]::EscapeDataString($redirectUri))" +
            "&response_mode=query" +
            "&scope=$([System.Uri]::EscapeDataString($scopeText))" +
            "&state=$state" +
            "&code_challenge=$challenge" +
            "&code_challenge_method=S256" +
            "&prompt=select_account"

        Write-DebugLog "Opening system browser for delegated Graph auth without WAM. Redirect URI: $redirectUri" "INFO"
        Start-Process $authorizeUri | Out-Null

        $acceptTask = $listener.AcceptTcpClientAsync()
        $deadline = (Get-Date).AddMinutes(5)
        while (-not $acceptTask.IsCompleted) {
            if ((Get-Date) -gt $deadline) { throw "Interactive delegated authentication timed out waiting for the browser redirect." }
            Start-Sleep -Milliseconds 100
            Do-Events
        }

        $client = $acceptTask.Result
        $stream = $client.GetStream()
        $reader = [System.IO.StreamReader]::new($stream)
        $requestLine = $reader.ReadLine()
        while (-not [string]::IsNullOrWhiteSpace($reader.ReadLine())) { }

        if ([string]::IsNullOrWhiteSpace($requestLine)) { throw "No browser redirect request was received." }
        $parts = $requestLine.Split(' ')
        if ($parts.Count -lt 2) { throw "Unexpected browser redirect request: $requestLine" }

        $localUri = [System.Uri]::new("http://localhost:$port$($parts[1])")
        $query = [System.Web.HttpUtility]::ParseQueryString($localUri.Query)

        $html = "<html><body style='font-family:Segoe UI;background:#081B35;color:white'><h2>Atlas delegated admin sign-in complete.</h2><p>You may return to the dashboard.</p></body></html>"
        if ($query['error']) {
            $html = "<html><body style='font-family:Segoe UI;background:#2b0d14;color:white'><h2>Atlas delegated admin sign-in failed.</h2><p>$($query['error_description'])</p></body></html>"
        }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($html.Length)`r`nConnection: close`r`n`r`n$html")
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()

        if ($query['error']) { throw "Delegated authentication failed: $($query['error']) - $($query['error_description'])" }
        if ($query['state'] -ne $state) { throw "Delegated authentication failed state validation." }
        $code = $query['code']
        if ([string]::IsNullOrWhiteSpace($code)) { throw "Delegated authentication completed but no authorization code was returned." }

        $tokenUri = "https://login.microsoftonline.us/$($script:GraphTenantId)/oauth2/v2.0/token"
        $token = Invoke-RestMethod -Method POST -Uri $tokenUri -ContentType "application/x-www-form-urlencoded" -Body @{
            client_id     = $ClientId
            grant_type    = "authorization_code"
            code          = $code
            redirect_uri  = $redirectUri
            scope         = $scopeText
            code_verifier = $verifier
        } -ErrorAction Stop

        if (-not $token.access_token) { throw "Delegated token request completed but no access_token was returned." }
        return $token
    }
    finally {
        try { if ($client) { $client.Close() } } catch {}
        try { if ($listener) { $listener.Stop() } } catch {}
    }
}

function Enable-DelegatedAdminMode {

    if ($Global:NoNet) {
        [System.Windows.MessageBox]::Show("NoNet mode is enabled. Delegated admin mode cannot connect to Graph.", "Delegated Admin Mode", "OK", "Warning") | Out-Null
        return
    }

    try {
        Write-DebugLog "Starting delegated Graph browser authentication with PKCE. WAM is bypassed completely." "INFO"

        Add-Type -AssemblyName System.Web

        $scopes = Get-DelegatedGraphScopes -split ' '
        $clientId = $script:GraphDelegatedClientId
        $usedClient = $clientId

        if ([string]::IsNullOrWhiteSpace($clientId)) {
            # Microsoft Graph PowerShell public client. This avoids requiring your confidential app to be reused as a native client.
            $clientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
            $usedClient = "Microsoft Graph PowerShell public client"
            Write-DebugLog "No delegated_client_id configured; using Microsoft Graph PowerShell public client ID $clientId." "WARN"
        }
        else {
            Write-DebugLog "Using configured delegated_client_id for browser PKCE auth: $clientId" "INFO"
        }

        $token = Invoke-DelegatedGraphBrowserAuth -ClientId $clientId -Scopes $scopes

        $script:GraphDelegatedAccessToken = $token.access_token
        $script:GraphDelegatedModeEnabled = $true
        $script:GraphDelegatedAdminUpn = $null

        try {
            $me = Invoke-GraphGet -Uri "https://graph.microsoft.us/v1.0/me?`$select=userPrincipalName,displayName" -Delegated
            if ($me.userPrincipalName) { $script:GraphDelegatedAdminUpn = $me.userPrincipalName }
        } catch {}

        $who = if ($script:GraphDelegatedAdminUpn) { $script:GraphDelegatedAdminUpn } else { "delegated admin" }
        Write-DebugLog "Delegated admin mode enabled as $who using $usedClient. WAM was not used." "SUCCESS"
    }
    catch {
        $script:GraphDelegatedAccessToken = $null
        $script:GraphDelegatedModeEnabled = $false
        Write-DebugLog "Delegated admin mode failed: $($_.Exception.Message)" "ERROR"
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Delegated Admin Mode Failed", "OK", "Error") | Out-Null
    }
}

function Show-HamburgerMenu {
    if (-not $script:HamburgerButton) { return }

    $menu = New-Object System.Windows.Controls.ContextMenu

    $delegated = New-Object System.Windows.Controls.MenuItem
    $delegated.Header = if ($script:GraphDelegatedModeEnabled) { "Delegated Admin Mode Enabled" } else { "Enable Delegated Admin Mode" }
    $delegated.IsEnabled = -not $script:GraphDelegatedModeEnabled
    $delegated.Add_Click({ Enable-DelegatedAdminMode })
    [void]$menu.Items.Add($delegated)

    $debug = New-Object System.Windows.Controls.MenuItem
    $debug.Header = if ($Global:DebugMode) { "Hide Debug Panel" } else { "Show Debug Panel" }
    $debug.Add_Click({ Toggle-DebugMode })
    [void]$menu.Items.Add($debug)

    $menu.PlacementTarget = $script:HamburgerButton
    $menu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
    $menu.IsOpen = $true
}


function Resolve-GraphUser {
    param([string]$Identity)

    Write-DebugLog "Resolve-GraphUser: $Identity" "INFO"

    if ($Global:NoNet) {
        throw "NoNet mode: Graph resolution disabled."
    }

    try {
        $ad = Resolve-ADUserIdentity $Identity
        if (-not $ad) { throw "Could not resolve identity '$Identity' in AD." }

        $filters = @()
        $immutable = $null

        if ($ad.ObjectGUID) {
            $immutable = [System.Convert]::ToBase64String($ad.ObjectGUID.ToByteArray())
            $filters += "onPremisesImmutableId eq '$immutable'"
        }
        if ($ad.Mail) {
            $safeMail = $ad.Mail.Replace("'","''")
            $filters += "mail eq '$safeMail'"
        }
        if ($ad.UserPrincipalName) {
            $safeUpn = $ad.UserPrincipalName.Replace("'","''")
            $filters += "userPrincipalName eq '$safeUpn'"
        }
        if ($ad.DisplayName) {
            $safeName = $ad.DisplayName.Replace("'","''")
            $filters += "startsWith(displayName,'$safeName')"
        }

        if ($filters.Count -eq 0) { throw "No usable attributes available to build Graph lookup filter." }

        $filterString = [string]::Join(" or ", $filters)
        $encoded = [System.Uri]::EscapeDataString($filterString)
        $url = "https://graph.microsoft.us/v1.0/users?`$filter=$encoded&`$count=true&`$select=id,displayName,userPrincipalName,mail,onPremisesImmutableId"

        Write-DebugLog "Graph user lookup URL: $url" "INFO"
        $response = Invoke-GraphGet -Uri $url

        if (-not $response.value -or $response.value.Count -eq 0) {
            throw "User not found in AzureAD using GCC High filter set."
        }

        $best = $null
        if ($ad.Mail) { $best = $response.value | Where-Object { $_.mail -eq $ad.Mail } | Select-Object -First 1 }
        if (-not $best -and $ad.UserPrincipalName) { $best = $response.value | Where-Object { $_.userPrincipalName -eq $ad.UserPrincipalName } | Select-Object -First 1 }
        if (-not $best -and $immutable) { $best = $response.value | Where-Object { $_.onPremisesImmutableId -eq $immutable } | Select-Object -First 1 }
        if (-not $best) { $best = $response.value[0] }

        $select = "id,displayName,userPrincipalName,mail,accountEnabled,department,city,state,country,streetAddress,postalCode,employeeId,onPremisesImmutableId,passwordPolicies,assignedLicenses,licenseAssignmentStates,officeLocation,jobTitle,companyName,mobilePhone,businessPhones,usageLocation"
        $detailUrl = "https://graph.microsoft.us/v1.0/users/$($best.id)?`$select=$select"
        $detail = Invoke-GraphGet -Uri $detailUrl

        Write-DebugLog "Graph user resolved: $($detail.id)" "SUCCESS"
        return $detail
    }
    catch {
        Write-DebugLog "Resolve-GraphUser failed: $($_.Exception.Message)" "ERROR"
        throw
    }
}


function Show-OverviewCards {
    if (-not $script:LastLookupResults) {
        Show-NoUserMessage
        return
    }

    Clear-ResultCards

    Add-ResultCard -Title "AD Core Info" `
        -Lines $script:LastLookupResults.ADInfo

    Add-ResultCard -Title "AD Security Groups" `
        -Lines $script:LastLookupResults.ADGroups

    #
    # NEW SEPARATED AZURE GROUPS
    #
    Add-ResultCard -Title "Azure Groups — Security Groups" `
        -Lines $script:LastLookupResults.SecurityGroups

    Add-ResultCard -Title "Azure Groups — Mail-Enabled Security Groups" `
        -Lines $script:LastLookupResults.MailSecurityGroups

    Add-ResultCard -Title "Azure Groups — Distribution Groups" `
        -Lines $script:LastLookupResults.DistributionGroups

    #
    # OTHER GRAPH CARDS
    #
    Add-ResultCard -Title "Owned Distribution Groups" `
        -Lines $script:LastLookupResults.OwnedDistributionGroups

    Add-ResultCard -Title "Mailbox Delegations" `
        -Lines $script:LastLookupResults.MailboxDelegations

    Add-ResultCard -Title "Mail Forwarding" `
        -Lines $script:LastLookupResults.MailForwarding

    Add-ResultCard -Title "Direct Reports" `
        -Lines $script:LastLookupResults.DirectReports

    Add-ResultCard -Title "AzureAD Properties (Graph)" `
        -Lines $script:LastLookupResults.AzureProperties

    Add-ResultCard -Title "AzureAD Roles" `
        -Lines $script:LastLookupResults.AzureRoles
}

function Resolve-ExchangeIdentity {
    param([string]$Identity)

    Write-DebugLog "Resolve-ExchangeIdentity: $Identity" "INFO"

    # Avoid Exchange cmdlets entirely; they can trigger implicit EXO connection hangs.
    # Return the best AD-backed mail identity for display/manual EXO use.
    try {
        $ad = Resolve-ADUserIdentity $Identity
        if ($ad) {
            if (-not [string]::IsNullOrWhiteSpace($ad.Mail)) { return [string]$ad.Mail }
            if (-not [string]::IsNullOrWhiteSpace($ad.UserPrincipalName)) { return [string]$ad.UserPrincipalName }
            if (-not [string]::IsNullOrWhiteSpace($ad.SamAccountName)) { return [string]$ad.SamAccountName }
        }
    } catch {}

    if (-not [string]::IsNullOrWhiteSpace($Identity)) { return $Identity.Trim() }
    return $null
}




function Resolve-GraphGroupName {
    param(
        [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('ObjectId','Id','GroupId','AssignedByGroup')]
        $AssignedByGroupRaw
    )

    if ($null -eq $AssignedByGroupRaw) { return "Direct" }

    $groupId = $null

    if ($AssignedByGroupRaw -is [string]) {
        $raw = $AssignedByGroupRaw.Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { return "Direct" }
        if ($raw -match '^[0-9a-fA-F-]{36}$') { $groupId = $raw }
        else {
            $guidMatch = [regex]::Match($raw, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
            if ($guidMatch.Success) { $groupId = $guidMatch.Value } else { return $raw }
        }
    }
    elseif ($AssignedByGroupRaw -is [pscustomobject] -and $AssignedByGroupRaw.PSObject.Properties['id']) {
        $groupId = [string]$AssignedByGroupRaw.id
    }
    elseif ($AssignedByGroupRaw -is [pscustomobject] -and $AssignedByGroupRaw.PSObject.Properties['directoryObjectId']) {
        $groupId = [string]$AssignedByGroupRaw.directoryObjectId
    }
    elseif ($AssignedByGroupRaw -is [pscustomobject] -and $AssignedByGroupRaw.PSObject.Properties['@odata.id']) {
        $groupId = [string](($AssignedByGroupRaw.'@odata.id' -split '/')[-1])
    }
    else {
        $raw = [string]$AssignedByGroupRaw
        $guidMatch = [regex]::Match($raw, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
        if ($guidMatch.Success) { $groupId = $guidMatch.Value } else { return $raw }
    }

    $groupId = ([string]$groupId).Trim()

    # Graph returns null/empty for direct assignments and can return the all-zero GUID for some states.
    # Do not call /groups/{id} unless we have a real GUID; otherwise Graph returns 400 Bad Request.
    if ([string]::IsNullOrWhiteSpace($groupId)) { return "Direct" }
    if ($groupId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { return $groupId }
    if ($groupId -eq '00000000-0000-0000-0000-000000000000') { return "Direct" }

    if (-not $script:GraphGroupNameCache) { $script:GraphGroupNameCache = @{} }
    if ($script:GraphGroupNameCache.ContainsKey($groupId)) { return $script:GraphGroupNameCache[$groupId] }

    try {
        $url = "https://graph.microsoft.us/v1.0/groups/$groupId?`$select=id,displayName"
        $resp = Invoke-GraphGet -Uri $url
        $name = if ($resp.displayName) { [string]$resp.displayName } else { $groupId }
        $script:GraphGroupNameCache[$groupId] = $name
        return $name
    }
    catch {
        Write-DebugLog "Unable to resolve license assignment group $groupId`: $($_.Exception.Message)" "WARN"
        $script:GraphGroupNameCache[$groupId] = $groupId
        return $groupId
    }
}


# =====================================================================
# ACTIVE DIRECTORY — CORE INFO
# =====================================================================
function Get-ADInfo {
    param([string]$Identity)

    Write-DebugLog "Get-ADInfo: $Identity" "INFO"
    $lines = @()

    if ($Global:NoNet) {
        return @("NoNet mode: AD lookups disabled.")
    }

    try {
        $resolved = Resolve-ADUserIdentity $Identity
        if (-not $resolved) { throw "Unable to resolve user '$Identity'." }

        $props = @(
            'DisplayName','GivenName','Surname','SamAccountName','UserPrincipalName','Mail','DistinguishedName',
            'Enabled','Title','Department','Company','Office','physicalDeliveryOfficeName',
            'City','State','StreetAddress','PostalCode','Country','telephoneNumber','mobile',
            'EmployeeID','BadgeID','Manager','Description','whenCreated','LastLogonDate',
            'extensionAttribute1','extensionAttribute2','extensionAttribute3','extensionAttribute4','extensionAttribute5',
            'extensionAttribute6','extensionAttribute7','extensionAttribute8','extensionAttribute9','extensionAttribute10',
            'extensionAttribute11','extensionAttribute12','extensionAttribute13','extensionAttribute14','extensionAttribute15'
        )

        $user = Get-ADUser -Identity $resolved.SamAccountName -Properties $props -ErrorAction Stop

        $office = $user.Office
        if ([string]::IsNullOrWhiteSpace($office)) { $office = $user.physicalDeliveryOfficeName }

        $badge = $user.BadgeID

        $lines += "Display Name:      $(Format-ADValue $user.DisplayName)"
        $lines += "SAM Account:       $(Format-ADValue $user.SamAccountName)"
        $lines += "UPN:               $(Format-ADValue $user.UserPrincipalName)"
        $lines += "Email:             $(Format-ADValue $user.Mail)"
        $lines += "Enabled:           $(Format-ADValue $user.Enabled)"
        $lines += "Title:             $(Format-ADValue $user.Title)"
        $lines += "Department:        $(Format-ADValue $user.Department)"
        $lines += "Company:           $(Format-ADValue $user.Company)"
        $lines += "Office:            $(Format-ADValue $office)"
        $lines += "EmployeeID:        $(Format-ADValue $user.EmployeeID)"
        $lines += "BadgeID:           $(Format-ADValue $badge)"
        $lines += "Manager:           $(Resolve-ManagerDisplayName $user.Manager)"
        $lines += "Phone:             $(Format-ADValue $user.telephoneNumber)"
        $lines += "Mobile:            $(Format-ADValue $user.mobile)"
        $lines += "Street:            $(Format-ADValue $user.StreetAddress)"
        $lines += "City:              $(Format-ADValue $user.City)"
        $lines += "State:             $(Format-ADValue $user.State)"
        $lines += "Postal Code:       $(Format-ADValue $user.PostalCode)"
        $lines += "Country:           $(Format-ADValue $user.Country)"
        $lines += "Created:           $(Format-ADValue $user.whenCreated)"
        $lines += "Last Logon:        $(Format-ADValue $user.LastLogonDate)"
        $lines += "Description:       $(Format-ADValue $user.Description)"
        $lines += "DN:                $(Format-ADValue $user.DistinguishedName)"
    }
    catch {
        $lines += "ERROR: Unable to retrieve AD base info: $($_.Exception.Message)"
    }

    return $lines
}

# =====================================================================
# ACTIVE DIRECTORY — GROUP MEMBERSHIP
# =====================================================================
function Get-ADGroups {
    param([string]$Identity)

    Write-DebugLog "Get-ADGroups: $Identity" "INFO"
    $lines = @()

    if ($Global:NoNet) { return @("NoNet mode: AD groups disabled.") }

    try {
        $groups = Get-ADPrincipalGroupMembership -Identity $Identity | Sort-Object Name

        if (-not $groups -or $groups.Count -eq 0) {
            $lines += "No AD security groups found."
        }
        else {
            foreach ($g in $groups) { $lines += $g.Name }
        }
    }
    catch {
        $lines += "ERROR: $($_.Exception.Message)"
    }

    return $lines
}

# =====================================================================
# Graph  — AZURE GROUP MEMBERSHIP
# =====================================================================
function Get-AzureGroups {
    param([string]$Identity)

    Write-DebugLog "Get-AzureGroups (Graph): $Identity" "INFO"

    if ($Global:NoNet) { 
        return @{ 
            SecurityGroups = @("NoNet mode") 
            MailSecurityGroups = @("NoNet mode")
            DistributionGroups = @("NoNet mode")
        }
    }

    try {
        #
        # Resolve Graph user
        #
        $u = Resolve-GraphUser $Identity
        if (-not $u.id) { throw "Graph user lookup failed." }

        #
        # Query groups via Microsoft Graph
        #
        $url = "https://graph.microsoft.us/v1.0/users/$($u.id)/memberOf"
        $resp = Invoke-GraphGet -Uri $url

        if (-not $resp.value) {
            throw "No group memberships returned from Graph."
        }

        #
        # Output containers
        #
        $Security = @()
        $MailSecurity = @()
        $Distro = @()

        #
        # Categorize each group
        #
        foreach ($g in $resp.value) {

            # Only process AAD groups
            if ($g.'@odata.type' -ne "#microsoft.graph.group") { continue }

            $name = $g.displayName
            $sec  = $g.securityEnabled -eq $true
            $mail = $g.mailEnabled     -eq $true
            $unified = $g.groupTypes -contains "Unified"

            # Skip M365 Unified Groups unless you want them
            if ($unified) { continue }

            # Security group only
            if ($sec -and -not $mail) {
                $Security += $name
                continue
            }

            # Mail-enabled security group
            if ($sec -and $mail) {
                $MailSecurity += $name
                continue
            }

            # Distribution group (DL)
            if (-not $sec -and $mail) {
                $Distro += $name
                continue
            }
        }

        #
        # Sort groups
        #
        $Security      = $Security      | Sort-Object
        $MailSecurity  = $MailSecurity  | Sort-Object
        $Distro        = $Distro        | Sort-Object

        #
        # Return as a structured object
        #
        return @{
            SecurityGroups       = $Security
            MailSecurityGroups   = $MailSecurity
            DistributionGroups   = $Distro
        }
    }
    catch {
        Write-DebugLog "Get-AzureGroups failed: $($_.Exception.Message)" "ERROR"
        return @{
            SecurityGroups       = @("ERROR: $($_.Exception.Message)")
            MailSecurityGroups   = @("ERROR: $($_.Exception.Message)")
            DistributionGroups   = @("ERROR: $($_.Exception.Message)")
        }
    }
}

# =====================================================================
# EXCHANGE — DISTRIBUTION GROUP OWNERSHIP
# =====================================================================

function Get-OwnedDistributionGroups {
    param([string]$Identity)

    Write-DebugLog "Get-OwnedDistributionGroups (Graph): $Identity" "INFO"
    $lines = @()

    if ($Global:NoNet) { return @("NoNet mode: Owned DG lookup disabled.") }

    try {
        # Do NOT enumerate every distribution group in Exchange Online here.
        # On larger tenants that can appear to hang because Get-DistributionGroup -ResultSize Unlimited
        # walks the entire tenant and then filters locally. Graph ownedObjects is targeted to this user.
        Set-LoadingStatus "Loading owned distribution groups from Graph..." 52

        $u = Resolve-GraphUser $Identity
        if (-not $u.id) { throw "Graph user lookup failed." }

        $select = "id,displayName,mail,mailEnabled,securityEnabled,groupTypes"
        $url = "https://graph.microsoft.us/v1.0/users/$($u.id)/ownedObjects/microsoft.graph.group?`$select=$select&`$top=999"
        $ownedGroups = @(Get-GraphPagedResults -Uri $url)

        $distributionGroups = @($ownedGroups | Where-Object {
            $_.mailEnabled -eq $true -and
            $_.securityEnabled -ne $true -and
            -not ($_.groupTypes -contains "Unified")
        } | Sort-Object displayName)

        if (-not $distributionGroups -or $distributionGroups.Count -eq 0) {
            return @("User does not own any distribution groups.")
        }

        foreach ($g in $distributionGroups) {
            $primary = if ($g.mail) { " <$($g.mail)>" } else { "" }
            $lines += "$($g.displayName)$primary"
        }
    }
    catch {
        Write-DebugLog "Graph owned DG lookup failed: $($_.Exception.Message)" "WARN"
        $lines += "ERROR: Unable to retrieve owned distribution groups through Graph: $($_.Exception.Message)"
        $lines += "This lookup no longer enumerates all Exchange Online distribution groups because that was causing hangs."
    }

    return $lines
}


# =====================================================================
# EXCHANGE — DELEGATED / ON-DEMAND SESSION CHECK
# =====================================================================
function Test-ExchangeOnlineConnected {
    try {
        if (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) {
            $ci = Get-ConnectionInformation -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Connected' } | Select-Object -First 1
            if ($ci) { return $true }
        }
    } catch {}
    return $false
}

function Ensure-ExchangeOnlineDelegatedSession {
    param([string]$UserPrincipalName)

    if ($Global:NoNet) { return $false }

    if (-not $script:GraphDelegatedModeEnabled) {
        Write-DebugLog "Exchange Online delegation lookup requires Delegated Admin Mode first." "WARN"
        return $false
    }

    try {
        return (Connect-ExchangeOnlineSafe -UserPrincipalName $UserPrincipalName)
    }
    catch {
        Write-DebugLog "Unable to establish Exchange Online delegated session: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# =====================================================================
# EXCHANGE — MAILBOX DELEGATIONS
# =====================================================================

function Get-MailboxDelegations {
    param([string]$Identity)

    Write-DebugLog "Get-MailboxDelegations (Exchange Online delegated): $Identity" "INFO"
    $lines = @()

    if ($Global:NoNet) { return @("NoNet mode: Mailbox delegation lookup disabled.") }

    if (-not $script:GraphDelegatedModeEnabled) {
        return @(
            "Enable Delegated Admin Mode to retrieve Exchange Online mailbox delegations.",
            "This lookup uses Exchange Online PowerShell with a delegated access token, not WAM/device-code auth."
        )
    }

    try {
        $ad = Resolve-ADUserIdentity $Identity
        if (-not $ad) { throw "Unable to resolve user '$Identity'." }

        $target = $ad.Mail
        if ([string]::IsNullOrWhiteSpace($target)) { $target = $ad.UserPrincipalName }
        if ([string]::IsNullOrWhiteSpace($target)) { $target = $ad.SamAccountName }
        if ([string]::IsNullOrWhiteSpace($target)) { throw "No mailbox identity was available for '$Identity'." }

        $adminUpn = $script:GraphDelegatedAdminUpn
        if ([string]::IsNullOrWhiteSpace($adminUpn)) { $adminUpn = $target }

        if (-not (Ensure-ExchangeOnlineDelegatedSession -UserPrincipalName $adminUpn)) {
            $why = if ($script:ExchangeOnlineConnectError) { $script:ExchangeOnlineConnectError } else { "unknown connection failure" }
            return @("ERROR: Unable to connect to Exchange Online delegated session: $why")
        }

        Set-LoadingStatus "Checking mailbox delegations..." 55

        $fullAccess = @()
        try {
            $fullAccess = @(Get-MailboxPermission -Identity $target -ErrorAction Stop | Where-Object {
                -not $_.IsInherited -and $_.User -notmatch 'NT AUTHORITY|S-1-5-.*' -and ($_.AccessRights -contains 'FullAccess')
            })
        }
        catch {
            $lines += "Full Access: ERROR: $($_.Exception.Message)"
        }

        if ($fullAccess.Count -gt 0) {
            $lines += "Full Access:"
            foreach ($p in $fullAccess | Sort-Object User) {
                $denyText = if ($p.Deny) { " (Deny)" } else { "" }
                $lines += "  $($p.User)$denyText"
            }
        }
        elseif (-not ($lines | Where-Object { $_ -like 'Full Access:*ERROR*' })) {
            $lines += "Full Access: None found"
        }

        $sendAs = @()
        try {
            $sendAs = @(Get-RecipientPermission -Identity $target -ErrorAction Stop | Where-Object {
                $_.Trustee -notmatch 'NT AUTHORITY|S-1-5-.*' -and ($_.AccessRights -contains 'SendAs')
            })
        }
        catch {
            $lines += "Send As: ERROR: $($_.Exception.Message)"
        }

        if ($sendAs.Count -gt 0) {
            $lines += "Send As:"
            foreach ($p in $sendAs | Sort-Object Trustee) {
                $denyText = if ($p.Deny) { " (Deny)" } else { "" }
                $lines += "  $($p.Trustee)$denyText"
            }
        }
        elseif (-not ($lines | Where-Object { $_ -like 'Send As:*ERROR*' })) {
            $lines += "Send As: None found"
        }

        try {
            $mbx = Get-Mailbox -Identity $target -ErrorAction Stop
            $sob = @($mbx.GrantSendOnBehalfTo) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            if ($sob.Count -gt 0) {
                $lines += "Send on Behalf:"
                foreach ($x in $sob) { $lines += "  $x" }
            }
            else {
                $lines += "Send on Behalf: None found"
            }
        }
        catch {
            $lines += "Send on Behalf: ERROR: $($_.Exception.Message)"
        }
    }
    catch {
        $lines += "ERROR: $($_.Exception.Message)"
    }

    return $lines
}





# =====================================================================
# EXCHANGE — MAIL FORWARDING
# =====================================================================
function Get-MailForwarding {
    param([string]$Identity)

    Write-DebugLog "Get-MailForwarding (Graph): $Identity" "INFO"
    $lines = @()

    if ($Global:NoNet) { return @("NoNet mode: Forwarding lookup disabled.") }

    try {
        $u = Resolve-GraphUser $Identity
        if (-not $u.id) { throw "Graph user lookup failed." }

        $url = "https://graph.microsoft.us/v1.0/users/$($u.id)/mailboxSettings"

        $resp = Invoke-GraphGet -Uri $url

        if ($resp.forwardingEnabled -eq $true) {
            $lines += "Forwarding Enabled: Yes"
            $lines += "Forwarding Address: $($resp.forwardingSmtpAddress)"
        }
        else {
            $lines += "Forwarding Enabled: No"
        }
    }
    catch {
        $lines += "ERROR: $($_.Exception.Message)"
    }

    return $lines
}


# =====================================================================
# ACTIVE DIRECTORY — DIRECT REPORTS
# =====================================================================
function Get-DirectReports {
    param([string]$Identity)

    Write-DebugLog "Get-DirectReports: $Identity" "INFO"
    $lines = @()

    if ($Global:NoNet) { return @("NoNet mode: Direct report lookup disabled.") }

    try {
        $user = Get-ADUser -Identity $Identity -Properties directReports -ErrorAction Stop

        if (-not $user.directReports -or $user.directReports.Count -eq 0) {
            $lines += "No direct reports found."
        }
        else {
            foreach ($dn in $user.directReports) {
                try {
                    $dr = Get-ADUser $dn -Properties DisplayName -ErrorAction Stop
                    $lines += $dr.DisplayName
                } 
                catch { 
                    $lines += "Unable to resolve: $dn" 
                }
            }
        }
    }
    catch {
        $lines += "ERROR: $($_.Exception.Message)"
    }

    return $lines
}

# =====================================================================
# AZURE AD — USER PROPERTIES
# =====================================================================

function Get-AzureProperties {
    param([string]$Identity)

    Write-DebugLog "Get-AzureProperties: $Identity" "INFO"
    $lines = @()

    if ($Global:NoNet) { return @("NoNet mode: Azure properties disabled.") }

    try {
        $user = Resolve-GraphUser $Identity
        if (-not $user) { throw "Graph returned no matching user for '$Identity'" }


        function Format-Line {
            param([string]$Label, $Value)
            if ($null -eq $Value -or [String]::IsNullOrWhiteSpace([string]$Value)) { 
                return ("{0}:    (no data)" -f $Label) 
            }
            return ("{0}:    {1}" -f $Label, $Value)
        }

        #
        # Friendly GCC High SKU names
        #
        $script:FriendlySkuNames = @{
            "VISIOCLIENT_USGOV_GCCHIGH"       = "Visio Plan 2 GCC High"
            "ENTERPRISEPACK_USGOV_GCCHIGH"    = "Office 365 E3 GCC High"
            "ATP_ENTERPRISE_USGOV_GCCHIGH"    = "Defender for Office 365 GCC High"
            "EMS_USGOV_GCCHIGH"               = "Enterprise Mobility + Security E3 GCC High"
            "MCOMEETADV_USGOV_GCCHIGH"        = "Audio Conferencing GCC High"
        }

        $skuMap = Get-LicenseSkuMap


        #
        # Header sections
        #
        $lines += "=== Identity ==="
        $lines += Format-Line "Display Name"        $user.displayName
        $lines += Format-Line "UPN"                 $user.userPrincipalName
        $lines += Format-Line "Mail"                $user.mail
        $lines += Format-Line "Account Enabled"     $user.accountEnabled

        $lines += ""
        $lines += "=== Job Information ==="
        $lines += Format-Line "Job Title"           $user.jobTitle
        $lines += Format-Line "Department"          $user.department
        $lines += Format-Line "Company"             $user.companyName

        $lines += ""
        $lines += "=== Location ==="
        $lines += Format-Line "Office Location"     $user.officeLocation
        $lines += Format-Line "City"                $user.city
        $lines += Format-Line "State"               $user.state
        $lines += Format-Line "Country"             $user.country
        $lines += Format-Line "Street"              $user.streetAddress
        $lines += Format-Line "Postal Code"         $user.postalCode
        $lines += Format-Line "Usage Location"      $user.usageLocation

        $lines += ""
        $lines += "=== Directory Metadata ==="
        $lines += Format-Line "Employee ID"         $user.employeeId
        $lines += Format-Line "Immutable ID"        $user.onPremisesImmutableId
        $lines += Format-Line "Password Policies"   $user.passwordPolicies


        #
        # License section
        #
        $lines += ""
        $lines += "=== Assigned Licenses ==="
        $licenseLines = @()

        # Convert skuId → friendly name
        function Convert-SkuId {
            param([string]$SkuId)

            if ($skuMap.ContainsKey($SkuId)) { 
                $part = $skuMap[$SkuId]
            }
            else { 
                return $SkuId 
            }

            if ($script:FriendlySkuNames.ContainsKey($part)) {
                return $script:FriendlySkuNames[$part]
            }

            return $part
        }

        #
        # AssignedLicenses (Direct Assignment)
        #
        foreach ($lic in @($user.assignedLicenses)) {
            $skuId = [string]$lic.skuId
            $name  = Convert-SkuId $skuId
            $licenseLines += "Assigned: $name (Direct)"
        }


        #
        # licenseAssignmentStates (Via Licensing Groups)
        #
        foreach ($state in @($user.licenseAssignmentStates)) {

            $skuId = [string]$state.skuId
            if ([string]::IsNullOrWhiteSpace($skuId)) { continue }
            $name  = Convert-SkuId $skuId

            $assignedByGroup = $null
            try { $assignedByGroup = $state.assignedByGroup } catch {}

            if (-not [string]::IsNullOrWhiteSpace([string]$assignedByGroup) -and [string]$assignedByGroup -ne '00000000-0000-0000-0000-000000000000') {
                $licenseLines += "Assigned: $name (Via Group)"
            }
        }


        #
        # Output
        #
        $licenseLines = @($licenseLines | Sort-Object -Unique)

        if ($licenseLines.Count -eq 0) {
            $lines += "(no assigned licenses found)"
        }
        else {
            $lines += $licenseLines
        }

    }
    catch {
        Write-DebugLog "AzureProperties failed: $($_.Exception.Message)" "ERROR"
        $lines += "ERROR: $($_.Exception.Message)"
    }

    return $lines
}
# =====================================================================
# AZURE AD — DIRECTORY ROLES
# =====================================================================


function Get-AzureRoles {
    param([string]$Identity)

    Write-DebugLog "Get-AzureRoles (Delegated PIM + Groups): $Identity" "INFO"
    $lines = @()

    if ($Global:NoNet) { return @("NoNet mode: Azure roles disabled.") }

    if (-not $script:GraphDelegatedModeEnabled) {
        return @(
            "Delegated Admin Mode is not enabled.",
            "Open the hamburger menu and choose 'Enable Delegated Admin Mode'.",
            "Azure AD Roles uses delegated Graph only because PIM and role-assignable group role checks cannot be completed with client-credentials app-only auth."
        )
    }

    try {
        $user = Resolve-GraphUser $Identity
        if (-not $user.id) { throw "Unable to resolve Graph user object ID." }
        $uid = $user.id

        $roleMap = Get-GraphRoleDefinitionMap -Delegated
        $results = @()

        # Direct active role assignments for the user.
        try {
            $directUrl = "https://graph.microsoft.us/v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$uid'&`$select=id,principalId,roleDefinitionId,directoryScopeId"
            $directAssignments = Get-GraphPagedResults -Uri $directUrl -Delegated
            foreach ($a in $directAssignments) {
                $roleName = if ($roleMap.ContainsKey($a.roleDefinitionId)) { $roleMap[$a.roleDefinitionId] } else { $a.roleDefinitionId }
                $results += "$roleName (Direct active assignment)"
            }
        }
        catch { $lines += "ERROR retrieving direct active roles: $($_.Exception.Message)" }

        # Role-assignable group path: get user's transitive groups, then role assignments for those group principals.
        try {
            $groupUrl = "https://graph.microsoft.us/v1.0/users/$uid/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName,isAssignableToRole"
            $groups = Get-GraphPagedResults -Uri $groupUrl -Delegated
            foreach ($g in @($groups)) {
                try {
                    $assignmentUrl = "https://graph.microsoft.us/v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$($g.id)'&`$select=id,principalId,roleDefinitionId,directoryScopeId"
                    $groupAssignments = Get-GraphPagedResults -Uri $assignmentUrl -Delegated
                    foreach ($a in $groupAssignments) {
                        $roleName = if ($roleMap.ContainsKey($a.roleDefinitionId)) { $roleMap[$a.roleDefinitionId] } else { $a.roleDefinitionId }
                        $results += "$roleName (via group: $($g.displayName))"
                    }
                } catch {}
            }
        }
        catch { $lines += "ERROR retrieving group-assigned roles: $($_.Exception.Message)" }

        # PIM active assignments.
        try {
            $pimActiveUrl = "https://graph.microsoft.us/beta/roleManagement/directory/roleAssignmentScheduleInstances?`$filter=principalId eq '$uid'"
            $pimActive = Get-GraphPagedResults -Uri $pimActiveUrl -Delegated
            foreach ($pa in $pimActive) {
                $roleName = if ($roleMap.ContainsKey($pa.roleDefinitionId)) { $roleMap[$pa.roleDefinitionId] } else { $pa.roleDefinitionId }
                $state = if ($pa.status) { $pa.status } else { "Active" }
                $results += "$roleName (PIM active: $state)"
            }
        }
        catch { $lines += "ERROR retrieving PIM active roles: $($_.Exception.Message)" }

        # PIM eligible assignments.
        try {
            $pimEligibleUrl = "https://graph.microsoft.us/beta/roleManagement/directory/roleEligibilityScheduleInstances?`$filter=principalId eq '$uid'"
            $pimEligible = Get-GraphPagedResults -Uri $pimEligibleUrl -Delegated
            foreach ($pe in $pimEligible) {
                $roleName = if ($roleMap.ContainsKey($pe.roleDefinitionId)) { $roleMap[$pe.roleDefinitionId] } else { $pe.roleDefinitionId }
                $results += "$roleName (PIM eligible)"
            }
        }
        catch { $lines += "ERROR retrieving PIM eligible roles: $($_.Exception.Message)" }

        $results = @($results | Sort-Object -Unique)
        if ($results.Count -eq 0 -and $lines.Count -eq 0) {
            $lines += "User holds no Azure AD directory roles returned by delegated Graph."
        }
        elseif ($results.Count -gt 0) {
            $lines += $results
        }
    }
    catch {
        $lines += "ERROR: $($_.Exception.Message)"
    }

    return $lines
}



# =====================================================================
# RESULT CARD BUILDERS
# =====================================================================
function Add-ResultCard {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Lines
    )

    try {
        if (-not $script:ResultsPanel) {
            $script:ResultsPanel = Find-Element -root $script:MainWindow -name "ResultsPanel"
        }
        if (-not $script:ResultsPanel) {
            throw "ResultsPanel is not mapped. Cannot add result card."
        }

        $lineArray = @($Lines)
        if (-not $lineArray -or $lineArray.Count -eq 0) { $lineArray = @("No data returned.") }

        $script:ResultsPanel.Dispatcher.Invoke([Action]{
            $card = New-CollapsibleCard -Header $Title -ContentLines $lineArray
            [void]$script:ResultsPanel.Children.Add($card)
            $script:ResultsPanel.UpdateLayout()
        })

        Write-DebugLog "Card added to ResultsPanel: $Title" "INFO"
    }
    catch {
        $msg = "Failed to add result card '$Title': $($_.Exception.Message)"
        Write-DebugLog $msg "ERROR"
        try {
            [System.Windows.MessageBox]::Show($msg, "Results Panel Error", "OK", "Error") | Out-Null
        } catch {}
    }
}

function Clear-ResultCards {
    try {
        if (-not $script:ResultsPanel) {
            $script:ResultsPanel = Find-Element -root $script:MainWindow -name "ResultsPanel"
        }
        if (-not $script:ResultsPanel) {
            throw "ResultsPanel is not mapped. Cannot clear result cards."
        }
        $script:ResultsPanel.Dispatcher.Invoke([Action]{
            $script:ResultsPanel.Children.Clear()
            $script:ResultsPanel.UpdateLayout()
        })
        Write-DebugLog "Result cards cleared." "INFO"
    }
    catch {
        Write-DebugLog "Failed clearing cards: $($_.Exception.Message)" "WARN"
    }
}

# =====================================================================
# ACTION PANEL ENGINE — MODERN GLASS ACTION CARDS (MEDIUM ELEVATION)
# =====================================================================



function Set-ActionPanelContent {
    param([System.Collections.IEnumerable]$CardDefinitions)

    # Find panel safely
    $script:ActionPanel = Find-Element -root $script:MainWindow -name "ActionPanel"

    if (-not $script:ActionPanel) {
        Write-Host "ERROR: ActionPanel not found." -ForegroundColor Red
        return
    }

    # FADE OUT OLD CONTENT (transition)
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fade.From = 1
    $fade.To   = 0
    $fade.Duration = "0:0:0.18"
    $script:ActionPanel.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)

    Start-Sleep -Milliseconds 180

    # Clear old menu
    $script:ActionPanel.Children.Clear()

    # Build new menu
    foreach ($card in $CardDefinitions) {

        $btn = New-Object System.Windows.Controls.Button
        $actionStyle = Get-AppResource "ActionCard"
        if ($actionStyle) {
            $btn.Style = $actionStyle
        }
        else {
            # Hard fallback so the action panel never reverts to classic gray buttons.
            $btn.Foreground = [System.Windows.Media.Brushes]::White
            $btn.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xFE,0x7A,0x00))
            $btn.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xFF,0xFE,0x50))
            $btn.BorderThickness = New-Object System.Windows.Thickness(1)
            $btn.FontSize = 20
            $btn.FontWeight = [System.Windows.FontWeights]::SemiBold
            $btn.Height = 58
            $btn.Padding = New-Object System.Windows.Thickness(18,10,18,10)
            $btn.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left
            $btn.Cursor = [System.Windows.Input.Cursors]::Hand
        }
        $btn.Content = $card.Label
        $btn.Margin = "0,0,0,12"

        if ($card.Action -is [scriptblock]) {
            $btn.Add_Click($card.Action)
        }
        else {
            $btn.Add_Click({
                Write-Host "Invalid menu action handler."
            })
        }

        $script:ActionPanel.Children.Add($btn)
    }

    # FADE IN NEW CONTENT
    $fadeIn = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fadeIn.From = 0
    $fadeIn.To   = 1
    $fadeIn.Duration = "0:0:0.18"
    $script:ActionPanel.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)
}

# ================================================================
# CREATE USER WIZARD LAUNCHER
# ================================================================
function Invoke-CreateUserWizard {
    try {
        Clear-ResultCards

        $wizardPath = Join-Path $ScriptRoot "New_User_Wizard.ps1"

        if (-not (Test-Path $wizardPath)) {
            Add-ResultCard -Title "Create User Wizard" -Lines @(
                "Result              : ERROR",
                "Message             : New_User_Wizard.ps1 was not found beside this console.",
                "Expected path       : $wizardPath",
                "Fix                 : Place New_User_Wizard.ps1 in the same folder as this console."
            )
            return
        }

        Add-ResultCard -Title "Create User Wizard" -Lines @(
            "Result              : Launching",
            "Path                : $wizardPath",
            "Mode                : Separate STA PowerShell process",
            "Note                : The wizard is isolated so it does not break the admin console state."
        )

        Write-DebugLog "Launching New User Wizard: $wizardPath" "INFO"

        $powershellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        if (-not (Test-Path $powershellExe)) { $powershellExe = "powershell.exe" }

        $argList = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-STA",
            "-File", $wizardPath
        )

        if ($Global:NoNet) { $argList += "-NoNet" }
        if ($DebugPreference -ne "SilentlyContinue") { $argList += "-Debug" }

        Start-Process -FilePath $powershellExe -ArgumentList $argList -WorkingDirectory $ScriptRoot | Out-Null
    }
    catch {
        Clear-ResultCards
        Add-ResultCard -Title "Create User Wizard" -Lines @(
            "Result              : ERROR",
            "Message             : $($_.Exception.Message)"
        )
        Write-DebugLog "Invoke-CreateUserWizard failed: $($_.Exception.Message)" "ERROR"
    }
}

# ================================================================
# ROOT MENU
# ================================================================
function Show-RootMenu {
    $menu = @(
        [PSCustomObject]@{
            Label = "User Details"
            Action = { Show-UserDetailsMenu }
        }
        [PSCustomObject]@{
            Label = "Manage User"
            Action = { Show-ManageUserMenu }
        }
        [PSCustomObject]@{
            Label = "Create User"
            Action = { Invoke-CreateUserWizard }
        }
        [PSCustomObject]@{
            Label = "Utilities"
            Action = { Show-UtilitiesMenu }
        }
        [PSCustomObject]@{
            Label = "Quit"
            Action = { $script:MainWindow.Close() }
        }
    )

    Set-ActionPanelContent $menu
}

# ================================================================
# USER DETAILS MENU
# ================================================================

function Show-UserDetailsMenu {
    $menu = @(
        [PSCustomObject]@{
            Label = "Overview"
            Action = { Show-OverviewCards }
        }
        [PSCustomObject]@{
            Label = "AD Core Info"
            Action = { Show-UserDetailsCard }
        }
        [PSCustomObject]@{
            Label = "AD Security Groups"
            Action = { Show-UserGroupsCard }
        }
        [PSCustomObject]@{
            Label = "Azure Groups"
            Action = { Show-AzureGroupsCard }
        }
        [PSCustomObject]@{
            Label = "Owned Distribution Groups"
            Action = {
                if (-not (Get-CurrentLookupIdentity)) { Show-NoUserMessage; return }
                Clear-ResultCards
                if ($script:LastLookupResults -and $script:LastLookupResults.OwnedDistributionGroups) {
                    Add-ResultCard -Title "Owned Distribution Groups" -Lines $script:LastLookupResults.OwnedDistributionGroups
                }
                else { Add-ResultCard -Title "Owned Distribution Groups" -Lines (Get-OwnedDistributionGroups (Get-CurrentLookupIdentity)) }
            }
        }
        [PSCustomObject]@{
            Label = "Mailbox Delegations"
            Action = {
                if (-not (Get-CurrentLookupIdentity)) { Show-NoUserMessage; return }
                Clear-ResultCards
                if ($script:LastLookupResults -and $script:LastLookupResults.MailboxDelegations) {
                    Add-ResultCard -Title "Mailbox Delegations" -Lines $script:LastLookupResults.MailboxDelegations
                }
                else { Add-ResultCard -Title "Mailbox Delegations" -Lines (Get-MailboxDelegations (Get-CurrentLookupIdentity)) }
            }
        }
        [PSCustomObject]@{
            Label = "Mail Forwarding"
            Action = {
                if (-not (Get-CurrentLookupIdentity)) { Show-NoUserMessage; return }
                Clear-ResultCards
                if ($script:LastLookupResults -and $script:LastLookupResults.MailForwarding) {
                    Add-ResultCard -Title "Mail Forwarding" -Lines $script:LastLookupResults.MailForwarding
                }
                else { Add-ResultCard -Title "Mail Forwarding" -Lines (Get-MailForwarding (Get-CurrentLookupIdentity)) }
            }
        }
        [PSCustomObject]@{
            Label = "Direct Reports"
            Action = { Show-UserDirectReportsCard }
        }
        [PSCustomObject]@{
            Label = "Azure AD Properties"
            Action = {
                if (-not (Get-CurrentLookupIdentity)) { Show-NoUserMessage; return }
                Clear-ResultCards
                if ($script:LastLookupResults -and $script:LastLookupResults.AzureProperties) {
                    Add-ResultCard -Title "AzureAD Properties" -Lines $script:LastLookupResults.AzureProperties
                }
                else { Add-ResultCard -Title "AzureAD Properties" -Lines (Get-AzureProperties (Get-CurrentLookupIdentity)) }
            }
        }
        [PSCustomObject]@{
            Label = "Azure AD Roles"
            Action = {
                if (-not (Get-CurrentLookupIdentity)) { Show-NoUserMessage; return }
                Clear-ResultCards
                # Always run Azure AD Roles fresh because this card intentionally switches to delegated Graph after Delegated Admin Mode is enabled.
                Add-ResultCard -Title "AzureAD Roles" -Lines (Get-AzureRoles (Get-CurrentLookupIdentity))
            }
        }
        [PSCustomObject]@{
            Label = "Back"
            Action = { Show-RootMenu }
        }
        [PSCustomObject]@{
            Label = "Quit"
            Action = { $script:MainWindow.Close() }
        }
    )

    Set-ActionPanelContent $menu
}

# ================================================================
# MANAGE USER MENU
# ================================================================
function Show-ManageUserMenu {
    $menu = @(
        [PSCustomObject]@{
            Label = "Clear AD Groups"
            Action = { Invoke-ClearADGroups }
        }
        [PSCustomObject]@{
            Label = "Clear Distribution Groups"
            Action = { Invoke-ClearDistro }
        }
        [PSCustomObject]@{
            Label = "Change DG Owner"
            Action = { Invoke-ChangeOwner }
        }
        [PSCustomObject]@{
            Label = "Change Manager"
            Action = { Invoke-SetSelectedUsersManager }
        }
        [PSCustomObject]@{
            Label = "Move Subordinates"
            Action = { Invoke-MoveSubordinates }
        }
        [PSCustomObject]@{
            Label = "Back"
            Action = { Show-RootMenu }
        }
        [PSCustomObject]@{
            Label = "Quit"
            Action = { $script:MainWindow.Close() }
        }
    )

    Set-ActionPanelContent $menu
}

# ================================================================
# UTILITIES MENU
# ================================================================
function Show-UtilitiesMenu {
    $menu = @(
        [PSCustomObject]@{
            Label = "Sync Azure AD"
            Action = { Invoke-AzureADDeltaSync }
        }
        [PSCustomObject]@{
            Label = "Sync All DCs"
            Action = { Invoke-SyncAllDomainControllers }
        }
        [PSCustomObject]@{
            Label = "Back"
            Action = { Show-RootMenu }
        }
        [PSCustomObject]@{
            Label = "Quit"
            Action = { $script:MainWindow.Close() }
        }
    )

    Set-ActionPanelContent $menu
}

# ================================================================
# No User selected helper
# ================================================================

function Show-NoUserMessage {
    Clear-ResultCards
    Add-ResultCard -Title "Notice" -Lines @("Search for a user first.")
}


# ================================================================
# CARD POPULATORS — Called by menu items above
# (You can expand these with richer data as requested)
# ================================================================
function Show-UserDetailsCard {
	if ([string]::IsNullOrWhiteSpace($script:SummarySam.Text) -or 
		$script:SummarySam.Text -eq "-" -or
		$script:SummaryDisplayName.Text -eq "Not Found") {
		Show-NoUserMessage
		return
	}

    Clear-ResultCards
    $id = Get-CurrentLookupIdentity
    Add-ResultCard -Title "User Details" -Lines (Get-ADInfo $id)
}

function Show-UserGroupsCard {
	if ([string]::IsNullOrWhiteSpace($script:SummarySam.Text) -or 
		$script:SummarySam.Text -eq "-" -or
		$script:SummaryDisplayName.Text -eq "Not Found") {
		Show-NoUserMessage
		return
	}
	
    Clear-ResultCards
    $id = Get-CurrentLookupIdentity
    if ($script:LastLookupResults -and $script:LastLookupResults.ADGroups) { Add-ResultCard -Title "AD Groups" -Lines $script:LastLookupResults.ADGroups } else { Add-ResultCard -Title "AD Groups" -Lines (Get-ADGroups $id) }
}

function Show-AzureGroupsCard {
    if (-not (Get-CurrentLookupIdentity)) { Show-NoUserMessage; return }

    Clear-ResultCards

    $groups = Get-AzureGroups (Get-CurrentLookupIdentity)

    Add-ResultCard -Title "Azure Groups — Security Groups" `
        -Lines $groups.SecurityGroups

    Add-ResultCard -Title "Azure Groups — Mail-Enabled Security Groups" `
        -Lines $groups.MailSecurityGroups

    Add-ResultCard -Title "Azure Groups — Distribution Groups" `
        -Lines $groups.DistributionGroups
}

function Show-UserEmailCard {
	if ([string]::IsNullOrWhiteSpace($script:SummarySam.Text) -or 
		$script:SummarySam.Text -eq "-" -or
		$script:SummaryDisplayName.Text -eq "Not Found") {
		Show-NoUserMessage
		return
	}
	
    Clear-ResultCards
    $id = $script:SummarySam.Text
    Add-ResultCard -Title "Email Details" -Lines (Get-MailForwarding $id)
}

function Show-UserDirectReportsCard {
	if ([string]::IsNullOrWhiteSpace($script:SummarySam.Text) -or 
		$script:SummarySam.Text -eq "-" -or
		$script:SummaryDisplayName.Text -eq "Not Found") {
		Show-NoUserMessage
		return
	}
	
    Clear-ResultCards
    $id = Get-CurrentLookupIdentity
    if ($script:LastLookupResults -and $script:LastLookupResults.DirectReports) { Add-ResultCard -Title "Subordinates" -Lines $script:LastLookupResults.DirectReports } else { Add-ResultCard -Title "Subordinates" -Lines (Get-DirectReports $id) }
}

# =====================================================================
# SUMMARY PANEL + LOOKUP PIPELINE + UI ACTION HANDLERS + WINDOW CHROME
# =====================================================================
# =====================================================================
# SUMMARY PANEL POPULATION
# =====================================================================
function Update-SummaryPanel {
    param([string]$Identity)

    Write-DebugLog "Updating summary panel for: $Identity" "INFO"

    if ($Global:NoNet) {
        $script:SummaryDisplayName.Text = "NoNet Mode"
        $script:SummarySam.Text         = "-"
        $script:SummaryEmail.Text       = "-"
        if ($script:SummaryEmployeeID) { $script:SummaryEmployeeID.Text = "-" }
        if ($script:SummaryBadgeID)    { $script:SummaryBadgeID.Text    = "-" }
        if ($script:SummaryManager)    { $script:SummaryManager.Text    = "-" }
        $script:SummaryDN.Text          = "-"
        return $null
    }

    try {
        $u = Resolve-ADUserIdentity $Identity
        if (-not $u) { throw "User not found." }

        $props = @('DisplayName','GivenName','Surname','SamAccountName','Mail','DistinguishedName','UserPrincipalName','EmployeeID','BadgeID','Manager','extensionAttribute15','extensionAttribute14','extensionAttribute13')
        $u = Get-ADUser -Identity $u.SamAccountName -Properties $props -ErrorAction Stop

        $badge = $u.BadgeID

        $script:SummaryDisplayName.Text = Format-ADValue $u.DisplayName
        $script:SummarySam.Text         = Format-ADValue $u.SamAccountName
        $script:SummaryEmail.Text       = Format-ADValue $u.Mail
        if ($script:SummaryEmployeeID) { $script:SummaryEmployeeID.Text = Format-ADValue $u.EmployeeID }
        if ($script:SummaryBadgeID)    { $script:SummaryBadgeID.Text    = Format-ADValue $badge }
        if ($script:SummaryManager)    { $script:SummaryManager.Text    = Resolve-ManagerDisplayName $u.Manager }
        $script:SummaryDN.Text          = Format-ADValue $u.DistinguishedName

        return $u
    }
    catch {
        $script:SummaryDisplayName.Text = "Not Found"
        $script:SummarySam.Text         = "-"
        $script:SummaryEmail.Text       = "-"
        if ($script:SummaryEmployeeID) { $script:SummaryEmployeeID.Text = "-" }
        if ($script:SummaryBadgeID)    { $script:SummaryBadgeID.Text    = "-" }
        if ($script:SummaryManager)    { $script:SummaryManager.Text    = "-" }
        $script:SummaryDN.Text          = "User not found or lookup error."
        $script:LastLookupIdentity      = $null
        $script:LastLookupResults       = $null

        Write-DebugLog "Summary panel update failed: $($_.Exception.Message)" "WARN"
        return $null
    }
}



# =====================================================================
# MASTER LOOKUP PIPELINE
# =====================================================================
function Invoke-UserLookup {
    param([string]$Query)

    if ([String]::IsNullOrWhiteSpace($Query)) {
        Write-DebugLog "Lookup aborted: Search text empty." "WARN"
        return
    }

    $identity = $Query.Trim()
    Write-DebugLog "Starting lookup for: $identity" "INFO"

    try {
        Show-LoadingOverlay
        Set-LoadingStatus "Searching for $identity ..." 5
        Do-Events
        Start-Sleep -Milliseconds 100
        Do-Events

        Clear-ResultCards
        Add-ResultCard -Title "Searching" -Lines @("Searching for $identity ...")
        Do-Events

        Set-LoadingStatus "Resolving Active Directory user..." 12
        $resolvedUser = Update-SummaryPanel -Identity $identity

        if (-not $resolvedUser -or $script:SummaryDisplayName.Text -eq "Not Found") {
            Clear-ResultCards
            Add-ResultCard -Title "Notice" -Lines @("User not found or lookup error.")
            return
        }

        $lookupId  = $resolvedUser.SamAccountName
        $lookupUPN = $resolvedUser.UserPrincipalName
        $script:LastLookupIdentity = $lookupId

        Write-DebugLog "Loading complete overview for: $lookupId" "INFO"

        Set-LoadingStatus "Loading AD profile..." 20
        $adInfo        = Get-ADInfo                  $lookupId

        Set-LoadingStatus "Loading AD groups..." 30
        $adGroups      = Get-ADGroups                $lookupId

        Set-LoadingStatus "Loading Azure groups..." 42
        $azureGroups   = Get-AzureGroups             $lookupId

        Set-LoadingStatus "Loading owned distribution groups from Graph..." 52
        $ownedDG       = Get-OwnedDistributionGroups $lookupId

        Set-LoadingStatus "Loading mailbox delegation lookup..." 63
        $delegations   = Get-MailboxDelegations      $lookupUPN

        Set-LoadingStatus "Loading mail forwarding..." 72
        $forwarding    = Get-MailForwarding          $lookupUPN

        Set-LoadingStatus "Loading direct reports..." 80
        $direct        = Get-DirectReports           $lookupId

        Set-LoadingStatus "Loading Azure properties and licenses..." 88
        $azProps       = Get-AzureProperties         $lookupId

        Set-LoadingStatus "Loading Azure AD roles..." 95
        $azRoles       = Get-AzureRoles              $lookupId

        $script:LastLookupResults = [PSCustomObject]@{
            ADInfo                  = @($adInfo)
            ADGroups                = @($adGroups)
            SecurityGroups          = @($azureGroups.SecurityGroups)
            MailSecurityGroups      = @($azureGroups.MailSecurityGroups)
            DistributionGroups      = @($azureGroups.DistributionGroups)
            OwnedDistributionGroups = @($ownedDG)
            MailboxDelegations      = @($delegations)
            MailForwarding          = @($forwarding)
            DirectReports           = @($direct)
            AzureProperties         = @($azProps)
            AzureRoles              = @($azRoles)
        }

        Set-LoadingStatus "Rendering results..." 100
        Show-OverviewCards
        Write-DebugLog "Lookup pipeline completed for: $lookupId" "SUCCESS"
    }
    finally {
        try { Fade-OutLoadingOverlay } catch { Hide-LoadingOverlay }
    }
}





# =====================================================================
# MANAGE USER ACTIONS — WIRED FROM ORIGINAL CONSOLE SCRIPT
# =====================================================================
function Read-TextInput {
    param(
        [string]$Prompt,
        [string]$Title = "Atlas User Dashboard",
        [string]$Default = ""
    )

    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
        return [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $Default)
    }
    catch {
        Write-DebugLog "InputBox failed: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Get-SelectedADUserForAction {
    $id = Get-CurrentLookupIdentity
    if ([string]::IsNullOrWhiteSpace($id)) {
        Show-NoUserMessage
        return $null
    }

    try {
        $props = @('DisplayName','GivenName','Surname','SamAccountName','UserPrincipalName','Mail','DistinguishedName','Manager','DirectReports')
        $u = Resolve-ADUserIdentity $id
        if (-not $u) { throw "Unable to resolve selected user '$id'." }
        return Get-ADUser -Identity $u.SamAccountName -Properties $props -ErrorAction Stop
    }
    catch {
        Clear-ResultCards
        Add-ResultCard -Title "Manage User" -Lines @("ERROR: $($_.Exception.Message)")
        Write-DebugLog "Selected user action resolution failed: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Invoke-ClearADGroups {
    $user = Get-SelectedADUserForAction
    if (-not $user) { return }

    try {
        Clear-ResultCards
        Add-ResultCard -Title "Clear AD Groups" -Lines @("Preparing Active Directory group removal for $($user.DisplayName) ($($user.SamAccountName))...")
        Do-Events

        $groups = @(Get-ADPrincipalGroupMembership -Identity $user.SamAccountName -ErrorAction Stop |
            Where-Object { $_.Name -ne "Domain Users" -and $_.SamAccountName -ne "Domain Users" } |
            Sort-Object Name)
        if ($groups.Count -eq 0) {
            Clear-ResultCards
            Add-ResultCard -Title "Clear AD Groups" -Lines @("No AD groups found for $($user.SamAccountName).")
            return
        }

        $groupNames = @($groups | Select-Object -ExpandProperty Name)
        $message = "Remove $($user.DisplayName) ($($user.SamAccountName)) from $($groups.Count) AD group(s)?`n`n" + (($groupNames | Select-Object -First 20) -join "`n")
        if ($groups.Count -gt 20) { $message += "`n...and $($groups.Count - 20) more." }
        if (-not (Confirm-Action $message)) { return }

        $removed = @()
        $failed = @()
        foreach ($g in $groups) {
            try {
                Remove-ADGroupMember -Identity $g.DistinguishedName -Members $user.DistinguishedName -Confirm:$false -ErrorAction Stop
                $removed += $g.Name
                Write-DebugLog "Removed $($user.SamAccountName) from AD group $($g.Name)." "SUCCESS"
            }
            catch {
                $failed += "$($g.Name): $($_.Exception.Message)"
                Write-DebugLog "Failed removing $($user.SamAccountName) from AD group $($g.Name): $($_.Exception.Message)" "WARN"
            }
        }

        Clear-ResultCards
        $lines = @("Removed from AD groups: $($removed.Count)")
        if ($removed.Count -gt 0) { $lines += ""; $lines += ($removed | ForEach-Object { "Removed: $_" }) }
        if ($failed.Count -gt 0) { $lines += ""; $lines += "Failures:"; $lines += $failed }
        Add-ResultCard -Title "Clear AD Groups" -Lines $lines
        $script:LastLookupResults = $null
    }
    catch {
        Clear-ResultCards
        Add-ResultCard -Title "Clear AD Groups" -Lines @("ERROR: $($_.Exception.Message)")
        Write-DebugLog "Invoke-ClearADGroups failed: $($_.Exception.Message)" "ERROR"
    }
}

function Get-ExchangeRecipientDistinguishedName {
    param([Parameter(Mandatory)]$User)

    $identity = $User.Mail
    if ([string]::IsNullOrWhiteSpace($identity)) { $identity = $User.UserPrincipalName }
    if ([string]::IsNullOrWhiteSpace($identity)) { $identity = $User.SamAccountName }

    $adminUpn = $script:GraphDelegatedAdminUpn
    if ([string]::IsNullOrWhiteSpace($adminUpn)) { $adminUpn = $identity }

    if (-not (Ensure-ExchangeOnlineDelegatedSession -UserPrincipalName $adminUpn)) {
        $why = if ($script:ExchangeOnlineConnectError) { $script:ExchangeOnlineConnectError } else { "unknown connection failure" }
        throw "Unable to connect to Exchange Online delegated session: $why"
    }

    $recipient = Get-Recipient -Identity $identity -ErrorAction Stop
    return [string]$recipient.DistinguishedName
}

function Get-UserDistributionGroupsForAction {
    param([Parameter(Mandatory)]$User)

    $userOdn = Get-ExchangeRecipientDistinguishedName -User $User
    $filter = "Members -like `"$userOdn`""
    return @(Get-DistributionGroup -ResultSize Unlimited -Filter $filter -ErrorAction Stop | Sort-Object Name)
}

function Invoke-ClearDistro {
    $user = Get-SelectedADUserForAction
    if (-not $user) { return }

    if (-not $script:GraphDelegatedModeEnabled) {
        Clear-ResultCards
        Add-ResultCard -Title "Clear Distribution Groups" -Lines @("Enable Delegated Admin Mode first. Distribution group changes require Exchange Online delegated access.")
        return
    }

    try {
        Clear-ResultCards
        Add-ResultCard -Title "Clear Distribution Groups" -Lines @("Finding Exchange Online distribution groups for $($user.DisplayName) ($($user.SamAccountName))...")
        Do-Events

        $groups = @(Get-UserDistributionGroupsForAction -User $user)
        if ($groups.Count -eq 0) {
            Clear-ResultCards
            Add-ResultCard -Title "Clear Distribution Groups" -Lines @("No Exchange Online distribution group memberships found for $($user.SamAccountName).")
            return
        }

        $names = @($groups | ForEach-Object { if ($_.DisplayName) { $_.DisplayName } else { $_.Name } })
        $message = "Remove $($user.DisplayName) ($($user.SamAccountName)) from $($groups.Count) Exchange distribution group(s)?`n`n" + (($names | Select-Object -First 20) -join "`n")
        if ($groups.Count -gt 20) { $message += "`n...and $($groups.Count - 20) more." }
        if (-not (Confirm-Action $message)) { return }

        $memberIdentity = $user.Mail
        if ([string]::IsNullOrWhiteSpace($memberIdentity)) { $memberIdentity = $user.UserPrincipalName }
        if ([string]::IsNullOrWhiteSpace($memberIdentity)) { $memberIdentity = $user.SamAccountName }

        $removed = @()
        $failed = @()
        foreach ($g in $groups) {
            $gId = if ($g.PrimarySmtpAddress) { [string]$g.PrimarySmtpAddress } elseif ($g.Identity) { [string]$g.Identity } else { [string]$g.Name }
            $gName = if ($g.DisplayName) { [string]$g.DisplayName } else { [string]$g.Name }
            try {
                Remove-DistributionGroupMember -Identity $gId -Member $memberIdentity -Confirm:$false -BypassSecurityGroupManagerCheck -ErrorAction Stop
                $removed += $gName
                Write-DebugLog "Removed $memberIdentity from distribution group $gName." "SUCCESS"
            }
            catch {
                $failed += "$($gName): $($_.Exception.Message)"
                Write-DebugLog "Failed removing $memberIdentity from distribution group $($gName): $($_.Exception.Message)" "WARN"
            }
        }

        Clear-ResultCards
        $lines = @("Removed from distribution groups: $($removed.Count)")
        if ($removed.Count -gt 0) { $lines += ""; $lines += ($removed | ForEach-Object { "Removed: $_" }) }
        if ($failed.Count -gt 0) { $lines += ""; $lines += "Failures:"; $lines += $failed }
        Add-ResultCard -Title "Clear Distribution Groups" -Lines $lines
        $script:LastLookupResults = $null
    }
    catch {
        Clear-ResultCards
        Add-ResultCard -Title "Clear Distribution Groups" -Lines @("ERROR: $($_.Exception.Message)")
        Write-DebugLog "Invoke-ClearDistro failed: $($_.Exception.Message)" "ERROR"
    }
}

function Invoke-ChangeOwner {
    $oldOwner = Get-SelectedADUserForAction
    if (-not $oldOwner) { return }

    if (-not $script:GraphDelegatedModeEnabled) {
        Clear-ResultCards
        Add-ResultCard -Title "Change DG Owner" -Lines @("Enable Delegated Admin Mode first. Distribution group ownership changes require Exchange Online delegated access.")
        return
    }

    $newOwnerSam = Read-TextInput -Prompt "Enter the SAM account, UPN, or email address for the new distribution group owner:" -Title "Change Distribution Group Owner"
    if ([string]::IsNullOrWhiteSpace($newOwnerSam)) { return }

    try {
        $newOwner = Resolve-ADUserIdentity $newOwnerSam
        if (-not $newOwner) { throw "Unable to resolve new owner '$newOwnerSam'." }
        $newOwner = Get-ADUser -Identity $newOwner.SamAccountName -Properties DisplayName,SamAccountName,UserPrincipalName,Mail,DistinguishedName -ErrorAction Stop

        $oldOdn = Get-ExchangeRecipientDistinguishedName -User $oldOwner
        $newOdn = Get-ExchangeRecipientDistinguishedName -User $newOwner

        Clear-ResultCards
        Add-ResultCard -Title "Change DG Owner" -Lines @("Finding groups managed by $($oldOwner.DisplayName) ($($oldOwner.SamAccountName))...")
        Do-Events

        $groups = @(Get-Recipient -Filter "ManagedBy -eq '$oldOdn'" -RecipientTypeDetails GroupMailbox,MailUniversalDistributionGroup,MailUniversalSecurityGroup,DynamicDistributionGroup -ErrorAction Stop | Sort-Object DisplayName)
        if ($groups.Count -eq 0) {
            Clear-ResultCards
            Add-ResultCard -Title "Change DG Owner" -Lines @("No owned Exchange Online groups found for $($oldOwner.SamAccountName).")
            return
        }

        $names = @($groups | ForEach-Object { if ($_.DisplayName) { $_.DisplayName } else { $_.Name } })
        $message = "Change owner on $($groups.Count) group(s) from $($oldOwner.DisplayName) to $($newOwner.DisplayName)?`n`n" + (($names | Select-Object -First 20) -join "`n")
        if ($groups.Count -gt 20) { $message += "`n...and $($groups.Count - 20) more." }
        if (-not (Confirm-Action $message)) { return }

        $changed = @()
        $failed = @()
        foreach ($g in $groups) {
            $gIdentity = if ($g.PrimarySmtpAddress) { [string]$g.PrimarySmtpAddress } elseif ($g.Identity) { [string]$g.Identity } else { [string]$g.Name }
            $gName = if ($g.DisplayName) { [string]$g.DisplayName } else { [string]$g.Name }
            try {
                Set-DistributionGroup -Identity $gIdentity -ManagedBy $newOdn -BypassSecurityGroupManagerCheck -ErrorAction Stop
                $changed += $gName
                Write-DebugLog "Changed distribution group owner for $($gName) to $($newOwner.SamAccountName)." "SUCCESS"
            }
            catch {
                $failed += "$($gName): $($_.Exception.Message)"
                Write-DebugLog "Failed changing distribution group owner for $($gName): $($_.Exception.Message)" "WARN"
            }
        }

        Clear-ResultCards
        $lines = @("Changed group ownership: $($changed.Count)", "New owner: $($newOwner.DisplayName) ($($newOwner.SamAccountName))")
        if ($changed.Count -gt 0) { $lines += ""; $lines += ($changed | ForEach-Object { "Changed: $_" }) }
        if ($failed.Count -gt 0) { $lines += ""; $lines += "Failures:"; $lines += $failed }
        Add-ResultCard -Title "Change DG Owner" -Lines $lines
        $script:LastLookupResults = $null
    }
    catch {
        Clear-ResultCards
        Add-ResultCard -Title "Change DG Owner" -Lines @("ERROR: $($_.Exception.Message)")
        Write-DebugLog "Invoke-ChangeOwner failed: $($_.Exception.Message)" "ERROR"
    }
}

function Invoke-MoveSubordinates {
    $oldManager = Get-SelectedADUserForAction
    if (-not $oldManager) { return }

    $newManagerInput = Read-TextInput -Prompt "Enter the SAM account, UPN, or email address for the new manager:" -Title "Move Subordinates"
    if ([string]::IsNullOrWhiteSpace($newManagerInput)) { return }

    try {
        $newManager = Resolve-ADUserIdentity $newManagerInput
        if (-not $newManager) { throw "Unable to resolve new manager '$newManagerInput'." }
        $newManager = Get-ADUser -Identity $newManager.SamAccountName -Properties DisplayName,SamAccountName,DistinguishedName -ErrorAction Stop

        $directReportDns = @($oldManager.DirectReports | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($directReportDns.Count -eq 0) {
            Clear-ResultCards
            Add-ResultCard -Title "Move Subordinates" -Lines @("$($oldManager.DisplayName) has no direct reports to move.")
            return
        }

        $reportNames = @()
        foreach ($dn in $directReportDns) {
            try {
                $r = Get-ADUser -Identity $dn -Properties DisplayName,SamAccountName -ErrorAction Stop
                $reportNames += "$($r.DisplayName) ($($r.SamAccountName))"
            } catch { $reportNames += [string]$dn }
        }

        $message = "Move $($directReportDns.Count) direct report(s) from $($oldManager.DisplayName) to $($newManager.DisplayName)?`n`n" + (($reportNames | Select-Object -First 20) -join "`n")
        if ($directReportDns.Count -gt 20) { $message += "`n...and $($directReportDns.Count - 20) more." }
        if (-not (Confirm-Action $message)) { return }

        $changed = @()
        $failed = @()
        foreach ($dn in $directReportDns) {
            try {
                $r = Get-ADUser -Identity $dn -Properties DisplayName,SamAccountName -ErrorAction Stop
                Set-ADUser -Identity $r.DistinguishedName -Manager $newManager.DistinguishedName -ErrorAction Stop
                $changed += "$($r.DisplayName) ($($r.SamAccountName))"
                Write-DebugLog "Moved direct report $($r.SamAccountName) to manager $($newManager.SamAccountName)." "SUCCESS"
            }
            catch {
                $failed += "$($dn): $($_.Exception.Message)"
                Write-DebugLog "Failed moving direct report $($dn): $($_.Exception.Message)" "WARN"
            }
        }

        Clear-ResultCards
        $lines = @("Moved direct reports: $($changed.Count)", "New manager: $($newManager.DisplayName) ($($newManager.SamAccountName))")
        if ($changed.Count -gt 0) { $lines += ""; $lines += ($changed | ForEach-Object { "Moved: $_" }) }
        if ($failed.Count -gt 0) { $lines += ""; $lines += "Failures:"; $lines += $failed }
        Add-ResultCard -Title "Move Subordinates" -Lines $lines
        $script:LastLookupResults = $null
    }
    catch {
        Clear-ResultCards
        Add-ResultCard -Title "Move Subordinates" -Lines @("ERROR: $($_.Exception.Message)")
        Write-DebugLog "Invoke-MoveSubordinates failed: $($_.Exception.Message)" "ERROR"
    }
}


function Invoke-SetSelectedUsersManager {
    $user = Get-SelectedADUserForAction
    if (-not $user) { return }

    $newManagerInput = Read-TextInput -Prompt "Enter the SAM account, UPN, or email address for the selected user's new manager:" -Title "Change Manager"
    if ([string]::IsNullOrWhiteSpace($newManagerInput)) { return }

    try {
        $newManager = Resolve-ADUserIdentity $newManagerInput
        if (-not $newManager) { throw "Unable to resolve new manager '$newManagerInput'." }
        $newManager = Get-ADUser -Identity $newManager.SamAccountName -Properties DisplayName,SamAccountName,DistinguishedName -ErrorAction Stop

        $currentManager = Resolve-ManagerDisplayName $user.Manager
        $message = "Change manager for $($user.DisplayName) ($($user.SamAccountName))?`n`nCurrent manager: $currentManager`nNew manager: $($newManager.DisplayName) ($($newManager.SamAccountName))"
        if (-not (Confirm-Action $message)) { return }

        Set-ADUser -Identity $user.DistinguishedName -Manager $newManager.DistinguishedName -ErrorAction Stop

        Clear-ResultCards
        Add-ResultCard -Title "Change Manager" -Lines @(
            "Updated manager for: $($user.DisplayName) ($($user.SamAccountName))",
            "Previous manager: $currentManager",
            "New manager: $($newManager.DisplayName) ($($newManager.SamAccountName))"
        )
        Write-DebugLog "Changed manager for $($user.SamAccountName) to $($newManager.SamAccountName)." "SUCCESS"
        $script:LastLookupResults = $null
    }
    catch {
        Clear-ResultCards
        Add-ResultCard -Title "Change Manager" -Lines @("ERROR: $($_.Exception.Message)")
        Write-DebugLog "Invoke-SetSelectedUsersManager failed: $($_.Exception.Message)" "ERROR"
    }
}


function Add-UtilityResultCard {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Lines
    )

    try {
        if (-not $script:ResultsPanel) {
            $script:ResultsPanel = Find-Element -root $script:MainWindow -name "ResultsPanel"
        }
        if (-not $script:ResultsPanel) { throw "ResultsPanel is not mapped." }

        $lineArray = @($Lines)
        if (-not $lineArray -or $lineArray.Count -eq 0) { $lineArray = @("No data returned.") }

        $script:ResultsPanel.Dispatcher.Invoke([Action]{
            $card = New-Object System.Windows.Controls.Border
            $card.CornerRadius = New-Object System.Windows.CornerRadius(14)
            $card.Padding = New-Object System.Windows.Thickness(14)
            $card.Margin = New-Object System.Windows.Thickness(0,0,0,16)
            $card.BorderThickness = New-Object System.Windows.Thickness(1)
            $glass = Get-AppResource "GlassCard"
            if ($glass) { $card.Background = $glass } else { $card.Background = [System.Windows.Media.Brushes]::Transparent }
            $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(0x66,0x7F,0xB8,0xE8))

            $outer = New-Object System.Windows.Controls.StackPanel

            $titleBlock = New-Object System.Windows.Controls.TextBlock
            $titleBlock.Text = $Title
            $titleBlock.FontSize = 22
            $titleBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
            $titleBlock.Foreground = [System.Windows.Media.Brushes]::White
            $titleBlock.Margin = New-Object System.Windows.Thickness(0,0,0,10)
            $glow = Get-AppResource "GlowOrange"
            if ($glow) { $titleBlock.Effect = $glow }
            [void]$outer.Children.Add($titleBlock)

            foreach ($line in $lineArray) {
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text = [string]$line
                $tb.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
                $tb.FontSize = 15
                $tb.Foreground = [System.Windows.Media.Brushes]::White
                $tb.Margin = New-Object System.Windows.Thickness(4,1,0,1)
                $tb.TextWrapping = "Wrap"
                [void]$outer.Children.Add($tb)
            }

            $card.Child = $outer
            [void]$script:ResultsPanel.Children.Add($card)
            $script:ResultsPanel.UpdateLayout()
        })
    }
    catch {
        Add-ResultCard -Title $Title -Lines $Lines
    }
}

function Add-DcSyncProgressCard {
    param([int]$Total)

    if (-not $script:ResultsPanel) {
        $script:ResultsPanel = Find-Element -root $script:MainWindow -name "ResultsPanel"
    }
    if (-not $script:ResultsPanel) { throw "ResultsPanel is not mapped." }

    $state = @{}
    $script:ResultsPanel.Dispatcher.Invoke([Action]{
        $card = New-Object System.Windows.Controls.Border
        $card.CornerRadius = New-Object System.Windows.CornerRadius(14)
        $card.Padding = New-Object System.Windows.Thickness(14)
        $card.Margin = New-Object System.Windows.Thickness(0,0,0,16)
        $card.BorderThickness = New-Object System.Windows.Thickness(1)
        $glass = Get-AppResource "GlassCard"
        if ($glass) { $card.Background = $glass } else { $card.Background = [System.Windows.Media.Brushes]::Transparent }
        $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(0x66,0x7F,0xB8,0xE8))

        $outer = New-Object System.Windows.Controls.StackPanel

        $titleBlock = New-Object System.Windows.Controls.TextBlock
        $titleBlock.Text = "Sync All DCs"
        $titleBlock.FontSize = 22
        $titleBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
        $titleBlock.Foreground = [System.Windows.Media.Brushes]::White
        $titleBlock.Margin = New-Object System.Windows.Thickness(0,0,0,10)
        $glow = Get-AppResource "GlowOrange"
        if ($glow) { $titleBlock.Effect = $glow }
        [void]$outer.Children.Add($titleBlock)

        $status = New-Object System.Windows.Controls.TextBlock
        $status.Text = "Preparing domain controller sync..."
        $status.FontSize = 16
        $status.Foreground = [System.Windows.Media.Brushes]::White
        $status.Margin = New-Object System.Windows.Thickness(4,0,0,8)
        [void]$outer.Children.Add($status)

        $bar = New-Object System.Windows.Controls.ProgressBar
        $bar.Minimum = 0
        $bar.Maximum = [Math]::Max(1,$Total)
        $bar.Value = 0
        $bar.Height = 24
        $bar.Margin = New-Object System.Windows.Thickness(4,0,4,10)
        $accent = Get-AppResource "AccentBright"
        if ($accent) { $bar.Foreground = $accent }
        [void]$outer.Children.Add($bar)

        $log = New-Object System.Windows.Controls.TextBox
        $log.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $log.FontSize = 13
        $log.Foreground = [System.Windows.Media.Brushes]::White
        $log.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(0x22,0x0A,0x15,0x25))
        $log.BorderThickness = New-Object System.Windows.Thickness(1)
        $log.IsReadOnly = $true
        $log.AcceptsReturn = $true
        $log.TextWrapping = "Wrap"
        $log.VerticalScrollBarVisibility = "Auto"
        $log.Height = 220
        [void]$outer.Children.Add($log)

        $card.Child = $outer
        [void]$script:ResultsPanel.Children.Add($card)
        $script:ResultsPanel.UpdateLayout()

        $state.Status = $status
        $state.Progress = $bar
        $state.Log = $log
    })
    return $state
}

function Update-DcSyncProgressCard {
    param(
        [Parameter(Mandatory)]$State,
        [int]$Index,
        [int]$Total,
        [string]$Current,
        [string]$LogLine
    )

    try {
        $State.Status.Dispatcher.Invoke([Action]{
            if ($Index -le 0) {
                $State.Status.Text = $Current
            }
            else {
                $State.Status.Text = "Syncing {0} of {1}: {2}" -f $Index, $Total, $Current
            }
            $State.Progress.Maximum = [Math]::Max(1,$Total)
            $State.Progress.Value = [Math]::Min($Index,$Total)
            if (-not [string]::IsNullOrWhiteSpace($LogLine)) {
                $State.Log.AppendText($LogLine + [Environment]::NewLine)
                $State.Log.ScrollToEnd()
            }
        })
    } catch {}
    Do-Events
}

function Get-AzureADConnectStatusLines {
    param($Status)

    $lines = @()
    if (-not $Status) { return @("Status: unavailable") }

    $lines += "Server              : $($Status.Server)"
    $lines += "AAD Connect status  : $($Status.Status)"
    $lines += "Sync enabled        : $($Status.SyncCycleEnabled)"
    $lines += "Sync in progress    : $($Status.SyncCycleInProgress)"
    $lines += "Scheduler suspended : $($Status.SchedulerSuspended)"
    $lines += "Staging mode        : $($Status.StagingModeEnabled)"
    $lines += "Next sync UTC       : $($Status.NextSyncCycleStartTimeInUTC)"
    $lines += "Effective interval  : $($Status.CurrentlyEffectiveSyncCycleInterval)"
    if ($Status.ConnectorRunStatus) {
        $lines += "Connector status    : $($Status.ConnectorRunStatus)"
    }
    return $lines
}

function Invoke-AzureADDeltaSync {
    if ($Global:NoNet) {
        Clear-ResultCards
        Add-UtilityResultCard -Title "Sync Azure AD" -Lines @("NoNet mode: Azure AD delta sync disabled.")
        return
    }

    $server = "genil"
    try {
        Clear-ResultCards
        Add-UtilityResultCard -Title "Sync Azure AD" -Lines @(
            "Server              : $server",
            "Action              : Delta sync",
            "Status              : Connecting and checking current scheduler state..."
        )
        Do-Events

        $result = Invoke-Command -ComputerName $server -ScriptBlock {
            Import-Module ADSync -ErrorAction Stop

            function Convert-SchedulerStatus {
                param($Scheduler, [string]$ServerName, [string]$State, $ConnectorStatus)
                [pscustomobject]@{
                    Server                                = $ServerName
                    Status                                = $State
                    SyncCycleEnabled                      = if ($Scheduler) { $Scheduler.SyncCycleEnabled } else { "Unknown" }
                    SyncCycleInProgress                   = if ($Scheduler -and $Scheduler.PSObject.Properties['SyncCycleInProgress']) { $Scheduler.SyncCycleInProgress } else { "Unknown" }
                    SchedulerSuspended                    = if ($Scheduler -and $Scheduler.PSObject.Properties['SchedulerSuspended']) { $Scheduler.SchedulerSuspended } else { "Unknown" }
                    StagingModeEnabled                    = if ($Scheduler -and $Scheduler.PSObject.Properties['StagingModeEnabled']) { $Scheduler.StagingModeEnabled } else { "Unknown" }
                    NextSyncCycleStartTimeInUTC           = if ($Scheduler -and $Scheduler.PSObject.Properties['NextSyncCycleStartTimeInUTC']) { $Scheduler.NextSyncCycleStartTimeInUTC } else { "Unknown" }
                    CurrentlyEffectiveSyncCycleInterval   = if ($Scheduler -and $Scheduler.PSObject.Properties['CurrentlyEffectiveSyncCycleInterval']) { $Scheduler.CurrentlyEffectiveSyncCycleInterval } else { "Unknown" }
                    ConnectorRunStatus                    = if ($ConnectorStatus) { (($ConnectorStatus | Out-String).Trim() -replace "`r?`n", "; ") } else { "No active connector run returned" }
                }
            }

            $beforeScheduler = Get-ADSyncScheduler
            $beforeConnector = $null
            try { $beforeConnector = Get-ADSyncConnectorRunStatus } catch {}

            $startResult = Start-ADSyncSyncCycle -PolicyType Delta
            Start-Sleep -Seconds 2

            $afterScheduler = Get-ADSyncScheduler
            $afterConnector = $null
            try { $afterConnector = Get-ADSyncConnectorRunStatus } catch {}

            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                StartResult  = (($startResult | Out-String).Trim() -replace "`r?`n", " ")
                Before       = Convert-SchedulerStatus -Scheduler $beforeScheduler -ServerName $env:COMPUTERNAME -State "Before request" -ConnectorStatus $beforeConnector
                After        = Convert-SchedulerStatus -Scheduler $afterScheduler -ServerName $env:COMPUTERNAME -State "After request" -ConnectorStatus $afterConnector
            }
        } -ErrorAction Stop

        Clear-ResultCards
        $lines = @(
            "Server              : $server",
            "Action              : Azure AD Connect delta sync",
            "Request result      : $(if ($result.StartResult) { $result.StartResult } else { 'Submitted' })"
        )
        $lines += ""
        $lines += "Current Status"
        $lines += "--------------"
        $lines += Get-AzureADConnectStatusLines -Status $result.After
        $lines += ""
        $lines += "Previous Status"
        $lines += "---------------"
        $lines += Get-AzureADConnectStatusLines -Status $result.Before

        Add-UtilityResultCard -Title "Sync Azure AD" -Lines $lines
        Write-DebugLog "Azure AD delta sync submitted on $server." "SUCCESS"
    }
    catch {
        Clear-ResultCards
        Add-UtilityResultCard -Title "Sync Azure AD" -Lines @(
            "Server              : $server",
            "Action              : Azure AD Connect delta sync",
            "Result              : ERROR",
            "Message             : $($_.Exception.Message)"
        )
        Write-DebugLog "Invoke-AzureADDeltaSync failed: $($_.Exception.Message)" "ERROR"
    }
}

function Invoke-SyncAllDomainControllers {
    if ($Global:NoNet) {
        Clear-ResultCards
        Add-UtilityResultCard -Title "Sync All DCs" -Lines @("NoNet mode: domain controller sync disabled.")
        return
    }

    $skipNames = @("eider","aldan")

    try {
        Clear-ResultCards
        Do-Events

        $allDcs = @(Get-ADDomainController -Filter * -ErrorAction Stop | Sort-Object HostName)
        if ($allDcs.Count -eq 0) { throw "No domain controllers were returned by Get-ADDomainController." }

        $skipped = @()
        $dcs = @()
        foreach ($dc in $allDcs) {
            $targetName = if ($dc.HostName) { [string]$dc.HostName } else { [string]$dc.Name }
            $shortName = ($targetName -split '\.')[0]
            if ($skipNames -contains $shortName.ToLowerInvariant()) {
                $skipped += $targetName
            }
            else {
                $dcs += $dc
            }
        }

        if ($dcs.Count -eq 0) { throw "All discovered domain controllers are excluded from this tool." }

        $progress = Add-DcSyncProgressCard -Total $dcs.Count
        Update-DcSyncProgressCard -State $progress -Index 0 -Total $dcs.Count -Current "Preparing to sync $($dcs.Count) domain controllers. Skipping: $($skipped -join ', ')" -LogLine "Excluded DCs: $($skipped -join ', ')"

        $succeeded = @()
        $failed = @()
        $index = 0

        foreach ($dc in $dcs) {
            $index++
            $target = if ($dc.HostName) { [string]$dc.HostName } else { [string]$dc.Name }
            Update-DcSyncProgressCard -State $progress -Index $index -Total $dcs.Count -Current $target -LogLine "[$index/$($dcs.Count)] Starting $target"

            try {
                Write-DebugLog "Running repadmin /syncall $target /AdeP" "INFO"
                $output = & repadmin.exe /syncall $target /AdeP 2>&1
                $outputText = ($output -join ' ').Trim()
                if ($LASTEXITCODE -eq 0) {
                    $succeeded += $target
                    Update-DcSyncProgressCard -State $progress -Index $index -Total $dcs.Count -Current $target -LogLine "[$index/$($dcs.Count)] SUCCESS $target"
                    Write-DebugLog "DC sync completed for $target." "SUCCESS"
                }
                else {
                    $failed += "${target}: $outputText"
                    Update-DcSyncProgressCard -State $progress -Index $index -Total $dcs.Count -Current $target -LogLine "[$index/$($dcs.Count)] FAILED  $target - $outputText"
                    Write-DebugLog "DC sync failed for ${target}: $outputText" "WARN"
                }
            }
            catch {
                $failed += "${target}: $($_.Exception.Message)"
                Update-DcSyncProgressCard -State $progress -Index $index -Total $dcs.Count -Current $target -LogLine "[$index/$($dcs.Count)] FAILED  $target - $($_.Exception.Message)"
                Write-DebugLog "DC sync failed for ${target}: $($_.Exception.Message)" "WARN"
            }
            Do-Events
        }

        Update-DcSyncProgressCard -State $progress -Index $dcs.Count -Total $dcs.Count -Current "Complete. Succeeded: $($succeeded.Count), Failed: $($failed.Count), Skipped: $($skipped.Count)" -LogLine "Complete. Succeeded: $($succeeded.Count), Failed: $($failed.Count), Skipped: $($skipped.Count)"

        $summary = @(
            "Total discovered     : $($allDcs.Count)",
            "Attempted            : $($dcs.Count)",
            "Succeeded            : $($succeeded.Count)",
            "Failed               : $($failed.Count)",
            "Skipped              : $($skipped.Count)"
        )
        if ($skipped.Count -gt 0) { $summary += ""; $summary += "Skipped DCs"; $summary += "-----------"; $summary += $skipped }
        if ($succeeded.Count -gt 0) { $summary += ""; $summary += "Succeeded"; $summary += "---------"; $summary += $succeeded }
        if ($failed.Count -gt 0) { $summary += ""; $summary += "Failures"; $summary += "--------"; $summary += $failed }

        Add-UtilityResultCard -Title "Sync All DCs — Summary" -Lines $summary
    }
    catch {
        Clear-ResultCards
        Add-UtilityResultCard -Title "Sync All DCs" -Lines @(
            "Result              : ERROR",
            "Message             : $($_.Exception.Message)"
        )
        Write-DebugLog "Invoke-SyncAllDomainControllers failed: $($_.Exception.Message)" "ERROR"
    }
}

# =====================================================================
# CONFIRM PROMPT HELPER
# =====================================================================
function Confirm-Action {
    param([string]$Message)

    $result = [System.Windows.MessageBox]::Show(
        $Message,
        "Confirm Action",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    return ($result -eq [System.Windows.MessageBoxResult]::Yes)
}

# =====================================================================
# EVENT BINDING — ALL DONE INSIDE THE WINDOW.LOADED EVENT
# =====================================================================

function Attach-UIEvents {

    Write-DebugLog "Wiring UI events..." "INFO"

    # -----------------------------------------------------------------
    # SEARCH BOX ENTER KEY HANDLER
    # -----------------------------------------------------------------
    $script:SearchUserBox.Add_PreviewKeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Return -or $eventArgs.Key -eq [System.Windows.Input.Key]::Enter) {
            $eventArgs.Handled = $true
            Invoke-UserLookup -Query $script:SearchUserBox.Text
        }
    })

    # -----------------------------------------------------------------
    # WINDOW CHROME
    # -----------------------------------------------------------------
    $script:MainWindow.Add_MouseDown({
        if ($_.ChangedButton -eq "Left") { $script:MainWindow.DragMove() }
    })

    $script:MinButton.Add_Click({ $script:MainWindow.WindowState = "Minimized" })

    $script:MaxButton.Add_Click({
        if ($script:MainWindow.WindowState -eq "Maximized") {
            $script:MainWindow.WindowState = "Normal"
        }
        else {
            $script:MainWindow.WindowState = "Maximized"
        }
    })

    $script:ExitButton.Add_Click({ $script:MainWindow.Close() })

    if ($script:HamburgerButton) {
        $script:HamburgerButton.Add_Click({ Show-HamburgerMenu })
    }

    # -----------------------------------------------------------------
    # DEBUG PANEL BUTTONS
    # -----------------------------------------------------------------

    # Toggle debug panel on CTRL + D
    $script:MainWindow.Add_KeyDown({
        if ($_.Key -eq "D" -and 
            [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::LeftCtrl)) 
        {
            Toggle-DebugMode
        }
    })

    Write-DebugLog "UI event wiring complete." "SUCCESS"
}

# =====================================================================
# WINDOW CREATION + RESOURCE INITIALIZATION + MODULE INIT + SHOW WINDOW
# Correct order:
#   1. Load resource dictionaries into Application.Resources.
#   2. Parse the main Window XAML after resources exist.
#   3. Attach the modal loading overlay.
#   4. Map named controls in Window.Loaded.
#   5. Wire events, initialize modules, then build initial UI.
#   6. Run the WPF application.
# =====================================================================

try {

    Write-DebugLog "Starting Atlas Dashboard..." "INFO"

    # ---------------------------------------------------------
    # 0. Ensure WPF Application Instance Exists
    # ---------------------------------------------------------
    if (-not [System.Windows.Application]::Current) {
        $script:App = New-Object System.Windows.Application
    }
    else {
        $script:App = [System.Windows.Application]::Current
    }

    # ---------------------------------------------------------
    # 1. Load app-level resources BEFORE parsing any XAML that
    #    references StaticResource keys.
    # ---------------------------------------------------------
    $script:App.Resources.MergedDictionaries.Clear()
    $script:App.Resources.MergedDictionaries.Add((Load-XamlString $XamlTheme))
    $script:App.Resources.MergedDictionaries.Add((Load-XamlString $XamlCollapsibleCard))

    # ---------------------------------------------------------
    # 2. Parse the Main Window AFTER resources are available.
    # ---------------------------------------------------------
    $mainWindowReader = New-Object System.Xml.XmlNodeReader ([xml]$XamlMainWindow)
    $script:MainWindow = [Windows.Markup.XamlReader]::Load($mainWindowReader)

    if (-not $script:MainWindow) {
        throw "Main window failed to load from XAML."
    }

    # Also attach resources directly to the Window so code-created controls
    # can resolve styles such as ActionCard and CollapsibleCardStyle.
    $script:MainWindow.Resources.MergedDictionaries.Add((Load-XamlString $XamlTheme))
    $script:MainWindow.Resources.MergedDictionaries.Add((Load-XamlString $XamlCollapsibleCard))

    # ---------------------------------------------------------
    # 3. Attach Loading Overlay after the main visual tree exists.
    # ---------------------------------------------------------
    Attach-LoadingOverlay -Window $script:MainWindow

    # ---------------------------------------------------------
    # 4. Handle Window Loaded: map controls, wire events, initialize.
    # ---------------------------------------------------------
    $script:MainWindow.Add_Loaded({

        Write-DebugLog "Loaded event fired." "INFO"

        try {
            Write-DebugLog "Mapping UI elements..." "INFO"

            $script:HamburgerButton   = $script:MainWindow.FindName("HamburgerButton")
            $script:SearchUserBox      = $script:MainWindow.FindName("SearchUserBox")
            $script:ResultsPanel       = $script:MainWindow.FindName("ResultsPanel")
            $script:ActionPanel        = $script:MainWindow.FindName("ActionPanel")

            $script:SummaryDisplayName = $script:MainWindow.FindName("SummaryDisplayName")
            $script:SummarySam         = $script:MainWindow.FindName("SummarySam")
            $script:SummaryEmail       = $script:MainWindow.FindName("SummaryEmail")
            $script:SummaryEmployeeID  = $script:MainWindow.FindName("SummaryEmployeeID")
            $script:SummaryBadgeID     = $script:MainWindow.FindName("SummaryBadgeID")
            $script:SummaryManager     = $script:MainWindow.FindName("SummaryManager")
            $script:SummaryDN          = $script:MainWindow.FindName("SummaryDN")

            $script:MinButton          = $script:MainWindow.FindName("MinButton")
            $script:MaxButton          = $script:MainWindow.FindName("MaxButton")
            $script:ExitButton         = $script:MainWindow.FindName("ExitButton")

            $script:DebugPanel         = $script:MainWindow.FindName("DebugPanel")
            $script:DebugOutputBox     = $script:MainWindow.FindName("DebugOutputBox")

            $requiredControls = @{
                HamburgerButton   = $script:HamburgerButton
                SearchUserBox      = $script:SearchUserBox
                ResultsPanel       = $script:ResultsPanel
                ActionPanel        = $script:ActionPanel
                SummaryDisplayName = $script:SummaryDisplayName
                SummarySam         = $script:SummarySam
                SummaryEmail       = $script:SummaryEmail
                SummaryEmployeeID  = $script:SummaryEmployeeID
                SummaryBadgeID     = $script:SummaryBadgeID
                SummaryManager     = $script:SummaryManager
                SummaryDN          = $script:SummaryDN
                MinButton          = $script:MinButton
                MaxButton          = $script:MaxButton
                ExitButton         = $script:ExitButton
                DebugPanel         = $script:DebugPanel
                DebugOutputBox     = $script:DebugOutputBox
            }

            foreach ($key in $requiredControls.Keys) {
                if (-not $requiredControls[$key]) {
                    throw "Required UI control not found: $key"
                }
            }

            $parentGrid = $script:DebugPanel.Parent
            if (-not $parentGrid -or -not $parentGrid.RowDefinitions -or $parentGrid.RowDefinitions.Count -lt 3) {
                throw "DebugPanel parent grid/row definition not found."
            }

            $script:DebugRow = $parentGrid.RowDefinitions[2]

            if ($Global:DebugMode) {
                $script:DebugPanel.Visibility = "Visible"
                $script:DebugRow.Height = New-Object System.Windows.GridLength(220)
                if (-not $script:DebugHeightAdded) {
                    $script:MainWindow.Height = $script:MainWindow.Height + 240
                    $script:MainWindow.MinHeight = [Math]::Max($script:MainWindow.MinHeight, 1090)
                    $script:DebugHeightAdded = $true
                }
            }
            else {
                $script:DebugPanel.Visibility = "Collapsed"
                $script:DebugRow.Height = New-Object System.Windows.GridLength(0)
            }

            Write-DebugLog "UI controls mapped successfully." "SUCCESS"

            Attach-UIEvents

            Show-RootMenu
            Show-NoUserMessage

            Write-DebugLog "Loaded event completed successfully. Module loading will begin after first render." "SUCCESS"
        }
        catch {
            Write-Host ""
            Write-Host "================ LOADED EVENT EXCEPTION ================" -ForegroundColor Red
            Write-Host "MESSAGE: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "TYPE:    $($_.Exception.GetType().FullName)" -ForegroundColor Yellow
            Write-Host "STACK:" -ForegroundColor Yellow
            Write-Host "$($_.Exception.StackTrace)"
            Write-Host "========================================================" -ForegroundColor Red
            Write-Host ""

            Write-DebugLog "Loaded event failed: $($_.Exception.Message)" "ERROR"
            try { Fade-OutLoadingOverlay } catch {}
        }
    })


    $script:StartupInitializationStarted = $false
    $script:MainWindow.Add_ContentRendered({
        if ($script:StartupInitializationStarted) { return }
        $script:StartupInitializationStarted = $true

        try {
            Show-LoadingOverlay
            Set-LoadingStatus "Initializing Atlas Dashboard..." 3
            Do-Events
            Initialize-Modules
            Fade-OutLoadingOverlay
        }
        catch {
            Write-DebugLog "Startup initialization failed: $($_.Exception.Message)" "ERROR"
            try { Fade-OutLoadingOverlay } catch {}
        }
    })

    $script:MainWindow.Add_Closed({
        try {
            [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
        }
        catch {}
    })

    # ---------------------------------------------------------
    # 5. Run the WPF application.
    # ---------------------------------------------------------
    Write-DebugLog "Window opening..." "INFO"
    [void]$script:App.Run($script:MainWindow)
}
catch {
    Write-Host "DASHBOARD FAILED TO START: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.InnerException) {
        Write-Host "INNER EXCEPTION: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
    throw
}
