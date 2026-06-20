<#
================================================================================
Atlas-Tech New User Wizard
Author: Zach Little
Purpose:
    A full WPF-based PowerShell wizard for creating new Active Directory users,
    enabling remote mailboxes (hybrid Exchange), assigning security groups,
    sending onboarding notifications, and guiding JAMIS claim account setup.

Major Components:
    • STA Relaunch Handler
        Ensures the script runs in a Single-Threaded Apartment (STA) so that
        WPF works correctly. Relaunches itself once with -STA if required.

    • XAML UI Loader
        Loads the main window and all pages (1–4), merges shared theme
        resources, and initializes UI element bindings.

    • Dynamic Navigation Engine
        Handles forward/backward movement between steps, including readiness
        checks, intake form validation, and review/execute logic.

    • Readiness Checks (Page 2)
        Non-blocking environment checks for:
            - RSAT Active Directory module + connectivity
            - Microsoft Graph module + app-based authentication
            - Hybrid Exchange snap‑in or remote PowerShell session
        Failures produce reminders but do NOT halt the wizard.

    • User Creation Pipeline
        Creates the AD account, assigns the correct OU, applies attributes,
        adds security groups, optionally creates a remote mailbox, sends a
        new-hire notification, and launches JAMIS claim setup.

    • Review Page (Page 4)
        Summarizes all collected values and projected group assignments
        before creation. Blocks progression if validation fails.

Debug Mode:
    • Enable with:  -Debug
    • Shows a collapsible debug pane at the bottom of the window.
    • Logs UI events, AD/Graph/Exchange steps, parameter values,
      validation results, errors, and workflow checkpoints.
    • Toggle during runtime using the ☰ button in the lower-left corner.

-NoNet Mode:
    • Enable with:  -NoNet
    • Skips loading config.json/aes.key, skips AD/Graph/Exchange checks,
      and disables *all network/creation* actions.
    • Wizard still fully loads for offline demonstration, UI preview,
      or troubleshooting layout/logic without touching production systems.

================================================================================#>
param(
    [switch]$Debug,
    [switch]$NoNet,
    [switch]$StaRelaunched
)

# WPF must run in an STA host. Do not use a process environment flag here;
# that flag stays behind in the parent PowerShell session and breaks later runs.
# Instead, relaunch once with a private script switch.
try { [Environment]::SetEnvironmentVariable('NEW_USER_WIZARD_STA_RELAUNCHED', $null, 'Process') } catch {}
$script:HostArgs = [Environment]::GetCommandLineArgs()
$script:HostWasStartedWithSta = @($script:HostArgs | Where-Object { $_ -match '^-STA$' }).Count -gt 0

if (-not $StaRelaunched.IsPresent -and -not $script:HostWasStartedWithSta) {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
        $winPs = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path $winPs)) { $winPs = 'powershell.exe' }

        $relaunchArgs = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-STA',
            '-File', $scriptPath
        )

        if ($Debug.IsPresent) { $relaunchArgs += '-Debug' }
        if ($NoNet.IsPresent) { $relaunchArgs += '-NoNet' }
        $relaunchArgs += '-StaRelaunched'

        & $winPs @relaunchArgs
        exit $LASTEXITCODE
    }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ============================================================
# Safe XAML Loader
# ============================================================
function Load-XamlString {
    param([Parameter(Mandatory)][string]$Xaml)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Xaml)
    $stream = New-Object System.IO.MemoryStream
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Position = 0

    return [Windows.Markup.XamlReader]::Load($stream)
}

function Do-Events {
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
        [Action]{},
        [System.Windows.Threading.DispatcherPriority]::Background
    )
}

# ============================================================
# UI Debug Logger
# ============================================================
$Global:DebugMode = $Debug.IsPresent
$Global:NoNet = $NoNet.IsPresent
$Global:DebugPaneExpanded = $false
$Global:DebugBaseWindowHeight = $null

function Write-DebugLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "[$timestamp][$Level] $Message"

    if ($Global:DebugMode) {
        Write-Host $line
    }

    try {
        if ($script:DebugOutputBox) {
            $script:DebugOutputBox.Dispatcher.Invoke([Action]{
                $script:DebugOutputBox.AppendText($line + [Environment]::NewLine)
                $script:DebugOutputBox.ScrollToEnd()
            })
        }
    }
    catch {
        # Do not allow debug logging to interrupt the wizard.
    }
}


function Write-DebugException {
    param(
        [Parameter(Mandatory)][System.Exception]$Exception,
        [string]$Context = "Exception"
    )

    Write-DebugLog "[$Context] $($Exception.Message)" "ERROR"

    if ($Exception.InnerException) {
        Write-DebugLog "[$Context] Inner Exception: $($Exception.InnerException.Message)" "ERROR"
    }

    # Stack trace
    if ($Exception.StackTrace) {
        Write-DebugLog "[$Context] Stack Trace:`n$($Exception.StackTrace)" "ERROR"
    }

    # PS extended exception data
    if ($Exception.PSObject.Properties["InvocationInfo"]) {
        Write-DebugLog "[$Context] Script Line: $($Exception.InvocationInfo.Line)" "ERROR"
        Write-DebugLog "[$Context] Offset: $($Exception.InvocationInfo.OffsetInLine)" "ERROR"
        Write-DebugLog "[$Context] Position: $($Exception.InvocationInfo.PositionMessage)" "ERROR"
    }
}


function Set-DebugMode {
    param([bool]$Enabled)

    $Global:DebugMode = $Enabled

    try {
        if ($script:DebugRowDefinition) {
            if ($Enabled) {
                $script:DebugRowDefinition.Height = New-Object System.Windows.GridLength(220)
            }
            else {
                $script:DebugRowDefinition.Height = New-Object System.Windows.GridLength(0)
            }
        }

        if ($script:DebugPanel) {
            $script:DebugPanel.Visibility = if ($Enabled) { "Visible" } else { "Collapsed" }
        }

        if ($script:DebugToggleIcon) {
            $script:DebugToggleIcon.Foreground = ([System.Windows.Media.BrushConverter]::new()).ConvertFromString($(if ($Enabled) { "#FE5000" } else { "#AA7E91AA" }))
        }

        if ($script:DebugTogglePanel) {
            $script:DebugTogglePanel.BorderBrush = ([System.Windows.Media.BrushConverter]::new()).ConvertFromString($(if ($Enabled) { "#FE5000" } else { "#668DA8D8" }))
        }

        if ($script:MainWindow -and $null -ne $Global:DebugBaseWindowHeight) {
            if ($Enabled) {
                $script:MainWindow.Height = $Global:DebugBaseWindowHeight + 230
                $script:MainWindow.MinHeight = [Math]::Max($script:MainWindow.MinHeight, 990)
            }
            else {
                $script:MainWindow.Height = $Global:DebugBaseWindowHeight
            }
        }

        $stateText = if ($Enabled) { "enabled" } else { "disabled" }
        Write-DebugLog "Debug mode $stateText." "SUCCESS"
    }
    catch {
        Write-Host "Failed to toggle debug pane: $($_.Exception.Message)"
    }
}

function Toggle-DebugMode {
    Set-DebugMode -Enabled (-not $Global:DebugMode)
}

#===================================================
#                Helper Functions
#===================================================
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
    Write-DebugLog "-NoNet enabled. Skipping config.json/aes.key loading." "WARN"
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
        Write-DebugLog "Secure configuration decrypted successfully. Client Secret Available!" "SUCCESS"
    }
    catch {
        Write-DebugLog "Unable to decrypt client secret. Check config.json and aes.key!" "WARN"
		$ClientSecretPlain = "TEST"
    }

    try {
        $TempPasswordPlain = Decrypt-Value $Config.temp_password $AESKey
        Write-DebugLog "Secure configuration decrypted successfully. Temp Password Available!" "SUCCESS"
    }
    catch {
        Write-DebugLog "Unable to decrypt Temp Password. Check config.json and aes.key!" "WARN"
		$TempPasswordPlain = "P@ssword123!"
    }
}

#Exit function
function Invoke-WizardCleanup {

    Write-DebugLog "Starting cleanup..." "INFO"

    if ($Global:NoNet) {
        Write-DebugLog "-NoNet enabled. Skipping Graph/Exchange/AD cleanup." "INFO"
        return
    }

    # ---------------------------
    # 1. Disconnect Microsoft Graph
    # ---------------------------
    try {
        if (Get-MgContext -ErrorAction SilentlyContinue) {
            Write-DebugLog "Disconnecting Microsoft Graph session..." "INFO"
            Disconnect-MgGraph -ErrorAction Stop
            Write-DebugLog "Graph disconnected." "SUCCESS"
        }
    }
    catch {
        Write-DebugLog "Error disconnecting Graph: $($_.Exception.Message)" "WARN"
    }

    # ---------------------------
    # 2. Remove Exchange Remote Session
    # ---------------------------
    try {
        $exchangeSessions = Get-PSSession | Where-Object {
            $_.ConfigurationName -eq "Microsoft.Exchange"
        }

        foreach ($session in $exchangeSessions) {
            Write-DebugLog "Removing Exchange remote PSSession ID $($session.Id)..." "INFO"
            Remove-PSSession $session -ErrorAction Stop
        }
    }
    catch {
        Write-DebugLog "Error removing Exchange sessions: $($_.Exception.Message)" "WARN"
    }

    # ---------------------------
    # 3. Remove Exchange Snap-ins
    # ---------------------------
    foreach ($snap in @(
        "Microsoft.Exchange.Management.PowerShell.SnapIn",
        "Microsoft.Exchange.Management.PowerShell.E2010"
    )) {
        try {
            if (Get-PSSnapin -Registered -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $snap }) {
                if (Get-PSSnapin -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $snap }) {
                    Write-DebugLog "Removing Exchange snap-in $snap..." "INFO"
                    Remove-PSSnapin $snap -ErrorAction Stop
                    Write-DebugLog "Removed snap-in $snap." "SUCCESS"
                }
            }
        }
        catch {
            Write-DebugLog "Error removing snap-in $snap : $($_.Exception.Message)" "WARN"
        }
    }

    # ---------------------------
    # 4. Remove Imported Modules
    # ---------------------------

    # AD
    try {
        if (Get-Module ActiveDirectory -ErrorAction SilentlyContinue) {
            Write-DebugLog "Unloading ActiveDirectory module..." "INFO"
            Remove-Module ActiveDirectory -ErrorAction Stop
            Write-DebugLog "ActiveDirectory module unloaded." "SUCCESS"
        }
    }
    catch {
        Write-DebugLog "Error unloading ActiveDirectory: $($_.Exception.Message)" "WARN"
    }

    # Microsoft Graph
    try {
        if (Get-Module Microsoft.Graph* -ErrorAction SilentlyContinue) {
            Write-DebugLog "Unloading Microsoft Graph modules..." "INFO"
            Get-Module Microsoft.Graph* | Remove-Module -Force -ErrorAction Stop
            Write-DebugLog "Graph modules unloaded." "SUCCESS"
        }
    }
    catch {
        Write-DebugLog "Error unloading Graph modules: $($_.Exception.Message)" "WARN"
    }

    # ---------------------------
    # 5. Remove orphaned runspace sessions
    # ---------------------------
    try {
        Get-PSSession | ForEach-Object {
            Write-DebugLog "Removing orphaned PSSession ID $($_.Id)..." "INFO"
            Remove-PSSession $_ -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-DebugLog "Cleanup of orphaned sessions failed: $($_.Exception.Message)" "WARN"
    }

    # ---------------------------
    # 6. Clear sensitive strings from memory
    # ---------------------------
    try {
        $script:ClientSecretPlain = $null
        $script:TempPasswordPlain = $null
        Write-DebugLog "Sensitive variables cleared from memory." "INFO"
    }
    catch {
        Write-DebugLog "Failed clearing sensitive variables: $($_.Exception.Message)" "WARN"
    }

    Write-DebugLog "Cleanup complete." "SUCCESS"
}


# ============================================================
# Theme XAML - Futuristic Glass
# ============================================================
$XamlTheme = @'
<ResourceDictionary
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <FontFamily x:Key="AppFont">Segoe UI Variable Display, Segoe UI</FontFamily>

    <SolidColorBrush x:Key="TextMain" Color="#FFF5F7FA"/>
    <SolidColorBrush x:Key="TextMuted" Color="#DDE6F2FF"/>
    <SolidColorBrush x:Key="TextSoft" Color="#AFC8DAEF"/>
    <SolidColorBrush x:Key="Accent" Color="#FE7A00"/>
    <SolidColorBrush x:Key="Accent2" Color="#FF6A00"/>
	<SolidColorBrush x:Key="Accent3" Color="#FE5000"/>
    <SolidColorBrush x:Key="Success" Color="#FF4CFF66"/>
    <SolidColorBrush x:Key="Warning" Color="#FFFFC857"/>
    <SolidColorBrush x:Key="Error" Color="#FFFF5C7A"/>
	
    <LinearGradientBrush x:Key="MainGradient" StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#FF061321" Offset="0"/>
        <GradientStop Color="#FF081B35" Offset="0.42"/>
        <GradientStop Color="#FF10193F" Offset="1"/>
    </LinearGradientBrush>

    <LinearGradientBrush x:Key="GlassGradient" StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#88184261" Offset="0"/>
        <GradientStop Color="#5F13254B" Offset="0.45"/>
        <GradientStop Color="#806468AD" Offset="1"/>
    </LinearGradientBrush>

    <LinearGradientBrush x:Key="GlassHeaderGradient" StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#33111D36" Offset="0"/>
        <GradientStop Color="#441A2F5A" Offset="0.5"/>
        <GradientStop Color="#22233E69" Offset="1"/>
    </LinearGradientBrush>

    <LinearGradientBrush x:Key="GlassCardGradient" StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#4E15314D" Offset="0"/>
        <GradientStop Color="#3B1A2D56" Offset="0.5"/>
        <GradientStop Color="#503B3F7F" Offset="1"/>
    </LinearGradientBrush>

    <LinearGradientBrush x:Key="AccentGradient" StartPoint="0,0" EndPoint="1,0">	
		<GradientStop Color="#FFFF8A00" Offset="0"/>
		<GradientStop Color="#FFFF7A00" Offset="0.55"/>
		<GradientStop Color="#FFFE5000" Offset="1"/>
	</LinearGradientBrush>

    <DropShadowEffect x:Key="CyanGlow"
                  Color="#64C7FF"
                  BlurRadius="34"
                  ShadowDepth="0"
                  Opacity="0.62"/>

    <DropShadowEffect x:Key="SoftBlueGlow"
                  Color="#3D63D8"
                  BlurRadius="56"
                  ShadowDepth="0"
                  Opacity="0.42"/>

    <DropShadowEffect x:Key="PanelShadow"
                      Color="#000000"
                      BlurRadius="32"
                      ShadowDepth="10"
                      Opacity="0.36"/>

    <Style x:Key="WindowChromeButton" TargetType="Button">
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="Foreground" Value="#DDEAF4FF"/>
        <Setter Property="FontSize" Value="26"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Width" Value="48"/>
        <Setter Property="Height" Value="38"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Background" Value="#00000000"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="Root" Background="{TemplateBinding Background}" CornerRadius="10">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Root" Property="Background" Value="#22FFFFFF"/>
                        </Trigger>
                        <Trigger Property="IsPressed" Value="True">
                            <Setter TargetName="Root" Property="Background" Value="#33FFFFFF"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style x:Key="GlassPanel" TargetType="Border">
        <Setter Property="CornerRadius" Value="24"/>
        <Setter Property="Padding" Value="24"/>
        <Setter Property="Background" Value="{StaticResource GlassGradient}"/>
        <Setter Property="BorderBrush" Value="#99A9C8FF"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Effect" Value="{StaticResource SoftBlueGlow}"/>
    </Style>

    <Style x:Key="GlassShell" TargetType="Border">
        <Setter Property="CornerRadius" Value="28"/>
        <Setter Property="Padding" Value="20"/>
        <Setter Property="Background" Value="{StaticResource MainGradient}"/>
        <Setter Property="BorderBrush" Value="#446EA0C8"/>
        <Setter Property="BorderThickness" Value="1"/>
    </Style>

    <Style x:Key="SoftCard" TargetType="Border">
        <Setter Property="CornerRadius" Value="20"/>
        <Setter Property="Padding" Value="18"/>
        <Setter Property="MinHeight" Value="120"/>
        <Setter Property="Background" Value="{StaticResource GlassCardGradient}"/>
        <Setter Property="BorderBrush" Value="#445F8EC8"/>
        <Setter Property="BorderThickness" Value="1"/>
    </Style>

    <Style x:Key="IconTile" TargetType="Border">
        <Setter Property="Width" Value="96"/>
        <Setter Property="Height" Value="96"/>
        <Setter Property="CornerRadius" Value="16"/>
        <Setter Property="Background" Value="#33385F76"/>
        <Setter Property="BorderBrush" Value="#446EA0C8"/>
        <Setter Property="BorderThickness" Value="1"/>
    </Style>

    <Style x:Key="PrimaryButton" TargetType="Button">
		<Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
		<Setter Property="Foreground" Value="#FF001018"/>
		<Setter Property="FontWeight" Value="SemiBold"/>
		<Setter Property="FontSize" Value="23"/>
		<Setter Property="Padding" Value="24,14"/>
		<Setter Property="Background" Value="{StaticResource AccentGradient}"/>
		<Setter Property="BorderThickness" Value="0"/>
		<Setter Property="Cursor" Value="Hand"/>
		<Setter Property="MinHeight" Value="58"/>

		<Setter Property="Template">
			<Setter.Value>
				<ControlTemplate TargetType="Button">
					<Border x:Name="Root"
							Background="{TemplateBinding Background}"
							CornerRadius="18"
							BorderBrush="#55FFFFFF"
							BorderThickness="1"
							Padding="{TemplateBinding Padding}"
							Effect="{StaticResource CyanGlow}">

						<ContentPresenter HorizontalAlignment="Center"
										  VerticalAlignment="Center"/>
					</Border>

					<ControlTemplate.Triggers>
						<Trigger Property="IsMouseOver" Value="True">
							<Setter TargetName="Root" Property="Opacity" Value="0.9"/>
						</Trigger>
						<Trigger Property="IsPressed" Value="True">
							<Setter TargetName="Root" Property="Opacity" Value="0.72"/>
						</Trigger>
						<Trigger Property="IsEnabled" Value="False">
							<Setter TargetName="Root" Property="Opacity" Value="0.35"/>
						</Trigger>
					</ControlTemplate.Triggers>

				</ControlTemplate>
			</Setter.Value>
		</Setter>
	</Style>

    <Style x:Key="GlassButton" TargetType="Button">
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
        <Setter Property="FontSize" Value="21"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="BorderBrush" Value="#668DA8D8"/>
        <Setter Property="Background" Value="#33182745"/>
        <Setter Property="Padding" Value="20,12"/>
        <Setter Property="MinHeight" Value="58"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="Root"
                            CornerRadius="16"
                            Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}"
                            Padding="{TemplateBinding Padding}">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Root" Property="Background" Value="#44223B65"/>
                            <Setter TargetName="Root" Property="BorderBrush" Value="#99A9C8FF"/>
                        </Trigger>
                        <Trigger Property="IsPressed" Value="True">
                            <Setter TargetName="Root" Property="Opacity" Value="0.75"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter TargetName="Root" Property="Opacity" Value="0.35"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style x:Key="TitleText" TargetType="TextBlock">
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
        <Setter Property="FontSize" Value="40"/>
        <Setter Property="FontWeight" Value="Bold"/>
        <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>

    <Style x:Key="SubtitleText" TargetType="TextBlock">
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="Foreground" Value="{StaticResource TextMuted}"/>
        <Setter Property="FontSize" Value="20"/>
        <Setter Property="LineHeight" Value="30"/>
        <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>

    <Style x:Key="CardHeaderText" TargetType="TextBlock">
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="Foreground" Value="White"/>
        <Setter Property="FontSize" Value="27"/>
        <Setter Property="FontWeight" Value="Bold"/>
        <Setter Property="Effect" Value="{StaticResource CyanGlow}"/>
    </Style>

    <Style x:Key="CardBodyText" TargetType="TextBlock">
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="Foreground" Value="White"/>
        <Setter Property="FontSize" Value="22"/>
        <Setter Property="LineHeight" Value="33"/>
        <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>

    <Style x:Key="StatusText" TargetType="TextBlock">
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="FontSize" Value="17"/>
        <Setter Property="Foreground" Value="{StaticResource TextMuted}"/>
        <Setter Property="Margin" Value="0,6,0,6"/>
        <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>

    <Style x:Key="StatusSuccess" TargetType="TextBlock" BasedOn="{StaticResource StatusText}">
        <Setter Property="Foreground" Value="{StaticResource Success}"/>
    </Style>

    <Style x:Key="StatusWarning" TargetType="TextBlock" BasedOn="{StaticResource StatusText}">
        <Setter Property="Foreground" Value="{StaticResource Warning}"/>
    </Style>

    <Style x:Key="StatusError" TargetType="TextBlock" BasedOn="{StaticResource StatusText}">
        <Setter Property="Foreground" Value="{StaticResource Error}"/>
    </Style>
	
	
	
	<Style TargetType="ScrollBar">
		<Setter Property="Width" Value="10"/>
		<Setter Property="Foreground" Value="#99A9C8FF"/>
		<Setter Property="Background" Value="#22091522"/>

		<Setter Property="Template">
			<Setter.Value>
				<ControlTemplate TargetType="ScrollBar">
					<Grid>

						<!-- Vertical ScrollBar -->
						<Grid x:Name="VerticalRoot" Visibility="Collapsed">
							<Rectangle Fill="#22091522"/>

							<Track x:Name="PART_Track"
								   Orientation="Vertical">

								<Track.Thumb>
									<Thumb>
										<Thumb.Template>
											<ControlTemplate TargetType="Thumb">
												<Border Background="#557FB8E8"
														BorderBrush="#88A9C8FF"
														BorderThickness="1"
														CornerRadius="5">
													<Border.Effect>
														<DropShadowEffect Color="#3D63D8"
																		  BlurRadius="16"
																		  ShadowDepth="0"
																		  Opacity="0.55"/>
													</Border.Effect>
												</Border>
											</ControlTemplate>
										</Thumb.Template>
									</Thumb>
								</Track.Thumb>

							</Track>
						</Grid>

						<!-- Horizontal ScrollBar -->
						<Grid x:Name="HorizontalRoot" Visibility="Collapsed">
							<Rectangle Fill="#22091522"/>

							<Track x:Name="PART_Track_H"
								   Orientation="Horizontal">

								<Track.Thumb>
									<Thumb>
										<Thumb.Template>
											<ControlTemplate TargetType="Thumb">
												<Border Background="#557FB8E8"
														BorderBrush="#88A9C8FF"
														BorderThickness="1"
														CornerRadius="5">
													<Border.Effect>
														<DropShadowEffect Color="#3D63D8"
																		  BlurRadius="16"
																		  ShadowDepth="0"
																		  Opacity="0.55"/>
													</Border.Effect>
												</Border>
											</ControlTemplate>
										</Thumb.Template>
									</Thumb>
								</Track.Thumb>

							</Track>
						</Grid>

					</Grid>

					<ControlTemplate.Triggers>

						<!-- When ScrollBar is vertical -->
						<Trigger Property="Orientation" Value="Vertical">
							<Setter TargetName="VerticalRoot" Property="Visibility" Value="Visible"/>
							<Setter TargetName="HorizontalRoot" Property="Visibility" Value="Collapsed"/>
						</Trigger>

						<!-- When ScrollBar is horizontal -->
						<Trigger Property="Orientation" Value="Horizontal">
							<Setter TargetName="HorizontalRoot" Property="Visibility" Value="Visible"/>
							<Setter TargetName="VerticalRoot" Property="Visibility" Value="Collapsed"/>
						</Trigger>

					</ControlTemplate.Triggers>
				</ControlTemplate>
			</Setter.Value>
		</Setter>
	</Style>




    <!-- ============================================================
         Shared Page Styles
         These used to be repeated inside each Page.Resources block.
         They live in the shared dictionary now, and the script loads
         this dictionary is also merged into each page after parsing
         so DynamicResource references resolve reliably in a Frame.
         ============================================================ -->

    <Style x:Key="StartButtonStyle" TargetType="Button">
    			<Setter Property="Foreground" Value="#FF001018"/>
    			<Setter Property="FontWeight" Value="Bold"/>
    			<Setter Property="FontSize" Value="24"/>
    			<Setter Property="Cursor" Value="Hand"/>
    			<Setter Property="BorderThickness" Value="0"/>
    			<Setter Property="Padding" Value="24,14"/>
    
    			<Setter Property="Template">
    				<Setter.Value>
    					<ControlTemplate TargetType="Button">
    
    						<Border x:Name="Root"
    								CornerRadius="28"
    								BorderBrush="#55FFFFFF"
    								BorderThickness="1"
    								Padding="{TemplateBinding Padding}"
    								Effect="{DynamicResource CyanGlow}">
    
    							<!-- FIXED: Now uses your orange AccentGradient -->
    							<Border.Background>
    								<StaticResource ResourceKey="AccentGradient"/>
    							</Border.Background>
    
    							<Grid>
    								<!-- Glossy highlight -->
    								<Border Height="22"
    										VerticalAlignment="Top"
    										Margin="12,8,12,0"
    										CornerRadius="12"
    										Opacity="0.20">
    									<Border.Background>
    										<LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
    											<GradientStop Color="#FFFFFFFF" Offset="0"/>
    											<GradientStop Color="#00FFFFFF" Offset="1"/>
    										</LinearGradientBrush>
    									</Border.Background>
    								</Border>
    
    								<ContentPresenter HorizontalAlignment="Center"
    												  VerticalAlignment="Center"/>
    							</Grid>
    						</Border>
    
    						<ControlTemplate.Triggers>
    							<Trigger Property="IsMouseOver" Value="True">
    								<Setter TargetName="Root" Property="Opacity" Value="0.92"/>
    							</Trigger>
    
    							<Trigger Property="IsPressed" Value="True">
    								<Setter TargetName="Root" Property="Opacity" Value="0.75"/>
    							</Trigger>
    
    						</ControlTemplate.Triggers>
    
    					</ControlTemplate>
    				</Setter.Value>
    			</Setter>
    		</Style>

    <Style x:Key="Page2CardHeaderText" TargetType="TextBlock">
                <Setter Property="FontFamily" Value="{DynamicResource AppFont}"/>
                <Setter Property="FontSize" Value="26"/>
                <Setter Property="FontWeight" Value="Bold"/>
                <Setter Property="Foreground" Value="White"/>
                <Setter Property="Effect">
                    <Setter.Value>
                        <DropShadowEffect Color="#FE7A00"
                                          BlurRadius="14"
                                          ShadowDepth="0"
                                          Opacity="0.55"/>
                    </Setter.Value>
                </Setter>
            </Style>

    <Style x:Key="Page2BodyText" TargetType="TextBlock">
                <Setter Property="FontFamily" Value="{DynamicResource AppFont}"/>
                <Setter Property="FontSize" Value="19"/>
                <Setter Property="Foreground" Value="White"/>
                <Setter Property="TextWrapping" Value="Wrap"/>
                <Setter Property="LineHeight" Value="29"/>
            </Style>

    <Style x:Key="Page2StatusText" TargetType="TextBlock">
                <Setter Property="FontFamily" Value="{DynamicResource AppFont}"/>
                <Setter Property="FontSize" Value="18"/>
                <Setter Property="Foreground" Value="White"/>
                <Setter Property="Margin" Value="0,8,0,0"/>
                <Setter Property="TextWrapping" Value="Wrap"/>
                <Setter Property="LineHeight" Value="27"/>
            </Style>

    <Style x:Key="FieldLabel" TargetType="TextBlock">
                <Setter Property="FontFamily" Value="{DynamicResource AppFont}"/>
                <Setter Property="FontSize" Value="16"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
                <Setter Property="Foreground" Value="White"/>
                <Setter Property="Margin" Value="0,0,0,6"/>
            </Style>

    <Style x:Key="GlassInput" TargetType="TextBox">
                <Setter Property="FontFamily" Value="{DynamicResource AppFont}"/>
                <Setter Property="FontSize" Value="18"/>
                <Setter Property="Foreground" Value="White"/>
                <Setter Property="CaretBrush" Value="{DynamicResource Accent}"/>
                <Setter Property="Background" Value="#FF0B1730"/>
    			<Setter Property="BorderBrush" Value="#557FB8E8"/>
    			<Setter Property="Foreground" Value="White"/>
                <Setter Property="BorderBrush" Value="#557FB8E8"/>
                <Setter Property="BorderThickness" Value="1"/>
                <Setter Property="Padding" Value="14,10"/>
                <Setter Property="MinHeight" Value="46"/>
            </Style>

    <Style x:Key="GlassCombo" TargetType="ComboBox">
    
    			<Style.Resources>
    
    				<SolidColorBrush x:Key="{x:Static SystemColors.WindowBrushKey}"
    								 Color="#0B1730"/>
    
    				<SolidColorBrush x:Key="{x:Static SystemColors.ControlBrushKey}"
    								 Color="#0B1730"/>
    
    			</Style.Resources>
    
    			<Setter Property="OverridesDefaultStyle" Value="False"/>
    			<Setter Property="FontFamily" Value="{DynamicResource AppFont}"/>
    			<Setter Property="FontSize" Value="17"/>
    			<Setter Property="Foreground" Value="White"/>
    			<Setter Property="Background" Value="#FF0B1730"/>
    			<Setter Property="BorderBrush" Value="#557FB8E8"/>
    			<Setter Property="BorderThickness" Value="1"/>
    			<Setter Property="Padding" Value="10,8"/>
    			<Setter Property="MinHeight" Value="46"/>
    
    			<Setter Property="ItemContainerStyle">
    				<Setter.Value>
    					<Style TargetType="ComboBoxItem">
    						<Setter Property="Foreground" Value="White"/>
    						<Setter Property="Background" Value="#FF0B1730"/>
    						<Setter Property="Padding" Value="10,8"/>
    
    						<Style.Triggers>
    							<Trigger Property="IsHighlighted" Value="True">
    								<Setter Property="Background" Value="#FF16345C"/>
    							</Trigger>
    						</Style.Triggers>
    					</Style>
    				</Setter.Value>
    			</Setter>
    
    		</Style>

    <Style TargetType="{x:Type TextBox}">
    			<Setter Property="Background" Value="#FF0B1730"/>
    			<Setter Property="Foreground" Value="White"/>
    			<Setter Property="BorderBrush" Value="#557FB8E8"/>
    		</Style>

    <Style x:Key="FormCard" TargetType="Border">
                <Setter Property="CornerRadius" Value="20"/>
                <Setter Property="BorderBrush" Value="#557FB8E8"/>
                <Setter Property="BorderThickness" Value="1"/>
                <Setter Property="Background" Value="#38132640"/>
                <Setter Property="Padding" Value="22"/>
                <Setter Property="Margin" Value="0,0,0,18"/>
                <Setter Property="Effect">
                    <Setter.Value>
                        <DropShadowEffect Color="#335EA8FF"
                                          BlurRadius="22"
                                          ShadowDepth="0"
                                          Opacity="0.45"/>
                    </Setter.Value>
                </Setter>
            </Style>

    <Style x:Key="SectionHeader" TargetType="TextBlock">
                <Setter Property="FontFamily" Value="{DynamicResource AppFont}"/>
                <Setter Property="FontSize" Value="26"/>
                <Setter Property="FontWeight" Value="Bold"/>
                <Setter Property="Foreground" Value="White"/>
                <Setter Property="Margin" Value="0,0,0,18"/>
                <Setter Property="Effect">
                    <Setter.Value>
                        <DropShadowEffect Color="#FE7A00"
                                          BlurRadius="14"
                                          ShadowDepth="0"
                                          Opacity="0.55"/>
                    </Setter.Value>
                </Setter>
            </Style>

    <Style x:Key="ReviewLabel" TargetType="TextBlock">
                <Setter Property="FontFamily" Value="{DynamicResource AppFont}"/>
                <Setter Property="FontSize" Value="15"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
                <Setter Property="Foreground" Value="#CCFFFFFF"/>
                <Setter Property="Margin" Value="0,0,0,4"/>
            </Style>

    <Style x:Key="ReviewValue" TargetType="TextBlock">
                <Setter Property="FontFamily" Value="{DynamicResource AppFont}"/>
                <Setter Property="FontSize" Value="18"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
                <Setter Property="Foreground" Value="White"/>
                <Setter Property="TextWrapping" Value="Wrap"/>
                <Setter Property="Margin" Value="0,0,0,16"/>
            </Style>

    <Style x:Key="ReviewCard" TargetType="Border">
                <Setter Property="CornerRadius" Value="20"/>
                <Setter Property="BorderBrush" Value="#557FB8E8"/>
                <Setter Property="BorderThickness" Value="1"/>
                <Setter Property="Background" Value="#38132640"/>
                <Setter Property="Padding" Value="22"/>
                <Setter Property="Margin" Value="0,0,0,18"/>
            </Style>

</ResourceDictionary>
'@


# ============================================================
# XAML Generators
# ============================================================
function ConvertTo-XamlText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return "" }
    return [System.Security.SecurityElement]::Escape($Text)
}

function New-FeatureCardXaml {
    param(
        [Parameter(Mandatory)][string]$Icon,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Body,
        [string]$Margin = "0,0,0,20"
    )

@"
                <Border CornerRadius="20"
                        BorderBrush="#557FB8E8"
                        BorderThickness="1"
                        Background="#38132640"
                        Padding="18"
                        MinHeight="124"
                        Margin="$Margin">
                    <Border.Effect>
                        <DropShadowEffect Color="#335EA8FF"
                                          BlurRadius="22"
                                          ShadowDepth="0"
                                          Opacity="0.45"/>
                    </Border.Effect>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="126"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Width="96"
                                Height="96"
                                CornerRadius="16"
                                Background="#33385F76"
                                BorderBrush="#557FB8E8"
                                BorderThickness="1">
                            <TextBlock Text="$(ConvertTo-XamlText $Icon)"
                                       FontSize="46"
                                       Foreground="{DynamicResource Accent3}"
                                       HorizontalAlignment="Center"
                                       VerticalAlignment="Center"/>
                        </Border>
                        <StackPanel Grid.Column="1"
                                    VerticalAlignment="Center"
                                    Margin="20,0,0,0">
                            <TextBlock Text="$(ConvertTo-XamlText $Title)"
                                       Style="{DynamicResource CardHeaderText}"/>
                            <TextBlock Text="$(ConvertTo-XamlText $Body)"
                                       Style="{DynamicResource CardBodyText}"
                                       Margin="0,10,0,0"/>
                        </StackPanel>
                    </Grid>
                </Border>
"@
}

function New-ReadinessCardXaml {
    param(
        [Parameter(Mandatory)][string]$Icon,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$StatusName1,
        [Parameter(Mandatory)][string]$StatusText1,
        [Parameter(Mandatory)][string]$StatusName2,
        [Parameter(Mandatory)][string]$StatusText2,
        [string]$Margin = "0,0,0,18",
        [string]$CardBackground = "#38132640",
        [string]$IconFontSize = "44"
    )

@"
                <Border CornerRadius="20"
                        BorderBrush="#557FB8E8"
                        BorderThickness="1"
                        Background="$CardBackground"
                        Padding="18"
                        MinHeight="134"
                        Margin="$Margin">
                    <Border.Effect>
                        <DropShadowEffect Color="#335EA8FF"
                                          BlurRadius="22"
                                          ShadowDepth="0"
                                          Opacity="0.45"/>
                    </Border.Effect>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="126"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Width="96"
                                Height="96"
                                CornerRadius="16"
                                Background="#33385F76"
                                BorderBrush="#557FB8E8"
                                BorderThickness="1">
                            <TextBlock Text="$(ConvertTo-XamlText $Icon)"
                                       FontFamily="{DynamicResource AppFont}"
                                       FontSize="$IconFontSize"
                                       FontWeight="Bold"
                                       Foreground="{DynamicResource Accent3}"
                                       HorizontalAlignment="Center"
                                       VerticalAlignment="Center"/>
                        </Border>
                        <StackPanel Grid.Column="1"
                                    VerticalAlignment="Center"
                                    Margin="20,0,0,0">
                            <TextBlock Text="$(ConvertTo-XamlText $Title)"
                                       Style="{DynamicResource Page2CardHeaderText}"/>
                            <TextBlock x:Name="$StatusName1"
                                       Style="{DynamicResource Page2StatusText}"
                                       Text="$(ConvertTo-XamlText $StatusText1)"/>
                            <TextBlock x:Name="$StatusName2"
                                       Style="{DynamicResource Page2StatusText}"
                                       Text="$(ConvertTo-XamlText $StatusText2)"/>
                        </StackPanel>
                    </Grid>
                </Border>
"@
}


# ============================================================
# Information Dialog XAML
# ============================================================

$XamlInfoDialog = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="About This Script"
    Width="680"
    Height="620"
    WindowStyle="None"
    ResizeMode="NoResize"
    Background="#FF0B1730"
    WindowStartupLocation="CenterOwner">

    <Border CornerRadius="20"
            Padding="18"
            Background="#FF0B1730"
            BorderBrush="#668DA8D8"
            BorderThickness="1">

        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="50"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="64"/>
            </Grid.RowDefinitions>

            <TextBlock Text="Atlas‑Tech New User Wizard"
                       FontFamily="Segoe UI Variable Display"
                       FontSize="26"
                       FontWeight="Bold"
                       Foreground="White"
                       VerticalAlignment="Center"/>

            <ScrollViewer Grid.Row="1"
                          Margin="0,12,0,12"
                          VerticalScrollBarVisibility="Auto">
                <TextBlock x:Name="InfoContentBlock"
                           FontFamily="Consolas"
                           FontSize="14"
                           Foreground="White"
                           TextWrapping="Wrap"
                           LineHeight="22"/>
            </ScrollViewer>

            <Button x:Name="CloseInfoButton"
					Grid.Row="2"
					Width="240"
					Height="50"
					Style="{DynamicResource PrimaryButton}"
					HorizontalAlignment="Center">

				<TextBlock Text="Close"
						   FontSize="22"
						   FontWeight="Bold"
						   Foreground="#001018"
						   VerticalAlignment="Center"
						   HorizontalAlignment="Center"/>
			</Button>

        </Grid>
    </Border>
</Window>
'@


# ============================================================
# Main Window XAML
# ============================================================
$XamlMainWindow = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="New User Creation Script"
    Width="1536"
    Height="1016"
    MinWidth="1180"
    MinHeight="760"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent"
    ResizeMode="CanResizeWithGrip"
    WindowStartupLocation="CenterScreen">

    <Border Style="{DynamicResource GlassShell}">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="120"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="136"/>
                <RowDefinition x:Name="DebugRowDefinition" Height="0"/>
            </Grid.RowDefinitions>

            <Ellipse Width="720"
                     Height="720"
                     HorizontalAlignment="Center"
                     VerticalAlignment="Top"
                     Margin="0,-280,0,0"
                     Opacity="0.45"
                     IsHitTestVisible="False">
                <Ellipse.Fill>
                    <RadialGradientBrush>
                        <GradientStop Color="#AA64C7FF" Offset="0"/>
                        <GradientStop Color="#332A7CFF" Offset="0.45"/>
                        <GradientStop Color="#00000000" Offset="1"/>
                    </RadialGradientBrush>
                </Ellipse.Fill>
            </Ellipse>

            <Rectangle HorizontalAlignment="Stretch"
                       VerticalAlignment="Stretch"
                       Opacity="0.34"
                       IsHitTestVisible="False">
                <Rectangle.Fill>
                    <RadialGradientBrush Center="0.52,0.55" GradientOrigin="0.52,0.55" RadiusX="0.58" RadiusY="0.72">
                        <GradientStop Color="#996BB9FF" Offset="0"/>
                        <GradientStop Color="#333D63D8" Offset="0.38"/>
                        <GradientStop Color="#00000000" Offset="1"/>
                    </RadialGradientBrush>
                </Rectangle.Fill>
            </Rectangle>

            <Ellipse Width="620"
                     Height="620"
                     HorizontalAlignment="Right"
                     VerticalAlignment="Bottom"
                     Margin="0,0,-210,-250"
                     Opacity="0.28"
                     IsHitTestVisible="False">
                <Ellipse.Fill>
                    <RadialGradientBrush>
                        <GradientStop Color="#AA39FFF5" Offset="0"/>
                        <GradientStop Color="#2224A3FF" Offset="0.42"/>
                        <GradientStop Color="#00000000" Offset="1"/>
                    </RadialGradientBrush>
                </Ellipse.Fill>
            </Ellipse>

            <Border x:Name="HeaderPanel"
                    Grid.Row="0"
                    CornerRadius="18"
                    Background="{DynamicResource GlassHeaderGradient}"
                    BorderBrush="#334E789A"
                    BorderThickness="1"
                    Padding="10">

                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="100"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="310"/>
                    </Grid.ColumnDefinitions>

                    <Border Width="88"
                            Height="88"
                            CornerRadius="18"
                            BorderBrush="{DynamicResource Accent}"
                            BorderThickness="1"
                            Background="#22203A4A"
                            Effect="{DynamicResource CyanGlow}">
                        <TextBlock Text="+"
                                   FontFamily="{DynamicResource AppFont}"
                                   FontSize="58"
                                   Foreground="{DynamicResource Accent}"
                                   HorizontalAlignment="Center"
                                   VerticalAlignment="Center"
								   Margin="0,0,0,10"/>
                    </Border>

                    <StackPanel Grid.Column="1"
                                VerticalAlignment="Center">
                        <TextBlock Text="Atlas-Tech New User Script"
                                   FontFamily="{DynamicResource AppFont}"
                                   Foreground="White"
                                   FontSize="34"
                                   FontWeight="SemiBold"
								   Margin="18,0,0,0"/>
                        <TextBlock Text="Step by Step new user creation guide."
                                   FontFamily="{DynamicResource AppFont}"
                                   Foreground="{DynamicResource TextMuted}"
                                   FontSize="20"
                                   Margin="42,6,0,0"/>
                    </StackPanel>

                    <StackPanel Grid.Column="2"
                                Orientation="Horizontal"
                                HorizontalAlignment="Right"
                                VerticalAlignment="Top">
						
						<Button x:Name="InfoButton"
								Content="ℹ"
								Style="{DynamicResource WindowChromeButton}"
								Margin="0,0,5,0"
								ToolTip="Information / About This Script"/>
                        <Button x:Name="MinButton"
                                Content="−"
                                Style="{DynamicResource WindowChromeButton}"
                                Margin="0,0,5,0"/>
                        <Button x:Name="MaxButton"
                                Content="□"
                                Style="{DynamicResource WindowChromeButton}"
                                Margin="0,0,5,0"/>
                        <Button x:Name="ExitXButton"
                                Content="×"
                                Style="{DynamicResource WindowChromeButton}"
                                Margin="0,0,10,0"/> 
                    </StackPanel>
                </Grid>
            </Border>

            <Frame x:Name="PageFrame"
                   Grid.Row="1"
                   NavigationUIVisibility="Hidden"
                   Background="Transparent"
                   Margin="0,22,0,22"/>

            <Border Grid.Row="2"
                    CornerRadius="22"
                    Background="#44121F39"
                    BorderBrush="#668DA8D8"
                    BorderThickness="1"
                    Padding="28,22,28,22"
                    Margin="0,0,0,4">

                <Grid>
                    <StackPanel Orientation="Horizontal"
                                HorizontalAlignment="Left"
                                VerticalAlignment="Center">

                        <Border x:Name="DebugTogglePanel"
                                Width="88"
                                Height="78"
                                CornerRadius="14"
                                BorderBrush="#668DA8D8"
                                BorderThickness="1"
                                Background="#33243B5E"
                                Cursor="Hand"
                                ToolTip="Toggle debug output">
                            <TextBlock x:Name="DebugToggleIcon"
                                       Text="☰"
                                       Foreground="#AA7E91AA"
                                       FontSize="44"
                                       HorizontalAlignment="Center"
                                       VerticalAlignment="Center"/>
                        </Border>

                        <StackPanel Margin="26,0,0,0"
                                    VerticalAlignment="Center">
                            <TextBlock x:Name="StepText"
                                       Text="Step 1 of 4"
                                       FontFamily="{DynamicResource AppFont}"
                                       FontSize="22"
                                       FontWeight="SemiBold"
                                       Foreground="White"/>

                            <StackPanel Orientation="Horizontal"
                                        Margin="0,16,0,0">
                                <Ellipse x:Name="Dot1" Width="18" Height="18" Fill="{DynamicResource Accent}" Margin="0,0,22,0"/>
                                <Ellipse x:Name="Dot2" Width="18" Height="18" Fill="#557E91AA" Margin="0,0,22,0"/>
                                <Ellipse x:Name="Dot3" Width="18" Height="18" Fill="#557E91AA" Margin="0,0,22,0"/>
                                <Ellipse x:Name="Dot4" Width="18" Height="18" Fill="#557E91AA"/>
                            </StackPanel>
                        </StackPanel>
                    </StackPanel>

                    <StackPanel Orientation="Horizontal"
            HorizontalAlignment="Right"
            VerticalAlignment="Center">

    <!-- BACK BUTTON -->
		<Button x:Name="BackButton"
				Width="170"
				Height="66"
				Style="{DynamicResource GlassButton}"
				Margin="0,0,24,0">

			<Grid Width="120"
				  HorizontalAlignment="Center"
				  VerticalAlignment="Center">

				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="Auto"/>
					<ColumnDefinition Width="*"/>
				</Grid.ColumnDefinitions>

				<TextBlock Grid.Column="0"
						   Text="‹"
						   FontFamily="Segoe UI Symbol"
						   FontSize="30"
						   FontWeight="SemiBold"
						   Foreground="White"
						   VerticalAlignment="Center"
						   Margin="0,0,14,0"/>

				<TextBlock Grid.Column="1"
						   Text="Back"
						   FontSize="20"
						   FontWeight="SemiBold"
						   Foreground="White"
						   VerticalAlignment="Center"
						   HorizontalAlignment="Center"/>
			</Grid>
		</Button>

		<!-- NEXT BUTTON -->
		<Button x:Name="NextButton"
				Width="210"
				Height="66"
				Style="{DynamicResource PrimaryButton}">

			<Grid Width="140"
				  HorizontalAlignment="Center"
				  VerticalAlignment="Center">

				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="*"/>
					<ColumnDefinition Width="Auto"/>
				</Grid.ColumnDefinitions>

				<TextBlock Grid.Column="0"
						   x:Name="NextButtonText"
						   Text="Next"
						   FontSize="20"
						   FontWeight="Bold"
						   Foreground="#FF001018"
						   VerticalAlignment="Center"
						   HorizontalAlignment="Center"/>

				<TextBlock Grid.Column="1"
						   Text="›"
						   FontFamily="Segoe UI Symbol"
						   FontSize="30"
						   FontWeight="SemiBold"
						   Foreground="#FF001018"
						   VerticalAlignment="Center"
						   Margin="14,0,0,0"/>
			</Grid>
		</Button>

	</StackPanel>
                </Grid>
            </Border>

            <Border x:Name="DebugPanel"
                    Grid.Row="3"
                    Visibility="Collapsed"
                    CornerRadius="18"
                    Background="#EE061321"
                    BorderBrush="#FFFE7A00"
                    BorderThickness="1"
                    Padding="18"
                    Margin="0,10,0,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <DockPanel Grid.Row="0" Margin="0,0,0,10">
                        <TextBlock Text="Debug Output"
                                   DockPanel.Dock="Left"
                                   FontFamily="{DynamicResource AppFont}"
                                   FontSize="20"
                                   FontWeight="Bold"
                                   Foreground="{DynamicResource Success}"/>

                        <Button x:Name="ClearDebugButton"
                                DockPanel.Dock="Right"
                                Content="Clear"
                                Width="92"
                                Height="34"
                                HorizontalAlignment="Right"
                                Style="{DynamicResource GlassButton}"/>
                    </DockPanel>

                    <TextBox x:Name="DebugOutputBox"
                             Grid.Row="1"
                             Background="#FF020A14"
                             Foreground="{DynamicResource Success}"
                             BorderBrush="#557FB8E8"
                             BorderThickness="1"
                             FontFamily="Consolas"
                             FontSize="13"
                             IsReadOnly="True"
                             AcceptsReturn="True"
                             TextWrapping="Wrap"
                             VerticalScrollBarVisibility="Auto"
                             HorizontalScrollBarVisibility="Auto"
                             Padding="12"/>
                </Grid>
            </Border>
        </Grid>
    </Border>
</Window>
'@

# ============================================================
# Page 1 XAML
# ============================================================
$XamlPage1 = @"
<Page
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Background="Transparent">
    <Grid>

        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="1.7*"/>
            <ColumnDefinition Width="1*"/>
        </Grid.ColumnDefinitions>

        <!-- LEFT PANEL -->
        <Border Grid.Column="0"
                CornerRadius="24"
                Margin="0,0,18,0"
                Padding="64,46"
                BorderBrush="#99A9C8FF"
                BorderThickness="1"
                Effect="{DynamicResource SoftBlueGlow}">

            <Border.Background>
                <LinearGradientBrush StartPoint="0,0"
                                     EndPoint="1,1">
                    <GradientStop Color="#7A123653"
                                  Offset="0"/>
                    <GradientStop Color="#52101E3E"
                                  Offset="0.45"/>
                    <GradientStop Color="#806064A8"
                                  Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>

            <StackPanel>

                <!-- TITLE -->
                <TextBlock FontFamily="{DynamicResource AppFont}"
                           FontSize="42"
                           FontWeight="Bold"
                           Foreground="White"
                           TextWrapping="Wrap">

                    <Run Text="Create"/>

                    <Run Text=" users with "/>

                    <Run Text="fewer surprises."
                         Foreground="{DynamicResource Accent3}"/>
                </TextBlock>

                <!-- UNDERLINE BAR -->
                <Border Width="74"
                        Height="6"
                        CornerRadius="1"
                        HorizontalAlignment="Left"
                        Margin="0,6,0,34"
                        Background="{DynamicResource AccentGradient}"/>

                $(New-FeatureCardXaml -Icon "✓" -Title "Smarter checks" -Body "This wizard checks whether this workstation has the tools needed for Active Directory, Microsoft Graph, and Exchange.")

                $(New-FeatureCardXaml -Icon "›_" -Title "No roadblocks" -Body "Missing tools are shown as reminders instead of stopping the workflow.")

                $(New-FeatureCardXaml -Icon "☁" -Title "Consistent execution" -Body "This script will create new users based on the input provided - no missed steps!" -Margin "0,0,0,12")
            </StackPanel>
        </Border>

        <!-- RIGHT PANEL -->
<Border Grid.Column="1"
        CornerRadius="24"
        Padding="52"
        BorderBrush="#99A9C8FF"
        BorderThickness="1"
        Effect="{DynamicResource SoftBlueGlow}">

    <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#7A123653" Offset="0"/>
            <GradientStop Color="#52101E3E" Offset="0.45"/>
            <GradientStop Color="#806064A8" Offset="1"/>
        </LinearGradientBrush>
    </Border.Background>

    <StackPanel HorizontalAlignment="Center"
                VerticalAlignment="Center">

        <Grid Margin="0,0,0,10">

			<!-- OUTER GLOW -->
			<Ellipse Width="178"
					 Height="178"
					 Opacity="0.65"
					 IsHitTestVisible="False">

				<Ellipse.Fill>
					<RadialGradientBrush>
						<GradientStop Color="#55FE7A00" Offset="0"/>
						<GradientStop Color="#22FE5000" Offset="0.55"/>
						<GradientStop Color="#00FE5000" Offset="1"/>
					</RadialGradientBrush>
				</Ellipse.Fill>
			</Ellipse>

			<!-- NEON RING -->
			<Border Width="154"
					Height="154"
					CornerRadius="77"
					BorderBrush="#FFFE7A00"
					BorderThickness="4"
					Background="Transparent"
					HorizontalAlignment="Center"
					VerticalAlignment="Center">

				<Border.Effect>
					<DropShadowEffect Color="#FE7A00"
									  BlurRadius="28"
									  ShadowDepth="0"
									  Opacity="1"/>
				</Border.Effect>

				<TextBlock Text="✓"
						   FontSize="82"
						   FontWeight="SemiBold"
						   Foreground="white"
						   HorizontalAlignment="Center"
						   VerticalAlignment="Center"/>
			</Border>

		</Grid>

        <TextBlock Text="Readiness Check"
                   FontFamily="{DynamicResource AppFont}"
                   FontSize="36"
                   FontWeight="Bold"
                   Foreground="White"
                   HorizontalAlignment="Center"
                   Margin="0,34,0,0"/>

        <TextBlock Text="Checks local modules, AD access,&#x0a;and Graph sign-in readiness."
                   FontFamily="{DynamicResource AppFont}"
                   FontSize="23"
                   FontWeight="SemiBold"
                   Foreground="White"
                   TextAlignment="Center"
                   TextWrapping="Wrap"
                   LineHeight="34"
                   Margin="0,22,0,58"/>

        <Button x:Name="NextButton_Page1"
                Width="360"
                Height="88"
                Style="{DynamicResource StartButtonStyle}">
            <StackPanel Orientation="Horizontal"
                        HorizontalAlignment="Center"
                        VerticalAlignment="Center">
                <TextBlock Text="Start"
                           FontWeight="Bold"
                           FontSize="24"
                           Foreground="#FF001018"
                           VerticalAlignment="Center"/>
                <TextBlock Text="›"
                           FontWeight="SemiBold"
                           FontSize="42"
                           Foreground="#FF001018"
                           Margin="44,-6,0,0"
                           VerticalAlignment="Center"/>
            </StackPanel>
        </Button>

    </StackPanel>
</Border>
    </Grid>
</Page>
"@

# ============================================================
# Page 2 XAML
# ============================================================
$XamlPage2 = @"
<Page
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Background="Transparent">
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="1.7*"/>
            <ColumnDefinition Width="1*"/>
        </Grid.ColumnDefinitions>

        <!-- LEFT PANEL -->
        <Border Grid.Column="0"
                CornerRadius="24"
                Margin="0,0,18,0"
                Padding="64,46"
                BorderBrush="#99A9C8FF"
                BorderThickness="1"
                Effect="{DynamicResource SoftBlueGlow}">

            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                    <GradientStop Color="#7A123653" Offset="0"/>
                    <GradientStop Color="#52101E3E" Offset="0.45"/>
                    <GradientStop Color="#806064A8" Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>

            <StackPanel>

                <TextBlock FontFamily="{DynamicResource AppFont}"
                           FontSize="42"
                           FontWeight="Bold"
                           Foreground="White"
                           TextWrapping="Wrap">
                    <Run Text="Environment"/>
                    <Run Text=" readiness "/>
                    <Run Text="checks." Foreground="{DynamicResource Accent3}"/>
                </TextBlock>
				
				<!-- UNDERLINE BAR -->
                <Border Width="74"
                        Height="6"
                        CornerRadius="1"
                        HorizontalAlignment="Left"
                        Margin="0,6,0,34"
                        Background="{DynamicResource AccentGradient}"/>

                $(New-ReadinessCardXaml -Icon "AD" -Title "Active Directory" -StatusName1 "StatusADModule" -StatusText1 "Waiting to check RSAT Active Directory module..." -StatusName2 "StatusADConnection" -StatusText2 "Waiting to check AD connectivity..." -IconFontSize "34")

                $(New-ReadinessCardXaml -Icon "☁" -Title "Microsoft Graph" -StatusName1 "StatusGraphModule" -StatusText1 "Waiting to check Microsoft Graph PowerShell module..." -StatusName2 "StatusGraphAuth" -StatusText2 "Waiting to check Graph sign-in readiness..." -IconFontSize "46")

                $(New-ReadinessCardXaml -Icon "✉" -Title "Connection to Congo (Exchange)" -StatusName1 "StatusExchangeModule" -StatusText1 "Waiting to detect local Exchange snap-in..." -StatusName2 "StatusExchangeAuth" -StatusText2 "Waiting to connect to local Exchange..." -Margin "0,0,0,12" -CardBackground "#33385F76")
            </StackPanel>
        </Border>

        <!-- RIGHT PANEL -->
        <Border Grid.Column="1"
                CornerRadius="24"
                Padding="36"
                BorderBrush="#99A9C8FF"
                BorderThickness="1"
                Effect="{DynamicResource SoftBlueGlow}">

            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                    <GradientStop Color="#7A123653" Offset="0"/>
                    <GradientStop Color="#52101E3E" Offset="0.45"/>
                    <GradientStop Color="#806064A8" Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>

            <StackPanel HorizontalAlignment="Center"
                        VerticalAlignment="Center">

                <Grid Margin="0,0,0,10">

                    <Ellipse Width="150"
                             Height="150"
                             Opacity="0.65"
                             IsHitTestVisible="False">
                        <Ellipse.Fill>
                            <RadialGradientBrush>
                                <GradientStop Color="#55FE7A00" Offset="0"/>
                                <GradientStop Color="#22FE5000" Offset="0.55"/>
                                <GradientStop Color="#00FE5000" Offset="1"/>
                            </RadialGradientBrush>
                        </Ellipse.Fill>
                    </Ellipse>

                    <Border Width="128"
                            Height="128"
                            CornerRadius="64"
                            BorderBrush="#FFFE7A00"
                            BorderThickness="4"
                            Background="Transparent"
                            HorizontalAlignment="Center"
                            VerticalAlignment="Center">

                        <Border.Effect>
                            <DropShadowEffect Color="#FE7A00"
                                              BlurRadius="28"
                                              ShadowDepth="0"
                                              Opacity="1"/>
                        </Border.Effect>

                        <TextBlock Text="!"
                                   FontSize="64"
                                   FontWeight="SemiBold"
                                   Foreground="White"
                                   HorizontalAlignment="Center"
                                   VerticalAlignment="Center"/>
                    </Border>
                </Grid>

                <TextBlock Text="Reminders"
                           FontFamily="{DynamicResource AppFont}"
                           FontSize="30"
                           FontWeight="Bold"
                           Foreground="White"
                           HorizontalAlignment="Center"
                           Margin="0,16,0,0"/>

                <TextBlock x:Name="ReminderText"
                           FontFamily="{DynamicResource AppFont}"
                           FontSize="17"
                           FontWeight="SemiBold"
                           Foreground="White"
                           TextWrapping="Wrap"
                           TextAlignment="Left"
                           LineHeight="25"
                           Text="No reminders yet."
                           Margin="0,16,0,0"/>

                <Border Height="1"
                        Background="#33FFFFFF"
                        Margin="0,28,0,28"/>

                <TextBlock Text="Install commands"
                           FontFamily="{DynamicResource AppFont}"
                           FontSize="24"
                           FontWeight="Bold"
                           Foreground="White"
                           HorizontalAlignment="Center"
                           Margin="0,0,0,16"/>

                <TextBlock FontFamily="Consolas"
                           FontSize="13"
                           Foreground="White"
                           TextWrapping="Wrap"
                           LineHeight="22"
                           Text="RSAT: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"/>

                <TextBlock FontFamily="Consolas"
                           FontSize="13"
                           Foreground="White"
                           TextWrapping="Wrap"
                           LineHeight="22"
                           Margin="0,12,0,0"
                           Text="Graph: Install-Module Microsoft.Graph -Scope CurrentUser"/>

                <Button x:Name="RunChecksButton"
						Margin="0,34,0,0"
						Height="76"
						Width="320"
						Style="{DynamicResource StartButtonStyle}">

					<TextBlock Text="Run Checks Again"
					   FontWeight="Bold"
					   FontSize="23"
					   Foreground="#FF001018"
					   HorizontalAlignment="Center"
					   TextAlignment="Center"/>
				</Button>
            </StackPanel>
        </Border>
    </Grid>
</Page>
"@

# ============================================================
# Placeholder Page 3 XAML
# ============================================================
$XamlPage3 = @'
<Page
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Background="Transparent">
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="1.7*"/>
            <ColumnDefinition Width="1*"/>
        </Grid.ColumnDefinitions>

        <!-- LEFT PANEL -->
        <Border Grid.Column="0"
                CornerRadius="24"
                Margin="0,0,18,0"
                Padding="48,40"
                BorderBrush="#99A9C8FF"
                BorderThickness="1"
                Effect="{DynamicResource SoftBlueGlow}">

            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                    <GradientStop Color="#7A123653" Offset="0"/>
                    <GradientStop Color="#52101E3E" Offset="0.45"/>
                    <GradientStop Color="#806064A8" Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>

            <ScrollViewer VerticalScrollBarVisibility="Auto"
                          HorizontalScrollBarVisibility="Disabled">

                <StackPanel>

                    <TextBlock FontFamily="{DynamicResource AppFont}"
                               FontSize="40"
                               FontWeight="Bold"
                               Foreground="White"
                               TextWrapping="Wrap">
                        <Run Text="New user"/>
                        <Run Text=" details "/>
                        <Run Text="entry." Foreground="{DynamicResource Accent3}"/>
                    </TextBlock>

                    <Border Width="74"
                            Height="6"
                            CornerRadius="4"
                            HorizontalAlignment="Left"
                            Margin="0,6,0,28"
                            Background="{DynamicResource AccentGradient}"/>

                    <!-- BASIC INFO -->
                    <Border Style="{DynamicResource FormCard}">
                        <StackPanel>
                            <TextBlock Text="Employee Information"
                                       Style="{DynamicResource SectionHeader}"/>

                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="18"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <StackPanel Grid.Column="0">
                                    <TextBlock Text="Expected Start Date" Style="{DynamicResource FieldLabel}"/>
                                    <DatePicker x:Name="StartDatePicker"
                                                MinHeight="46"
                                                FontSize="17"/>

                                    <TextBlock Text="First Name" Style="{DynamicResource FieldLabel}" Margin="0,18,0,6"/>
                                    <TextBox x:Name="FirstNameBox" Style="{DynamicResource GlassInput}"/>

                                    <TextBlock Text="Middle Initial" Style="{DynamicResource FieldLabel}" Margin="0,18,0,6"/>
                                    <TextBox x:Name="MiddleInitialBox"
                                             Style="{DynamicResource GlassInput}"
                                             MaxLength="1"/>
                                </StackPanel>

                                <StackPanel Grid.Column="2">
                                    <TextBlock Text="Home Org" Style="{DynamicResource FieldLabel}"/>
                                    <ComboBox x:Name="HomeOrgComboBox"
										  Style="{DynamicResource GlassCombo}"
										  IsEditable="True"
										  IsReadOnly="True">
                                        <ComboBoxItem Content="1. Draco"/>
                                        <ComboBoxItem Content="2. Pavo"/>
                                        <ComboBoxItem Content="3. Corvus"/>
                                    </ComboBox>

                                    <TextBlock Text="Last Name" Style="{DynamicResource FieldLabel}" Margin="0,18,0,6"/>
                                    <TextBox x:Name="LastNameBox" Style="{DynamicResource GlassInput}"/>

                                    <CheckBox x:Name="IncludeMiddleInitialCheckBox"
                                              Content="Add middle initial to username?"
                                              Foreground="White"
                                              FontFamily="{DynamicResource AppFont}"
                                              FontSize="17"
                                              Margin="0,24,0,0"
											  Background="#FF0B1730"/>
									<CheckBox x:Name="CACCheckBox"
									  Content="CAC Required?"
									  Foreground="White"
									  FontFamily="{DynamicResource AppFont}"
									  FontSize="17"
									  Margin="0,0,0,14"
									  IsChecked="False"
									  Background="#FF0B1730"/>
                                </StackPanel>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <!-- ORG INFO -->
                    <Border Style="{DynamicResource FormCard}">
                        <StackPanel>
                            <TextBlock Text="Organizational Information"
                                       Style="{DynamicResource SectionHeader}"/>

                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="18"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <StackPanel Grid.Column="0">
                                    <TextBlock Text="Job Title" Style="{DynamicResource FieldLabel}"/>
                                    <TextBox x:Name="JobTitleBox" Style="{DynamicResource GlassInput}"/>

                                    <TextBlock Text="Work Location" Style="{DynamicResource FieldLabel}" Margin="0,18,0,6"/>
                                    <ComboBox x:Name="LocationComboBox" Style="{DynamicResource GlassCombo}" Background="#FF0B1730">
                                        <ComboBoxItem Content="1. Rivers"/>
                                        <ComboBoxItem Content="2. Remount"/>
                                        <ComboBoxItem Content="3. Virginia Beach"/>
                                        <ComboBoxItem Content="4. San Diego"/>
                                        <ComboBoxItem Content="5. Alexandria"/>
                                        <ComboBoxItem Content="6. Lexington"/>
                                    </ComboBox>

                                    <TextBlock Text="Employee ID #" Style="{DynamicResource FieldLabel}" Margin="0,18,0,6"/>
                                    <TextBox x:Name="EmployeeIdBox" Style="{DynamicResource GlassInput}"/>
                                </StackPanel>

                                <StackPanel Grid.Column="2">
                                    <TextBlock Text="Manager" Style="{DynamicResource FieldLabel}"/>
                                    <ComboBox x:Name="ManagerComboBox"
                                              Style="{DynamicResource GlassCombo}"
											  Background="#FF0B1730"/>

                                    <TextBlock Text="Department" Style="{DynamicResource FieldLabel}" Margin="0,18,0,6"/>
                                    <ComboBox x:Name="DepartmentComboBox" Style="{DynamicResource GlassCombo}" Background="#FF0B1730">
                                        <ComboBoxItem Content="1. Dept 00 - Accounting"/>
                                        <ComboBoxItem Content="2. Dept 00 - Information Technology"/>
                                        <ComboBoxItem Content="3. Dept 00 - Executive"/>
                                        <ComboBoxItem Content="4. Dept 00 - Human Resources"/>
                                        <ComboBoxItem Content="5. Dept 01 - Contracts"/>
                                        <ComboBoxItem Content="6. Dept 01 - Operations"/>
                                        <ComboBoxItem Content="7. Dept 02 - DC/PAX/Charleston Division"/>
                                        <ComboBoxItem Content="8. Dept 03 - VABeach Division"/>
                                        <ComboBoxItem Content="9. Dept 04 - San Diego Division"/>
                                        <ComboBoxItem Content="10. Service Account"/>
                                    </ComboBox>

                                    <TextBlock Text="Encoded Badge Number #" Style="{DynamicResource FieldLabel}" Margin="0,18,0,6"/>
                                    <TextBox x:Name="BadgeIdBox" Style="{DynamicResource GlassInput}"/>
                                </StackPanel>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <!-- PHONE INFO -->
                    <Border Style="{DynamicResource FormCard}" Margin="0,0,0,6">
                        <StackPanel>
                            <TextBlock Text="Phone Information"
                                       Style="{DynamicResource SectionHeader}"/>

                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="18"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <StackPanel Grid.Column="0">
                                    <TextBlock Text="Office Phone" Style="{DynamicResource FieldLabel}"/>
                                    <TextBox x:Name="OfficePhoneBox"
                                             Style="{DynamicResource GlassInput}"
                                             ToolTip="Example: 843-725-2300"/>
                                </StackPanel>

                                <StackPanel Grid.Column="2">
                                    <TextBlock Text="Mobile Phone" Style="{DynamicResource FieldLabel}"/>
                                    <TextBox x:Name="MobilePhoneBox"
                                             Style="{DynamicResource GlassInput}"
                                             ToolTip="Example: 843-518-2300"/>
                                </StackPanel>
                            </Grid>
                        </StackPanel>
                    </Border>
					
					<!-- MAIL / NOTIFICATION INFO -->
					<Border Style="{DynamicResource FormCard}" Margin="0,0,0,6">
						<StackPanel>
							<TextBlock Text="Mailbox and Notifications"
									   Style="{DynamicResource SectionHeader}"/>

							<CheckBox x:Name="CreateMailboxCheckBox"
									  Content="Create Microsoft 365 / cloud mailbox"
									  Foreground="White"
									  FontFamily="{DynamicResource AppFont}"
									  FontSize="17"
									  Margin="0,0,0,14"
									  IsChecked="True"
									  Background="#FF0B1730"/>

							<CheckBox x:Name="SendNewHireNoticeCheckBox"
									  Content="Send new-hire onboarding notice to ITSupport"
									  Foreground="White"
									  FontFamily="{DynamicResource AppFont}"
									  FontSize="17"
									  Margin="0,22,0,14"
									  IsChecked="True"
									  Background="#FF0B1730"/>

							<TextBlock Text="Notification Recipient"
									   Style="{DynamicResource FieldLabel}"/>
							<TextBox x:Name="NotificationRecipientBox"
									 Style="{DynamicResource GlassInput}"
									 Text="ITSupport@atlas-tech.com"/>

							<TextBlock Text="Notification Sender"
									   Style="{DynamicResource FieldLabel}"
									   Margin="0,18,0,6"/>
							<TextBox x:Name="NotificationSenderBox"
									 Style="{DynamicResource GlassInput}"
									 Text="NEW-HIRE-INFO@atlas-tech.com"/>
						</StackPanel>
					</Border>
					
					<!-- Requested Data -->
					<Border Style="{DynamicResource FormCard}" Margin="0,0,0,6">
						<StackPanel>
							<TextBlock Text="Requests:"
									   Style="{DynamicResource SectionHeader}"/>
							<TextBlock Text="Which of the following assets will be issued to the employee? This information is provided in the&#x0a;Paylocity User ID form. If nothing was requested in Paylocity, ONLY check Nothing Requested."
										Style="{DynamicResource FieldLabel}"/>
							
							<Grid>
								<Grid.ColumnDefinitions>
									<ColumnDefinition Width="*"/>
									<ColumnDefinition Width="*"/>
								</Grid.ColumnDefinitions>

								<!-- LEFT COLUMN -->
								<StackPanel Grid.Column="0">
									<CheckBox x:Name="NothingRequestedCheckBox"
											  Content="Nothing Requested"
											  Foreground="White"
											  FontFamily="{DynamicResource AppFont}"
											  FontSize="17"
											  Margin="0,16,0,14"
											  IsChecked="False"
											  Background="#FF0B1730"/>

									<CheckBox x:Name="TemporaryOfficeSpaceCheckBox"
											  Content="Temporary Office Space"
											  Foreground="White"
											  FontFamily="{DynamicResource AppFont}"
											  FontSize="17"
											  Margin="0,0,0,14"
											  IsChecked="False"
											  Background="#FF0B1730"/>

									<CheckBox x:Name="PermanentOfficeSpaceCheckBox"
											  Content="Permanent Office Space"
											  Foreground="White"
											  FontFamily="{DynamicResource AppFont}"
											  FontSize="17"
											  Margin="0,0,0,14"
											  IsChecked="False"
											  Background="#FF0B1730"/>

									<CheckBox x:Name="DesktopCheckBox"
											  Content="Desktop"
											  Foreground="White"
											  FontFamily="{DynamicResource AppFont}"
											  FontSize="17"
											  Margin="0,0,0,14"
											  IsChecked="False"
											  Background="#FF0B1730"/>
									
									<CheckBox x:Name="LaptopCheckBox"
											  Content="Laptop"
											  Foreground="White"
											  FontFamily="{DynamicResource AppFont}"
											  FontSize="17"
											  Margin="0,0,0,14"
											  IsChecked="False"
											  Background="#FF0B1730"/>

									<CheckBox x:Name="DockingStationCheckBox"
											  Content="Docking Station"
											  Foreground="White"
											  FontFamily="{DynamicResource AppFont}"
											  FontSize="17"
											  Margin="0,0,0,14"
											  IsChecked="False"
											  Background="#FF0B1730"/>
								</StackPanel>

								<!-- RIGHT COLUMN -->
								<StackPanel Grid.Column="1" Margin="32,16,0,0">
									<CheckBox x:Name="MouseKeyboardCheckBox"
											  Content="Mouse/Keyboard Combo"
											  Foreground="White"
											  FontFamily="{DynamicResource AppFont}"
											  FontSize="17"
											  Margin="0,0,0,14"
											  IsChecked="False"
											  Background="#FF0B1730"/>

									<CheckBox x:Name="MonitorCheckBox"
											  Content="Monitor"
											  Foreground="White"
											  FontFamily="{DynamicResource AppFont}"
											  FontSize="17"
											  Margin="0,0,0,14"
											  IsChecked="False"
											  Background="#FF0B1730"/>

									<CheckBox x:Name="DualMonitorCheckBox"
											  Content="Dual Monitor"
											  Foreground="White"
											  FontFamily="{DynamicResource AppFont}"
											  FontSize="17"
											  Margin="0,0,0,14"
											  IsChecked="False"
											  Background="#FF0B1730"/>

									<CheckBox x:Name="DeskPhoneCheckBox"
											  Content="Desk Phone"
											  Foreground="White"
											  FontFamily="{DynamicResource AppFont}"
											  FontSize="17"
											  Margin="0,0,0,14"
											  IsChecked="False"
											  Background="#FF0B1730"/>

									<CheckBox x:Name="CellPhoneCheckBox"
											  Content="Cellphone"
											  Foreground="White"
											  FontFamily="{DynamicResource AppFont}"
											  FontSize="17"
											  Margin="0,0,0,14"
											  IsChecked="False"
											  Background="#FF0B1730"/>

									<CheckBox x:Name="SpeakersCheckBox"
											  Content="Speakers"
											  Foreground="White"
											  FontFamily="{DynamicResource AppFont}"
											  FontSize="17"
											  Margin="0,0,0,14"
											  IsChecked="false"
											  Background="#FF0B1730"/>
								</StackPanel>
							</Grid>

							
						</StackPanel>
					</Border>

                </StackPanel>
            </ScrollViewer>
        </Border>

        <!-- RIGHT PANEL -->
        <Border Grid.Column="1"
                CornerRadius="24"
                Padding="42"
                BorderBrush="#99A9C8FF"
                BorderThickness="1"
                Effect="{DynamicResource SoftBlueGlow}">

            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                    <GradientStop Color="#7A123653" Offset="0"/>
                    <GradientStop Color="#52101E3E" Offset="0.45"/>
                    <GradientStop Color="#806064A8" Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>

            <StackPanel VerticalAlignment="Center">

                <Grid HorizontalAlignment="Center" Margin="0,0,0,28">
                    <Ellipse Width="150"
                             Height="150"
                             Opacity="0.65">
                        <Ellipse.Fill>
                            <RadialGradientBrush>
                                <GradientStop Color="#55FE7A00" Offset="0"/>
                                <GradientStop Color="#22FE5000" Offset="0.55"/>
                                <GradientStop Color="#00FE5000" Offset="1"/>
                            </RadialGradientBrush>
                        </Ellipse.Fill>
                    </Ellipse>

                    <Border Width="128"
                            Height="128"
                            CornerRadius="64"
                            BorderBrush="#FFFE7A00"
                            BorderThickness="4"
                            Background="Transparent"
                            HorizontalAlignment="Center"
                            VerticalAlignment="Center">
                        <Border.Effect>
                            <DropShadowEffect Color="#FE7A00"
                                              BlurRadius="28"
                                              ShadowDepth="0"
                                              Opacity="1"/>
                        </Border.Effect>

                        <TextBlock Text="👤"
                                   FontSize="56"
                                   Foreground="white"
                                   HorizontalAlignment="Center"
                                   VerticalAlignment="Center"/>
                    </Border>
                </Grid>

                <TextBlock x:Name="IntakeHeader"
						   Text="User Intake"
                           FontFamily="{DynamicResource AppFont}"
                           FontSize="36"
                           FontWeight="Bold"
                           Foreground="White"
                           HorizontalAlignment="Center"/>

                <TextBlock x:Name="IntakeDetails"
						   Text="Enter the new hire details from the new employee form. The next page can review and generate the AD, Exchange, and notification actions."
                           FontFamily="{DynamicResource AppFont}"
                           FontSize="18"
                           FontWeight="SemiBold"
                           Foreground="White"
                           TextWrapping="Wrap"
                           TextAlignment="Center"
                           Margin="0,24,0,34"/>

                <Border Height="1"
                        Background="#33FFFFFF"
                        Margin="0,0,0,28"/>

                <TextBlock Text="Validation Summary"
                           FontFamily="{DynamicResource AppFont}"
                           FontSize="24"
                           FontWeight="Bold"
                           Foreground="White"
                           HorizontalAlignment="Center"
                           Margin="0,0,0,18"/>

                <TextBlock x:Name="ValidationSummaryText"
						   FontFamily="{DynamicResource AppFont}"
						   FontSize="18"
						   Foreground="White"
						   TextWrapping="Wrap"
						   Margin="0,18,0,0"/>

            </StackPanel>
        </Border>
    </Grid>
</Page>
'@

# ============================================================
# Placeholder Page 4 XAML
# ============================================================
$XamlPage4 = @'
<Page
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Background="Transparent">
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="1.7*"/>
            <ColumnDefinition Width="1*"/>
        </Grid.ColumnDefinitions>

        <!-- LEFT PANEL -->
        <Border Grid.Column="0"
                CornerRadius="24"
                Margin="0,0,18,0"
                Padding="48,40"
                BorderBrush="#99A9C8FF"
                BorderThickness="1"
                Effect="{DynamicResource SoftBlueGlow}">

            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                    <GradientStop Color="#7A123653" Offset="0"/>
                    <GradientStop Color="#52101E3E" Offset="0.45"/>
                    <GradientStop Color="#806064A8" Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>

            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel>

                    <TextBlock FontFamily="{DynamicResource AppFont}"
                               FontSize="40"
                               FontWeight="Bold"
                               Foreground="White"
                               TextWrapping="Wrap">
                        <Run Text="Review"/>
                        <Run Text=" and "/>
                        <Run Text="execute." Foreground="{DynamicResource Accent3}"/>
                    </TextBlock>

                    <Border Width="74"
                            Height="6"
                            CornerRadius="4"
                            HorizontalAlignment="Left"
                            Margin="0,6,0,28"
                            Background="{DynamicResource AccentGradient}"/>

                    <!-- ACCOUNT SUMMARY -->
                    <Border Style="{DynamicResource ReviewCard}">
                        <StackPanel>
                            <TextBlock Text="Account Summary"
                                       FontSize="26"
                                       FontWeight="Bold"
                                       Foreground="White"
                                       Margin="0,0,0,18"/>

                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="18"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <StackPanel Grid.Column="0">
                                    <TextBlock Text="Display Name" Style="{DynamicResource ReviewLabel}"/>
                                    <TextBlock x:Name="ReviewDisplayName" Text="-" Style="{DynamicResource ReviewValue}"/>

                                    <TextBlock Text="Username" Style="{DynamicResource ReviewLabel}"/>
                                    <TextBlock x:Name="ReviewUsername" Text="-" Style="{DynamicResource ReviewValue}"/>

                                    <TextBlock Text="Start Date" Style="{DynamicResource ReviewLabel}"/>
                                    <TextBlock x:Name="ReviewStartDate" Text="-" Style="{DynamicResource ReviewValue}"/>
                                </StackPanel>

                                <StackPanel Grid.Column="2">
                                    <TextBlock Text="Home Org" Style="{DynamicResource ReviewLabel}"/>
                                    <TextBlock x:Name="ReviewHomeOrg" Text="-" Style="{DynamicResource ReviewValue}"/>

                                    <TextBlock Text="Employee ID" Style="{DynamicResource ReviewLabel}"/>
                                    <TextBlock x:Name="ReviewEmployeeId" Text="-" Style="{DynamicResource ReviewValue}"/>

                                    <TextBlock Text="Badge ID" Style="{DynamicResource ReviewLabel}"/>
                                    <TextBlock x:Name="ReviewBadgeId" Text="-" Style="{DynamicResource ReviewValue}"/>
									
									<TextBlock Text="CAC Required" Style="{DynamicResource ReviewLabel}"/>
									<TextBlock x:Name="ReviewCAC" Text="-" Style="{DynamicResource ReviewValue}"/>
                                </StackPanel>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <!-- ORGANIZATION SUMMARY -->
                    <Border Style="{DynamicResource ReviewCard}">
                        <StackPanel>
                            <TextBlock Text="Organization Summary"
                                       FontSize="26"
                                       FontWeight="Bold"
                                       Foreground="White"
                                       Margin="0,0,0,18"/>

                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="18"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <StackPanel Grid.Column="0">
                                    <TextBlock Text="Job Title" Style="{DynamicResource ReviewLabel}"/>
                                    <TextBlock x:Name="ReviewJobTitle" Text="-" Style="{DynamicResource ReviewValue}"/>

                                    <TextBlock Text="Manager" Style="{DynamicResource ReviewLabel}"/>
                                    <TextBlock x:Name="ReviewManager" Text="-" Style="{DynamicResource ReviewValue}"/>
                                </StackPanel>

                                <StackPanel Grid.Column="2">
                                    <TextBlock Text="Location" Style="{DynamicResource ReviewLabel}"/>
                                    <TextBlock x:Name="ReviewLocation" Text="-" Style="{DynamicResource ReviewValue}"/>

                                    <TextBlock Text="Department" Style="{DynamicResource ReviewLabel}"/>
                                    <TextBlock x:Name="ReviewDepartment" Text="-" Style="{DynamicResource ReviewValue}"/>
                                </StackPanel>
                            </Grid>
                        </StackPanel>
                    </Border>
					
					<Border Style="{DynamicResource ReviewCard}" Margin="0,0,0,6">
						<StackPanel>
							<TextBlock Text="Office &amp; Address"
									   FontSize="26"
									   FontWeight="Bold"
									   Foreground="White"
									   Margin="0,0,0,18"/>
							<Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="18"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
							
								<StackPanel Grid.Column="0">
									<TextBlock Text="Home Office" Style="{DynamicResource ReviewLabel}"/>
									<TextBlock x:Name="HomeOfficeReview" Text="-" Style="{DynamicResource ReviewValue}"/>

									<TextBlock Text="Street Address" Style="{DynamicResource ReviewLabel}"/>
									<TextBlock x:Name="StreetAddressReview" Text="-" Style="{DynamicResource ReviewValue}"/>
								</StackPanel>
								<StackPanel Grid.Column="2">
									<TextBlock Text="City" Style="{DynamicResource ReviewLabel}"/>
									<TextBlock x:Name="CityReview" Text="-" Style="{DynamicResource ReviewValue}"/>

									<TextBlock Text="State" Style="{DynamicResource ReviewLabel}"/>
									<TextBlock x:Name="StateReview" Text="-" Style="{DynamicResource ReviewValue}"/>
									<TextBlock Text="Postal Code" Style="{DynamicResource ReviewLabel}"/>
									<TextBlock x:Name="PostalCodeReview" Text="-" Style="{DynamicResource ReviewValue}"/>
								</StackPanel>
							</Grid>
						</StackPanel>
					</Border>

                    <!-- PHONE SUMMARY -->
                    <Border Style="{DynamicResource ReviewCard}" Margin="0,0,0,6">
                        <StackPanel>
                            <TextBlock Text="Phone Summary"
                                       FontSize="26"
                                       FontWeight="Bold"
                                       Foreground="White"
                                       Margin="0,0,0,18"/>

                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="18"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <StackPanel Grid.Column="0">
                                    <TextBlock Text="Office Phone" Style="{DynamicResource ReviewLabel}"/>
                                    <TextBlock x:Name="ReviewOfficePhone" Text="-" Style="{DynamicResource ReviewValue}"/>
                                </StackPanel>

                                <StackPanel Grid.Column="2">
                                    <TextBlock Text="Mobile Phone" Style="{DynamicResource ReviewLabel}"/>
                                    <TextBlock x:Name="ReviewMobilePhone" Text="-" Style="{DynamicResource ReviewValue}"/>
                                </StackPanel>
                            </Grid>
                        </StackPanel>
                    </Border>
					
					<Border Style="{DynamicResource ReviewCard}" Margin="0,0,0,6">
						<StackPanel>
							<TextBlock Text="Mailbox and Notifications"
									   FontSize="26"
									   FontWeight="Bold"
									   Foreground="White"
									   Margin="0,0,0,18"/>

							<TextBlock Text="Create Mailbox" Style="{DynamicResource ReviewLabel}"/>
							<TextBlock x:Name="ReviewMailbox" Text="-" Style="{DynamicResource ReviewValue}"/>

							<TextBlock Text="Remote Routing Address" Style="{DynamicResource ReviewLabel}"/>
							<TextBlock x:Name="ReviewRemoteRouting" Text="-" Style="{DynamicResource ReviewValue}"/>

							<TextBlock Text="Send Notification" Style="{DynamicResource ReviewLabel}"/>
							<TextBlock x:Name="ReviewNotification" Text="-" Style="{DynamicResource ReviewValue}"/>

							<TextBlock Text="Notification Recipient" Style="{DynamicResource ReviewLabel}"/>
							<TextBlock x:Name="ReviewNotificationRecipient" Text="-" Style="{DynamicResource ReviewValue}"/>
						</StackPanel>
					</Border>
					
					<Border Style="{DynamicResource ReviewCard}" Margin="0,0,0,6">
						<StackPanel>

							<TextBlock Text="Asset Requests"
									   FontSize="26"
									   FontWeight="Bold"
									   Foreground="White"
									   Margin="0,0,0,18"/>

							<Grid>
								<Grid.ColumnDefinitions>
									<ColumnDefinition Width="*" />
									<ColumnDefinition Width="18" />
									<ColumnDefinition Width="*" />
								</Grid.ColumnDefinitions>

								<!-- LEFT COLUMN -->
								<StackPanel Grid.Column="0">
									<TextBlock Text="Nothing Requested" Style="{DynamicResource ReviewLabel}" />
									<TextBlock x:Name="ReviewNothingRequested"
											   Text="-"
											   Style="{DynamicResource ReviewValue}" />

									<TextBlock Text="Temporary Office Space" Style="{DynamicResource ReviewLabel}" />
									<TextBlock x:Name="ReviewTemporaryOfficeSpace"
											   Text="-"
											   Style="{DynamicResource ReviewValue}" />

									<TextBlock Text="Permanent Office Space" Style="{DynamicResource ReviewLabel}" />
									<TextBlock x:Name="ReviewPermanentOfficeSpace"
											   Text="-"
											   Style="{DynamicResource ReviewValue}" />

									<TextBlock Text="Desktop" Style="{DynamicResource ReviewLabel}" />
									<TextBlock x:Name="ReviewDesktop"
											   Text="-"
											   Style="{DynamicResource ReviewValue}" />

									<TextBlock Text="Laptop" Style="{DynamicResource ReviewLabel}" />
									<TextBlock x:Name="ReviewLaptop"
											   Text="-"
											   Style="{DynamicResource ReviewValue}" />

									<TextBlock Text="Docking Station" Style="{DynamicResource ReviewLabel}" />
									<TextBlock x:Name="ReviewDockingStation"
											   Text="-"
											   Style="{DynamicResource ReviewValue}" />
								</StackPanel>

								<!-- RIGHT COLUMN -->
								<StackPanel Grid.Column="2">
									<TextBlock Text="Mouse/Keyboard Combo" Style="{DynamicResource ReviewLabel}" />
									<TextBlock x:Name="ReviewMouseKeyboard"
											   Text="-"
											   Style="{DynamicResource ReviewValue}" />

									<TextBlock Text="Monitor" Style="{DynamicResource ReviewLabel}" />
									<TextBlock x:Name="ReviewMonitor"
											   Text="-"
											   Style="{DynamicResource ReviewValue}" />

									<TextBlock Text="Dual Monitor" Style="{DynamicResource ReviewLabel}" />
									<TextBlock x:Name="ReviewDualMonitor"
											   Text="-"
											   Style="{DynamicResource ReviewValue}" />

									<TextBlock Text="Desk Phone" Style="{DynamicResource ReviewLabel}" />
									<TextBlock x:Name="ReviewDeskPhone"
											   Text="-"
											   Style="{DynamicResource ReviewValue}" />

									<TextBlock Text="Cell Phone" Style="{DynamicResource ReviewLabel}" />
									<TextBlock x:Name="ReviewCellPhone"
											   Text="-"
											   Style="{DynamicResource ReviewValue}" />

									<TextBlock Text="Speakers" Style="{DynamicResource ReviewLabel}" />
									<TextBlock x:Name="ReviewSpeakers"
											   Text="-"
											   Style="{DynamicResource ReviewValue}" />
								</StackPanel>

							</Grid>
						</StackPanel>
					</Border>
					
					<Border Style="{DynamicResource ReviewCard}" Margin="0,0,0,6">
						<StackPanel>

							<TextBlock Text="Security Groups"
									   FontSize="26"
									   FontWeight="Bold"
									   Foreground="White"
									   Margin="0,0,0,18"/>

							<TextBlock Text="The following groups will be assigned to the user:"
									   Style="{DynamicResource ReviewLabel}"
									   Margin="0,0,0,10"/>

							<TextBlock x:Name="ReviewGroupList"
									   Text="-"
									   Style="{DynamicResource ReviewValue}"
									   TextWrapping="Wrap"/>
						</StackPanel>
					</Border>

                </StackPanel>
            </ScrollViewer>
        </Border>

        <!-- RIGHT PANEL -->
        <Border Grid.Column="1"
                CornerRadius="24"
                Padding="42"
                BorderBrush="#99A9C8FF"
                BorderThickness="1"
                Effect="{DynamicResource SoftBlueGlow}">

            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                    <GradientStop Color="#7A123653" Offset="0"/>
                    <GradientStop Color="#52101E3E" Offset="0.45"/>
                    <GradientStop Color="#806064A8" Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>

            <StackPanel VerticalAlignment="Center">

                <Grid HorizontalAlignment="Center" Margin="0,0,0,28">
                    <Ellipse Width="150" Height="150" Opacity="0.65">
                        <Ellipse.Fill>
                            <RadialGradientBrush>
                                <GradientStop Color="#55FE7A00" Offset="0"/>
                                <GradientStop Color="#22FE5000" Offset="0.55"/>
                                <GradientStop Color="#00FE5000" Offset="1"/>
                            </RadialGradientBrush>
                        </Ellipse.Fill>
                    </Ellipse>

                    <Border Width="128"
                            Height="128"
                            CornerRadius="64"
                            BorderBrush="#FFFE7A00"
                            BorderThickness="4"
                            Background="Transparent"
                            HorizontalAlignment="Center"
                            VerticalAlignment="Center">
                        <Border.Effect>
                            <DropShadowEffect Color="#FE7A00"
                                              BlurRadius="28"
                                              ShadowDepth="0"
                                              Opacity="1"/>
                        </Border.Effect>

                        <TextBlock Text="✓"
                                   FontSize="72"
                                   FontWeight="SemiBold"
                                   Foreground="white"
                                   HorizontalAlignment="Center"
                                   VerticalAlignment="Center"/>
                    </Border>
                </Grid>

                <TextBlock Text="Ready to Create"
                           FontFamily="{DynamicResource AppFont}"
                           FontSize="36"
                           FontWeight="Bold"
                           Foreground="White"
                           HorizontalAlignment="Center"/>

                <TextBlock Text="Review the collected information before creating the account. Use Back to make corrections."
                           FontFamily="{DynamicResource AppFont}"
                           FontSize="21"
                           FontWeight="SemiBold"
                           Foreground="White"
                           TextWrapping="Wrap"
                           TextAlignment="Center"
                           LineHeight="31"
                           Margin="0,24,0,34"/>

                <Border Height="1"
                        Background="#33FFFFFF"
                        Margin="0,0,0,28"/>

                <TextBlock x:Name="ReviewStatusText"
                           Text="Waiting for review."
                           FontFamily="{DynamicResource AppFont}"
                           FontSize="18"
                           FontWeight="SemiBold"
                           Foreground="White"
                           TextWrapping="Wrap"
                           TextAlignment="Center"
                           LineHeight="28"
                           Margin="0,0,0,28"/>

                <Button x:Name="ExecuteCreateUserButton"
                        Width="320"
                        Height="76"
                        Style="{DynamicResource StartButtonStyle}">
                    <TextBlock Text="Create User"
                               FontWeight="Bold"
                               FontSize="23"
                               Foreground="#FF001018"
                               HorizontalAlignment="Center"
                               TextAlignment="Center"/>
                </Button>

            </StackPanel>
        </Border>
    </Grid>
</Page>
'@

# ============================================================
# Load UI
# ============================================================
try {
    $ThemeDictionary = Load-XamlString $XamlTheme
    $MainWindow = Load-XamlString $XamlMainWindow
    $MainWindow.Resources.MergedDictionaries.Add($ThemeDictionary) | Out-Null
    $Page1 = Load-XamlString $XamlPage1
    $Page1.Resources.MergedDictionaries.Add((Load-XamlString $XamlTheme)) | Out-Null
    $Page2 = Load-XamlString $XamlPage2
    $Page2.Resources.MergedDictionaries.Add((Load-XamlString $XamlTheme)) | Out-Null
    $Page3 = Load-XamlString $XamlPage3
    $Page3.Resources.MergedDictionaries.Add((Load-XamlString $XamlTheme)) | Out-Null
    $Page4 = Load-XamlString $XamlPage4
    $Page4.Resources.MergedDictionaries.Add((Load-XamlString $XamlTheme)) | Out-Null
}
catch {
    Write-Host "Failed to load wizard XAML: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.InnerException) {
        Write-Host "Inner exception: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
    throw
}

$HeaderPanel    = $MainWindow.FindName("HeaderPanel")
$ExitXButton    = $MainWindow.FindName("ExitXButton")
$InfoButton 	= $MainWindow.FindName("InfoButton")
$MinButton      = $MainWindow.FindName("MinButton")
$MaxButton      = $MainWindow.FindName("MaxButton")
$PageFrame      = $MainWindow.FindName("PageFrame")
$NextButton     = $MainWindow.FindName("NextButton")
$BackButton     = $MainWindow.FindName("BackButton")
$NextButtonText = $MainWindow.FindName("NextButtonText")
$StepText       = $MainWindow.FindName("StepText")
$Dot1           = $MainWindow.FindName("Dot1")
$Dot2           = $MainWindow.FindName("Dot2")
$Dot3           = $MainWindow.FindName("Dot3")
$Dot4           = $MainWindow.FindName("Dot4")
$DebugTogglePanel    = $MainWindow.FindName("DebugTogglePanel")
$DebugToggleIcon     = $MainWindow.FindName("DebugToggleIcon")
$DebugPanel          = $MainWindow.FindName("DebugPanel")
$DebugOutputBox      = $MainWindow.FindName("DebugOutputBox")
$DebugRowDefinition  = $MainWindow.FindName("DebugRowDefinition")
$ClearDebugButton    = $MainWindow.FindName("ClearDebugButton")

$script:MainWindow = $MainWindow
$script:DebugTogglePanel = $DebugTogglePanel
$script:DebugToggleIcon = $DebugToggleIcon
$script:DebugPanel = $DebugPanel
$script:DebugOutputBox = $DebugOutputBox
$script:DebugRowDefinition = $DebugRowDefinition
$Global:DebugBaseWindowHeight = $MainWindow.Height

function Get-WizardBrush {
    param(
        [Parameter(Mandatory)][string]$ResourceKey,
        [Parameter(Mandatory)][string]$Fallback
    )

    try {
        $resource = $MainWindow.TryFindResource($ResourceKey)
        if ($resource) { return $resource }
    }
    catch { }

    return ([System.Windows.Media.BrushConverter]::new()).ConvertFromString($Fallback)
}


function Show-InfoDialog {
    param([string]$Content)

    $InfoWin = Load-XamlString $XamlInfoDialog
	$InfoWin.Resources.MergedDictionaries.Add($ThemeDictionary) | Out-Null

    $InfoContentBlock = $InfoWin.FindName("InfoContentBlock")
    $CloseInfoButton  = $InfoWin.FindName("CloseInfoButton")

    # Load the text
    $InfoContentBlock.Text = $Content

    # Bind close button
    $CloseInfoButton.Add_Click({
        $InfoWin.Close()
    })
	
	$InfoWin.Add_MouseDown({
		if ($_.ChangedButton -eq "Left") {
			$InfoWin.DragMove()
		}
	})

    # Modal dialog with main window as owner
    $InfoWin.Owner = $MainWindow
    $InfoWin.ShowDialog() | Out-Null
}

$ExecuteCreateUserButton = $Page4.FindName("ExecuteCreateUserButton")

$Global:WizardStep = 1
$Global:UserCreated = $false

$StartDatePicker = $Page3.FindName("StartDatePicker")

$Today = Get-Date
$DaysUntilMonday = ([int][DayOfWeek]::Monday - [int]$Today.DayOfWeek + 7) % 7

if ($DaysUntilMonday -eq 0) {
    $DaysUntilMonday = 7
}

if ($Today.DayOfWeek -eq [DayOfWeek]::Thursday) {
    $DaysUntilMonday += 7
}

$DefaultStartDate = $Today.Date.AddDays($DaysUntilMonday)

$StartDatePicker.SelectedDate = $DefaultStartDate
$StartDatePicker.DisplayDate  = $DefaultStartDate

$ManagerComboBoxFound = $Page3.FindName("ManagerComboBox")

# Load all managers (example: anyone with direct reports)
if ($Global:NoNet) {
    Write-DebugLog "-NoNet enabled. Skipping AD manager lookup." "WARN"
    $AllManagers = @()
}
else {
    try {
        $AllManagers = Get-ADUser -Filter { directReports -like "*" } -Properties SamAccountName, Name |
                       Sort-Object Name
    }
    catch {
        Write-DebugLog "Manager lookup failed: $($_.Exception.Message)" "WARN"
        $AllManagers = @([PSCustomObject]@{
				Name            = "No Managers Available"
				SamAccountName  = "NoManagers"
			}
		)
    }
}

# Bind all managers to the ComboBox
$ManagerComboBoxFound.ItemsSource = $AllManagers
$ManagerComboBoxFound.DisplayMemberPath = "Name"
$ManagerComboBoxFound.SelectedValuePath = "SamAccountName"

$SelectedManager = $AllManagers | Where-Object { $_.Name -eq $ManagerN }
if ($SelectedManager) {
    $ManagerComboBoxFound.SelectedItem = $SelectedManager
}

$MainWindow.Add_Closing({
    Write-DebugLog "Window closing..." "INFO"
    Invoke-WizardCleanup
})
# ============================================================
# UI Helpers
# ============================================================
function Set-Status {
    param(
        [Parameter(Mandatory)]$Page,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet("normal", "success", "warning", "error")]
        [string]$State = "normal"
    )

    $Block = $Page.FindName($Name)
    if (-not $Block) { return }

    $Block.Text = $Text

    switch ($State) {
        "success" { $Block.Style = $MainWindow.Resources["StatusSuccess"] }
        "warning" { $Block.Style = $MainWindow.Resources["StatusWarning"] }
        "error"   { $Block.Style = $MainWindow.Resources["StatusError"] }
        default   { $Block.Style = $MainWindow.Resources["StatusText"] }
    }

    Do-Events
}

function Add-Reminder {
    param(
        [Parameter(Mandatory)]$Page,
        [Parameter(Mandatory)][string]$Message
    )

    $ReminderText = $Page.FindName("ReminderText")
    if (-not $ReminderText) { return }

    # Escape wildcard characters so -notlike doesn’t explode
    $SafeMessage = [regex]::Escape($Message)

    if ($ReminderText.Text -eq "No reminders yet.") {
        $ReminderText.Text = "• $Message"
    }
    elseif ($ReminderText.Text -notmatch $SafeMessage) {
        $ReminderText.Text += "`n`n• $Message"
    }

    Do-Events
}

function Clear-Reminders {
    param([Parameter(Mandatory)]$Page)

    $ReminderText = $Page.FindName("ReminderText")
    if ($ReminderText) {
        $ReminderText.Text = "No reminders yet."
    }
}

function Update-WizardUI {
    Write-DebugLog "Updating wizard UI to step $Global:WizardStep." "INFO"
    switch ($Global:WizardStep) {
        1 {
            $PageFrame.Content = $Page1
            $StepText.Text = "Step 1 of 4"
            $NextButtonText.Text = "Next"
            $BackButton.IsEnabled = $false
            $Dot1.Fill = (Get-WizardBrush -ResourceKey "Accent" -Fallback "#FE7A00")
            $Dot2.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#557E91AA")
            $Dot3.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#557E91AA")
            $Dot4.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#557E91AA")
        }
        2 {
            $PageFrame.Content = $Page2
            $StepText.Text = "Step 2 of 4"
            $NextButtonText.Text = "Next"
            $BackButton.IsEnabled = $true
            $Dot1.Fill = (Get-WizardBrush -ResourceKey "Accent" -Fallback "#FE7A00")
            $Dot2.Fill = (Get-WizardBrush -ResourceKey "Accent" -Fallback "#FE7A00")
            $Dot3.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#557E91AA")
            $Dot4.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#557E91AA")
        }
        3 {
            $PageFrame.Content = $Page3
            $StepText.Text = "Step 3 of 4"
            $NextButtonText.Text = "Next"
            $BackButton.IsEnabled = $true
            $Dot1.Fill = (Get-WizardBrush -ResourceKey "Accent" -Fallback "#FE7A00")
            $Dot2.Fill = (Get-WizardBrush -ResourceKey "Accent" -Fallback "#FE7A00")
            $Dot3.Fill = (Get-WizardBrush -ResourceKey "Accent" -Fallback "#FE7A00")
            $Dot4.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#557E91AA")
        }
        4 {
            $PageFrame.Content = $Page4
            $StepText.Text = "Step 4 of 4"
            $NextButtonText.Text = "Finish"
            $BackButton.IsEnabled = $true
			$NextButton.IsEnabled = $false
			$NextButton.Opacity = 0.45
            $Dot1.Fill = (Get-WizardBrush -ResourceKey "Accent" -Fallback "#FE7A00")
            $Dot2.Fill = (Get-WizardBrush -ResourceKey "Accent" -Fallback "#FE7A00")
            $Dot3.Fill = (Get-WizardBrush -ResourceKey "Accent" -Fallback "#FE7A00")
            $Dot4.Fill = (Get-WizardBrush -ResourceKey "Accent" -Fallback "#FE7A00")
        }
    }

    Do-Events
}

# ============================================================
# Checks: Non-blocking reminders, not hard failures
# ============================================================
function Start-Checks {
    param([Parameter(Mandatory)]$Page)

    Write-DebugLog "Start-Checks invoked." "INFO"

    Clear-Reminders $Page

    if ($Global:NoNet) {
        Set-Status $Page "StatusDetail" "Offline / no-network mode is enabled. Module loading and network checks were skipped." "warning"
        Set-Status $Page "StatusADModule" "⚠ -NoNet enabled. Active Directory module check skipped." "warning"
        Set-Status $Page "StatusADConnection" "⚠ -NoNet enabled. AD connectivity check skipped." "warning"
        Set-Status $Page "StatusGraphModule" "⚠ -NoNet enabled. Microsoft Graph module check skipped." "warning"
        Set-Status $Page "StatusGraphAuth" "⚠ -NoNet enabled. Graph authentication skipped." "warning"
        Set-Status $Page "StatusExchangeModule" "⚠ -NoNet enabled. Exchange module/session check skipped." "warning"
        Set-Status $Page "StatusExchangeAuth" "⚠ -NoNet enabled. Exchange connection skipped." "warning"
        Add-Reminder $Page "-NoNet mode is active. This is UI/offline mode only; user creation, AD, Graph, and Exchange actions are disabled."
        $NextButton.IsEnabled = $true
        return
    }

    Set-Status $Page "StatusDetail" "Checking local prerequisites..." "normal"

    $HasADModule = $false
    $HasGraphModule = $false

    # ----------------------------
    # RSAT / Active Directory check
    # ----------------------------
    if (Get-Module -ListAvailable -Name ActiveDirectory) {
        $HasADModule = $true
        Set-Status $Page "StatusADModule" "✓ RSAT Active Directory module is installed." "success"

        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            Set-Status $Page "StatusADConnection" "Checking Active Directory connectivity..." "normal"
            Get-ADDomain -ErrorAction Stop | Out-Null
            Set-Status $Page "StatusADConnection" "✓ Active Directory connectivity confirmed." "success"
        }
        catch {
            Set-Status $Page "StatusADConnection" "⚠ RSAT is installed, but AD connectivity was not confirmed." "warning"
            Add-Reminder $Page "This PC has the AD module, but could not query the domain. Run from a domain-joined management PC, connect VPN, or use PowerShell remoting to a management server. Error: $($_.Exception.Message)"
        }
    }
    else {
        Set-Status $Page "StatusADModule" "⚠ RSAT Active Directory module is not installed on this computer." "warning"
        Set-Status $Page "StatusADConnection" "⚠ AD checks skipped because RSAT is missing." "warning"
        Add-Reminder $Page "Install RSAT Active Directory tools on this PC, or run AD actions remotely from a management server that already has RSAT."
    }

    # ----------------------------
    # Microsoft Graph check
    # ----------------------------
    $TenantId = "ea26f921-331e-4244-948d-d4d13598bbf5"
    $ClientId = "94e76399-fbd5-4aa3-9efd-b658efe42baf"
    $ClientSecret = $ClientSecretPlain
    $Authority = "https://login.microsoftonline.us/$TenantId/oauth2/v2.0/token"
    $Scopes = "https://graph.microsoft.us/.default"

    if (Get-Module -ListAvailable -Name Microsoft.Graph) {
        $HasGraphModule = $true
        Set-Status $Page "StatusGraphModule" "✓ Microsoft Graph PowerShell module is installed." "success"

        try {
            Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

            if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
                throw "Client secret is empty or unavailable. Check config.json/aes.key, or launch with -NoNet for offline UI mode."
            }

            Set-Status $Page "StatusGraphAuth" "Requesting Microsoft Graph token using app registration..." "warning"

            $TokenResponse = Invoke-RestMethod `
                -Method POST `
                -Uri $Authority `
                -Body @{
                    client_id     = $ClientId
                    client_secret = $ClientSecret
                    scope         = $Scopes
                    grant_type    = "client_credentials"
                } `
                -ContentType "application/x-www-form-urlencoded" `
                -ErrorAction Stop

            if (-not $TokenResponse.access_token) {
                throw "Token request failed. No access_token returned."
            }

            $SecureToken = ConvertTo-SecureString $TokenResponse.access_token -AsPlainText -Force
            Connect-MgGraph -AccessToken $SecureToken -NoWelcome -ErrorAction Stop | Out-Null

            $Context = Get-MgContext
            if ($Context) {
                Set-Status $Page "StatusGraphAuth" "✓ Microsoft Graph app authentication successful." "success"
                Add-Reminder $Page "Graph connected using app registration (client secret)."
            }
            else {
                Set-Status $Page "StatusGraphAuth" "⚠ Token succeeded, but Graph context is empty." "warning"
            }
        }
        catch {
            Set-Status $Page "StatusGraphAuth" "⚠ Microsoft Graph authentication failed." "warning"
            Add-Reminder $Page "Graph sign-in failed. Error: $($_.Exception.Message)"
        }
    }
    else {
        Set-Status $Page "StatusGraphModule" "⚠ Microsoft Graph PowerShell module is not installed on this computer." "warning"
        Set-Status $Page "StatusGraphAuth" "⚠ Graph sign-in skipped because the module is missing." "warning"
        Add-Reminder $Page "Install Microsoft Graph PowerShell on this PC, or run Microsoft 365 / Entra actions remotely from a management server."
    }

    # ----------------------------
    # Hybrid Exchange Server Check
    # ----------------------------
    Set-Status $Page "StatusExchangeModule" "Checking on-prem Exchange PowerShell..." "normal"
    Set-Status $Page "StatusExchangeAuth" "Checking Exchange connectivity..." "normal"

    try {
        $ExchangeSnapin = Get-PSSnapin -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "Microsoft.Exchange.Management.PowerShell.*" }

        $ExistingExchangeSession = Get-PSSession -ErrorAction SilentlyContinue |
            Where-Object { $_.ConfigurationName -eq "Microsoft.Exchange" }

        if ($ExchangeSnapin) {
            Set-Status $Page "StatusExchangeModule" "✓ Exchange snap-in already loaded." "success"
            Set-Status $Page "StatusExchangeAuth" "✓ Connected to local Exchange." "success"
            Add-Reminder $Page "Exchange snap-in already loaded (hybrid mode)."
            $ExchangeLoaded = $true
        }
        elseif ($ExistingExchangeSession) {
            Import-PSSession `
                -Session $ExistingExchangeSession `
                -DisableNameChecking `
                -AllowClobber `
                -CommandName @("Enable-RemoteMailbox", "Set-RemoteMailbox", "Get-RemoteMailbox", "Get-Mailbox", "New-Mailbox") |
                Out-Null

            Set-Status $Page "StatusExchangeModule" "✓ Remote Exchange session active." "success"
            Set-Status $Page "StatusExchangeAuth" "✓ Connected to Hybrid Exchange." "success"
            Add-Reminder $Page "Hybrid Exchange session already active (minimal cmdlets loaded)."
            $ExchangeLoaded = $true
        }
        else {
            $SessionEX = New-PSSession `
                -ConfigurationName Microsoft.Exchange `
                -ConnectionUri "http://congo.atlas-tech.com/PowerShell/" `
                -Authentication Kerberos `
                -ErrorAction Stop

            Import-PSSession `
                -Session $SessionEX `
                -DisableNameChecking `
                -AllowClobber `
                -CommandName @("Enable-RemoteMailbox", "Set-RemoteMailbox", "Get-RemoteMailbox", "Get-Mailbox", "New-Mailbox") `
                -ErrorAction Stop |
                Out-Null

            Set-Status $Page "StatusExchangeModule" "✓ Remote Exchange session established." "success"
            Set-Status $Page "StatusExchangeAuth" "✓ Connected to Hybrid Exchange." "success"
            Add-Reminder $Page "Connected to Hybrid Exchange (minimal cmdlets loaded)."
            $ExchangeLoaded = $true
        }
    }
    catch {
        Set-Status $Page "StatusExchangeModule" "⚠ Exchange module/session not available." "warning"
        Set-Status $Page "StatusExchangeAuth" "❌ Unable to connect to Hybrid Exchange." "error"
        Add-Reminder $Page "Exchange Hybrid connection failed: $($_.Exception.Message)"
    }

    # ----------------------------
    # Final status
    # ----------------------------
    if ($HasADModule -and $HasGraphModule) {
        Set-Status $Page "StatusDetail" "Readiness checks completed. This computer appears ready for local AD and Graph actions." "success"
    }
    elseif ($HasADModule -or $HasGraphModule) {
        Set-Status $Page "StatusDetail" "Readiness checks completed with reminders. You can continue, but some actions may need to run remotely." "warning"
    }
    else {
        Set-Status $Page "StatusDetail" "This PC is missing local management modules. You can continue using the GUI, but AD/Graph actions must run elsewhere or after installing prerequisites." "warning"
    }

    $NextButton.IsEnabled = $true
}

# ============================================================
# Window Events
# ============================================================
$HeaderPanel.Add_MouseDown({
    if ($_.ChangedButton -eq "Left") {
        $MainWindow.DragMove()
    }
})


$ExitXButton.Add_Click({
    Write-DebugLog "Exit button clicked." "INFO"
    Invoke-WizardCleanup
	$script:StartupAborted = $true
    $MainWindow.Close()
})


$InfoButton.Add_Click({
    $InfoText = @"
	
This wizard assists with:
 • Active Directory new user creation
 • Hybrid Exchange remote mailbox setup
 • Group assignment (region, org, CAC, TEEntry)
 • JAMIS claim account initiation
 • New-hire onboarding notifications
 • Full WPF-guided multi-step intake workflow

Debug Mode:
 • Launch with -Debug
 • Shows a collapsible live logging pane
 • Toggle anytime using the ☰ icon

-NoNet Mode:
 • Launch with -NoNet
 • Skips AD/Graph/Exchange modules
 • Disables user creation & network actions
 • Allows offline UI testing and demonstrations

Other:
 • Handles STA re-launch for WPF reliability
 • Performs non-blocking readiness checks
 • Full review step before execution
"@

    Show-InfoDialog -Content $InfoText
})

$MinButton.Add_Click({
    $MainWindow.WindowState = "Minimized"
})

$MaxButton.Add_Click({
    if ($MainWindow.WindowState -eq "Maximized") {
        $MainWindow.WindowState = "Normal"
    }
    else {
        $MainWindow.WindowState = "Maximized"
    }
})

if ($DebugTogglePanel) {
    $DebugTogglePanel.Add_MouseLeftButtonUp({
        Toggle-DebugMode
    })
}

if ($ClearDebugButton) {
    $ClearDebugButton.Add_Click({
        if ($script:DebugOutputBox) {
            $script:DebugOutputBox.Clear()
        }
        Write-DebugLog "Debug output cleared." "INFO"
    })
}

Write-DebugLog "Wizard UI initialized." "INFO"
if ($Debug.IsPresent) {
    Set-DebugMode -Enabled $true
}

# Page 1 internal Start button
$Page1NextButton = $Page1.FindName("NextButton_Page1")
$Page1NextButton.Add_Click({
    $NextButton.RaiseEvent(
        [System.Windows.RoutedEventArgs]::new(
            [System.Windows.Controls.Button]::ClickEvent
        )
    )
})

# Page 2 rerun button
$RunChecksButton = $Page2.FindName("RunChecksButton")
$RunChecksButton.Add_Click({
    Write-DebugLog "Run Checks Again clicked." "INFO"
    Start-Checks -Page $Page2
})

function Get-SelectedNumber {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    return [int]($Value.Split('.')[0].Trim())
}

function Get-NewUserMappings {
    param(
        [int]$OfficeN,
        [int]$DeptN,
        [int]$HomeOrgV
    )

    $OfficeMap = @{
        1 = @{ Atlasloc = "Atlas-Charleston"; City = "North Charleston"; StreetAddress = "5416-A Rivers Avenue - Suite 105"; StateField = "SC"; PostalCode = "29406" }
        2 = @{ Atlasloc = "Atlas-Charleston"; City = "North Charleston"; StreetAddress = "1101 Remount Rd, Suite 800"; StateField = "SC"; PostalCode = "29406" }
        3 = @{ Atlasloc = "Atlas-VABeach"; City = "Virginia Beach"; StreetAddress = "168 Business Park Drive, Suite 103"; StateField = "VA"; PostalCode = "23462" }
        4 = @{ Atlasloc = "Atlas-SD"; City = "San Diego"; StreetAddress = "4250 Pacific Highway, 105"; StateField = "CA"; PostalCode = "92110" }
        5 = @{ Atlasloc = "Atlas-DC"; City = "Alexandria"; StreetAddress = "5911 Kingstowne Village Parkway Suite 310"; StateField = "VA"; PostalCode = "22315" }
        6 = @{ Atlasloc = "Atlas-MD"; City = "Lexington"; StreetAddress = "Not Available"; StateField = "MD"; PostalCode = "Not Available" }
    }

    $HomeOrgMap = @{
        1 = @{ HomeOrgG = "Draco.Team"; HomeOrgGnoPeriod = "Draco Team" }
        2 = @{ HomeOrgG = "Pavo.Team"; HomeOrgGnoPeriod = "Pavo Team" }
        3 = @{ HomeOrgG = "Corvus.Team"; HomeOrgGnoPeriod = "Corvus Team" }
    }

    $OuMap = @{
        "HQ:1" = "OU=Users,OU=Accounting,OU=Dept-00,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com"
        "HQ:2" = "OU=Users,OU=IT,OU=Dept-00,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com"
        "HQ:3" = "OU=Users,OU=Exec,OU=Dept-00,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com"
        "HQ:4" = "OU=Users,OU=HR,OU=Dept-00,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com"
        "HQ:5" = "OU=Users,OU=Contracts,OU=Dept-01,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com"
        "HQ:6" = "OU=Users,OU=Operations,OU=Dept-01,OU=HQ,OU=Atlas-tech,DC=atlas-tech,DC=com"
        "HQ:7" = "OU=Users,OU=Dept-02,OU=SC,OU=Atlas-tech,DC=atlas-tech,DC=com"
        "3:8"  = "OU=Users,OU=Dept-03,OU=VA,OU=Atlas-tech,DC=atlas-tech,DC=com"
        "4:9"  = "OU=Users,OU=Dept-04,OU=CA,OU=Atlas-tech,DC=atlas-tech,DC=com"
        "5:7"  = "OU=Users,OU=Dept-02,OU=DC,OU=Atlas-tech,DC=atlas-tech,DC=com"
        "6:7"  = "OU=Users,OU=Dept-02,OU=MD,OU=Atlas-tech,DC=atlas-tech,DC=com"
    }

    $Office = if ($OfficeMap.ContainsKey($OfficeN)) { $OfficeMap[$OfficeN] } else { @{ Atlasloc = "Atlas-Charleston"; City = "Not Entered"; StreetAddress = "Not Entered"; StateField = "NA"; PostalCode = "Not Available" } }
    $HomeOrg = if ($HomeOrgMap.ContainsKey($HomeOrgV)) { $HomeOrgMap[$HomeOrgV] } else { @{ HomeOrgG = "NA"; HomeOrgGnoPeriod = $null } }

    if ($DeptN -eq 10) {
        $PathOU = "OU=Service Accounts,OU=Atlas-tech,DC=atlas-tech,DC=com"
    }
    else {
        $OuKey = if ($OfficeN -in @(1,2)) { "HQ:$DeptN" } else { "${OfficeN}:$DeptN" }
        $PathOU = if ($OuMap.ContainsKey($OuKey)) { $OuMap[$OuKey] } else { "CN=Users,DC=atlas-tech,DC=com" }
    }

    return @{
        CGUsersSC        = "SC_CGUsers"
        CGUsersSD        = "SD_CGUsers"
        CGUsersVA        = "VABeach_CGUsers"
        CAC              = "CAC_Holders"
        Atlasloc         = $Office.Atlasloc
        HomeOrgG         = $HomeOrg.HomeOrgG
        HomeOrgGnoPeriod = $HomeOrg.HomeOrgGnoPeriod
        PathOU           = $PathOU
        City             = $Office.City
        StreetAddress    = $Office.StreetAddress
        StateField       = $Office.StateField
        PostalCode       = $Office.PostalCode
    }
}

function Invoke-JamisClaimSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][int]$DeptN
    )

    Write-DebugLog "Invoke-JamisClaimSetup started." "INFO"

    # -------------------------
    # 1. Skip JAMIS for Service Accounts
    # -------------------------
    if ($DeptN -eq 10) {
        Write-DebugLog "JAMIS skipped because DeptN = 10 (service account)." "INFO"
        return
    }

    # -------------------------
    # 2. User Prompt – Start
    # -------------------------
    $Start = [System.Windows.MessageBox]::Show(
        "JAMIS claim account creation is required.

Chrome will open using the new user's credentials.

Complete the JAMIS login prompts, wait until the page fully loads,
then close the Chrome window.

Continue?",
        "JAMIS Claim Account Creation Required",
        [System.Windows.MessageBoxButton]::OKCancel,
        [System.Windows.MessageBoxImage]::Warning
    )

    if ($Start -ne [System.Windows.MessageBoxResult]::OK) {
        throw "JAMIS claim account setup was cancelled by the operator."
    }

    # -------------------------
    # 3. Chrome Path Detection
    # -------------------------
    $ChromePath = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path $ChromePath)) {
        $ChromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    }
    if (-not (Test-Path $ChromePath)) {
        throw "Chrome browser could not be located. JAMIS login must be performed manually."
    }

    Write-DebugLog "Chrome located at: $ChromePath" "INFO"

    # -------------------------
    # 4. Build Credential For JAMIS Login
    # -------------------------
    try {
        $Cred = New-Object System.Management.Automation.PSCredential(
            "atlas-tech\$SamAccountName",
            (ConvertTo-SecureString $TempPasswordPlain -AsPlainText -Force)
        )
        Write-DebugLog "Credential object created for JAMIS launch." "INFO"
    }
    catch {
        throw "Failed to generate credential for JAMIS login: $($_.Exception.Message)"
    }

    # -------------------------
    # 5. Launch Chrome as the New User
    # -------------------------
    Write-DebugLog "Launching Chrome as '$SamAccountName' for JAMIS claim creation." "INFO"

    try {
        Start-Process `
            -FilePath $ChromePath `
            -Credential $Cred `
            -ArgumentList "-incognito https://axisng.atlas-tech.com/Main.aspx?ScreenId=DH000100&SilentLogin=Federation" `
            -WorkingDirectory "C:\" `
            -Wait

        Write-DebugLog "Chrome session completed." "INFO"
    }
    catch {
        throw "Chrome failed to launch for JAMIS login: $($_.Exception.Message)"
    }

    # -------------------------
    # 6. Confirmation Prompt
    # -------------------------
    $Confirm = [System.Windows.MessageBox]::Show(
        "Did you complete creation of the employee's JAMIS claim account?

Do NOT click Yes until the JAMIS page has finished loading and initial setup is complete.",
        "JAMIS Claim Account Confirmation",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    if ($Confirm -ne [System.Windows.MessageBoxResult]::Yes) {
        throw "JAMIS claim account was not confirmed by the operator."
    }

    # -------------------------
    # 8. Finished
    # -------------------------
    Write-DebugLog "JAMIS claim account setup completed successfully for $SamAccountName." "SUCCESS"
}

function Invoke-NewUserCreation {
    if ($Global:NoNet) {
        throw "-NoNet mode is enabled. User creation and AD/Graph/Exchange write actions are disabled."
    }

    Write-DebugLog "Invoke-NewUserCreation started." "INFO"
    $FirstName = $Page3.FindName("FirstNameBox").Text.Trim()
    $MiddleInitial = $Page3.FindName("MiddleInitialBox").Text.Trim()
    $LastName = $Page3.FindName("LastNameBox").Text.Trim()
    $IncludeMI = $Page3.FindName("IncludeMiddleInitialCheckBox").IsChecked

    if ($IncludeMI -and $MiddleInitial) {
        $SamAccountName = ($FirstName.Substring(0,1) + $MiddleInitial + $LastName).ToLower()
    }
    else {
        $SamAccountName = ($FirstName.Substring(0,1) + $LastName).ToLower()
    }

    $DisplayName = "$FirstName $LastName"
    $UserPrincipalName = "$SamAccountName@atlas-tech.com"

    $StartDate   = $Page3.FindName("StartDatePicker").SelectedDate
    $Title       = $Page3.FindName("JobTitleBox").Text.Trim()
    $Manager     = $Page3.FindName("ManagerComboBox").SelectedValue
    $Location    = $Page3.FindName("LocationComboBox").Text.Trim()
    $Department  = $Page3.FindName("DepartmentComboBox").Text.Trim()
    $Empid       = $Page3.FindName("EmployeeIdBox").Text.Trim()
    $Bdgeid      = $Page3.FindName("BadgeIdBox").Text.Trim()
    $OfficePhn   = $Page3.FindName("OfficePhoneBox").Text.Trim()
    $MobilePhone = $Page3.FindName("MobilePhoneBox").Text.Trim()
	
	
	if([string]::IsNullOrEmpty($OfficePhn)) {$OfficePhn = "NA"} 
		$countOP= $OfficePhn | measure-object -character | select -expandproperty characters
		if ($countOP -lt 12) 
		{ 
		$OfficePhn = "NA" 
		}elseif ($countOP -gt 12){ 
		$OfficePhn = "NA"
		}
	$ZLOffice = $Location -replace '^\d+\.\s*', ''
	$ZLDepartment = $Department -replace '^\d+\.\s*', ''
	$ZLDepartment = $ZLDepartment -replace '^Dept\s*(\d+)\s*-.*$', '$1'



    $CreateMailbox = $Page3.FindName("CreateMailboxCheckBox").IsChecked
	$NotifyUSR   = $Page3.FindName("SendNewHireNoticeCheckBox").IsChecked
	$CACReq        = $Page3.FindName("CACCheckBox").IsChecked
    $SendNotice    = $Page3.FindName("SendNewHireNoticeCheckBox").IsChecked
	Write-DebugLog "Manager field lookup raw: $Manager" "INFO"
    # Mapping MUST happen before New-ADUser
    $OfficeN   = Get-SelectedNumber $Location
    $DeptN     = Get-SelectedNumber $Department
    $HomeOrgV  = Get-SelectedNumber $Page3.FindName("HomeOrgComboBox").Text

    $Mappings = Get-NewUserMappings `
        -OfficeN $OfficeN `
        -DeptN $DeptN `
        -HomeOrgV $HomeOrgV

    $PathOU           = $Mappings.PathOU
    $CGUsersSC        = $Mappings.CGUsersSC
    $CGUsersSD        = $Mappings.CGUsersSD
    $CGUsersVA        = $Mappings.CGUsersVA
    $Atlasloc         = $Mappings.Atlasloc
    $HomeOrgG         = $Mappings.HomeOrgG
    $HomeOrgGnoPeriod = $Mappings.HomeOrgGnoPeriod
	$City			  = $Mappings.City
	$StreetAddress	  = $Mappings.StreetAddress
	$StateField		  = $Mappings.StateField
	$PostalCode		  = $Mappings.PostalCode
	
	$NothingRequested                     = ($Page3.FindName("NothingRequestedCheckBox")).IsChecked
	$TemporaryOfficeSpace                 = ($Page3.FindName("TemporaryOfficeSpaceCheckBox")).IsChecked
	$PermanentOfficeSpace                 = ($Page3.FindName("PermanentOfficeSpaceCheckBox")).IsChecked
	$Desktop                              = ($Page3.FindName("DesktopCheckBox")).IsChecked
	$Laptop                               = ($Page3.FindName("LaptopCheckBox")).IsChecked
	$DockingStation                       = ($Page3.FindName("DockingStationCheckBox")).IsChecked
	$MouseKeyboard                        = ($Page3.FindName("MouseKeyboardCheckBox")).IsChecked
	$Monitor                              = ($Page3.FindName("MonitorCheckBox")).IsChecked
	$DualMonitor                          = ($Page3.FindName("DualMonitorCheckBox")).IsChecked
	$DeskPhone                            = ($Page3.FindName("DeskPhoneCheckBox")).IsChecked
	$CellPhone                            = ($Page3.FindName("CellPhoneCheckBox")).IsChecked
	$Speakers                             = ($Page3.FindName("SpeakersCheckBox")).IsChecked

    $Company = "Atlas Technologies, Inc."
    $Office = $Location
    $Description = $Title
    $ipPhone = $OfficePhn
    $Pass = ConvertTo-SecureString $TempPasswordPlain -AsPlainText -Force
	
	$ManagerValue = $Manager
	Write-DebugLog "ManagerValue at set: $ManagerValue | Manager: $Manager" "INFO"
	if (-not [string]::IsNullOrWhiteSpace($Manager)) {
		try {
			$ManagerValue = (Get-ADUser -Filter "SamAccountName -eq '$Manager'" -ErrorAction Stop).DistinguishedName
			Write-DebugLog "ManagerValue (In try block): $ManagerValue | Manager: $Manager" "INFO"
		}
		catch {
			throw "Could not resolve manager '$Manager' to an AD user."
		}
	}
	Write-DebugLog "PathOU: $PathOU" "INFO"
	Write-DebugLog "CGUsersSC: $CGUsersSC" "INFO"
	Write-DebugLog "CGUsersSD: $CGUsersSD" "INFO"
	Write-DebugLog "CGUsersVA: $CGUsersVA" "INFO"
	Write-DebugLog "Atlasloc: $Atlasloc" "INFO"
	Write-DebugLog "HomeOrgG: $HomeOrgG" "INFO"
	Write-DebugLog "HomeOrgGnoPeriod: $HomeOrgGnoPeriod" "INFO"
	Write-DebugLog "NothingRequested: $NothingRequested" "INFO"
	Write-DebugLog "TemporaryOfficeSpace: $TemporaryOfficeSpace" "INFO"
	Write-DebugLog "PermanentOfficeSpace: $PermanentOfficeSpace" "INFO"
	Write-DebugLog "Desktop: $Desktop" "INFO"
	Write-DebugLog "Laptop: $Laptop" "INFO"
	Write-DebugLog "DockingStation: $DockingStation" "INFO"
	Write-DebugLog "MouseKeyboard: $MouseKeyboard" "INFO"
	Write-DebugLog "Monitor: $Monitor" "INFO"
	Write-DebugLog "DualMonitor: $DualMonitor" "INFO"
	Write-DebugLog "DeskPhone: $DeskPhone" "INFO"
	Write-DebugLog "CellPhone: $CellPhone" "INFO"
	Write-DebugLog "Speakers: $Speakers" "INFO"
	Write-DebugLog "Company: $Company" "INFO"
	Write-DebugLog "Office: $Office" "INFO"
	Write-DebugLog "Description: $Description" "INFO"
	Write-DebugLog "ipPhone: $ipPhone" "INFO"
	Write-DebugLog "Pass (SecureString length): $($Pass.Length)" "INFO"
	Write-DebugLog "ManagerValue: $ManagerValue" "INFO"

    $Params = @{
		Enabled           = $true
		Name              = $DisplayName
		GivenName         = $FirstName
		Surname           = $LastName
		Initial     	  = $MiddleInitial
		DisplayName       = $DisplayName
		SamAccountName    = $SamAccountName
		UserPrincipalName = $UserPrincipalName
		AccountPassword   = $Pass
		Path              = $PathOU
		Company           = $Company
		Manager           = $ManagerValue
		Description       = $Description
		Office            = $ZLOffice
		OfficePhone       = $OfficePhn
		MobilePhone       = $MobilePhone
		Department        = $ZLDepartment
		EmployeeID        = $Empid
		City			  = $City	
		StreetAddress     = $StreetAddress
		State             = $StateField
		PostalCode        = $PostalCode
						  
		Server            = "tanana.atlas-tech.com"
		OtherAttributes   = @{
			title   = $Title
			badgeID = $Bdgeid
			ipPhone = $ipPhone
		}
	}
	
	foreach ($key in @($Params.Keys)) {
		if ([string]::IsNullOrWhiteSpace($Params[$key])) {
			Write-DebugLog "Removing empty parameter '$key'" "INFO"
			$Params.Remove($key)
		}
	}

    Write-DebugLog "Creating AD user $SamAccountName in OU: $PathOU" "INFO"
	Write-DebugLog ("Params:`n$($Params | Format-List | Out-String)") "INFO"
    try {
		New-ADUser @Params -ErrorAction Stop
	}
	catch {
		Write-DebugLog "New-ADUser failed: $($_.Exception.Message)" "ERROR"
		throw
	}
    Write-DebugLog "AD user $SamAccountName created." "SUCCESS"
	
	
	for ($i = 1; $i -le 10; $i++) {
		try {
			Write-DebugLog "Querying AD for new user... Attempt #$i" "INFO"
			$UserObj = Get-ADUser -Identity $SamAccountName -Server tanana.atlas-tech.com -ErrorAction Stop
			break
		}
		catch {
			Start-Sleep -Milliseconds 400
		}
	}

	if (-not $UserObj) {
		Write-DebugLog "User not found in AD after 10 attempts." "ERROR"
		throw "User not found in AD after creation — replication timeout."
	}


    # ============================================================
	# GROUP ASSIGNMENT (REWRITTEN + CONSOLIDATED + RESILIENT)
	# ============================================================

	Write-DebugLog "Starting unified group assignment process..." "INFO"

	$GroupsToAssign = @()

	# Build list of groups only if not a service account (DeptN != 10)
	if ($DeptN -ne 10) {
		if ($CGUsersSC) { $GroupsToAssign += $CGUsersSC }
		if ($CGUsersSD) { $GroupsToAssign += $CGUsersSD }
		if ($CGUsersVA) { $GroupsToAssign += $CGUsersVA }
		if ($Atlasloc)  { $GroupsToAssign += $Atlasloc }
		if ($HomeOrgGnoPeriod) { $GroupsToAssign += $HomeOrgGnoPeriod }
		if ($HomeOrgG -and $HomeOrgG -ne "NA") { $GroupsToAssign += $HomeOrgG }
		if ($CACReq) { $GroupsToAssign += "CAC_Holders" }
		$GroupsToAssign += "TEEntry"
	}

	if ($GroupsToAssign.Count -eq 0) {
		Write-DebugLog "No security groups to assign (service account or no matches)." "INFO"
	}
	else {

		Write-DebugLog "Preparing to assign $($GroupsToAssign.Count) security groups..." "INFO"

		$FailedGroups = @()

		foreach ($group in $GroupsToAssign) {

			Write-DebugLog "Attempting to add user to group: $group" "INFO"

			try {
				Add-ADGroupMember -Identity $group -Members $SamAccountName -ErrorAction Stop

				Write-DebugLog "✓ Added to group: $group" "SUCCESS"
			}
			catch {
				$msg = "Failed to add user to group '$group': $($_.Exception.Message)"
				Write-DebugLog $msg "ERROR"
				$FailedGroups += $group
			}
		}

		if ($FailedGroups.Count -gt 0) {

			Write-DebugLog "Group assignment completed with failures." "WARN"
			Write-DebugLog ("Failed groups:`n" + ($FailedGroups -join "`n")) "WARN"
		}
		else {
			Write-DebugLog "All group assignments completed successfully." "SUCCESS"
		}
	}

    if ($CreateMailbox) {
        Write-DebugLog "Mailbox creation selected." "INFO"
        $RemoteRouting = "{0}@atlastechcloud.mail.onmicrosoft.com" -f $SamAccountName
		$ExchangeGUID  = [guid]::NewGuid()
		Set-ADUser $SAMACCOUNTNAME -Replace @{
			msExchRemoteRecipientType = 4
			targetAddress             = $RemoteRouting
			msExchMailboxGuid         = $ExchangeGUID.ToByteArray()
		}


        if ([string]::IsNullOrWhiteSpace($RemoteRouting)) {
            $RemoteRouting = "$SamAccountName@atlastechcloud.mail.onmicrosoft.com"
        }

        Write-DebugLog "Creating remote mailbox for $SamAccountName." "INFO"
		try{
			Enable-RemoteMailbox `
            -Identity $SamAccountName `
            -RemoteRoutingAddress $RemoteRouting `
            -Alias $SamAccountName
			-ExchangeGuid $ExchangeGUID
        Write-DebugLog "Remote mailbox enabled for $SamAccountName with routing $RemoteRouting." "SUCCESS"
		} catch {
			Write-DebugLog "Could not create mailbox: $($_.Exception.Message)" "ERROR"
			return
		}
    }

    if ($SendNotice) {
        Write-DebugLog "New-hire notification selected." "INFO"
        $smtpserver = "atlastechcloud.mail.protection.office365.us"
        $from = $Page3.FindName("NotificationSenderBox").Text.Trim()
        $to = $Page3.FindName("NotificationRecipientBox").Text.Trim()

        if ([string]::IsNullOrWhiteSpace($from)) {
            $from = "New Hire Onboarding Notice <NEW-HIRE-INFO@atlas-tech.com>"
        }

        if ([string]::IsNullOrWhiteSpace($to)) {
            $to = "ITSupport <ITSupport@atlas-tech.com>"
        }
		
		
		$RunBy   = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
		$RunDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"


        $Subject = "[NEW-HIRE-INFO] New Hire Account $DisplayName Has Been Created"

        $Body = @"
				<div style='font-family:Arial; font-size:14px;'>

				<p>
				<b>THIS EMAIL MAY CONTAIN CONFIDENTIAL OR PII DATA.<br>
				DO NOT FORWARD OUTSIDE THE ORGANIZATION.</b>
				</p>
				<p>
				The account for <b>$DisplayName</b> has been created.<br>
				Please complete the ERP and inventory portions of onboarding.
				</p>
				<h3 style='margin-top:25px;'>General Information</h3>
					<table border='1' cellpadding='6' cellspacing='0' style='border-collapse:collapse;'>
						<tr><th align='left'>Field</th><th align='left'>Value</th></tr>
						<tr><td>Expected Start Date</td><td>$StartDate</td></tr>
						<tr><td>Script Run By</td><td>$RunBy</td></tr>
						<tr><td>Script Run Date</td><td>$RunDate</td></tr>
						<tr><td>Network Username</td><td>$SamAccountName</td></tr>
						<tr><td>User Principal Name</td><td>$UserPrincipalName</td></tr>
						<tr><td>Notify IT of AD User Creation</td><td>$NotifyUSR</td></tr>
						<tr><td>JAMIS Claim Account Created</td><td>In-Progress</td></tr>
						<tr><td>First Name</td><td>$FirstName</td></tr>
						<tr><td>Last Name</td><td>$LastName</td></tr>
						<tr><td>Middle Initial</td><td>$MiddleInitial</td></tr>
						<tr><td>Display Name</td><td>$DisplayName</td></tr>
						<tr><td>Use Middle Initial in Username</td><td>$IncludeMI</td></tr>
						<tr><td>Title</td><td>$Title</td></tr>
						<tr><td>Description</td><td>$Description</td></tr>
						<tr><td>Manager</td><td>$Manager</td></tr>
						<tr><td>Department</td><td>$ZLDepartment</td></tr>
						<tr><td>Employee ID</td><td>$Empid</td></tr>
						<tr><td>Badge ID</td><td>$Bdgeid</td></tr>
						<tr><td>Office Phone</td><td>$OfficePhn</td></tr>
						<tr><td>Mobile Phone</td><td>$MobilePhone</td></tr>
						<tr><td>IP Phone</td><td>$ipPhone</td></tr>
						<tr><td>Company</td><td>$Company</td></tr>
						<tr><td>Office</td><td>$ZLOffice</td></tr>
						<tr><td>Street Address</td><td>$StreetAddress</td></tr>
						<tr><td>City</td><td>$City</td></tr>
						<tr><td>State</td><td>$StateField</td></tr>
						<tr><td>Postal Code</td><td>$PostalCode</td></tr>
						<tr><td>Email Address</td><td>$UserPrincipalName</td></tr>
					</table>
				<h3 style='margin-top:25px;'>Group Assignments</h3>
					<table border='1' cellpadding='6' cellspacing='0' style='border-collapse:collapse;'>
						<tr><th align='left'>Group</th><th align='left'>Value</th></tr>
						<tr><td>RODC SC</td><td>$CGUsersSC</td></tr>
						<tr><td>RODC SD</td><td>$CGUsersSD</td></tr>
						<tr><td>RODC VA</td><td>$CGUsersVA</td></tr>
						<tr><td>Default Email Distribution</td><td>$Atlasloc</td></tr>
					</table>
				<h3 style='margin-top:25px;'>Equipment & Workspace Requests</h3>
					<table border='1' cellpadding='6' cellspacing='0' style='border-collapse:collapse;'>
						<tr><th align='left'>Asset</th><th align='left'>Requested</th></tr>
						<tr><td>Nothing Requested</td><td>$NothingRequested</td></tr>
						<tr><td>Temporary Office Space</td><td>$TemporaryOfficeSpace</td></tr>
						<tr><td>Permanent Office Space</td><td>$PermanentOfficeSpace</td></tr>
						<tr><td>Desktop</td><td>$Desktop</td></tr>
						<tr><td>Laptop</td><td>$Laptop</td></tr>
						<tr><td>Docking Station</td><td>$DockingStation</td></tr>
						<tr><td>Mouse/Keyboard Combo</td><td>$MouseKeyboard</td></tr>
						<tr><td>Monitor</td><td>$Monitor</td></tr>
						<tr><td>Dual Monitors</td><td>$DualMonitor</td></tr>
						<tr><td>Desk Phone</td><td>$DeskPhone</td></tr>
						<tr><td>Cell Phone</td><td>$CellPhone</td></tr>
						<tr><td>Speakers</td><td>$Speakers</td></tr>
					</table>
				</div>
"@

        Write-DebugLog "Sending new-hire onboarding report (user: $DisplayName, UPN: $UserPrincipalName) to $to. Includes AD profile, location info, group assignments, and equipment selections." "INFO"
        try{
			Send-MailMessage `
            -To $to `
            -From $from `
            -Subject $Subject `
            -Body $Body `
            -BodyAsHtml `
            -Priority High `
            -Dno onSuccess,onFailure `
            -SmtpServer $smtpserver
        Write-DebugLog "New-hire notification sent." "SUCCESS"
		} catch {
			Write-DebugLog "Could not send SMTP Message: $($_.Exception.Message)" "ERROR"
			return
		}
    }
	
	Invoke-JamisClaimSetup `
    -SamAccountName $SamAccountName `
    -DeptN $DeptN

    return $SamAccountName
}

#Execute Create User Button
$ExecuteCreateUserButton.Add_Click({

    Write-DebugLog "Create User button clicked." "INFO"
    try {

        $Page4.FindName("ReviewStatusText").Text = "Creating Active Directory user..."

		$ExecuteCreateUserButton.IsEnabled = $false
		$ExecuteCreateUserButton.Opacity = 0.55
		
        if ($Global:NoNet) { throw "-NoNet mode is enabled. User creation is disabled in offline mode." }

        $CreatedSam = Invoke-NewUserCreation

		$Global:UserCreated = $true

		$Page4.FindName("ReviewStatusText").Text =
			"✓ User '$CreatedSam' successfully created."

        Start-Sleep 2

        $Global:UserCreated = $true

        $Page4.FindName("ReviewStatusText").Text =
            "✓ User successfully created."

        $NextButton.IsEnabled = $true
        $NextButton.Opacity = 1

        $ExecuteCreateUserButton.IsEnabled = $false
        $ExecuteCreateUserButton.Opacity = 0.55
        Write-DebugLog "Create User workflow completed successfully for $CreatedSam." "SUCCESS"

    }
    catch {

        Write-DebugLog "User creation failed: $($_.Exception.Message)" "ERROR"
        $Page4.FindName("ReviewStatusText").Text =
            "⚠ User creation failed: $($_.Exception.Message)"

        $Global:UserCreated = $false
        $ExecuteCreateUserButton.IsEnabled = $true
        $ExecuteCreateUserButton.Opacity = 1
    }
})

function IsBlank($value) {
		return [string]::IsNullOrWhiteSpace($value)
	}

function Update-ReviewPage {
    function P3 { param([string]$Name) return $Page3.FindName($Name) }
    function P4 { param([string]$Name) return $Page4.FindName($Name) }
    function YesNo { param([bool]$Value) if ($Value) { "Yes" } else { "No" } }
    function Set-ReviewText {
        param([hashtable]$Map)
        foreach ($key in $Map.Keys) {
            $control = P4 $key
            if ($control) { $control.Text = [string]$Map[$key] }
        }
    }

    Write-DebugLog "Collecting Page 3 values for review." "INFO"
	
	$FirstName          = (P3 "FirstNameBox").Text.Trim()
    $MiddleInitial      = (P3 "MiddleInitialBox").Text.Trim()
    $LastName           = (P3 "LastNameBox").Text.Trim()
	$IncludeMI          = [bool](P3 "IncludeMiddleInitialCheckBox").IsChecked
	
	if ($IncludeMI -and $MiddleInitial) {
        $SamAccountName = ($FirstName.Substring(0,1) + $MiddleInitial + $LastName).ToLower()
    }
    else {
        $SamAccountName = ($FirstName.Substring(0,1) + $LastName).ToLower()
    }

    $Values = @{
        FirstName          = (P3 "FirstNameBox").Text.Trim()
        MiddleInitial      = (P3 "MiddleInitialBox").Text.Trim()
        LastName           = (P3 "LastNameBox").Text.Trim()
        JobTitle           = (P3 "JobTitleBox").Text.Trim()
        Manager            = (P3 "ManagerComboBox").Text
        Location           = (P3 "LocationComboBox").Text
        Department         = (P3 "DepartmentComboBox").Text
        HomeOrg            = (P3 "HomeOrgComboBox").Text
        EmployeeId         = (P3 "EmployeeIdBox").Text
        BadgeId            = (P3 "BadgeIdBox").Text
        OfficePhone        = (P3 "OfficePhoneBox").Text
        MobilePhone        = (P3 "MobilePhoneBox").Text
        NoticeRecipient    = (P3 "NotificationRecipientBox").Text
		RemoteRouting	   = "{0}@atlastechcloud.mail.onmicrosoft.com" -f $SamAccountName
        IncludeMI          = [bool](P3 "IncludeMiddleInitialCheckBox").IsChecked
        CACRequired        = [bool](P3 "CACCheckBox").IsChecked
        CreateMailbox      = [bool](P3 "CreateMailboxCheckBox").IsChecked
        SendNotice         = [bool](P3 "SendNewHireNoticeCheckBox").IsChecked
    }

    $RequiredFields = @(
        @{ Label = "First Name"; Value = $Values.FirstName }
        @{ Label = "Last Name"; Value = $Values.LastName }
        @{ Label = "Job Title"; Value = $Values.JobTitle }
        @{ Label = "Manager"; Value = $Values.Manager }
        @{ Label = "Work Location"; Value = $Values.Location }
        @{ Label = "Department"; Value = $Values.Department }
        @{ Label = "Employee ID #"; Value = $Values.EmployeeId }
        @{ Label = "Encoded Badge Number #"; Value = $Values.BadgeId }
    )

    $Missing = @($RequiredFields | Where-Object { IsBlank $_.Value } | ForEach-Object { $_.Label })
    if ($Missing.Count -gt 0) {
        $msg = "The following required fields are missing:`n" + ($Missing -join "`n")
        (P3 "ValidationSummaryText").Text = $msg
        foreach ($name in @("IntakeDetails", "IntakeHeader")) {
            (P3 $name).Text = ""
            (P3 $name).Margin = "0,0,0,0"
        }
        foreach ($field in $Missing) { Write-DebugLog "Required field missing: $field" "WARN" }
        Write-DebugLog "Validation blocked Page3 submit due to missing fields." "WARN"
        return $false
    }

    $OfficeN  = Get-SelectedNumber $Values.Location
    $DeptN    = Get-SelectedNumber $Values.Department
    $HomeOrgV = Get-SelectedNumber $Values.HomeOrg
    $Mappings = Get-NewUserMappings -OfficeN $OfficeN -DeptN $DeptN -HomeOrgV $HomeOrgV

    $groupList = @()
    if ($DeptN -ne 10) {
        foreach ($group in @($Mappings.CGUsersSC, $Mappings.CGUsersSD, $Mappings.CGUsersVA, $Mappings.Atlasloc, $Mappings.HomeOrgGnoPeriod, $Mappings.HomeOrgG)) {
            if ($group -and $group -ne "NA") { $groupList += $group }
        }
        if ($Values.CACRequired) { $groupList += $Mappings.CAC }
        $groupList += "TEEntry"
    }

    (P4 "ReviewGroupList").Text = if ($groupList.Count) { $groupList -join "`n" } else { "No security groups will be assigned." }

    $DisplayName = "$($Values.FirstName) $($Values.LastName)".Trim()
    $Username = if ($Values.IncludeMI -and $Values.MiddleInitial) {
        ($Values.FirstName.Substring(0,1) + $Values.MiddleInitial + $Values.LastName).ToLower()
    }
    else {
        ($Values.FirstName.Substring(0,1) + $Values.LastName).ToLower()
    }

    Set-ReviewText @{
        ReviewDisplayName            = $DisplayName
        ReviewUsername               = $Username
        ReviewStartDate              = (P3 "StartDatePicker").SelectedDate
        ReviewHomeOrg                = $Values.HomeOrg
        ReviewEmployeeId             = $Values.EmployeeId
        ReviewBadgeId                = $Values.BadgeId
        ReviewJobTitle               = $Values.JobTitle
        ReviewManager                = $Values.Manager
        ReviewLocation               = $Values.Location
        ReviewDepartment             = $Values.Department
        ReviewOfficePhone            = $Values.OfficePhone
        ReviewMobilePhone            = $Values.MobilePhone
        ReviewMailbox                = (YesNo $Values.CreateMailbox)
        ReviewCAC                    = (YesNo $Values.CACRequired)
        HomeOfficeReview             = $Values.Location
        StreetAddressReview          = $Mappings.StreetAddress
        CityReview                   = $Mappings.City
        StateReview                  = $Mappings.StateField
        PostalCodeReview             = $Mappings.PostalCode
        ReviewRemoteRouting          = $Values.RemoteRouting
        ReviewNotification           = (YesNo $Values.SendNotice)
        ReviewNotificationRecipient  = $Values.NoticeRecipient
    }

    $EquipmentReviewMap = @{
        ReviewNothingRequested       = "NothingRequestedCheckBox"
        ReviewTemporaryOfficeSpace   = "TemporaryOfficeSpaceCheckBox"
        ReviewPermanentOfficeSpace   = "PermanentOfficeSpaceCheckBox"
        ReviewDesktop                = "DesktopCheckBox"
        ReviewLaptop                 = "LaptopCheckBox"
        ReviewDockingStation         = "DockingStationCheckBox"
        ReviewMouseKeyboard          = "MouseKeyboardCheckBox"
        ReviewMonitor                = "MonitorCheckBox"
        ReviewDualMonitor            = "DualMonitorCheckBox"
        ReviewDeskPhone              = "DeskPhoneCheckBox"
        ReviewCellPhone              = "CellPhoneCheckBox"
        ReviewSpeakers               = "SpeakersCheckBox"
    }

    foreach ($reviewName in $EquipmentReviewMap.Keys) {
        (P4 $reviewName).Text = YesNo ([bool](P3 $EquipmentReviewMap[$reviewName]).IsChecked)
    }

    return $true
}

# ============================================================
# Navigation
# ============================================================
$NextButton.Add_Click({
    Write-DebugLog "Next clicked on step $Global:WizardStep." "INFO"
    switch ($Global:WizardStep) {
        1 {
            $Global:WizardStep = 2
            Update-WizardUI
            Start-Checks -Page $Page2
        }
        2 {
            $Global:WizardStep = 3
            Update-WizardUI
        }
        3 {
		if ($NoNet.IsPresent) {
			Write-DebugLog "NoNet mode enabled; bypassing Page 3 validation/review population." "WARN"
			$Global:WizardStep = 4
			Update-WizardUI
			return
		}

		if (-not (Update-ReviewPage)) {
			Write-DebugLog "Navigation halted due to validation failure on step 3." "WARN"
			return
		}

		$Global:WizardStep = 4
		Update-WizardUI
	}
        4 {
			Invoke-WizardCleanup
			$script:StartupAborted = $true
            $MainWindow.Close()
        }
        default {
			Invoke-WizardCleanup
			$script:StartupAborted = $true
            $MainWindow.Close()
        }
    }
})

$BackButton.Add_Click({
    Write-DebugLog "Back clicked on step $Global:WizardStep." "INFO"
    if ($Global:WizardStep -gt 1) {
		$NextButton.IsEnabled = $true
		$NextButton.Opacity = 1
        $Global:WizardStep--
        Update-WizardUI
    }
})

# ============================================================
# Startup
# ============================================================
try {
    $script:StartupAborted = $false
    Update-WizardUI

    if ($MainWindow -and -not $script:StartupAborted) {
        Write-DebugLog "Opening wizard window." "INFO"

        $MainWindow.WindowStartupLocation = "CenterScreen"
        $MainWindow.WindowState = "Normal"
        $MainWindow.ShowInTaskbar = $true
        $MainWindow.Topmost = $true

        $MainWindow.Add_SourceInitialized({
            try {
                Write-DebugLog "Window source initialized; forcing foreground activation." "INFO"
                $MainWindow.Topmost = $true
                $MainWindow.Activate() | Out-Null
                $MainWindow.Focus() | Out-Null

                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromMilliseconds(750)
                $timer.Add_Tick({
                    try {
                        $timer.Stop()
                        $MainWindow.Topmost = $false
                        $MainWindow.Activate() | Out-Null
                    } catch {}
                })
                $timer.Start()
            }
            catch {
                Write-DebugLog "Window activation helper failed: $($_.Exception.Message)" "WARN"
            }
        })

        $dialogResult = $MainWindow.ShowDialog()
        Write-DebugLog "ShowDialog returned: $dialogResult" "INFO"
    }
    else {
        Write-Host "Wizard startup was aborted before the window could be shown." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Wizard failed before or during ShowDialog: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.InnerException) {
        Write-Host "Inner exception: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
    throw
}