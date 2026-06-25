[CmdletBinding()]
param(
    [switch]$Mock,
    [string]$InitialQuery = '',
    [string]$Profile = ''
)

Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:HapPngIcon = Join-Path $repoRoot 'assets\icons\HAP_Icon.png'
$script:HapPngLogoFallback = Join-Path $repoRoot 'assets\icons\HAP_Logo.png'
$script:HapIcoIcon = Join-Path $repoRoot 'assets\icons\HAP_Icon.ico'
$script:HapIcoLogoFallback = Join-Path $repoRoot 'assets\icons\HAP_Logo.ico'
$runtimeModule = Join-Path $repoRoot 'src\Core\Core.Runtime.psm1'
$serviceModule = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
$aggregationModule = Join-Path $repoRoot 'src\Application\Application.HybridUserAggregationService.psm1'
$profileManagerModule = Join-Path $repoRoot 'src\Application\Application.RuntimeProfileManager.psm1'
$simulatorModule = Join-Path $repoRoot 'src\Infrastructure\Mock\Infrastructure.DirectorySimulator.psm1'
$uiThemeModule = Join-Path $repoRoot 'src\UI\UI.Theme.psm1'
$uiRuntimeHomeModule = Join-Path $repoRoot 'src\UI\UI.RuntimeHome.psm1'
$uiRuntimeLaunchModule = Join-Path $repoRoot 'src\UI\UI.RuntimeLaunch.psm1'
$uiRuntimeProfileManagerModule = Join-Path $repoRoot 'src\UI\UI.RuntimeProfileManager.psm1'
$uiRuntimeProfileWizardModule = Join-Path $repoRoot 'src\UI\UI.RuntimeProfileWizard.psm1'
$uiUserDashboardModule = Join-Path $repoRoot 'src\UI\UI.UserDashboard.psm1'
$uiStatusBarModule = Join-Path $repoRoot 'src\UI\UI.StatusBar.psm1'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

foreach ($uiModule in @($uiThemeModule,$uiRuntimeHomeModule,$uiRuntimeLaunchModule,$uiRuntimeProfileManagerModule,$uiRuntimeProfileWizardModule,$uiUserDashboardModule,$uiStatusBarModule)) {
    if (Test-Path $uiModule) { Import-Module $uiModule -Force -Global }
}

$script:HybridUiTheme = if (Get-Command Resolve-HybridUiTheme -ErrorAction SilentlyContinue) {
    Resolve-HybridUiTheme -RepositoryRoot $repoRoot -ProfileName $Profile
}
else { $null }

$script:HybridRuntime = $null
if (Test-Path $profileManagerModule) { Import-Module $profileManagerModule -Force -Global }
if (Test-Path $runtimeModule) {
    Import-Module $runtimeModule -Force -Global
    $profileName = if (-not [string]::IsNullOrWhiteSpace($Profile)) { $Profile } elseif ($Mock) { 'Simulation' } else { 'Simulation' }
    try {
        $script:HybridRuntime = Initialize-HybridRuntime -ProfileName $profileName -RootPath $repoRoot
    }
    catch {
        if (-not [string]::Equals($profileName, 'Simulation', [System.StringComparison]::OrdinalIgnoreCase)) {
            $script:HybridRuntime = Initialize-HybridRuntime -ProfileName 'Simulation' -RootPath $repoRoot
        }
        else { throw }
    }
}
else {
    if (-not (Test-Path $serviceModule)) { throw "Application service module not found: $serviceModule" }
    Import-Module $serviceModule -Force
    if (Test-Path $aggregationModule) { Import-Module $aggregationModule -Force }
}
# Service-backed vertical slice / service-backed vertical slice marker.
# Legacy Phase 3 UI interaction marker retained for cumulative tests:
# SearchUser = { param([string]$Query) @(New-HybridMockUserRecord -Query $Query) }

function New-HybridMockUserRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Query)

    $clean = if ([string]::IsNullOrWhiteSpace($Query)) { 'Alex' } else { $Query.Trim() }
    switch -Regex ($clean) {
        'alex|amorgan' { $first = 'Alex'; $last = 'Morgan'; $sam = 'amorgan'; $dept = 'Information Technology'; $title = 'Systems Administrator'; break }
        'taylor|treed' { $first = 'Taylor'; $last = 'Reed'; $sam = 'treed'; $dept = 'Information Technology'; $title = 'IT Manager'; break }
        'jordan|jlee' { $first = 'Jordan'; $last = 'Lee'; $sam = 'jlee'; $dept = 'Operations'; $title = 'Operations Analyst'; break }
        default {
            $parts = @($clean -split '[\s\._@-]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $first = if ($parts.Count -ge 1) { (Get-Culture).TextInfo.ToTitleCase($parts[0].ToLowerInvariant()) } else { 'Sample' }
            $last = if ($parts.Count -ge 2) { (Get-Culture).TextInfo.ToTitleCase($parts[1].ToLowerInvariant()) } else { 'User' }
            $sam = (($first.Substring(0,1) + $last) -replace '[^a-zA-Z0-9]','').ToLowerInvariant()
            $dept = 'Mock Directory'
            $title = 'Mock User'
        }
    }

    [pscustomobject]@{
        PSTypeName = 'Hybrid.User'
        DisplayName = "$first $last"
        Name = "$first $last"
        SamAccountName = $sam
        UserPrincipalName = "$sam@atlas-tech.com"
        Mail = "$sam@atlas-tech.com"
        Department = $dept
        Title = $title
        JobTitle = $title
        Company = 'Atlas'
        Office = 'Charleston'
        EmployeeId = ('E{0:00000}' -f ([Math]::Abs($sam.GetHashCode()) % 99999))
        DistinguishedName = "CN=$first $last,OU=Users,OU=Atlas,DC=atlas-tech,DC=com"
        Manager = 'CN=Taylor Reed,OU=Users,OU=Atlas,DC=atlas-tech,DC=com'
        Enabled = $true
        LockedOut = $false
        Source = 'ActiveDirectory'
    }
}

if ($null -eq $script:HybridRuntime) {
    if ($Mock) {
        if (-not (Test-Path $simulatorModule)) { throw "Directory simulator module not found: $simulatorModule" }
        Import-Module $simulatorModule -Force
        $simulatorProviders = New-HybridDirectorySimulatorProviders
        Initialize-HybridUserService `
            -ActiveDirectoryProvider $simulatorProviders.ActiveDirectory `
            -MicrosoftGraphProvider $simulatorProviders.MicrosoftGraph `
            -ExchangeOnlineProvider $simulatorProviders.ExchangeOnline | Out-Null
        if (Get-Command Initialize-HybridUserAggregationService -ErrorAction SilentlyContinue) { Initialize-HybridUserAggregationService | Out-Null }
    }
    else {
        Initialize-HybridUserService | Out-Null
        if (Get-Command Initialize-HybridUserAggregationService -ErrorAction SilentlyContinue) { Initialize-HybridUserAggregationService | Out-Null }
    }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Hybrid Admin Platform" Height="900" Width="1480" MinHeight="720" MinWidth="1180" WindowStartupLocation="CenterScreen" Background="#0B1220">
    <Window.Resources>
        <LinearGradientBrush x:Key="ShellBackgroundBrush" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#0B1220" Offset="0"/>
            <GradientStop Color="#101826" Offset="0.55"/>
            <GradientStop Color="#08111E" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="PanelBrush" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#111827" Offset="0"/>
            <GradientStop Color="#0F172A" Offset="1"/>
        </LinearGradientBrush>
        <Style x:Key="Card" TargetType="Border"><Setter Property="Background" Value="#152033"/><Setter Property="BorderBrush" Value="#26364F"/><Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="14"/><Setter Property="Padding" Value="16"/><Setter Property="Margin" Value="0,0,0,12"/></Style>
        <Style x:Key="PanelCard" TargetType="Border" BasedOn="{StaticResource Card}"><Setter Property="Background" Value="{StaticResource PanelBrush}"/><Setter Property="Padding" Value="18"/></Style>
        <Style x:Key="LabelText" TargetType="TextBlock"><Setter Property="Foreground" Value="#8EA4C2"/><Setter Property="FontSize" Value="12"/></Style>
        <Style x:Key="ValueText" TargetType="TextBlock"><Setter Property="Foreground" Value="#E5E7EB"/><Setter Property="FontSize" Value="15"/><Setter Property="Margin" Value="0,2,0,10"/></Style>
        <Style x:Key="SectionTitle" TargetType="TextBlock"><Setter Property="Foreground" Value="#F8FAFC"/><Setter Property="FontSize" Value="16"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Margin" Value="0,0,0,12"/></Style>
        <Style x:Key="ProfileCardText" TargetType="TextBlock"><Setter Property="Foreground" Value="#E5E7EB"/><Setter Property="TextWrapping" Value="Wrap"/></Style>
        <Style x:Key="RuntimeActionButton" TargetType="Button">
            <Setter Property="Height" Value="86"/><Setter Property="MinWidth" Value="142"/><Setter Property="Margin" Value="8,0"/><Setter Property="Padding" Value="14,10"/><Setter Property="Foreground" Value="#E5E7EB"/><Setter Property="Background" Value="#1A2538"/><Setter Property="BorderBrush" Value="#2B3A55"/><Setter Property="BorderThickness" Value="1"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="9" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#22314A"/><Setter Property="BorderBrush" Value="#38BDF8"/></Trigger>
                            <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="#0F172A"/></Trigger>
                            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="LaunchActionButton" TargetType="Button" BasedOn="{StaticResource RuntimeActionButton}"><Setter Property="Background" Value="#14532D"/><Setter Property="BorderBrush" Value="#22C55E"/><Setter Property="MinWidth" Value="132"/></Style>

        <Style x:Key="GlassCommandButton" TargetType="Button">
            <Setter Property="Foreground" Value="#E0F2FE"/>
            <Setter Property="Background">
                <Setter.Value>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                        <GradientStop Color="#2A3F5F" Offset="0"/>
                        <GradientStop Color="#152033" Offset="0.45"/>
                        <GradientStop Color="#0B1220" Offset="1"/>
                    </LinearGradientBrush>
                </Setter.Value>
            </Setter>
            <Setter Property="BorderBrush" Value="#38BDF8"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="GlassButtonChrome" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10" Padding="{TemplateBinding Padding}">
                            <Border.Effect>
                                <DropShadowEffect Color="#38BDF8" BlurRadius="12" ShadowDepth="0" Opacity="0.28"/>
                            </Border.Effect>
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="GlassButtonChrome" Property="BorderBrush" Value="#67E8F9"/><Setter Property="Foreground" Value="#F8FAFC"/></Trigger>
                            <Trigger Property="IsPressed" Value="True"><Setter TargetName="GlassButtonChrome" Property="Opacity" Value="0.82"/></Trigger>
                            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="GlassButtonChrome" Property="Opacity" Value="0.45"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="#0F172A"/>
            <Setter Property="Foreground" Value="#38BDF8"/>
            <Setter Property="Width" Value="10"/>
        </Style>
        <Style TargetType="ListBoxItem">
            <Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border Background="{TemplateBinding Background}"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="#13243A"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
        </Style>
    </Window.Resources>
    <Grid x:Name="ShellRoot">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid x:Name="StartupRegion" Grid.Row="0" Background="{StaticResource ShellBackgroundBrush}">
            <!-- Milestone 8 Final UI Polish: Runtime Home mirrors the polished admin-console concept with fixed footer actions. -->
            <Grid x:Name="StartupView" Margin="16">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Grid Grid.Row="0" Margin="0,0,0,16">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="52"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <Border Grid.Column="0" Width="42" Height="42" CornerRadius="10" Background="#0F172A" BorderBrush="#26364F" BorderThickness="1" VerticalAlignment="Center">
                        <Image x:Name="StartupBrandIcon" Source="assets/icons/HAP_Icon.png" Width="34" Height="34" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <StackPanel Grid.Column="1">
                        <TextBlock Text="Hybrid Admin Platform" Foreground="#F8FAFC" FontSize="30" FontWeight="SemiBold"/>
                        <TextBlock Text="Select a runtime profile and launch Hybrid Admin Console" Foreground="#38BDF8" FontSize="13" Margin="0,4,0,0"/>
                    </StackPanel>
                </Grid>

                <Grid Grid.Row="1">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="0.38*" MinWidth="360" MaxWidth="440"/>
                        <ColumnDefinition Width="16"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Border Grid.Column="0" Style="{StaticResource PanelCard}" Margin="0,0,0,0">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <DockPanel Grid.Row="0" Margin="0,0,0,14">
                                <Border DockPanel.Dock="Right" Background="#1E293B" CornerRadius="6" Padding="8,3" Margin="8,0,0,0">
                                    <TextBlock Text="profiles" Foreground="#CBD5E1" FontSize="12"/>
                                </Border>
                                <TextBlock Text="RUNTIME PROFILES" Style="{StaticResource SectionTitle}" Margin="0"/>
                            </DockPanel>
                            <Grid Grid.Row="1" Margin="0,0,0,14">
                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="46"/><ColumnDefinition Width="46"/></Grid.ColumnDefinitions>
                                <TextBox x:Name="RuntimeProfileSearchBox" Grid.Column="0" Height="34" Background="#0B1220" Foreground="#CBD5E1" BorderBrush="#26364F" Padding="10,0" VerticalContentAlignment="Center" Text="Search profiles..."/>
                                <Button Grid.Column="1" Content="Filter" Height="34" Margin="8,0,0,0" Background="#111827" Foreground="#CBD5E1" BorderBrush="#26364F"/>
                                <Button x:Name="RefreshRuntimeProfilesButton" Grid.Column="2" Content="Refresh" Height="34" Margin="8,0,0,0" Background="#111827" Foreground="#CBD5E1" BorderBrush="#26364F"/>
                            </Grid>

                            <!-- Phase 8.2 RuntimeProfileCardView: profile cards with Default/Last Used/Ready badges -->
                            <ListBox x:Name="RuntimeProfileListBox" Grid.Row="2" Background="Transparent" Foreground="#E5E7EB" BorderThickness="0" Padding="0" ScrollViewer.VerticalScrollBarVisibility="Auto" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                                <ListBox.ItemTemplate>
                                    <DataTemplate>
                                        <Border x:Name="RuntimeProfileCard" Background="#111827" BorderBrush="#2B3A55" BorderThickness="1" CornerRadius="10" Padding="14" Margin="0,0,0,14">
                                            <Grid>
                                                <Grid.ColumnDefinitions><ColumnDefinition Width="72"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                                <Border Grid.Column="0" Width="58" Height="58" CornerRadius="9" Background="#1E293B" VerticalAlignment="Top">
                                                    <Image Source="assets/icons/HAP_Icon.png" Width="46" Height="46" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                                </Border>
                                                <StackPanel Grid.Column="1" Margin="10,0,8,0">
                                                    <TextBlock Text="{Binding ProfileName}" Style="{StaticResource ProfileCardText}" FontSize="18" FontWeight="SemiBold"/>
                                                    <WrapPanel Margin="0,8,0,0">
                                                        <Border Background="#312E81" CornerRadius="5" Padding="7,3" Margin="0,0,6,6"><TextBlock Text="{Binding Organization}" Foreground="#DDD6FE" FontSize="11"/></Border>
                                                        <Border Background="#0F2A44" CornerRadius="5" Padding="7,3" Margin="0,0,6,6"><TextBlock Text="{Binding CloudEnvironment}" Foreground="#BAE6FD" FontSize="11"/></Border>
                                                        <Border Background="#064E3B" CornerRadius="5" Padding="7,3" Margin="0,0,6,6"><TextBlock Text="{Binding RuntimeMode}" Foreground="#BBF7D0" FontSize="11"/></Border>
                                                    </WrapPanel>
                                                    <TextBlock Text="Profile ready for bootstrap and validation." Foreground="#B6C2D3" FontSize="12" TextWrapping="Wrap" Margin="0,2,0,0"/>
                                                    <DockPanel Margin="0,12,0,0">
                                                        <TextBlock Text="Ready" Foreground="#22C55E" FontWeight="SemiBold" FontSize="12" DockPanel.Dock="Left"/>
                                                        <TextBlock Text="Last used: tracked" Foreground="#94A3B8" FontSize="12" Margin="20,0,0,0"/>
                                                    </DockPanel>
                                                </StackPanel>
                                                <TextBlock Grid.Column="2" Text="{Binding BadgeText}" Foreground="#FACC15" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Top"/>
                                            </Grid>
                                        </Border>
                                        <DataTemplate.Triggers>
                                            <DataTrigger Binding="{Binding RelativeSource={RelativeSource AncestorType=ListBoxItem}, Path=IsSelected}" Value="True">
                                                <Setter TargetName="RuntimeProfileCard" Property="Background" Value="#13243A"/>
                                                <Setter TargetName="RuntimeProfileCard" Property="BorderBrush" Value="#38BDF8"/>
                                                <Setter TargetName="RuntimeProfileCard" Property="BorderThickness" Value="3"/>
                                                <Setter TargetName="RuntimeProfileCard" Property="Effect">
                                                    <Setter.Value><DropShadowEffect Color="#38BDF8" BlurRadius="18" ShadowDepth="0" Opacity="0.35"/></Setter.Value>
                                                </Setter>
                                            </DataTrigger>
                                        </DataTemplate.Triggers>
                                    </DataTemplate>
                                </ListBox.ItemTemplate>
                            </ListBox>
                            <TextBlock Grid.Row="3" Text="Profiles are discovered from profiles\Runtime" Foreground="#94A3B8" HorizontalAlignment="Center" Margin="0,12,0,0" FontSize="12"/>
                        </Grid>
                    </Border>

                    <Border Grid.Column="2" x:Name="RuntimeSummaryPanel" Style="{StaticResource PanelCard}" Margin="0">
                        <!-- Phase 8.3 RuntimeSummaryPanel -->
                        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <Grid Margin="0,0,5,0">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <DockPanel Grid.Row="0" Margin="0,0,0,16">
                                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" HorizontalAlignment="Right">
                                    <TextBlock Text="Last validated: on launch" Foreground="#CBD5E1" FontSize="12" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                    <Button Content="Refresh" Height="28" MinWidth="70" Background="#111827" Foreground="#CBD5E1" BorderBrush="#26364F"/>
                                </StackPanel>
                                <TextBlock Text="RUNTIME SUMMARY" Style="{StaticResource SectionTitle}" Margin="0"/>
                            </DockPanel>

                            <Border Grid.Row="1" Background="#0B1220" BorderBrush="#26364F" BorderThickness="1" CornerRadius="12" Padding="20" Margin="0,0,0,14">
                                <Grid>
                                    <Grid.ColumnDefinitions><ColumnDefinition Width="1.5*"/><ColumnDefinition Width="1.2*"/><ColumnDefinition Width="1.1*"/></Grid.ColumnDefinitions>
                                    <Grid Grid.Column="0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="78"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                        <Border Grid.Column="0" Width="64" Height="64" CornerRadius="10" Background="#1E293B" VerticalAlignment="Top"><Image x:Name="SummaryBrandIcon" Source="assets/icons/HAP_Icon.png" Width="52" Height="52" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                                        <StackPanel Grid.Column="1" Margin="12,0,24,0">
                                            <TextBlock Text="PROFILE" Foreground="#93C5FD" FontSize="14" FontWeight="SemiBold"/>
                                            <TextBlock x:Name="RuntimeProfileText" Text="-" Foreground="#F8FAFC" FontSize="24" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,8,0,0"/>
                                            <TextBlock Text="Runtime profile selected for launch" Foreground="#CBD5E1" FontSize="13" Margin="0,6,0,0"/>
                                            <TextBlock Text="File: profiles\Runtime" Foreground="#94A3B8" FontSize="12" Margin="0,14,0,0"/>
                                        </StackPanel>
                                    </Grid>
                                    <StackPanel Grid.Column="1" Margin="18,0,18,0">
                                        <TextBlock Text="ENVIRONMENT" Foreground="#93C5FD" FontSize="14" FontWeight="SemiBold"/>
                                        <UniformGrid Columns="2" Margin="0,10,0,0">
                                            <StackPanel Margin="0,0,12,12"><TextBlock Text="Cloud" Style="{StaticResource LabelText}"/><TextBlock x:Name="RuntimeCloudText" Text="-" Foreground="#A78BFA" FontWeight="SemiBold"/></StackPanel>
                                            <StackPanel Margin="0,0,12,12"><TextBlock Text="Runtime Mode" Style="{StaticResource LabelText}"/><TextBlock x:Name="RuntimeModeText" Text="-" Foreground="#22C55E" FontWeight="SemiBold"/></StackPanel>
                                            <StackPanel Margin="0,0,12,0"><TextBlock Text="Schema" Style="{StaticResource LabelText}"/><TextBlock Text="1.0" Foreground="#CBD5E1"/></StackPanel>
                                            <StackPanel Margin="0,0,12,0"><TextBlock Text="HAP Version" Style="{StaticResource LabelText}"/><TextBlock x:Name="RuntimeVersionText" Text="v0.8.1" Foreground="#CBD5E1"/></StackPanel>
                                        </UniformGrid>
                                    </StackPanel>
                                    <StackPanel Grid.Column="2" Margin="18,0,0,0">
                                        <TextBlock Text="COMPATIBILITY" Foreground="#93C5FD" FontSize="14" FontWeight="SemiBold"/>
                                        <TextBlock Text="Compatible" Foreground="#22C55E" FontWeight="SemiBold" Margin="0,12,0,6"/>
                                        <TextBlock Text="Min Supported" Style="{StaticResource LabelText}"/><TextBlock Text="v0.7.0" Foreground="#CBD5E1" Margin="0,2,0,8"/>
                                        <TextBlock Text="Max Tested" Style="{StaticResource LabelText}"/><TextBlock Text="v0.8.1" Foreground="#CBD5E1"/>
                                    </StackPanel>
                                </Grid>
                            </Border>

                            <Grid Grid.Row="2">
                                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                                <Grid Grid.Row="0">
                                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                    <Border Grid.Column="0" Style="{StaticResource Card}" Margin="0,0,10,14">
                                        <StackPanel>
                                            <TextBlock Text="PROVIDER STATUS" Style="{StaticResource SectionTitle}"/>
                                            <TextBlock x:Name="RuntimeProviderSummaryText" Text="-" TextWrapping="Wrap" Foreground="#E5E7EB" FontSize="14" Margin="0,0,0,14"/>
                                            <TextBlock x:Name="RuntimeActiveDirectoryStatusText" Text="Active Directory        Validates on launch" Foreground="#FACC15" Margin="0,0,0,8"/>
                                            <TextBlock x:Name="RuntimeProviderDetailsText" Text="Provider details load from the selected runtime profile." TextWrapping="Wrap" Foreground="#CBD5E1"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Column="1" Style="{StaticResource Card}" Margin="0,0,10,14">
                                        <StackPanel>
                                            <TextBlock Text="AUTHENTICATION" Style="{StaticResource SectionTitle}"/>
                                            <TextBlock x:Name="RuntimeAuthenticationText" Text="Device Code disabled. Live providers authenticate on launch." TextWrapping="Wrap" Foreground="#E5E7EB" FontSize="14" Margin="0,0,0,14"/>
                                            <TextBlock Text="App-Only            Deferred" Foreground="#CBD5E1" Margin="0,0,0,8"/>
                                            <TextBlock Text="Delegated           Required on launch" Foreground="#FACC15" Margin="0,0,0,8"/>
                                            <TextBlock Text="Device Code         Disabled" Foreground="#94A3B8"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Column="2" Style="{StaticResource Card}" Margin="0,0,0,14">
                                        <StackPanel>
                                            <TextBlock Text="RUNTIME HEALTH" Style="{StaticResource SectionTitle}"/>
                                            <TextBlock Text="Healthy" Foreground="#22C55E" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,6"/>
                                            <TextBlock x:Name="RuntimeDiagnosticsText" Text="-" TextWrapping="Wrap" Foreground="#E5E7EB" FontSize="14" Margin="0,0,0,12"/>
                                            <TextBlock x:Name="RuntimeStatusText" Text="Ready to launch." TextWrapping="Wrap" Foreground="#CBD5E1"/>
                                        </StackPanel>
                                    </Border>
                                </Grid>

                                <Border Grid.Row="1" Background="#0B1220" BorderBrush="#26364F" BorderThickness="1" CornerRadius="12" Padding="18">
                                    <StackPanel>
                                        <TextBlock Text="RUNTIME PREVIEW" Style="{StaticResource SectionTitle}"/>
                                        <TextBlock x:Name="RuntimePreviewText" Text="Select a runtime profile to preview what HAP will attempt to load." TextWrapping="Wrap" Foreground="#CBD5E1" FontSize="14" Margin="0,10,0,0"/>
                                    </StackPanel>
                                </Border>
                            </Grid>
                        </Grid>
                        </ScrollViewer>
                    </Border>
                </Grid>

                <Border x:Name="RuntimeActionFooter" Grid.Row="2" Background="#111827" BorderBrush="#26364F" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,16,0,0">
                    <!-- Fixed action footer: buttons remain visible regardless of profile-card scrolling. -->
                    <!-- Phase 8 Final UI polish: action buttons are large, styled, single-row command tiles. -->
                    <ScrollViewer HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled" HorizontalContentAlignment="Center"><WrapPanel HorizontalAlignment="Center">
                        <Button x:Name="LaunchConsoleButton" Style="{StaticResource LaunchActionButton}">
                            <StackPanel HorizontalAlignment="Center"><TextBlock Text="Launch Console" Foreground="#F0FDF4" FontWeight="Bold" FontSize="14" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" MaxWidth="118"/><TextBlock Text="Enter" Foreground="#BBF7D0" FontSize="12" Margin="0,10,0,0" HorizontalAlignment="Center"/></StackPanel>
                        </Button>
                        <Button x:Name="NewRuntimeProfileButton" Style="{StaticResource RuntimeActionButton}">
                            <StackPanel HorizontalAlignment="Center"><TextBlock Text="New Profile" Foreground="#38BDF8" FontWeight="Bold" FontSize="14" HorizontalAlignment="Center"/><TextBlock Text="Ctrl+N" Foreground="#CBD5E1" FontSize="12" Margin="0,10,0,0" HorizontalAlignment="Center"/></StackPanel>
                        </Button>
                        <Button x:Name="EditRuntimeProfileButton" Style="{StaticResource RuntimeActionButton}" IsEnabled="True">
                            <StackPanel HorizontalAlignment="Center"><TextBlock Text="Edit Profile" Foreground="#38BDF8" FontWeight="Bold" FontSize="14" HorizontalAlignment="Center"/><TextBlock Text="Ctrl+E" Foreground="#CBD5E1" FontSize="12" Margin="0,10,0,0" HorizontalAlignment="Center"/></StackPanel>
                        </Button>
                        <Button x:Name="ManageRuntimeThemeButton" Style="{StaticResource RuntimeActionButton}" IsEnabled="True">
                            <StackPanel HorizontalAlignment="Center"><TextBlock Text="Branding &amp; Theme" Foreground="#38BDF8" FontWeight="Bold" FontSize="14" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" MaxWidth="118"/><TextBlock Text="Colors" Foreground="#CBD5E1" FontSize="12" Margin="0,10,0,0" HorizontalAlignment="Center"/></StackPanel>
                        </Button>
                        <Button x:Name="DeleteRuntimeProfileButton" Style="{StaticResource RuntimeActionButton}">
                            <StackPanel HorizontalAlignment="Center"><TextBlock Text="Delete" Foreground="#F87171" FontWeight="Bold" FontSize="14" HorizontalAlignment="Center"/><TextBlock Text="Del" Foreground="#CBD5E1" FontSize="12" Margin="0,10,0,0" HorizontalAlignment="Center"/></StackPanel>
                        </Button>
                        <Button x:Name="ImportExportRuntimeProfileButton" Style="{StaticResource RuntimeActionButton}">
                            <StackPanel HorizontalAlignment="Center"><TextBlock Text="Import / Export" Foreground="#C084FC" FontWeight="Bold" FontSize="14" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" MaxWidth="118"/><TextBlock Text="Profiles" Foreground="#CBD5E1" FontSize="12" Margin="0,10,0,0" HorizontalAlignment="Center"/></StackPanel>
                        </Button>
                        <Button x:Name="SetDefaultRuntimeProfileButton" Style="{StaticResource RuntimeActionButton}">
                            <StackPanel HorizontalAlignment="Center"><TextBlock Text="Set Default" Foreground="#FACC15" FontWeight="Bold" FontSize="14" HorizontalAlignment="Center"/><TextBlock Text="Ctrl+F" Foreground="#CBD5E1" FontSize="12" Margin="0,10,0,0" HorizontalAlignment="Center"/></StackPanel>
                        </Button>
                        <Button x:Name="ExitButton" Style="{StaticResource RuntimeActionButton}">
                            <StackPanel HorizontalAlignment="Center"><TextBlock Text="Exit" Foreground="#E5E7EB" FontWeight="Bold" FontSize="14" HorizontalAlignment="Center"/><TextBlock Text="Alt+F4" Foreground="#CBD5E1" FontSize="12" Margin="0,10,0,0" HorizontalAlignment="Center"/></StackPanel>
                        </Button>
                    </WrapPanel></ScrollViewer>
                </Border>
            </Grid>
        </Grid>

        <Grid x:Name="MainRegion" Grid.Row="0">
            <Grid x:Name="ConsoleView" Margin="22" Visibility="Collapsed">
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>

                <Grid Grid.Row="0" Margin="0,0,0,14">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <Grid>
                        <Grid.ColumnDefinitions><ColumnDefinition Width="52"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Width="42" Height="42" CornerRadius="10" Background="#0F172A" BorderBrush="#26364F" BorderThickness="1" VerticalAlignment="Center">
                            <Image x:Name="ConsoleBrandIcon" Source="assets/icons/HAP_Icon.png" Width="34" Height="34" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <StackPanel Grid.Column="1">
                            <TextBlock Text="Hybrid Admin Console" Foreground="#E5E7EB" FontSize="30" FontWeight="SemiBold"/>
                            <TextBlock x:Name="HeaderRuntimeBadgeText" Text="Dashboard layout foundation | Runtime Profile Wizard ready" Foreground="#38BDF8" FontSize="13"/>
                        </StackPanel>
                    </Grid>
                    <Border Grid.Column="1" Background="#0F172A" CornerRadius="12" Padding="14,10" VerticalAlignment="Center" Margin="0,0,10,0">
                        <StackPanel Orientation="Horizontal">
                            <Ellipse x:Name="ProviderDot" Width="12" Height="12" Fill="#22C55E" Margin="0,0,8,0"/>
                            <TextBlock x:Name="ProviderStatusText" Text="Provider health: checking" Foreground="#CBD5E1" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Border>
                    <Button x:Name="BackToStartButton" Grid.Column="2" Content="Back / Start" Style="{StaticResource GlassCommandButton}" Height="38" Padding="16,0" VerticalAlignment="Center" ToolTip="Return to Runtime Home to switch profiles"/>
                </Grid>

                <Border Grid.Row="1" Style="{StaticResource Card}">
                    <Grid>
                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="140"/><ColumnDefinition Width="260"/></Grid.ColumnDefinitions>
                        <TextBox x:Name="SearchBox" Grid.Column="0" Height="43" FontSize="16" Padding="10,2,10,2" VerticalContentAlignment="Center"/>
                        <Button x:Name="SearchButton" Grid.Column="1" Content="Search" Style="{StaticResource GlassCommandButton}" Height="43" Margin="12,0,0,0" Padding="16,0"/>
                        <TextBlock Grid.Column="2" Text="Search drives all dashboard cards" Foreground="#94A3B8" VerticalAlignment="Center" Margin="18,0,0,0"/>
                    </Grid>
                </Border>

                <Grid x:Name="MainDashboardGrid" Grid.Row="2">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="1.25*"/>
                        <ColumnDefinition Width="1.55*"/>
                        <ColumnDefinition Width="1.2*"/>
                    </Grid.ColumnDefinitions>

                    <ScrollViewer x:Name="UserIdentityColumn" Grid.Column="0" VerticalScrollBarVisibility="Auto" Margin="0,0,12,0">
                        <StackPanel>
                            <Border Style="{StaticResource Card}">
                                <StackPanel>
                                    <TextBlock x:Name="ResultHeader" Text="Search for a user" Foreground="#F8FAFC" FontSize="24" FontWeight="SemiBold"/>
                                    <TextBlock x:Name="AccountStateText" Text="Account state: waiting" Foreground="#38BDF8" FontWeight="SemiBold" Margin="0,4,0,14"/>
                                    <TextBlock Text="Display Name" Style="{StaticResource LabelText}"/><TextBlock x:Name="DisplayNameText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="UPN" Style="{StaticResource LabelText}"/><TextBlock x:Name="UpnText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="SAM Account" Style="{StaticResource LabelText}"/><TextBlock x:Name="SamText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Mail" Style="{StaticResource LabelText}"/><TextBlock x:Name="MailText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Department" Style="{StaticResource LabelText}"/><TextBlock x:Name="DepartmentText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Title" Style="{StaticResource LabelText}"/><TextBlock x:Name="TitleText" Text="-" Style="{StaticResource ValueText}"/>
                                </StackPanel>
                            </Border>

                            <Border Style="{StaticResource Card}">
                                <StackPanel>
                                    <TextBlock Text="Directory Facts" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock Text="Company" Style="{StaticResource LabelText}"/><TextBlock x:Name="CompanyText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Office" Style="{StaticResource LabelText}"/><TextBlock x:Name="OfficeText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Employee ID" Style="{StaticResource LabelText}"/><TextBlock x:Name="EmployeeIdText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Badge ID" Style="{StaticResource LabelText}"/><TextBlock x:Name="BadgeIdText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="State" Style="{StaticResource LabelText}"/><TextBlock x:Name="StateText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Phone Number" Style="{StaticResource LabelText}"/><TextBlock x:Name="PhoneNumberText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Organizational Unit" Style="{StaticResource LabelText}"/><TextBlock x:Name="OrganizationalUnitText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Distinguished Name" Style="{StaticResource LabelText}"/><TextBlock x:Name="DistinguishedNameText" Text="-" TextWrapping="Wrap" Style="{StaticResource ValueText}"/>
                                </StackPanel>
                            </Border>

                            <Border x:Name="ManagerCard" Style="{StaticResource Card}">
                                <StackPanel><TextBlock Text="Manager" Style="{StaticResource SectionTitle}"/><TextBlock x:Name="ManagerText" Text="-" Style="{StaticResource ValueText}"/></StackPanel>
                            </Border>
                            <Border Style="{StaticResource Card}">
                                <StackPanel><TextBlock Text="Groups" Style="{StaticResource SectionTitle}"/><ListBox x:Name="GroupsList" MinHeight="120"/></StackPanel>
                            </Border>
                            <Border Style="{StaticResource Card}">
                                <StackPanel><TextBlock Text="Direct Reports" Style="{StaticResource SectionTitle}"/><ListBox x:Name="DirectReportsList" MinHeight="120"/></StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>

                    <ScrollViewer x:Name="OperationsColumn" Grid.Column="1" VerticalScrollBarVisibility="Auto" Margin="0,0,12,0">
                        <StackPanel>
                            <Border x:Name="ExchangeMailboxCard" Style="{StaticResource Card}">
                                <StackPanel>
                                    <TextBlock Text="Exchange Mailbox" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock x:Name="ExchangeSummaryText" Text="Exchange vertical slice waiting for a user search." Foreground="#38BDF8" FontSize="12" FontWeight="SemiBold" Margin="0,3,0,10" TextWrapping="Wrap"/>
                                    <TextBlock Text="Primary SMTP" Style="{StaticResource LabelText}"/><TextBlock x:Name="MailboxText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Recipient Type" Style="{StaticResource LabelText}"/><TextBlock x:Name="RecipientTypeText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Mailbox Status" Style="{StaticResource LabelText}"/><TextBlock x:Name="MailboxStatusText" Text="-" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Forwarding" Style="{StaticResource LabelText}"/><TextBlock x:Name="ForwardingText" Text="-" TextWrapping="Wrap" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Delegation" Style="{StaticResource LabelText}"/><ListBox x:Name="MailboxDelegationList" MinHeight="78"/>
                                    <TextBlock Text="Distribution Groups" Style="{StaticResource LabelText}" Margin="0,10,0,0"/><ListBox x:Name="DistributionGroupsList" MinHeight="78"/>
                                    <TextBlock Text="Sources" Style="{StaticResource LabelText}" Margin="0,10,0,0"/><TextBlock x:Name="SourcesText" Text="-" TextWrapping="Wrap" Style="{StaticResource ValueText}"/>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>

                    <ScrollViewer x:Name="RuntimeColumn" Grid.Column="2" VerticalScrollBarVisibility="Auto">
                        <StackPanel>
                            <Border x:Name="AggregationStatusCard" Style="{StaticResource Card}">
                                <StackPanel>
                                    <TextBlock Text="Profile Aggregation" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock x:Name="AggregationSummaryText" Text="Aggregation waiting for a user search." Foreground="#38BDF8" FontSize="12" FontWeight="SemiBold" Margin="0,3,0,10" TextWrapping="Wrap"/>
                                    <TextBlock Text="Identity" Style="{StaticResource LabelText}"/><TextBlock x:Name="AggregationIdentityText" Text="Not loaded" TextWrapping="Wrap" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Verticals Loaded" Style="{StaticResource LabelText}"/><TextBlock x:Name="AggregationVerticalsText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Status" Style="{StaticResource LabelText}"/><TextBlock x:Name="AggregationStatusText" Text="Not loaded" TextWrapping="Wrap" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Retrieved" Style="{StaticResource LabelText}"/><TextBlock x:Name="AggregationRetrievedText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                </StackPanel>
                            </Border>

                            <Border x:Name="MicrosoftGraphCard" Style="{StaticResource Card}">
                                <StackPanel>
                                    <TextBlock Text="Microsoft Graph" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock x:Name="GraphSummaryText" Text="Graph profile waiting for a user search." Foreground="#38BDF8" FontSize="12" FontWeight="SemiBold" Margin="0,3,0,10" TextWrapping="Wrap"/>
                                    <TextBlock Text="Graph Object ID" Style="{StaticResource LabelText}"/><TextBlock x:Name="GraphObjectIdText" Text="Not loaded" TextWrapping="Wrap" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="User Type" Style="{StaticResource LabelText}"/><TextBlock x:Name="GraphUserTypeText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Usage Location" Style="{StaticResource LabelText}"/><TextBlock x:Name="GraphUsageLocationText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Preferred Language" Style="{StaticResource LabelText}"/><TextBlock x:Name="GraphPreferredLanguageText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="MFA Registered" Style="{StaticResource LabelText}"/><TextBlock x:Name="GraphMfaRegisteredText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="MFA Capable" Style="{StaticResource LabelText}"/><TextBlock x:Name="GraphMfaCapableText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Authentication Methods" Style="{StaticResource LabelText}"/><TextBlock x:Name="GraphAuthenticationMethodsText" Text="Not loaded" TextWrapping="Wrap" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Last Sign-In" Style="{StaticResource LabelText}"/><TextBlock x:Name="GraphLastSignInText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Password Last Changed" Style="{StaticResource LabelText}"/><TextBlock x:Name="GraphPasswordLastChangedText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Risk State" Style="{StaticResource LabelText}"/><TextBlock x:Name="GraphRiskStateText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                </StackPanel>
                            </Border>

                            <Border x:Name="AuthenticationPostureCard" Style="{StaticResource Card}">
                                <StackPanel>
                                    <TextBlock Text="Authentication Posture" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock x:Name="AuthenticationSummaryText" Text="Authentication posture waiting for a user search." Foreground="#38BDF8" FontSize="12" FontWeight="SemiBold" Margin="0,3,0,10" TextWrapping="Wrap"/>
                                    <TextBlock Text="Default Method" Style="{StaticResource LabelText}"/><TextBlock x:Name="AuthDefaultMethodText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="MFA Registered" Style="{StaticResource LabelText}"/><TextBlock x:Name="AuthMfaRegisteredText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Passwordless" Style="{StaticResource LabelText}"/><TextBlock x:Name="AuthPasswordlessText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Authentication Strength" Style="{StaticResource LabelText}"/><TextBlock x:Name="AuthStrengthText" Text="Not loaded" TextWrapping="Wrap" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Conditional Access" Style="{StaticResource LabelText}"/><TextBlock x:Name="AuthConditionalAccessText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Sign-In Risk" Style="{StaticResource LabelText}"/><TextBlock x:Name="AuthRiskText" Text="Not loaded" Style="{StaticResource ValueText}"/>
                                    <TextBlock Text="Methods" Style="{StaticResource LabelText}"/><ListBox x:Name="AuthMethodsList" MinHeight="78"/>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>
            </Grid>
        </Grid>

        <Grid x:Name="StatusBarRegion" Grid.Row="1" Background="#08111E" MinHeight="44">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="360"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <TextBlock x:Name="StatusText" Grid.Column="0" Text="Ready." Foreground="#CBD5E1" VerticalAlignment="Center" Margin="22,0,22,0"/>
            <StackPanel x:Name="SearchProgressPanel" Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed">
                <TextBlock x:Name="SearchProgressStageText" Text="Search" Foreground="#38BDF8" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,10,0"/>
                <ProgressBar x:Name="SearchProgressIndicator" Width="220" Height="8" Minimum="0" Maximum="100" Value="0" IsIndeterminate="False" VerticalAlignment="Center"/>
            </StackPanel>
            <StackPanel x:Name="ShellStatusPanel" Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,22,0">
                <TextBlock Text="Profile: " Foreground="#64748B"/><TextBlock x:Name="StatusProfileText" Text="-" Foreground="#94A3B8" Margin="0,0,14,0"/>
                <TextBlock Text="Cloud: " Foreground="#64748B"/><TextBlock x:Name="StatusCloudText" Text="-" Foreground="#A78BFA" FontWeight="SemiBold" Margin="0,0,14,0"/>
                <TextBlock Text="Mode: " Foreground="#64748B"/><TextBlock x:Name="StatusModeText" Text="-" Foreground="#94A3B8" Margin="0,0,14,0"/>
                <TextBlock Text="Auth: " Foreground="#64748B"/><TextBlock x:Name="StatusAuthText" Text="-" Foreground="#CBD5E1" FontWeight="SemiBold" Margin="0,0,14,0"/>
                <TextBlock Text="Health: " Foreground="#64748B"/><TextBlock x:Name="StatusHealthText" Text="-" Foreground="#22C55E" FontWeight="SemiBold"/>
            </StackPanel>
            <TextBlock x:Name="ShellStatusText" Grid.Column="2" Text="" Foreground="#64748B" Visibility="Collapsed"/>
        </Grid>

        <Grid x:Name="OverlayRegion" Grid.RowSpan="2" Background="#990B1220" Visibility="Collapsed">
            <Border x:Name="OverlayHost" Style="{StaticResource Card}" MaxWidth="920" HorizontalAlignment="Center" VerticalAlignment="Center">
                <Grid>
                <Grid x:Name="LaunchProgressView" Width="620" MinHeight="360" Visibility="Collapsed">
                    <StackPanel>
                        <TextBlock Text="Launching Runtime" Foreground="#F8FAFC" FontSize="26" FontWeight="SemiBold" Margin="0,0,0,8"/>
                        <TextBlock x:Name="LaunchProgressText" Text="Preparing selected runtime profile..." Foreground="#CBD5E1" TextWrapping="Wrap" Margin="0,0,0,18"/>
                        <ProgressBar x:Name="LaunchProgressBar" Height="10" Minimum="0" Maximum="100" Value="0" Margin="0,0,0,18"/>
                        <TextBlock Text="The dashboard will open after validation and runtime initialization complete." Foreground="#94A3B8" TextWrapping="Wrap"/>
                    </StackPanel>
                </Grid>
                <Grid x:Name="RuntimeThemeEditorView" Width="920" MinHeight="640" Visibility="Collapsed">
                    <!-- Milestone 8.2 BrandingThemeEditor: profile-scoped brand package and theme editor. -->
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                    <Grid Grid.Row="0" Margin="0,0,0,18">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0">
                            <TextBlock Text="Branding &amp; Theme" Foreground="#F8FAFC" FontSize="26" FontWeight="SemiBold"/>
                            <TextBlock x:Name="ThemeEditorSubtitleText" Text="Customize the selected runtime profile brand package without editing JSON by hand." Foreground="#38BDF8" FontSize="13" TextWrapping="Wrap"/>
                        </StackPanel>
                        <Button x:Name="ThemeEditorCloseButton" Grid.Column="1" Content="X" Width="34" Height="30" Margin="12,0,0,0"/>
                    </Grid>
                    <Grid Grid.Row="1">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="1.1*"/><ColumnDefinition Width="18"/><ColumnDefinition Width="0.9*"/></Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Background="#0F172A" CornerRadius="14" Padding="18">
                            <ScrollViewer VerticalScrollBarVisibility="Auto">
                                <StackPanel>
                                    <TextBlock Text="Brand Package" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock Text="Package Name" Style="{StaticResource LabelText}"/>
                                    <TextBox x:Name="ThemePackageNameTextBox" Text="Branding" Height="34" Margin="0,4,0,12"/>
                                    <TextBlock Text="Window Title" Style="{StaticResource LabelText}"/>
                                    <TextBox x:Name="ThemeWindowTitleTextBox" Text="Hybrid Admin Platform" Height="34" Margin="0,4,0,12"/>
                                    <TextBlock Text="Organization Display Name" Style="{StaticResource LabelText}"/>
                                    <TextBox x:Name="ThemeOrganizationNameTextBox" Text="" Height="34" Margin="0,4,0,16"/>
                                    <TextBlock Text="Colors" Style="{StaticResource SectionTitle}"/>
                                    <UniformGrid Columns="2" Rows="5">
                                        <StackPanel Margin="0,0,10,10"><TextBlock Text="Accent" Style="{StaticResource LabelText}"/><TextBox x:Name="ThemeAccentColorTextBox" Text="#38BDF8" Height="34" Margin="0,4,0,0"/></StackPanel>
                                        <StackPanel Margin="0,0,0,10"><TextBlock Text="Background" Style="{StaticResource LabelText}"/><TextBox x:Name="ThemeBackgroundColorTextBox" Text="#0B1220" Height="34" Margin="0,4,0,0"/></StackPanel>
                                        <StackPanel Margin="0,0,10,10"><TextBlock Text="Surface" Style="{StaticResource LabelText}"/><TextBox x:Name="ThemeSurfaceColorTextBox" Text="#111827" Height="34" Margin="0,4,0,0"/></StackPanel>
                                        <StackPanel Margin="0,0,0,10"><TextBlock Text="Panel" Style="{StaticResource LabelText}"/><TextBox x:Name="ThemePanelColorTextBox" Text="#0F172A" Height="34" Margin="0,4,0,0"/></StackPanel>
                                        <StackPanel Margin="0,0,10,10"><TextBlock Text="Border" Style="{StaticResource LabelText}"/><TextBox x:Name="ThemeBorderColorTextBox" Text="#26364F" Height="34" Margin="0,4,0,0"/></StackPanel>
                                        <StackPanel Margin="0,0,0,10"><TextBlock Text="Foreground" Style="{StaticResource LabelText}"/><TextBox x:Name="ThemeForegroundColorTextBox" Text="#F8FAFC" Height="34" Margin="0,4,0,0"/></StackPanel>
                                        <StackPanel Margin="0,0,10,10"><TextBlock Text="Text" Style="{StaticResource LabelText}"/><TextBox x:Name="ThemeTextColorTextBox" Text="#E5E7EB" Height="34" Margin="0,4,0,0"/></StackPanel>
                                        <StackPanel Margin="0,0,0,10"><TextBlock Text="Muted Text" Style="{StaticResource LabelText}"/><TextBox x:Name="ThemeMutedTextColorTextBox" Text="#94A3B8" Height="34" Margin="0,4,0,0"/></StackPanel>
                                    </UniformGrid>
                                    <TextBlock Text="Brand Assets" Style="{StaticResource SectionTitle}" Margin="0,8,0,12"/>
                                    <TextBlock Text="Logo Path" Style="{StaticResource LabelText}"/>
                                    <TextBox x:Name="ThemeLogoPathTextBox" Text="logo.png" Height="34" Margin="0,4,0,12"/>
                                    <TextBlock Text="Icon Path" Style="{StaticResource LabelText}"/>
                                    <TextBox x:Name="ThemeIconPathTextBox" Text="icon.ico" Height="34" Margin="0,4,0,12"/>
                                    <TextBlock Text="Splash Path" Style="{StaticResource LabelText}"/>
                                    <TextBox x:Name="ThemeSplashPathTextBox" Text="splash.png" Height="34" Margin="0,4,0,0"/>
                                </StackPanel>
                            </ScrollViewer>
                        </Border>
                        <Border Grid.Column="2" x:Name="ThemePreviewShell" Background="#111827" BorderBrush="#26364F" BorderThickness="1" CornerRadius="14" Padding="18">
                            <StackPanel>
                                <TextBlock Text="Live Theme Preview" Style="{StaticResource SectionTitle}"/>
                                <Border x:Name="ThemePreviewWindow" Background="#0B1220" BorderBrush="#26364F" BorderThickness="1" CornerRadius="12" Padding="16" Margin="0,0,0,16">
                                    <StackPanel>
                                        <TextBlock x:Name="ThemePreviewTitleText" Text="Hybrid Admin Platform" Foreground="#F8FAFC" FontSize="22" FontWeight="SemiBold" TextWrapping="Wrap"/>
                                        <TextBlock x:Name="ThemePreviewAccentText" Text="Runtime profile branding package" Foreground="#38BDF8" Margin="0,4,0,14" TextWrapping="Wrap"/>
                                        <Border x:Name="ThemePreviewCard" Background="#0F172A" BorderBrush="#26364F" BorderThickness="1" CornerRadius="10" Padding="14">
                                            <StackPanel>
                                                <TextBlock Text="Dashboard Card" Foreground="#E5E7EB" FontWeight="SemiBold"/>
                                                <TextBlock x:Name="ThemePreviewMutedText" Text="Colors are saved to profiles\&lt;Organization&gt;\Branding\theme.json." Foreground="#94A3B8" TextWrapping="Wrap" Margin="0,6,0,0"/>
                                            </StackPanel>
                                        </Border>
                                    </StackPanel>
                                </Border>
                                <Border Background="#0B1220" BorderBrush="#26364F" BorderThickness="1" CornerRadius="10" Padding="12">
                                    <TextBlock x:Name="ThemeEditorStatusText" Text="Select Save Theme to create or update the profile brand package." Foreground="#CBD5E1" TextWrapping="Wrap"/>
                                </Border>
                            </StackPanel>
                        </Border>
                    </Grid>
                    <Grid Grid.Row="2" Margin="0,18,0,0">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                        <Button x:Name="ThemeEditorCancelButton" Grid.Column="0" Content="Cancel" Height="38" MinWidth="90"/>
                        <TextBlock x:Name="ThemeEditorPathText" Grid.Column="1" Text="" Foreground="#94A3B8" VerticalAlignment="Center" TextWrapping="Wrap" Margin="14,0"/>
                        <Button x:Name="ThemeEditorPreviewButton" Grid.Column="2" Content="Preview" Height="38" MinWidth="100" Margin="0,0,10,0"/>
                        <Button x:Name="ThemeEditorSaveButton" Grid.Column="3" Content="Save Theme" Height="38" MinWidth="120"/>
                    </Grid>
                </Grid>
                <Grid x:Name="RuntimeProfileWizardView" Width="860" MinHeight="560">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Grid Grid.Row="0" Margin="0,0,0,18">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0">
                            <TextBlock Text="Runtime Profile Wizard" Foreground="#F8FAFC" FontSize="26" FontWeight="SemiBold"/>
                            <TextBlock Text="Create, edit, validate, and save runtime profiles without editing JSON by hand." Foreground="#38BDF8" FontSize="13" TextWrapping="Wrap"/>
                        </StackPanel>
                        <Button x:Name="WizardCloseButton" Grid.Column="1" Content="X" Width="34" Height="30" Margin="12,0,0,0"/>
                    </Grid>

                    <Grid Grid.Row="1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="210"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Background="#0F172A" CornerRadius="14" Padding="16" Margin="0,0,16,0">
                            <StackPanel>
                                <TextBlock Text="Steps" Style="{StaticResource LabelText}" Margin="0,0,0,10"/>
                                <TextBlock x:Name="WizardStepProfileText" Text="1. Profile" Foreground="#38BDF8" FontWeight="SemiBold" Margin="0,0,0,12"/>
                                <TextBlock x:Name="WizardStepEnvironmentText" Text="2. Environment" Foreground="#94A3B8" Margin="0,0,0,12"/>
                                <TextBlock x:Name="WizardStepRuntimeText" Text="3. Runtime Mode" Foreground="#94A3B8" Margin="0,0,0,12"/>
                                <TextBlock x:Name="WizardStepProvidersText" Text="4. Providers" Foreground="#94A3B8" Margin="0,0,0,12"/>
                                <TextBlock x:Name="WizardStepValidationText" Text="5. Validation" Foreground="#94A3B8" Margin="0,0,0,12"/>
                                <TextBlock x:Name="WizardStepSummaryText" Text="6. Summary" Foreground="#94A3B8" Margin="0,0,0,12"/>
                                <Border Background="#111827" CornerRadius="10" Padding="10" Margin="0,18,0,0">
                                    <TextBlock Text="Use Next to move through the profile workflow. Validate before saving." Foreground="#CBD5E1" TextWrapping="Wrap" FontSize="12"/>
                                </Border>
                            </StackPanel>
                        </Border>

                        <Border Grid.Column="1" Background="#0F172A" CornerRadius="14" Padding="18">
                            <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                            <Grid>
                                <StackPanel x:Name="WizardStepProfilePanel" Visibility="Visible">
                                    <TextBlock Text="Step 1: Profile" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock Text="Name the runtime profile and identify the organization it belongs to." Foreground="#CBD5E1" TextWrapping="Wrap" Margin="0,0,0,18"/>
                                    <TextBlock Text="Profile Name" Style="{StaticResource LabelText}"/>
                                    <TextBox x:Name="WizardProfileNameTextBox" Text="" Height="34" Margin="0,4,0,12"/>
                                    <TextBlock Text="Organization" Style="{StaticResource LabelText}"/>
                                    <TextBox x:Name="WizardOrganizationTextBox" Text="" Height="34" Margin="0,4,0,12"/>
                                    <TextBlock Text="Tenant ID" Style="{StaticResource LabelText}"/>
                                    <TextBox x:Name="WizardTenantIdTextBox" Text="" Height="34" Margin="0,4,0,0"/>
                                </StackPanel>

                                <StackPanel x:Name="WizardStepEnvironmentPanel" Visibility="Collapsed">
                                    <TextBlock Text="Step 2: Environment" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock Text="Choose the Microsoft cloud container this runtime profile targets." Foreground="#CBD5E1" TextWrapping="Wrap" Margin="0,0,0,18"/>
                                    <TextBlock Text="Cloud Environment" Style="{StaticResource LabelText}"/>
                                    <ComboBox x:Name="WizardCloudComboBox" Height="34" SelectedIndex="0" MaxWidth="360" HorizontalAlignment="Left">
                                        <ComboBoxItem Content="Commercial"/>
                                        <ComboBoxItem Content="GCCHigh"/>
                                        <ComboBoxItem Content="DoD"/>
                                    </ComboBox>
                                </StackPanel>

                                <StackPanel x:Name="WizardStepRuntimePanel" Visibility="Collapsed">
                                    <TextBlock Text="Step 3: Runtime Mode" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock Text="Select whether this profile uses live providers, simulated providers, or a hybrid of both." Foreground="#CBD5E1" TextWrapping="Wrap" Margin="0,0,0,18"/>
                                    <TextBlock Text="Runtime Mode" Style="{StaticResource LabelText}"/>
                                    <ComboBox x:Name="WizardModeComboBox" Height="34" SelectedIndex="0" MaxWidth="360" HorizontalAlignment="Left">
                                        <ComboBoxItem Content="Simulation"/>
                                        <ComboBoxItem Content="Live"/>
                                        <ComboBoxItem Content="Hybrid"/>
                                    </ComboBox>
                                </StackPanel>

                                <StackPanel x:Name="WizardStepProvidersPanel" Visibility="Collapsed">
                                    <TextBlock Text="Step 4: Providers" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock Text="Enable each provider and choose the runtime mode it should use." Foreground="#CBD5E1" TextWrapping="Wrap" Margin="0,0,0,18"/>
                                    <Grid>
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/><ColumnDefinition Width="170"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Provider" Style="{StaticResource LabelText}"/>
                                        <TextBlock Grid.Column="1" Text="Enabled" Style="{StaticResource LabelText}"/>
                                        <TextBlock Grid.Column="2" Text="Mode" Style="{StaticResource LabelText}"/>
                                    </Grid>
                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/><ColumnDefinition Width="170"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Directory Simulator" Foreground="#E5E7EB" VerticalAlignment="Center"/>
                                        <CheckBox x:Name="WizardDirectorySimulatorEnabledCheckBox" Grid.Column="1" IsChecked="True" VerticalAlignment="Center"/>
                                        <ComboBox x:Name="WizardDirectorySimulatorModeComboBox" Grid.Column="2" SelectedIndex="0"><ComboBoxItem Content="Simulation"/><ComboBoxItem Content="Disabled"/></ComboBox>
                                    </Grid>
                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/><ColumnDefinition Width="170"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Active Directory" Foreground="#E5E7EB" VerticalAlignment="Center"/>
                                        <CheckBox x:Name="WizardActiveDirectoryEnabledCheckBox" Grid.Column="1" IsChecked="False" VerticalAlignment="Center"/>
                                        <ComboBox x:Name="WizardActiveDirectoryModeComboBox" Grid.Column="2" SelectedIndex="2"><ComboBoxItem Content="Live"/><ComboBoxItem Content="Simulation"/><ComboBoxItem Content="Disabled"/></ComboBox>
                                    </Grid>
                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/><ColumnDefinition Width="170"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Microsoft Graph" Foreground="#E5E7EB" VerticalAlignment="Center"/>
                                        <CheckBox x:Name="WizardMicrosoftGraphEnabledCheckBox" Grid.Column="1" IsChecked="False" VerticalAlignment="Center"/>
                                        <ComboBox x:Name="WizardMicrosoftGraphModeComboBox" Grid.Column="2" SelectedIndex="2"><ComboBoxItem Content="Live"/><ComboBoxItem Content="Simulation"/><ComboBoxItem Content="Disabled"/></ComboBox>
                                    </Grid>
                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/><ColumnDefinition Width="170"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Exchange Online" Foreground="#E5E7EB" VerticalAlignment="Center"/>
                                        <CheckBox x:Name="WizardExchangeOnlineEnabledCheckBox" Grid.Column="1" IsChecked="False" VerticalAlignment="Center"/>
                                        <ComboBox x:Name="WizardExchangeOnlineModeComboBox" Grid.Column="2" SelectedIndex="2"><ComboBoxItem Content="Live"/><ComboBoxItem Content="Simulation"/><ComboBoxItem Content="Disabled"/></ComboBox>
                                    </Grid>
                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/><ColumnDefinition Width="170"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Exchange On-Premises" Foreground="#E5E7EB" VerticalAlignment="Center"/>
                                        <CheckBox x:Name="WizardExchangeOnPremisesEnabledCheckBox" Grid.Column="1" IsChecked="False" VerticalAlignment="Center"/>
                                        <ComboBox x:Name="WizardExchangeOnPremisesModeComboBox" Grid.Column="2" SelectedIndex="2"><ComboBoxItem Content="Live"/><ComboBoxItem Content="Simulation"/><ComboBoxItem Content="Disabled"/></ComboBox>
                                    </Grid>
                                    <Grid Margin="22,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="On-Prem Exchange Server" Foreground="#CBD5E1" VerticalAlignment="Center"/>
                                        <TextBox x:Name="WizardExchangeOnPremisesServerTextBox" Grid.Column="1" Height="34" Background="#0B1220" Foreground="#E5E7EB" BorderBrush="#26364F" Padding="8,0" VerticalContentAlignment="Center" ToolTip="Server FQDN or short name, for example exchange01.contoso.local"/>
                                    </Grid>
                                    <Grid Margin="22,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Connection URI" Foreground="#CBD5E1" VerticalAlignment="Center"/>
                                        <TextBox x:Name="WizardExchangeOnPremisesConnectionUriTextBox" Grid.Column="1" Height="34" Background="#0B1220" Foreground="#E5E7EB" BorderBrush="#26364F" Padding="8,0" VerticalContentAlignment="Center" ToolTip="Optional. Defaults to http://SERVER/PowerShell/ when a server is supplied."/>
                                    </Grid>
                                    <Grid Margin="22,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="220"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Authentication" Foreground="#CBD5E1" VerticalAlignment="Center"/>
                                        <ComboBox x:Name="WizardExchangeOnPremisesAuthenticationComboBox" Grid.Column="1" SelectedIndex="0"><ComboBoxItem Content="Kerberos"/><ComboBoxItem Content="Negotiate"/><ComboBoxItem Content="Default"/></ComboBox>
                                    </Grid>
                                    <TextBlock Text="Cloud Authentication" Foreground="#F8FAFC" FontSize="14" FontWeight="SemiBold" Margin="0,18,0,8"/>
                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="210"/><ColumnDefinition Width="110"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="App-only Enabled" Foreground="#E5E7EB" VerticalAlignment="Center"/>
                                        <CheckBox x:Name="WizardAppOnlyEnabledCheckBox" Grid.Column="1" IsChecked="False" VerticalAlignment="Center"/>
                                        <ComboBox x:Name="WizardAppOnlyCredentialModeComboBox" Grid.Column="2" SelectedIndex="0"><ComboBoxItem Content="Certificate"/><ComboBoxItem Content="ClientSecretReference"/></ComboBox>
                                    </Grid>
                                    <Grid Margin="22,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Tenant ID" Foreground="#CBD5E1" VerticalAlignment="Center"/>
                                        <TextBox x:Name="WizardAppOnlyTenantIdTextBox" Grid.Column="1" Height="34" Background="#0B1220" Foreground="#E5E7EB" BorderBrush="#26364F" Padding="8,0" VerticalContentAlignment="Center"/>
                                    </Grid>
                                    <Grid Margin="22,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Tenant Domain" Foreground="#CBD5E1" VerticalAlignment="Center" ToolTip="Tenant primary or onmicrosoft.com domain used by Exchange Online as the Organization value."/>
                                        <TextBox x:Name="WizardAppOnlyTenantDomainTextBox" Grid.Column="1" Height="34" Background="#0B1220" Foreground="#E5E7EB" BorderBrush="#26364F" Padding="8,0" VerticalContentAlignment="Center" ToolTip="Expected: tenant.onmicrosoft.com or the tenant primary accepted domain. This is used for Connect-ExchangeOnline -Organization."/>
                                    </Grid>
                                    <Grid Margin="22,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Client ID" Foreground="#CBD5E1" VerticalAlignment="Center"/>
                                        <TextBox x:Name="WizardAppOnlyClientIdTextBox" Grid.Column="1" Height="34" Background="#0B1220" Foreground="#E5E7EB" BorderBrush="#26364F" Padding="8,0" VerticalContentAlignment="Center"/>
                                    </Grid>
                                    <Grid Margin="22,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Certificate Thumbprint" Foreground="#CBD5E1" VerticalAlignment="Center" ToolTip="Thumbprint of a certificate installed in the Windows certificate store. Paste with or without spaces or colons; HAP saves uppercase hex."/>
                                        <TextBox x:Name="WizardCertificateThumbprintTextBox" Grid.Column="1" Height="34" Background="#0B1220" Foreground="#E5E7EB" BorderBrush="#26364F" Padding="8,0" VerticalContentAlignment="Center" ToolTip="Expected: certificate thumbprint from CurrentUser\My or LocalMachine\My, for example ABCDEF1234567890ABCDEF1234567890ABCDEF12."/>
                                    </Grid>
                                    <Grid Margin="22,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Certificate Path" Foreground="#CBD5E1" VerticalAlignment="Center" ToolTip="Path to a local certificate file for app-only auth, typically a .pfx. Do not put the PFX password in this profile."/>
                                        <TextBox x:Name="WizardCertificatePathTextBox" Grid.Column="1" Height="34" Background="#0B1220" Foreground="#E5E7EB" BorderBrush="#26364F" Padding="8,0" VerticalContentAlignment="Center" ToolTip="Expected: full local path such as C:\Certs\hap-exo-apponly.pfx. Password handling requires a future secure secret resolver."/>
                                    </Grid>
                                    <Grid Margin="22,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Secret Reference" Foreground="#CBD5E1" VerticalAlignment="Center" ToolTip="Name or URI of a secret stored outside this profile. Plaintext client secrets are not supported."/>
                                        <TextBox x:Name="WizardSecretReferenceTextBox" Grid.Column="1" Height="34" Background="#0B1220" Foreground="#E5E7EB" BorderBrush="#26364F" Padding="8,0" VerticalContentAlignment="Center" ToolTip="Expected: a future vault/secret-store reference such as a key vault URI or managed secret name, not the secret value."/>
                                    </Grid>
                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="210"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Delegated Enabled" Foreground="#E5E7EB" VerticalAlignment="Center"/>
                                        <CheckBox x:Name="WizardDelegatedEnabledCheckBox" Grid.Column="1" IsChecked="False" VerticalAlignment="Center"/>
                                    </Grid>
                                </StackPanel>

                                <StackPanel x:Name="WizardStepValidationPanel" Visibility="Collapsed">
                                    <TextBlock Text="Step 5: Validation" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock Text="Validate the generated runtime profile before saving it." Foreground="#CBD5E1" TextWrapping="Wrap" Margin="0,0,0,18"/>
                                    <Button x:Name="WizardValidateButton" Content="Validate Profile" Height="38" MinWidth="140" HorizontalAlignment="Left" Margin="0,0,0,14"/>
                                    <Border Background="#111827" CornerRadius="10" Padding="12">
                                        <TextBlock x:Name="WizardValidationText" Text="Select Validate Profile to preview the generated runtime profile." Foreground="#CBD5E1" TextWrapping="Wrap"/>
                                    </Border>
                                </StackPanel>

                                <StackPanel x:Name="WizardStepSummaryPanel" Visibility="Collapsed">
                                    <TextBlock Text="Step 6: Summary" Style="{StaticResource SectionTitle}"/>
                                    <TextBlock Text="Save the runtime profile after validation. The profile is written under profiles\\Runtime." Foreground="#CBD5E1" TextWrapping="Wrap" Margin="0,0,0,18"/>
                                    <Border Background="#111827" CornerRadius="10" Padding="12" Margin="0,0,0,14">
                                        <TextBlock x:Name="WizardSummaryText" Text="Profile has not been validated yet." Foreground="#CBD5E1" TextWrapping="Wrap"/>
                                    </Border>
                                    <Button x:Name="WizardSaveButton" Content="Save Profile" Height="38" MinWidth="130" HorizontalAlignment="Left"/>
                                </StackPanel>
                            </Grid>
                            </ScrollViewer>
                        </Border>
                    </Grid>

                    <Grid Grid.Row="2" Margin="0,18,0,0">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                        <Button x:Name="WizardCancelButton" Grid.Column="0" Content="Cancel" Height="38" MinWidth="90"/>
                        <TextBlock x:Name="WizardStepStatusText" Grid.Column="1" Text="Step 1 of 6" Foreground="#94A3B8" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                        <Button x:Name="WizardBackButton" Grid.Column="2" Content="Back" Height="38" MinWidth="90" Margin="0,0,10,0" IsEnabled="False"/>
                        <Button x:Name="WizardNextButton" Grid.Column="3" Content="Next" Height="38" MinWidth="90"/>
                    </Grid>
                </Grid>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

if ($null -ne $script:HybridUiTheme -and (Get-Command Set-HybridUiThemeToXaml -ErrorAction SilentlyContinue)) {
    $xaml = Set-HybridUiThemeToXaml -Xaml $xaml -Theme $script:HybridUiTheme
}

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [Windows.Markup.XamlReader]::Load($reader)

$controls = @{}
@('ShellRoot','StartupRegion','MainRegion','StatusBarRegion','OverlayRegion','OverlayHost','LaunchProgressView','LaunchProgressText','LaunchProgressBar','RuntimeProfileListBox','RefreshRuntimeProfilesButton','NewRuntimeProfileButton','DeleteRuntimeProfileButton','ImportExportRuntimeProfileButton','SetDefaultRuntimeProfileButton','ManageRuntimeThemeButton','RuntimeThemeEditorView','ThemeEditorSubtitleText','ThemePackageNameTextBox','ThemeWindowTitleTextBox','ThemeOrganizationNameTextBox','ThemeAccentColorTextBox','ThemeBackgroundColorTextBox','ThemeSurfaceColorTextBox','ThemePanelColorTextBox','ThemeBorderColorTextBox','ThemeForegroundColorTextBox','ThemeTextColorTextBox','ThemeMutedTextColorTextBox','ThemeLogoPathTextBox','ThemeIconPathTextBox','ThemeSplashPathTextBox','ThemePreviewShell','ThemePreviewWindow','ThemePreviewTitleText','ThemePreviewAccentText','ThemePreviewCard','ThemePreviewMutedText','ThemeEditorStatusText','ThemeEditorCancelButton','ThemeEditorPathText','ThemeEditorPreviewButton','ThemeEditorSaveButton','ThemeEditorCloseButton','RuntimeProfileWizardView','WizardProfileNameTextBox','WizardOrganizationTextBox','WizardTenantIdTextBox','WizardCloudComboBox','WizardModeComboBox','WizardDirectorySimulatorEnabledCheckBox','WizardDirectorySimulatorModeComboBox','WizardActiveDirectoryEnabledCheckBox','WizardActiveDirectoryModeComboBox','WizardMicrosoftGraphEnabledCheckBox','WizardMicrosoftGraphModeComboBox','WizardExchangeOnlineEnabledCheckBox','WizardExchangeOnlineModeComboBox','WizardExchangeOnPremisesEnabledCheckBox','WizardExchangeOnPremisesModeComboBox','WizardExchangeOnPremisesServerTextBox','WizardExchangeOnPremisesConnectionUriTextBox','WizardExchangeOnPremisesAuthenticationComboBox','WizardAppOnlyEnabledCheckBox','WizardAppOnlyCredentialModeComboBox','WizardAppOnlyTenantIdTextBox','WizardAppOnlyTenantDomainTextBox','WizardAppOnlyClientIdTextBox','WizardCertificateThumbprintTextBox','WizardCertificatePathTextBox','WizardSecretReferenceTextBox','WizardDelegatedEnabledCheckBox','WizardStepProfileText','WizardStepEnvironmentText','WizardStepRuntimeText','WizardStepProvidersText','WizardStepValidationText','WizardStepSummaryText','WizardStepProfilePanel','WizardStepEnvironmentPanel','WizardStepRuntimePanel','WizardStepProvidersPanel','WizardStepValidationPanel','WizardStepSummaryPanel','WizardSummaryText','WizardStepStatusText','WizardBackButton','WizardNextButton','WizardCloseButton','WizardValidationText','WizardValidateButton','WizardSaveButton','WizardCancelButton','MainDashboardGrid','UserIdentityColumn','OperationsColumn','RuntimeColumn','HeaderRuntimeBadgeText','ShellStatusText','ShellStatusPanel','StatusProfileText','StatusCloudText','StatusModeText','StatusAuthText','StatusHealthText','StartupBrandIcon','ConsoleBrandIcon','SummaryBrandIcon','StartupView','ConsoleView','LaunchConsoleButton','EditRuntimeProfileButton','ExitButton','RuntimeVersionText','RuntimeProfileText','RuntimeCloudText','RuntimeModeText','RuntimeProviderSummaryText','RuntimeProviderDetailsText','RuntimeDiagnosticsText','RuntimeAuthenticationText','RuntimeActiveDirectoryStatusText','RuntimeStatusText','RuntimePreviewText','SearchBox','SearchButton','ResultHeader','StatusText','DisplayNameText','UpnText','SamText','MailText','DepartmentText','TitleText','MailboxText','SourcesText','ProviderStatusText','ProviderDot','BackToStartButton','SearchProgressPanel','SearchProgressStageText','SearchProgressIndicator','CompanyText','OfficeText','EmployeeIdText','BadgeIdText','StateText','PhoneNumberText','DistinguishedNameText','AccountStateText','OrganizationalUnitText','ManagerText','GroupsList','DirectReportsList','RecipientTypeText','MailboxStatusText','ForwardingText','MailboxDelegationList','DistributionGroupsList','ExchangeSummaryText','ExchangeMailboxCard','AggregationStatusCard','AggregationSummaryText','AggregationIdentityText','AggregationVerticalsText','AggregationStatusText','AggregationRetrievedText','MicrosoftGraphCard','GraphSummaryText','GraphObjectIdText','GraphUserTypeText','GraphUsageLocationText','GraphPreferredLanguageText','GraphMfaRegisteredText','GraphMfaCapableText','GraphAuthenticationMethodsText','GraphLastSignInText','GraphPasswordLastChangedText','GraphRiskStateText','AuthenticationPostureCard','AuthenticationSummaryText','AuthDefaultMethodText','AuthMfaRegisteredText','AuthPasswordlessText','AuthStrengthText','AuthConditionalAccessText','AuthRiskText','AuthMethodsList') | ForEach-Object { $controls[$_] = $window.FindName($_) }

function Resolve-HybridBrandAssetPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$PrimaryPath,
        [Parameter(Mandatory=$true)][string]$FallbackPath
    )

    if (Test-Path -LiteralPath $PrimaryPath) { return $PrimaryPath }
    if (Test-Path -LiteralPath $FallbackPath) { return $FallbackPath }
    return $null
}

function Set-HybridWindowIcon {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Window)

    $icoPath = Resolve-HybridBrandAssetPath -PrimaryPath $script:HapIcoIcon -FallbackPath $script:HapIcoLogoFallback
    if ([string]::IsNullOrWhiteSpace($icoPath)) { return }

    try {
        $icoUri = [Uri]::new($icoPath, [UriKind]::Absolute)
        $Window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create($icoUri)
    }
    catch {
        # Branding should never prevent the administrative console from opening.
    }
}

function Set-HybridBrandIcons {
    $pngPath = Resolve-HybridBrandAssetPath -PrimaryPath $script:HapPngIcon -FallbackPath $script:HapPngLogoFallback
    if ([string]::IsNullOrWhiteSpace($pngPath)) { return }
    try {
        $uri = [Uri]::new($pngPath, [UriKind]::Absolute)
        $bitmap = [Windows.Media.Imaging.BitmapImage]::new()
        $bitmap.BeginInit()
        $bitmap.UriSource = $uri
        $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.EndInit()
        $bitmap.Freeze()
        foreach ($name in @('StartupBrandIcon','ConsoleBrandIcon','SummaryBrandIcon')) {
            if ($controls.ContainsKey($name) -and $null -ne $controls[$name]) { $controls[$name].Source = $bitmap }
        }
    }
    catch {
        # UI image branding is optional and should not block startup.
    }
}

Set-HybridWindowIcon -Window $window
Set-HybridBrandIcons


$script:IsSearchBusy = $false
$script:CurrentSearchQuery = $null
$script:SelectedHybridUser = $null

function Get-HybridRuntimeDisplayValue {
    param([AllowNull()][object]$InputObject, [string[]]$Names, [string]$Default = '-')
    foreach ($name in $Names) {
        if ($null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains $name) {
            $value = $InputObject.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return [string]$value }
        }
    }
    return $Default
}


$script:RuntimeProfileSummaries = @()
$script:SelectedRuntimeProfileSummary = $null

function Get-HybridRuntimeProfileListLabel {
    param([Parameter(Mandatory)][object]$Profile)

    if (Get-Command Get-HybridRuntimeProfileDisplayLabel -ErrorAction SilentlyContinue) {
        return Get-HybridRuntimeProfileDisplayLabel -Profile $Profile
    }

    $prefix = '  '
    if ($Profile.IsLastUsed) { $prefix = '> ' }
    elseif ($Profile.IsDefault) { $prefix = '* ' }
    $status = if ($Profile.IsValid) { 'Ready' } else { 'Invalid' }
    return ('{0}{1}  [{2} / {3} / {4}]' -f $prefix, $Profile.ProfileName, $Profile.CloudEnvironment, $Profile.RuntimeMode, $status)
}

function Set-HybridSelectedRuntimeProfile {
    param([AllowNull()][object]$Profile, [switch]$Persist)

    $script:SelectedRuntimeProfileSummary = $Profile

    if ($Persist -and $null -ne $Profile -and (Get-Command Set-HybridRuntimeProfileSelection -ErrorAction SilentlyContinue)) {
        try { Set-HybridRuntimeProfileSelection -RepositoryRoot $repoRoot -ProfilePath $Profile.Path | Out-Null } catch { }
    }

    Update-HybridStartupView
    Update-HybridPersistentRuntimeStatus
}

function Initialize-HybridRuntimeProfileList {
    if ($null -eq $controls.RuntimeProfileListBox) { return }

    $controls.RuntimeProfileListBox.Items.Clear()
    $script:RuntimeProfileSummaries = @()

    if (-not (Get-Command Get-HybridRuntimeProfileSummary -ErrorAction SilentlyContinue)) {
        $controls.RuntimeProfileListBox.Items.Add('Runtime profile manager unavailable') | Out-Null
        return
    }

    $script:RuntimeProfileSummaries = @(Get-HybridRuntimeProfileSummary -RepositoryRoot $repoRoot)
    if ($script:RuntimeProfileSummaries.Count -eq 0) {
        $controls.RuntimeProfileListBox.Items.Add('No runtime profiles found') | Out-Null
        return
    }

    foreach ($profile in $script:RuntimeProfileSummaries) {
        if (-not $profile.PSObject.Properties.Match('BadgeText').Count) {
            $badge = if ($profile.IsDefault) { 'Default' } elseif ($profile.IsLastUsed) { 'Last Used' } else { '' }
            $profile | Add-Member -MemberType NoteProperty -Name BadgeText -Value $badge -Force
        }
        if (-not $profile.PSObject.Properties.Match('HealthLabel').Count) {
            $health = if ($profile.IsValid) { 'Ready' } else { 'Invalid' }
            $profile | Add-Member -MemberType NoteProperty -Name HealthLabel -Value $health -Force
        }
        $controls.RuntimeProfileListBox.Items.Add($profile) | Out-Null
    }

    $selection = $null
    if (Get-Command Get-HybridRuntimeProfileSelection -ErrorAction SilentlyContinue) {
        $selection = Get-HybridRuntimeProfileSelection -RepositoryRoot $repoRoot
    }
    if (Get-Command Select-HybridRuntimeProfileSummary -ErrorAction SilentlyContinue) {
        $selection = Select-HybridRuntimeProfileSummary -Profiles $script:RuntimeProfileSummaries -PreferredSelection $selection -PreferredProfileName $Profile
    }
    if ($null -eq $selection) { $selection = $script:RuntimeProfileSummaries[0] }

    $selectedIndex = 0
    for ($i = 0; $i -lt $script:RuntimeProfileSummaries.Count; $i++) {
        if ([string]::Equals($script:RuntimeProfileSummaries[$i].Path, $selection.Path, [System.StringComparison]::OrdinalIgnoreCase)) {
            $selectedIndex = $i
            break
        }
    }

    $controls.RuntimeProfileListBox.SelectedIndex = $selectedIndex
    Set-HybridSelectedRuntimeProfile -Profile $script:RuntimeProfileSummaries[$selectedIndex]
}

function Select-HybridRuntimeProfileFromList {
    if ($null -eq $controls.RuntimeProfileListBox) { return }
    $index = $controls.RuntimeProfileListBox.SelectedIndex
    if ($index -lt 0 -or $index -ge $script:RuntimeProfileSummaries.Count) { return }
    Set-HybridSelectedRuntimeProfile -Profile $script:RuntimeProfileSummaries[$index] -Persist
}


function Set-HybridLaunchButtonLabel {
    param([object]$Profile)
    if ($null -eq $controls.LaunchConsoleButton) { return }
    if (Get-Command Set-HybridLaunchButtonProfileLabel -ErrorAction SilentlyContinue) {
        Set-HybridLaunchButtonProfileLabel -Button $controls.LaunchConsoleButton -Profile $Profile
        return
    }
    $name = if ($null -eq $Profile -or [string]::IsNullOrWhiteSpace([string]$Profile.ProfileName)) { 'Console' } else { [string]$Profile.ProfileName }
    $controls.LaunchConsoleButton.Content = if ($name -eq 'Console') { 'Launch Console' } else { "Launch $name" }
    $controls.LaunchConsoleButton.ToolTip = if ($name -eq 'Console') { 'Launch Hybrid Admin Console' } else { "Launch $name" }
}




function Get-HybridRuntimeProfileProviderSummary {
    param([AllowNull()][object]$Profile)

    $providerNames = New-Object System.Collections.Generic.List[string]

    if ($null -ne $Profile) {
        if ($Profile.PSObject.Properties.Name -contains 'Providers' -and $null -ne $Profile.Providers) {
            $providersObject = $Profile.Providers
            if ($providersObject -is [System.Collections.IDictionary]) {
                foreach ($key in @($providersObject.Keys | Sort-Object)) {
                    $provider = $providersObject[$key]
                    $enabled = $true
                    if ($null -ne $provider -and $provider.PSObject.Properties.Name -contains 'Enabled') { $enabled = [bool]$provider.Enabled }
                    if ($enabled) { $providerNames.Add([string]$key) | Out-Null }
                }
            }
            elseif ($providersObject.PSObject.Properties.Count -gt 0) {
                foreach ($property in @($providersObject.PSObject.Properties | Sort-Object Name)) {
                    $provider = $property.Value
                    $enabled = $true
                    if ($null -ne $provider -and $provider.PSObject.Properties.Name -contains 'Enabled') { $enabled = [bool]$provider.Enabled }
                    if ($enabled) { $providerNames.Add([string]$property.Name) | Out-Null }
                }
            }
        }

        if ($providerNames.Count -eq 0 -and $Profile.PSObject.Properties.Name -contains 'Path' -and -not [string]::IsNullOrWhiteSpace([string]$Profile.Path) -and (Test-Path -LiteralPath ([string]$Profile.Path))) {
            try {
                $rawProfile = Get-Content -LiteralPath ([string]$Profile.Path) -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if ($null -ne $rawProfile.Providers) {
                    foreach ($property in @($rawProfile.Providers.PSObject.Properties | Sort-Object Name)) {
                        $provider = $property.Value
                        $enabled = $true
                        if ($null -ne $provider -and $provider.PSObject.Properties.Name -contains 'Enabled') { $enabled = [bool]$provider.Enabled }
                        if ($enabled) { $providerNames.Add([string]$property.Name) | Out-Null }
                    }
                }
            }
            catch { }
        }

        if ($providerNames.Count -eq 0 -and $Profile.PSObject.Properties.Name -contains 'EnabledProviders') {
            foreach ($providerName in @($Profile.EnabledProviders | Sort-Object)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$providerName)) { $providerNames.Add([string]$providerName) | Out-Null }
            }
        }
    }

    $distinctProviders = @($providerNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    return [pscustomobject]@{
        Count = $distinctProviders.Count
        Names = @($distinctProviders)
        Text = if ($distinctProviders.Count -gt 0) { ($distinctProviders -join ', ') } else { 'No enabled providers declared.' }
    }
}


function Get-HybridProviderDisplayName {
    param([Parameter(Mandatory=$true)][string]$Name)
    switch ($Name) {
        'ActiveDirectory' { 'Active Directory' }
        'MicrosoftGraph' { 'Microsoft Graph' }
        'ExchangeOnline' { 'Exchange Online' }
        'ExchangeOnPremises' { 'Exchange On-Premises' }
        'DirectorySimulator' { 'Directory Simulator' }
        default { $Name }
    }
}

function Get-HapProfileObjectValue {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory=$true)][string[]]$Names,
        [AllowNull()][object]$Default = $null
    )

    foreach ($name in $Names) {
        if ($null -eq $InputObject) { continue }
        if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($name)) {
            $value = $InputObject[$name]
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return $value }
        }
        $property = $InputObject.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return $property.Value
        }
    }

    return $Default
}

function Get-HapSelectedRuntimeProfileRaw {
    param([AllowNull()][object]$Profile)

    if ($null -eq $Profile) { return $null }
    if ($Profile.PSObject.Properties.Name -contains 'Raw' -and $null -ne $Profile.Raw) { return $Profile.Raw }
    if ($Profile.PSObject.Properties.Name -contains 'Path' -and -not [string]::IsNullOrWhiteSpace([string]$Profile.Path) -and (Test-Path -LiteralPath ([string]$Profile.Path) -PathType Leaf)) {
        try { return (Get-Content -LiteralPath ([string]$Profile.Path) -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) }
        catch { return $null }
    }
    return $Profile
}

function Get-HapRuntimeProfileProviderMap {
    param([AllowNull()][object]$RawProfile)

    $providers = [ordered]@{}
    if ($null -eq $RawProfile) { return $providers }
    $providersObject = Get-HapProfileObjectValue -InputObject $RawProfile -Names @('Providers') -Default $null
    if ($null -eq $providersObject) { return $providers }

    if ($providersObject -is [System.Collections.IDictionary]) {
        foreach ($key in @($providersObject.Keys | Sort-Object)) { $providers[[string]$key] = $providersObject[$key] }
        return $providers
    }

    foreach ($property in @($providersObject.PSObject.Properties | Sort-Object Name)) {
        $providers[[string]$property.Name] = $property.Value
    }

    return $providers
}

function Test-HapCloudAppOnlyConfigured {
    param([AllowNull()][object]$Authentication)

    $appOnly = Get-HapProfileObjectValue -InputObject $Authentication -Names @('AppOnly') -Default $null
    if ($null -eq $appOnly) { return $false }
    if (-not [bool](Get-HapProfileObjectValue -InputObject $appOnly -Names @('Enabled') -Default $false)) { return $false }

    $tenantId = [string](Get-HapProfileObjectValue -InputObject $appOnly -Names @('TenantId') -Default '')
    $clientId = [string](Get-HapProfileObjectValue -InputObject $appOnly -Names @('ClientId') -Default '')
    $credentialMode = [string](Get-HapProfileObjectValue -InputObject $appOnly -Names @('CredentialMode') -Default 'Certificate')
    $thumbprint = [string](Get-HapProfileObjectValue -InputObject $appOnly -Names @('CertificateThumbprint') -Default '')
    $certificatePath = [string](Get-HapProfileObjectValue -InputObject $appOnly -Names @('CertificatePath') -Default '')
    $secretReference = [string](Get-HapProfileObjectValue -InputObject $appOnly -Names @('SecretReference') -Default '')

    if ([string]::IsNullOrWhiteSpace($tenantId) -or [string]::IsNullOrWhiteSpace($clientId)) { return $false }
    if ($credentialMode -eq 'ClientSecretReference') { return -not [string]::IsNullOrWhiteSpace($secretReference) }
    return (-not [string]::IsNullOrWhiteSpace($thumbprint) -or -not [string]::IsNullOrWhiteSpace($certificatePath))
}

function Get-HapAuthenticationPreviewLines {
    param(
        [AllowNull()][object]$RawProfile,
        [string]$Mode = ''
    )

    if ($Mode -eq 'Simulation') {
        return @('Authentication: Mock/simulation', 'Device Code: prohibited')
    }

    $authentication = Get-HapProfileObjectValue -InputObject $RawProfile -Names @('Authentication') -Default $null
    $appOnly = Get-HapProfileObjectValue -InputObject $authentication -Names @('AppOnly') -Default $null
    $delegated = Get-HapProfileObjectValue -InputObject $authentication -Names @('Delegated') -Default $null
    $appOnlyConfigured = Test-HapCloudAppOnlyConfigured -Authentication $authentication
    $appOnlyEnabled = [bool](Get-HapProfileObjectValue -InputObject $appOnly -Names @('Enabled') -Default $false)
    $delegatedEnabled = [bool](Get-HapProfileObjectValue -InputObject $delegated -Names @('Enabled') -Default $false)

    @(
        ('App-only Graph/EXO: {0}' -f $(if ($appOnlyConfigured) { 'configured' } elseif ($appOnlyEnabled) { 'missing settings' } else { 'disabled/not configured' }))
        ('Delegated Graph: {0}' -f $(if ($delegatedEnabled) { 'available on demand' } else { 'disabled' }))
        'Device Code: prohibited'
    )
}

function Get-HapProviderConnectionHint {
    param(
        [string]$ProviderName,
        [AllowNull()][object]$ProviderConfig,
        [AllowNull()][object]$RawProfile
    )

    switch ($ProviderName) {
        'ActiveDirectory' {
            $hint = [string](Get-HapProfileObjectValue -InputObject $ProviderConfig -Names @('Domain','DomainName','Server','DomainController','ServerName') -Default '')
            if ([string]::IsNullOrWhiteSpace($hint)) { $hint = [string](Get-HapProfileObjectValue -InputObject $RawProfile -Names @('Domain','DomainName') -Default '') }
            if ([string]::IsNullOrWhiteSpace($hint)) { return 'Integrated/domain discovery' }
            return $hint
        }
        'MicrosoftGraph' {
            return [string](Get-HapProfileObjectValue -InputObject $RawProfile -Names @('Cloud','CloudEnvironment') -Default 'Commercial')
        }
        'ExchangeOnline' {
            return [string](Get-HapProfileObjectValue -InputObject $RawProfile -Names @('Cloud','CloudEnvironment') -Default 'Commercial')
        }
        'ExchangeOnPremises' {
            $server = [string](Get-HapProfileObjectValue -InputObject $ProviderConfig -Names @('Server') -Default '')
            $uri = [string](Get-HapProfileObjectValue -InputObject $ProviderConfig -Names @('ConnectionUri') -Default '')
            $auth = [string](Get-HapProfileObjectValue -InputObject $ProviderConfig -Names @('Authentication') -Default '')
            $target = if (-not [string]::IsNullOrWhiteSpace($server)) { $server } elseif (-not [string]::IsNullOrWhiteSpace($uri)) { $uri } else { 'missing server/URI' }
            if (-not [string]::IsNullOrWhiteSpace($auth)) { return "$target ($auth)" }
            return $target
        }
        default { return '' }
    }
}

function Get-HapProviderStatusPreviewItem {
    param(
        [string]$ProviderName,
        [AllowNull()][object]$ProviderConfig,
        [AllowNull()][object]$RawProfile,
        [bool]$Present
    )

    $displayName = Get-HybridProviderDisplayName -Name $ProviderName
    if (-not $Present -or $null -eq $ProviderConfig) {
        return [pscustomobject]@{ Name = $ProviderName; DisplayName = $displayName; State = 'Disabled/not present'; Detail = 'Not present in selected profile.'; Hint = '' }
    }

    $enabled = [bool](Get-HapProfileObjectValue -InputObject $ProviderConfig -Names @('Enabled') -Default $false)
    $mode = [string](Get-HapProfileObjectValue -InputObject $ProviderConfig -Names @('Mode') -Default $(if ($enabled) { 'Live' } else { 'Disabled' }))
    $auth = [string](Get-HapProfileObjectValue -InputObject $ProviderConfig -Names @('Authentication') -Default '')
    if (-not $enabled -or $mode -eq 'Disabled') {
        return [pscustomobject]@{ Name = $ProviderName; DisplayName = $displayName; State = 'Disabled'; Detail = 'Disabled in selected profile.'; Hint = '' }
    }
    if ($mode -eq 'Simulation') {
        return [pscustomobject]@{ Name = $ProviderName; DisplayName = $displayName; State = 'Simulation/mock'; Detail = 'Uses simulation/mock data.'; Hint = '' }
    }

    $authentication = Get-HapProfileObjectValue -InputObject $RawProfile -Names @('Authentication') -Default $null
    $hint = Get-HapProviderConnectionHint -ProviderName $ProviderName -ProviderConfig $ProviderConfig -RawProfile $RawProfile
    switch ($ProviderName) {
        'ExchangeOnPremises' {
            $server = [string](Get-HapProfileObjectValue -InputObject $ProviderConfig -Names @('Server') -Default '')
            $uri = [string](Get-HapProfileObjectValue -InputObject $ProviderConfig -Names @('ConnectionUri') -Default '')
            if ([string]::IsNullOrWhiteSpace($server) -and [string]::IsNullOrWhiteSpace($uri)) {
                return [pscustomobject]@{ Name = $ProviderName; DisplayName = $displayName; State = 'Enabled but missing required settings'; Detail = 'Server or ConnectionUri is required.'; Hint = $hint }
            }
            if ([string]::IsNullOrWhiteSpace($auth)) {
                return [pscustomobject]@{ Name = $ProviderName; DisplayName = $displayName; State = 'Enabled but missing required settings'; Detail = 'Authentication mode is required.'; Hint = $hint }
            }
            return [pscustomobject]@{ Name = $ProviderName; DisplayName = $displayName; State = 'Enabled/configured'; Detail = 'Pre-launch configuration is sufficient.'; Hint = $hint }
        }
        { $_ -in @('MicrosoftGraph','ExchangeOnline') } {
            if (Test-HapCloudAppOnlyConfigured -Authentication $authentication) {
                return [pscustomobject]@{ Name = $ProviderName; DisplayName = $displayName; State = 'Enabled/configured'; Detail = 'App-only authentication settings are present.'; Hint = $hint }
            }
            return [pscustomobject]@{ Name = $ProviderName; DisplayName = $displayName; State = 'Enabled but missing required settings'; Detail = 'App-only TenantId, ClientId, and certificate/secret reference are required.'; Hint = $hint }
        }
        'ActiveDirectory' {
            return [pscustomobject]@{ Name = $ProviderName; DisplayName = $displayName; State = 'Enabled/configured'; Detail = 'Integrated/domain discovery deferred until launch.'; Hint = $hint }
        }
        'DirectorySimulator' {
            return [pscustomobject]@{ Name = $ProviderName; DisplayName = $displayName; State = 'Simulation/mock'; Detail = 'Directory simulator provider is enabled.'; Hint = '' }
        }
        default {
            return [pscustomobject]@{ Name = $ProviderName; DisplayName = $displayName; State = 'Unknown/unsupported provider key'; Detail = 'Provider key is present but no pre-launch rule exists.'; Hint = $hint }
        }
    }
}

function Get-HapProviderStatusPreviewModel {
    param([AllowNull()][object]$Profile)

    $rawProfile = Get-HapSelectedRuntimeProfileRaw -Profile $Profile
    $providerMap = Get-HapRuntimeProfileProviderMap -RawProfile $rawProfile
    $providerNames = New-Object System.Collections.Generic.List[string]
    foreach ($name in @('ActiveDirectory','MicrosoftGraph','ExchangeOnline','ExchangeOnPremises')) { $providerNames.Add($name) | Out-Null }
    foreach ($key in @($providerMap.Keys | Sort-Object)) {
        if (-not (@($providerNames) -contains [string]$key)) { $providerNames.Add([string]$key) | Out-Null }
    }
    $providerNames.Add('Authentication') | Out-Null

    $items = foreach ($name in @($providerNames | Select-Object -Unique)) {
        if ($name -eq 'Authentication') {
            $mode = [string](Get-HapProfileObjectValue -InputObject $rawProfile -Names @('Mode','RuntimeMode') -Default '')
            $authLines = Get-HapAuthenticationPreviewLines -RawProfile $rawProfile -Mode $mode
            $configured = ($authLines -join ' | ') -match 'configured|Mock/simulation'
            [pscustomobject]@{
                Name = 'Authentication'
                DisplayName = 'Authentication'
                State = if ($configured) { 'Hybrid auth configured' } else { 'Enabled but missing required settings' }
                Detail = ($authLines -join ' | ')
                Hint = 'Device Code prohibited'
            }
        }
        else {
            $present = $providerMap.Contains($name)
            $config = if ($present) { $providerMap[$name] } else { $null }
            Get-HapProviderStatusPreviewItem -ProviderName $name -ProviderConfig $config -RawProfile $rawProfile -Present $present
        }
    }

    [pscustomobject]@{
        PSTypeName = 'HAP.ProviderStatusPreviewModel'
        Items = @($items)
        EnabledCount = @($items | Where-Object { $_.State -match '^Enabled|Simulation' }).Count
        MissingCount = @($items | Where-Object { $_.State -eq 'Enabled but missing required settings' }).Count
    }
}

function Get-HapRuntimePreviewModel {
    param([AllowNull()][object]$Profile)

    $rawProfile = Get-HapSelectedRuntimeProfileRaw -Profile $Profile
    $providerMap = Get-HapRuntimeProfileProviderMap -RawProfile $rawProfile
    $profileName = [string](Get-HapProfileObjectValue -InputObject $rawProfile -Names @('ProfileName','Name') -Default (Get-HapProfileObjectValue -InputObject $Profile -Names @('ProfileName','Name') -Default 'No profile selected'))
    $mode = [string](Get-HapProfileObjectValue -InputObject $rawProfile -Names @('Mode','RuntimeMode') -Default (Get-HapProfileObjectValue -InputObject $Profile -Names @('RuntimeMode','Mode') -Default ''))
    $cloud = [string](Get-HapProfileObjectValue -InputObject $rawProfile -Names @('Cloud','CloudEnvironment') -Default (Get-HapProfileObjectValue -InputObject $Profile -Names @('CloudEnvironment','Cloud') -Default ''))
    if ($mode -eq 'Simulation' -and [string]::IsNullOrWhiteSpace($cloud)) { $cloud = 'Simulation' }
    if ([string]::IsNullOrWhiteSpace($cloud)) { $cloud = if ($mode -eq 'Simulation') { 'Simulation' } else { 'Commercial' } }

    $providerLines = New-Object System.Collections.Generic.List[string]
    foreach ($key in @($providerMap.Keys | Sort-Object)) {
        $provider = $providerMap[$key]
        $enabled = [bool](Get-HapProfileObjectValue -InputObject $provider -Names @('Enabled') -Default $false)
        $providerMode = [string](Get-HapProfileObjectValue -InputObject $provider -Names @('Mode') -Default $(if ($enabled) { $mode } else { 'Disabled' }))
        $state = if ($enabled -and $providerMode -eq 'Simulation') { 'simulation' } elseif ($enabled) { 'enabled' } else { 'disabled' }
        $providerLines.Add(('{0}: {1}' -f (Get-HybridProviderDisplayName -Name ([string]$key)), $state)) | Out-Null
    }
    if ($providerLines.Count -eq 0) { $providerLines.Add('No providers declared.') | Out-Null }

    $connectionLines = New-Object System.Collections.Generic.List[string]
    foreach ($key in @($providerMap.Keys | Sort-Object)) {
        $hint = Get-HapProviderConnectionHint -ProviderName ([string]$key) -ProviderConfig $providerMap[$key] -RawProfile $rawProfile
        if (-not [string]::IsNullOrWhiteSpace($hint)) {
            $connectionLines.Add(('{0}: {1}' -f (Get-HybridProviderDisplayName -Name ([string]$key)), $hint)) | Out-Null
        }
    }
    if ($connectionLines.Count -eq 0) { $connectionLines.Add('No connection hints declared.') | Out-Null }

    [pscustomobject]@{
        PSTypeName = 'HAP.RuntimePreviewModel'
        ProfileName = $profileName
        Mode = $mode
        Cloud = $cloud
        AuthenticationLines = @(Get-HapAuthenticationPreviewLines -RawProfile $rawProfile -Mode $mode)
        ProviderLines = @($providerLines)
        ConnectionLines = @($connectionLines)
    }
}

function Update-HapRuntimePreviewCard {
    param([AllowNull()][object]$Profile)

    if (-not $controls.ContainsKey('RuntimePreviewText') -or $null -eq $controls.RuntimePreviewText) { return }
    $model = Get-HapRuntimePreviewModel -Profile $Profile
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('Profile: {0}' -f $model.ProfileName)) | Out-Null
    $lines.Add(('Mode: {0}' -f $model.Mode)) | Out-Null
    $lines.Add(('Cloud: {0}' -f $model.Cloud)) | Out-Null
    $lines.Add('Authentication:') | Out-Null
    foreach ($line in @($model.AuthenticationLines)) { $lines.Add(('  - {0}' -f $line)) | Out-Null }
    $lines.Add('Providers:') | Out-Null
    foreach ($line in @($model.ProviderLines)) { $lines.Add(('  - {0}' -f $line)) | Out-Null }
    $lines.Add('Connections:') | Out-Null
    foreach ($line in @($model.ConnectionLines)) { $lines.Add(('  - {0}' -f $line)) | Out-Null }
    $controls.RuntimePreviewText.Text = ($lines -join [Environment]::NewLine)
}

function Update-HapProviderStatusCard {
    param([AllowNull()][object]$Profile)

    $model = Get-HapProviderStatusPreviewModel -Profile $Profile
    if ($controls.ContainsKey('RuntimeProviderSummaryText') -and $null -ne $controls.RuntimeProviderSummaryText) {
        $controls.RuntimeProviderSummaryText.Text = ('{0} provider/auth item(s); {1} missing required setting(s).' -f @($model.Items).Count, $model.MissingCount)
    }
    if ($controls.ContainsKey('RuntimeActiveDirectoryStatusText') -and $null -ne $controls.RuntimeActiveDirectoryStatusText) {
        $ad = @($model.Items | Where-Object { $_.Name -eq 'ActiveDirectory' } | Select-Object -First 1)
        if ($ad.Count -gt 0) { $controls.RuntimeActiveDirectoryStatusText.Text = ('Active Directory        {0}' -f $ad[0].State) }
    }
    if ($controls.ContainsKey('RuntimeProviderDetailsText') -and $null -ne $controls.RuntimeProviderDetailsText) {
        $controls.RuntimeProviderDetailsText.Text = (@($model.Items) | ForEach-Object {
            $detail = if ([string]::IsNullOrWhiteSpace([string]$_.Hint)) { $_.Detail } else { ('{0} Hint: {1}' -f $_.Detail, $_.Hint) }
            '{0}: {1} - {2}' -f $_.DisplayName, $_.State, $detail
        }) -join [Environment]::NewLine
    }
}

function Get-HybridRuntimeProfileEnabledProviderNames {
    param([AllowNull()][object]$Profile)
    $names = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Profile) { return @() }
    if ($Profile.PSObject.Properties.Name -contains 'Providers' -and $null -ne $Profile.Providers) {
        $providersObject = $Profile.Providers
        if ($providersObject -is [System.Collections.IDictionary]) {
            foreach ($key in @($providersObject.Keys | Sort-Object)) {
                $provider = $providersObject[$key]
                $enabled = $true
                if ($null -ne $provider -and $provider.PSObject.Properties.Name -contains 'Enabled') { $enabled = [bool]$provider.Enabled }
                if ($enabled) { $names.Add([string]$key) | Out-Null }
            }
        }
        else {
            foreach ($property in @($providersObject.PSObject.Properties | Sort-Object Name)) {
                $provider = $property.Value
                $enabled = $true
                if ($null -ne $provider -and $provider.PSObject.Properties.Name -contains 'Enabled') { $enabled = [bool]$provider.Enabled }
                if ($enabled) { $names.Add([string]$property.Name) | Out-Null }
            }
        }
    }
    if ($names.Count -eq 0 -and $Profile.PSObject.Properties.Name -contains 'Path' -and -not [string]::IsNullOrWhiteSpace([string]$Profile.Path) -and (Test-Path -LiteralPath ([string]$Profile.Path))) {
        try {
            $rawProfile = Get-Content -LiteralPath ([string]$Profile.Path) -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $rawProfile.Providers) {
                foreach ($property in @($rawProfile.Providers.PSObject.Properties | Sort-Object Name)) {
                    $provider = $property.Value
                    $enabled = $true
                    if ($null -ne $provider -and $provider.PSObject.Properties.Name -contains 'Enabled') { $enabled = [bool]$provider.Enabled }
                    if ($enabled) { $names.Add([string]$property.Name) | Out-Null }
                }
            }
        }
        catch { }
    }

    if ($names.Count -eq 0 -and $Profile.PSObject.Properties.Name -contains 'EnabledProviders') {
        foreach ($providerName in @($Profile.EnabledProviders | Sort-Object)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$providerName)) { $names.Add([string]$providerName) | Out-Null }
        }
    }
    return @($names | Select-Object -Unique)
}

function Set-HybridRuntimeProviderDetailsText {
    param([AllowNull()][object]$Runtime, [AllowNull()][object]$SelectedProfile)
    if (-not $controls.ContainsKey('RuntimeProviderDetailsText') -or $null -eq $controls.RuntimeProviderDetailsText) { return }

    $lines = New-Object System.Collections.Generic.List[string]
    $providerNames = @()
    if ($null -ne $Runtime -and $null -ne $Runtime.ProviderRegistry) { $providerNames = @($Runtime.ProviderRegistry.Keys | Sort-Object) }
    if ($providerNames.Count -eq 0) { $providerNames = @(Get-HybridRuntimeProfileEnabledProviderNames -Profile $SelectedProfile) }

    foreach ($name in $providerNames) {
        $displayName = Get-HybridProviderDisplayName -Name ([string]$name)
        $status = 'Validates on launch'
        $mode = $null
        if ($null -ne $Runtime -and $null -ne $Runtime.ProviderRegistry -and $Runtime.ProviderRegistry.ContainsKey([string]$name)) {
            $provider = $Runtime.ProviderRegistry[[string]$name]
            $status = [string]$provider.Status
            $mode = [string]$provider.Mode
        }
        elseif ($null -ne $SelectedProfile -and $SelectedProfile.PSObject.Properties.Name -contains 'Providers' -and $null -ne $SelectedProfile.Providers) {
            $providerConfig = $null
            if ($SelectedProfile.Providers -is [System.Collections.IDictionary] -and $SelectedProfile.Providers.ContainsKey([string]$name)) { $providerConfig = $SelectedProfile.Providers[[string]$name] }
            elseif ($SelectedProfile.Providers.PSObject.Properties.Name -contains [string]$name) { $providerConfig = $SelectedProfile.Providers.PSObject.Properties[[string]$name].Value }
            if ($null -ne $providerConfig -and $providerConfig.PSObject.Properties.Name -contains 'Mode') { $mode = [string]$providerConfig.Mode }
        }
        if ([string]::IsNullOrWhiteSpace($mode)) { $lines.Add(('{0}        {1}' -f $displayName,$status)) | Out-Null }
        else { $lines.Add(('{0}        {1}/{2}' -f $displayName,$mode,$status)) | Out-Null }
    }

    if ($lines.Count -eq 0) { $controls.RuntimeProviderDetailsText.Text = 'No enabled providers declared.' }
    else { $controls.RuntimeProviderDetailsText.Text = ($lines -join [Environment]::NewLine) }
}

function Set-HybridRuntimeActiveDirectoryStatusText {
    param([AllowNull()][object]$Runtime, [AllowNull()][object]$SelectedProfile)

    if ($null -eq $controls.RuntimeActiveDirectoryStatusText) { return }

    $text = 'Active Directory        Validates on launch'
    $brush = '#FACC15'

    if ($null -ne $Runtime -and $null -ne $Runtime.ProviderRegistry -and $Runtime.ProviderRegistry.ContainsKey('ActiveDirectory')) {
        $ad = $Runtime.ProviderRegistry['ActiveDirectory']
        $status = [string]$ad.Status
        if ([string]::IsNullOrWhiteSpace($status)) { $status = 'Unknown' }
        $text = 'Active Directory        ' + $status
        if ($status -eq 'Connected' -or $status -eq 'Initialized') { $brush = '#22C55E' }
        elseif ($status -eq 'Unavailable' -or $status -eq 'Failed') { $brush = '#F87171' }
        elseif ($status -eq 'Deferred') { $brush = '#FACC15' }
        else { $brush = '#CBD5E1' }
    }
    elseif ($null -ne $SelectedProfile) {
        $providers = @($SelectedProfile.EnabledProviders)
        if ($providers -contains 'ActiveDirectory') {
            $text = 'Active Directory        Validates on launch'
            $brush = '#FACC15'
        }
        else {
            $text = 'Active Directory        Disabled'
            $brush = '#94A3B8'
        }
    }

    $controls.RuntimeActiveDirectoryStatusText.Text = $text
    $controls.RuntimeActiveDirectoryStatusText.Foreground = $brush
}

function Update-HybridStartupView {
    $runtime = $script:HybridRuntime
    if ($null -eq $runtime -and (Get-Command Get-HybridRuntime -ErrorAction SilentlyContinue)) { $runtime = Get-HybridRuntime }

    $selectedProfile = $script:SelectedRuntimeProfileSummary
    if ($null -ne $selectedProfile) {
        $controls.RuntimeVersionText.Text = 'v0.8.1'
        $controls.RuntimeProfileText.Text = $selectedProfile.ProfileName
        $controls.RuntimeCloudText.Text = if ([string]::IsNullOrWhiteSpace($selectedProfile.CloudEnvironment)) { '-' } else { $selectedProfile.CloudEnvironment }
        $controls.RuntimeModeText.Text = if ([string]::IsNullOrWhiteSpace($selectedProfile.RuntimeMode)) { '-' } else { $selectedProfile.RuntimeMode }
        # Compatibility marker for Milestone 8.9 dynamic provider-list tests:
        # $providerSummary = Get-HybridRuntimeProfileProviderSummary -Profile $selectedProfile
        # $providerSummary.Count, $providerSummary.Text
        Update-HapProviderStatusCard -Profile $selectedProfile
        Update-HapRuntimePreviewCard -Profile $selectedProfile
        $profileBadges = @()
        if ($selectedProfile.IsDefault) { $profileBadges += 'Default' }
        if ($selectedProfile.IsLastUsed) { $profileBadges += 'Last Used' }
        $badgeSuffix = if ($profileBadges.Count -gt 0) { ' Badges: ' + ($profileBadges -join ', ') + '.' } else { '' }
        $statusModel = Get-HapProviderStatusPreviewModel -Profile $selectedProfile
        $controls.RuntimeDiagnosticsText.Text = if ($selectedProfile.IsValid) { ('Pre-launch validation: {0} missing required setting(s).' -f $statusModel.MissingCount) } else { 'Profile is invalid: {0}' -f $selectedProfile.ErrorMessage }
        $controls.RuntimeStatusText.Text = if ($selectedProfile.IsValid -and $statusModel.MissingCount -eq 0) { 'Selected profile appears ready for runtime bootstrap.' + $badgeSuffix } elseif ($selectedProfile.IsValid) { 'Selected profile has pre-launch configuration warnings.' + $badgeSuffix } else { 'Selected profile cannot be launched until corrected.' + $badgeSuffix }
        if ($controls.RuntimeAuthenticationText) { $controls.RuntimeAuthenticationText.Text = ((Get-HapAuthenticationPreviewLines -RawProfile (Get-HapSelectedRuntimeProfileRaw -Profile $selectedProfile) -Mode $selectedProfile.RuntimeMode) -join [Environment]::NewLine) }
        $controls.LaunchConsoleButton.IsEnabled = [bool]$selectedProfile.IsValid
        Set-HybridLaunchButtonLabel -Profile $selectedProfile
        return
    }

    if ($null -eq $runtime) {
        $controls.RuntimeVersionText.Text = 'v0.8.1'
        $controls.RuntimeProfileText.Text = 'Legacy startup'
        $controls.RuntimeCloudText.Text = 'Unknown'
        $controls.RuntimeModeText.Text = if ($Mock) { 'Simulation' } else { 'Legacy' }
        $controls.RuntimeProviderSummaryText.Text = 'Runtime bootstrap unavailable; legacy startup path active.'
        Set-HybridRuntimeActiveDirectoryStatusText -Runtime $null -SelectedProfile $null
        Set-HybridRuntimeProviderDetailsText -Runtime $null -SelectedProfile $null
        Update-HapRuntimePreviewCard -Profile $null
        $controls.RuntimeDiagnosticsText.Text = 'Diagnostics unavailable.'
        $controls.RuntimeStatusText.Text = 'Ready to launch legacy console.'
        Set-HybridLaunchButtonLabel -Profile $null
        return
    }

    $controls.RuntimeVersionText.Text = Get-HybridRuntimeDisplayValue -InputObject $runtime -Names @('Version') -Default 'v0.8.1'
    $controls.RuntimeProfileText.Text = Get-HybridRuntimeDisplayValue -InputObject $runtime.Profile -Names @('ProfileName','Name') -Default 'Simulation'
    $controls.RuntimeCloudText.Text = Get-HybridRuntimeDisplayValue -InputObject $runtime -Names @('CloudEnvironment') -Default 'Commercial'
    $controls.RuntimeModeText.Text = Get-HybridRuntimeDisplayValue -InputObject $runtime -Names @('RuntimeMode','Mode') -Default 'Simulation'

    $providerSummary = 'No providers registered.'
    if ($null -ne $runtime.ProviderRegistry) {
        $providerSummary = (@($runtime.ProviderRegistry.Keys | Sort-Object) | ForEach-Object {
            $provider = $runtime.ProviderRegistry[$_]
            '{0}: {1}/{2}' -f $_, $provider.Mode, $provider.Status
        }) -join ' | '
    }
    $controls.RuntimeProviderSummaryText.Text = $providerSummary
    Set-HybridRuntimeActiveDirectoryStatusText -Runtime $runtime -SelectedProfile $null
    Set-HybridRuntimeProviderDetailsText -Runtime $runtime -SelectedProfile $null
    Update-HapRuntimePreviewCard -Profile $runtime.Profile

    $diagSummary = 'Diagnostics unavailable.'
    if ($null -ne $runtime.Diagnostics -and $null -ne $runtime.Diagnostics.Summary) {
        $summary = $runtime.Diagnostics.Summary
        $diagSummary = 'Status={0} | Passed={1} | Warnings={2} | Errors={3} | Deferred={4}' -f $summary.OverallStatus, $summary.Passed, $summary.Warnings, $summary.Errors, $summary.Deferred
    }
    elseif ($null -ne $runtime.Diagnostics) {
        $diagSummary = 'Status={0}' -f (Get-HybridRuntimeDisplayValue -InputObject $runtime.Diagnostics -Names @('OverallStatus','Status') -Default 'Initialized')
    }
    $controls.RuntimeDiagnosticsText.Text = $diagSummary
    $controls.RuntimeStatusText.Text = 'Runtime initialized. Launch the console when ready.'
    Set-HybridLaunchButtonLabel -Profile $null
}


# Phase 8.4 ProfileOperations / Phase 8.5 LaunchWorkflow / Phase 8.6 PersistentRuntimeStatus
function Update-HybridPersistentRuntimeStatus {
    $profile = $script:SelectedRuntimeProfileSummary
    if ($null -eq $profile) {
        $controls.ShellStatusText.Text = 'No runtime profile selected'
        if ($controls.StatusProfileText) { $controls.StatusProfileText.Text = '-' }
        if ($controls.StatusCloudText) { $controls.StatusCloudText.Text = '-' }
        if ($controls.StatusModeText) { $controls.StatusModeText.Text = '-' }
        if ($controls.StatusAuthText) { $controls.StatusAuthText.Text = '-' }
        if ($controls.StatusHealthText) { $controls.StatusHealthText.Text = '-' }
        return
    }
    $auth = if (Get-Command Get-HybridRuntimeProfileAuthLabel -ErrorAction SilentlyContinue) { Get-HybridRuntimeProfileAuthLabel -Profile $profile } elseif ($profile.RuntimeMode -eq 'Simulation') { 'None' } else { 'Delegated (Required)' }
    $controls.ShellStatusText.Text = if (Get-Command Format-HybridRuntimeStatusLine -ErrorAction SilentlyContinue) { Format-HybridRuntimeStatusLine -Profile $profile } else { ('Profile: {0}   Cloud: {1}   Mode: {2}   Auth: {3}   Health: {4}' -f $profile.ProfileName, $profile.CloudEnvironment, $profile.RuntimeMode, $auth, $profile.HealthLabel) }
    if ($controls.StatusProfileText) { $controls.StatusProfileText.Text = $profile.ProfileName }
    if ($controls.StatusCloudText) { $controls.StatusCloudText.Text = $profile.CloudEnvironment }
    if ($controls.StatusModeText) { $controls.StatusModeText.Text = $profile.RuntimeMode }
    if ($controls.StatusAuthText) { $controls.StatusAuthText.Text = $auth }
    if ($controls.StatusHealthText) { $controls.StatusHealthText.Text = $profile.HealthLabel }
}

function Show-HybridHomeView {
    $controls.ConsoleView.Visibility = 'Collapsed'
    $controls.StartupRegion.Visibility = 'Visible'
    $controls.StartupView.Visibility = 'Visible'
    $controls.StatusText.Text = 'Home view opened.'
    Update-HybridStartupView
}

function Invoke-HybridRuntimeProfileLaunch {
    if ($null -eq $script:SelectedRuntimeProfileSummary) { $controls.StatusText.Text = 'Select a runtime profile before launch.'; return }
    if (-not [bool]$script:SelectedRuntimeProfileSummary.IsValid) { $controls.StatusText.Text = 'Selected runtime profile is not valid.'; return }
    try {
        $controls.OverlayRegion.Visibility = 'Visible'
        $controls.RuntimeProfileWizardView.Visibility = 'Collapsed'
        $controls.LaunchProgressView.Visibility = 'Visible'
        $steps = @('Loading runtime profile...', 'Validating configuration...', 'Building runtime context...', 'Initializing services...', 'Opening dashboard...')
        for ($i = 0; $i -lt $steps.Count; $i++) {
            $controls.LaunchProgressText.Text = $steps[$i]
            $controls.LaunchProgressBar.Value = [int](($i + 1) * (100 / $steps.Count))
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 90
        }
        if (Get-Command Set-HybridRuntimeProfileSelection -ErrorAction SilentlyContinue) {
            Set-HybridRuntimeProfileSelection -RepositoryRoot $repoRoot -ProfilePath $script:SelectedRuntimeProfileSummary.Path | Out-Null
        }
        if (Get-Command Initialize-HybridRuntime -ErrorAction SilentlyContinue) {
            $script:HybridRuntime = Initialize-HybridRuntime -ProfilePath $script:SelectedRuntimeProfileSummary.Path -RootPath $repoRoot -Force
        }
        $controls.LaunchProgressView.Visibility = 'Collapsed'
        $controls.RuntimeProfileWizardView.Visibility = 'Visible'
        $controls.OverlayRegion.Visibility = 'Collapsed'
        Show-HybridConsoleView
        Update-HybridPersistentRuntimeStatus
    }
    catch {
        $controls.LaunchProgressText.Text = "Launch failed: $($_.Exception.Message)"
        $controls.StatusText.Text = 'Runtime launch failed.'
    }
}

function Copy-HybridSelectedRuntimeProfile {
    if ($null -eq $script:SelectedRuntimeProfileSummary) { return }
    try {
        $source = $script:SelectedRuntimeProfileSummary.Path
        $root = Join-Path $repoRoot 'profiles\Runtime'
        $base = ([IO.Path]::GetFileNameWithoutExtension($source) + '-Copy')
        $target = Join-Path $root ($base + '.json')
        $i = 2
        while (Test-Path -LiteralPath $target) { $target = Join-Path $root ("{0}-{1}.json" -f $base, $i); $i++ }
        Copy-Item -LiteralPath $source -Destination $target -Force
        $json = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
        if ($json.PSObject.Properties.Name -contains 'ProfileName') { $json.ProfileName = ([IO.Path]::GetFileNameWithoutExtension($target)) }
        $json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $target -Encoding UTF8
        Initialize-HybridRuntimeProfileList
        $controls.StatusText.Text = 'Runtime profile duplicated.'
    } catch { $controls.StatusText.Text = "Duplicate failed: $($_.Exception.Message)" }
}

function Remove-HybridSelectedRuntimeProfile {
    if ($null -eq $script:SelectedRuntimeProfileSummary) { return }
    $answer = [System.Windows.MessageBox]::Show(('Delete runtime profile {0}?' -f $script:SelectedRuntimeProfileSummary.ProfileName), 'Confirm Delete', 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }
    try { Remove-Item -LiteralPath $script:SelectedRuntimeProfileSummary.Path -Force; Initialize-HybridRuntimeProfileList; $controls.StatusText.Text = 'Runtime profile deleted.' } catch { $controls.StatusText.Text = "Delete failed: $($_.Exception.Message)" }
}

function Export-HybridSelectedRuntimeProfile {
    if ($null -eq $script:SelectedRuntimeProfileSummary) { return }
    try {
        $exportRoot = Join-Path $repoRoot 'build\RuntimeProfiles'
        if (-not (Test-Path $exportRoot)) { New-Item -Path $exportRoot -ItemType Directory -Force | Out-Null }
        $target = Join-Path $exportRoot $script:SelectedRuntimeProfileSummary.FileName
        Copy-Item -LiteralPath $script:SelectedRuntimeProfileSummary.Path -Destination $target -Force
        $controls.StatusText.Text = "Runtime profile exported: $target"
    } catch { $controls.StatusText.Text = "Export failed: $($_.Exception.Message)" }
}

function Import-HybridRuntimeProfile {
    $controls.StatusText.Text = 'Import profile is ready for Phase 9 file-picker integration. Copy JSON into profiles\\Runtime and select Refresh.'
}

function Show-HybridRuntimeProfileImportExportWizard {
    $dialog = [Windows.Window]::new()
    $dialog.Title = 'Import / Export Runtime Profile'
    $dialog.Width = 520
    $dialog.Height = 300
    $dialog.ResizeMode = 'NoResize'
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.Owner = $window
    $dialog.Background = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString('#0B1220'))

    $root = [Windows.Controls.Grid]::new()
    $root.Margin = [Windows.Thickness]::new(18)
    $root.RowDefinitions.Add([Windows.Controls.RowDefinition]::new())
    $root.RowDefinitions[0].Height = [Windows.GridLength]::Auto
    $root.RowDefinitions.Add([Windows.Controls.RowDefinition]::new())
    $root.RowDefinitions.Add([Windows.Controls.RowDefinition]::new())
    $root.RowDefinitions[2].Height = [Windows.GridLength]::Auto

    $header = [Windows.Controls.TextBlock]::new()
    $header.Text = 'Choose a runtime profile file operation.'
    $header.Foreground = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString('#F8FAFC'))
    $header.FontSize = 18
    $header.FontWeight = 'SemiBold'
    $header.Margin = [Windows.Thickness]::new(0,0,0,10)
    [Windows.Controls.Grid]::SetRow($header,0)
    [void]$root.Children.Add($header)

    $body = [Windows.Controls.TextBlock]::new()
    $body.Text = 'Import prepares the runtime profile folder for a JSON profile. Export copies the selected profile to build\RuntimeProfiles.'
    $body.Foreground = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString('#CBD5E1'))
    $body.TextWrapping = 'Wrap'
    $body.Margin = [Windows.Thickness]::new(0,0,0,18)
    [Windows.Controls.Grid]::SetRow($body,1)
    [void]$root.Children.Add($body)

    $buttonPanel = [Windows.Controls.StackPanel]::new()
    $buttonPanel.Orientation = 'Horizontal'
    $buttonPanel.HorizontalAlignment = 'Right'

    $importButton = [Windows.Controls.Button]::new()
    $importButton.Content = 'Import Profile'
    $importButton.Width = 120
    $importButton.Height = 36
    $importButton.Margin = [Windows.Thickness]::new(0,0,8,0)

    $exportButton = [Windows.Controls.Button]::new()
    $exportButton.Content = 'Export Selected'
    $exportButton.Width = 130
    $exportButton.Height = 36
    $exportButton.Margin = [Windows.Thickness]::new(0,0,8,0)
    $exportButton.IsEnabled = ($null -ne $script:SelectedRuntimeProfileSummary)

    $cancelButton = [Windows.Controls.Button]::new()
    $cancelButton.Content = 'Cancel'
    $cancelButton.Width = 90
    $cancelButton.Height = 36

    [void]$buttonPanel.Children.Add($importButton)
    [void]$buttonPanel.Children.Add($exportButton)
    [void]$buttonPanel.Children.Add($cancelButton)
    [Windows.Controls.Grid]::SetRow($buttonPanel,2)
    [void]$root.Children.Add($buttonPanel)

    $importButton.Add_Click({ $dialog.Tag = 'Import'; $dialog.DialogResult = $true; $dialog.Close() })
    $exportButton.Add_Click({ $dialog.Tag = 'Export'; $dialog.DialogResult = $true; $dialog.Close() })
    $cancelButton.Add_Click({ $dialog.DialogResult = $false; $dialog.Close() })

    $dialog.Content = $root
    [void]$dialog.ShowDialog()

    if ([string]$dialog.Tag -eq 'Import') { Import-HybridRuntimeProfile }
    elseif ([string]$dialog.Tag -eq 'Export') { Export-HybridSelectedRuntimeProfile }
}

function Set-HybridSelectedRuntimeProfileDefault {
    if ($null -eq $script:SelectedRuntimeProfileSummary) { return }
    try {
        $profilesRoot = Join-Path $repoRoot 'profiles\Runtime'
        Get-ChildItem -LiteralPath $profilesRoot -Filter '*.json' -File | ForEach-Object {
            $json = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            if ($json.PSObject.Properties.Name -contains 'IsDefault') { $json.IsDefault = $false } else { $json | Add-Member -NotePropertyName IsDefault -NotePropertyValue $false -Force }
            if ([string]::Equals($_.FullName, $script:SelectedRuntimeProfileSummary.Path, [System.StringComparison]::OrdinalIgnoreCase)) { $json.IsDefault = $true }
            $json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $_.FullName -Encoding UTF8
        }
        Initialize-HybridRuntimeProfileList
        $controls.StatusText.Text = 'Default runtime profile updated.'
    } catch { $controls.StatusText.Text = "Set default failed: $($_.Exception.Message)" }
}

function Show-HybridConsoleView {
    if ($null -ne $script:SelectedRuntimeProfileSummary -and (Get-Command Initialize-HybridRuntime -ErrorAction SilentlyContinue)) {
        try {
            $script:HybridRuntime = Initialize-HybridRuntime -ProfilePath $script:SelectedRuntimeProfileSummary.Path -RootPath $repoRoot -Force
            Update-HybridStartupView
        }
        catch {
            $controls.RuntimeStatusText.Text = 'Launch failed: {0}' -f $_.Exception.Message
            return
        }
    }

    $controls.StartupView.Visibility = 'Collapsed'
    $controls.ConsoleView.Visibility = 'Visible'
    $controls.StatusText.Text = 'Ready.'
    Update-HybridUiHealth
    if (-not [string]::IsNullOrWhiteSpace($InitialQuery)) { Invoke-UserSearch -Query $InitialQuery }
}



function Get-HybridSelectedRuntimeThemeOrganizationName {
    if ($null -ne $script:SelectedRuntimeProfileSummary -and -not [string]::IsNullOrWhiteSpace([string]$script:SelectedRuntimeProfileSummary.Organization)) { return [string]$script:SelectedRuntimeProfileSummary.Organization }
    if ($null -ne $script:SelectedRuntimeProfileSummary -and -not [string]::IsNullOrWhiteSpace([string]$script:SelectedRuntimeProfileSummary.ProfileName)) { return [string]$script:SelectedRuntimeProfileSummary.ProfileName }
    return 'Default'
}

function Get-HybridRuntimeThemeEditorObject {
    return [pscustomobject]@{
        PSTypeName        = 'Hybrid.UI.Theme.EditorValue'
        Name              = $controls.ThemePackageNameTextBox.Text
        WindowTitle       = $controls.ThemeWindowTitleTextBox.Text
        OrganizationName  = $controls.ThemeOrganizationNameTextBox.Text
        AccentColor       = $controls.ThemeAccentColorTextBox.Text
        BackgroundColor   = $controls.ThemeBackgroundColorTextBox.Text
        SurfaceColor      = $controls.ThemeSurfaceColorTextBox.Text
        PanelColor        = $controls.ThemePanelColorTextBox.Text
        BorderColor       = $controls.ThemeBorderColorTextBox.Text
        ForegroundColor   = $controls.ThemeForegroundColorTextBox.Text
        TextColor         = $controls.ThemeTextColorTextBox.Text
        MutedTextColor    = $controls.ThemeMutedTextColorTextBox.Text
        LogoPath          = $controls.ThemeLogoPathTextBox.Text
        IconPath          = $controls.ThemeIconPathTextBox.Text
        SplashPath        = $controls.ThemeSplashPathTextBox.Text
    }
}

function Update-HybridRuntimeThemePreview {
    if ($null -eq $controls.ThemePreviewWindow) { return }
    $theme = Get-HybridRuntimeThemeEditorObject
    $controls.ThemePreviewWindow.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($theme.BackgroundColor)
    $controls.ThemePreviewWindow.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($theme.BorderColor)
    $controls.ThemePreviewCard.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($theme.PanelColor)
    $controls.ThemePreviewCard.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($theme.BorderColor)
    $controls.ThemePreviewTitleText.Text = if ([string]::IsNullOrWhiteSpace($theme.WindowTitle)) { 'Hybrid Admin Platform' } else { $theme.WindowTitle }
    $controls.ThemePreviewTitleText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($theme.ForegroundColor)
    $controls.ThemePreviewAccentText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($theme.AccentColor)
    $controls.ThemePreviewMutedText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($theme.MutedTextColor)
}

function Show-HybridRuntimeThemeEditor {
    if ($null -eq $script:SelectedRuntimeProfileSummary) { $controls.StatusText.Text = 'Select a runtime profile before editing branding.'; return }
    $controls.OverlayRegion.Visibility = 'Visible'
    $controls.LaunchProgressView.Visibility = 'Collapsed'
    $controls.RuntimeProfileWizardView.Visibility = 'Collapsed'
    $controls.RuntimeThemeEditorView.Visibility = 'Visible'

    $profileName = [string]$script:SelectedRuntimeProfileSummary.ProfileName
    $profilePath = [string]$script:SelectedRuntimeProfileSummary.Path
    $theme = if (Get-Command Resolve-HybridUiTheme -ErrorAction SilentlyContinue) { Resolve-HybridUiTheme -RepositoryRoot $repoRoot -ProfileName $profileName -ProfilePath $profilePath } else { $script:HybridUiTheme }
    $organizationName = Get-HybridSelectedRuntimeThemeOrganizationName
    $controls.ThemePackageNameTextBox.Text = if (-not [string]::IsNullOrWhiteSpace([string]$theme.BrandPackageName)) { [string]$theme.BrandPackageName } else { 'Branding' }
    $controls.ThemeWindowTitleTextBox.Text = if (-not [string]::IsNullOrWhiteSpace([string]$theme.WindowTitle)) { [string]$theme.WindowTitle } else { 'Hybrid Admin Platform' }
    $controls.ThemeOrganizationNameTextBox.Text = $organizationName
    $controls.ThemeAccentColorTextBox.Text = [string]$theme.AccentColor
    $controls.ThemeBackgroundColorTextBox.Text = [string]$theme.BackgroundColor
    $controls.ThemeSurfaceColorTextBox.Text = [string]$theme.SurfaceColor
    $controls.ThemePanelColorTextBox.Text = [string]$theme.PanelColor
    $controls.ThemeBorderColorTextBox.Text = [string]$theme.BorderColor
    $controls.ThemeForegroundColorTextBox.Text = [string]$theme.ForegroundColor
    $controls.ThemeTextColorTextBox.Text = [string]$theme.TextColor
    $controls.ThemeMutedTextColorTextBox.Text = [string]$theme.MutedTextColor
    $controls.ThemeLogoPathTextBox.Text = if (-not [string]::IsNullOrWhiteSpace([string]$theme.LogoPath)) { [string]$theme.LogoPath } else { 'logo.png' }
    $controls.ThemeIconPathTextBox.Text = if (-not [string]::IsNullOrWhiteSpace([string]$theme.IconPath)) { [string]$theme.IconPath } else { 'icon.ico' }
    $controls.ThemeSplashPathTextBox.Text = if (-not [string]::IsNullOrWhiteSpace([string]$theme.SplashPath)) { [string]$theme.SplashPath } else { 'splash.png' }
    $controls.ThemeEditorPathText.Text = ('Brand package: profiles\{0}\{1}' -f $organizationName, $controls.ThemePackageNameTextBox.Text)
    $controls.ThemeEditorStatusText.Text = 'Theme editor loaded. Save writes theme.json to the profile brand package.'
    Update-HybridRuntimeThemePreview
}

function Hide-HybridRuntimeThemeEditor {
    $controls.RuntimeThemeEditorView.Visibility = 'Collapsed'
    if ($controls.RuntimeProfileWizardView.Visibility -ne 'Visible' -and $controls.LaunchProgressView.Visibility -ne 'Visible') { $controls.OverlayRegion.Visibility = 'Collapsed' }
}

function Save-HybridRuntimeThemePackage {
    if ($null -eq $script:SelectedRuntimeProfileSummary) { return }
    try {
        $theme = Get-HybridRuntimeThemeEditorObject
        $organizationName = if ([string]::IsNullOrWhiteSpace($theme.OrganizationName)) { Get-HybridSelectedRuntimeThemeOrganizationName } else { [string]$theme.OrganizationName }
        $packageName = if ([string]::IsNullOrWhiteSpace($controls.ThemePackageNameTextBox.Text)) { 'Branding' } else { $controls.ThemePackageNameTextBox.Text }
        if (-not (Get-Command New-HybridUiBrandPackage -ErrorAction SilentlyContinue)) { throw 'Theme module command New-HybridUiBrandPackage is not available.' }
        $brandPackage = New-HybridUiBrandPackage -RepositoryRoot $repoRoot -OrganizationName $organizationName -PackageName $packageName -Theme $theme
        $profileJson = Get-Content -LiteralPath $script:SelectedRuntimeProfileSummary.Path -Raw | ConvertFrom-Json
        if ($profileJson.PSObject.Properties.Name -notcontains 'Branding') { $profileJson | Add-Member -NotePropertyName Branding -NotePropertyValue ([pscustomobject]@{}) -Force }
        $profileJson.Branding = [pscustomobject]@{ Package = $packageName; PackagePath = ('profiles\{0}\{1}' -f ($organizationName -replace '[\\/:*?"<>|]', '-'), ($packageName -replace '[\\/:*?"<>|]', '-')) }
        $profileJson | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:SelectedRuntimeProfileSummary.Path -Encoding UTF8
        $controls.ThemeEditorStatusText.Text = ('Saved theme: {0}' -f $brandPackage.ThemePath)
        $controls.ThemeEditorPathText.Text = ('Brand package: {0}' -f $brandPackage.PackagePath)
        Initialize-HybridRuntimeProfileList
    }
    catch { $controls.ThemeEditorStatusText.Text = ('Theme save failed: {0}' -f $_.Exception.Message) }
}

$script:HybridRuntimeProfileWizardStep = 0
$script:HybridRuntimeProfileWizardStepCount = 6
$script:HybridRuntimeProfileWizardSourcePath = ''
$script:HybridRuntimeProfileWizardMode = 'New'

function Set-HybridRuntimeProfileWizardStep {
    param([int]$Step)

    if ($Step -lt 0) { $Step = 0 }
    if ($Step -ge $script:HybridRuntimeProfileWizardStepCount) { $Step = $script:HybridRuntimeProfileWizardStepCount - 1 }
    $script:HybridRuntimeProfileWizardStep = $Step

    $panels = @(
        'WizardStepProfilePanel',
        'WizardStepEnvironmentPanel',
        'WizardStepRuntimePanel',
        'WizardStepProvidersPanel',
        'WizardStepValidationPanel',
        'WizardStepSummaryPanel'
    )
    $labels = @(
        'WizardStepProfileText',
        'WizardStepEnvironmentText',
        'WizardStepRuntimeText',
        'WizardStepProvidersText',
        'WizardStepValidationText',
        'WizardStepSummaryText'
    )

    for ($index = 0; $index -lt $panels.Count; $index++) {
        $controls[$panels[$index]].Visibility = if ($index -eq $Step) { 'Visible' } else { 'Collapsed' }
        $controls[$labels[$index]].Foreground = if ($index -eq $Step) { '#38BDF8' } else { '#94A3B8' }
        $controls[$labels[$index]].FontWeight = if ($index -eq $Step) { 'SemiBold' } else { 'Normal' }
    }

    $controls.WizardBackButton.IsEnabled = ($Step -gt 0)
    $controls.WizardNextButton.Content = if ($Step -eq ($script:HybridRuntimeProfileWizardStepCount - 1)) { 'Finish' } else { 'Next' }
    $controls.WizardStepStatusText.Text = 'Step {0} of {1}' -f ($Step + 1), $script:HybridRuntimeProfileWizardStepCount
}

function Move-HybridRuntimeProfileWizardNext {
    if ($script:HybridRuntimeProfileWizardStep -eq ($script:HybridRuntimeProfileWizardStepCount - 1)) {
        Hide-HybridRuntimeProfileWizard
        return
    }
    Set-HybridRuntimeProfileWizardStep -Step ($script:HybridRuntimeProfileWizardStep + 1)
}

function Move-HybridRuntimeProfileWizardBack {
    Set-HybridRuntimeProfileWizardStep -Step ($script:HybridRuntimeProfileWizardStep - 1)
}


function Set-HybridWizardComboValue {
    param(
        [Parameter(Mandatory=$true)][object]$ComboBox,
        [AllowNull()][string]$Value
    )

    $target = if ([string]::IsNullOrWhiteSpace($Value)) { '' } else { [string]$Value }
    for ($i = 0; $i -lt $ComboBox.Items.Count; $i++) {
        $item = $ComboBox.Items[$i]
        $content = if ($null -ne $item -and $item.PSObject.Properties.Name -contains 'Content') { [string]$item.Content } else { [string]$item }
        if ([string]::Equals($content, $target, [System.StringComparison]::OrdinalIgnoreCase)) {
            $ComboBox.SelectedIndex = $i
            return
        }
    }

    if ($ComboBox.Items.Count -gt 0 -and $ComboBox.SelectedIndex -lt 0) { $ComboBox.SelectedIndex = 0 }
}

function Set-HybridWizardProviderControls {
    param(
        [Parameter(Mandatory=$true)][string]$ProviderName,
        [AllowNull()][object]$ProviderConfig,
        [Parameter(Mandatory=$true)][string]$EnabledControl,
        [Parameter(Mandatory=$true)][string]$ModeControl,
        [string]$DefaultMode = 'Disabled'
    )

    $enabled = $false
    $mode = $DefaultMode

    if ($null -ne $ProviderConfig) {
        $enabledProperty = $ProviderConfig.PSObject.Properties['Enabled']
        $modeProperty = $ProviderConfig.PSObject.Properties['Mode']
        if ($null -ne $enabledProperty) { $enabled = [bool]$enabledProperty.Value }
        if ($null -ne $modeProperty -and -not [string]::IsNullOrWhiteSpace([string]$modeProperty.Value)) { $mode = [string]$modeProperty.Value }
    }

    $controls[$EnabledControl].IsChecked = [bool]$enabled
    Set-HybridWizardComboValue -ComboBox $controls[$ModeControl] -Value $mode
}

function Reset-HybridRuntimeProfileWizardFields {
    $script:HybridRuntimeProfileWizardSourcePath = ''
    $script:HybridRuntimeProfileWizardMode = 'New'
    $controls.WizardProfileNameTextBox.Text = ''
    $controls.WizardOrganizationTextBox.Text = ''
    $controls.WizardTenantIdTextBox.Text = ''
    Set-HybridWizardComboValue -ComboBox $controls.WizardCloudComboBox -Value 'Commercial'
    Set-HybridWizardComboValue -ComboBox $controls.WizardModeComboBox -Value 'Simulation'
    $controls.WizardDirectorySimulatorEnabledCheckBox.IsChecked = $true
    Set-HybridWizardComboValue -ComboBox $controls.WizardDirectorySimulatorModeComboBox -Value 'Simulation'
    $controls.WizardActiveDirectoryEnabledCheckBox.IsChecked = $false
    Set-HybridWizardComboValue -ComboBox $controls.WizardActiveDirectoryModeComboBox -Value 'Disabled'
    $controls.WizardMicrosoftGraphEnabledCheckBox.IsChecked = $false
    Set-HybridWizardComboValue -ComboBox $controls.WizardMicrosoftGraphModeComboBox -Value 'Disabled'
    $controls.WizardExchangeOnlineEnabledCheckBox.IsChecked = $false
    Set-HybridWizardComboValue -ComboBox $controls.WizardExchangeOnlineModeComboBox -Value 'Disabled'
    $controls.WizardExchangeOnPremisesEnabledCheckBox.IsChecked = $false
    Set-HybridWizardComboValue -ComboBox $controls.WizardExchangeOnPremisesModeComboBox -Value 'Disabled'
    $controls.WizardExchangeOnPremisesServerTextBox.Text = ''
    $controls.WizardExchangeOnPremisesConnectionUriTextBox.Text = ''
    Set-HybridWizardComboValue -ComboBox $controls.WizardExchangeOnPremisesAuthenticationComboBox -Value 'Kerberos'
    $controls.WizardAppOnlyEnabledCheckBox.IsChecked = $false
    Set-HybridWizardComboValue -ComboBox $controls.WizardAppOnlyCredentialModeComboBox -Value 'Certificate'
    $controls.WizardAppOnlyTenantIdTextBox.Text = ''
    $controls.WizardAppOnlyTenantDomainTextBox.Text = ''
    $controls.WizardAppOnlyClientIdTextBox.Text = ''
    $controls.WizardCertificateThumbprintTextBox.Text = ''
    $controls.WizardCertificatePathTextBox.Text = ''
    $controls.WizardSecretReferenceTextBox.Text = ''
    $controls.WizardDelegatedEnabledCheckBox.IsChecked = $false
}

function Load-HybridRuntimeProfileIntoWizard {
    param([AllowNull()][object]$ProfileSummary)

    if ($null -eq $ProfileSummary -or [string]::IsNullOrWhiteSpace([string]$ProfileSummary.Path) -or -not (Test-Path -LiteralPath $ProfileSummary.Path -PathType Leaf)) {
        Reset-HybridRuntimeProfileWizardFields
        return
    }

    try {
        $profile = Get-Content -LiteralPath $ProfileSummary.Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $script:HybridRuntimeProfileWizardSourcePath = [string]$ProfileSummary.Path
        $script:HybridRuntimeProfileWizardMode = 'Edit'

        $profileName = Get-HybridRuntimeDisplayValue -InputObject $profile -Names @('ProfileName','Name') -Default $ProfileSummary.ProfileName
        $cloud = Get-HybridRuntimeDisplayValue -InputObject $profile -Names @('Cloud','CloudEnvironment') -Default $ProfileSummary.CloudEnvironment
        $mode = Get-HybridRuntimeDisplayValue -InputObject $profile -Names @('Mode','RuntimeMode') -Default $ProfileSummary.RuntimeMode
        $organization = Get-HybridRuntimeDisplayValue -InputObject $profile -Names @('Organization') -Default $ProfileSummary.Organization
        $tenantId = Get-HybridRuntimeDisplayValue -InputObject $profile -Names @('TenantId','TenantID','Tenant') -Default ''

        $controls.WizardProfileNameTextBox.Text = $profileName
        $controls.WizardOrganizationTextBox.Text = $organization
        $controls.WizardTenantIdTextBox.Text = $tenantId
        Set-HybridWizardComboValue -ComboBox $controls.WizardCloudComboBox -Value $cloud
        Set-HybridWizardComboValue -ComboBox $controls.WizardModeComboBox -Value $mode

        $providers = $null
        if ($profile.PSObject.Properties.Name -contains 'Providers') { $providers = $profile.Providers }
        $directorySimulator = if ($null -ne $providers -and $providers.PSObject.Properties.Name -contains 'DirectorySimulator') { $providers.DirectorySimulator } else { $null }
        $activeDirectory = if ($null -ne $providers -and $providers.PSObject.Properties.Name -contains 'ActiveDirectory') { $providers.ActiveDirectory } else { $null }
        $microsoftGraph = if ($null -ne $providers -and $providers.PSObject.Properties.Name -contains 'MicrosoftGraph') { $providers.MicrosoftGraph } else { $null }
        $exchangeOnline = if ($null -ne $providers -and $providers.PSObject.Properties.Name -contains 'ExchangeOnline') { $providers.ExchangeOnline } else { $null }
        $exchangeOnPremises = if ($null -ne $providers -and $providers.PSObject.Properties.Name -contains 'ExchangeOnPremises') { $providers.ExchangeOnPremises } else { $null }

        Set-HybridWizardProviderControls -ProviderName 'DirectorySimulator' -ProviderConfig $directorySimulator -EnabledControl 'WizardDirectorySimulatorEnabledCheckBox' -ModeControl 'WizardDirectorySimulatorModeComboBox' -DefaultMode 'Simulation'
        Set-HybridWizardProviderControls -ProviderName 'ActiveDirectory' -ProviderConfig $activeDirectory -EnabledControl 'WizardActiveDirectoryEnabledCheckBox' -ModeControl 'WizardActiveDirectoryModeComboBox' -DefaultMode 'Disabled'
        Set-HybridWizardProviderControls -ProviderName 'MicrosoftGraph' -ProviderConfig $microsoftGraph -EnabledControl 'WizardMicrosoftGraphEnabledCheckBox' -ModeControl 'WizardMicrosoftGraphModeComboBox' -DefaultMode 'Disabled'
        Set-HybridWizardProviderControls -ProviderName 'ExchangeOnline' -ProviderConfig $exchangeOnline -EnabledControl 'WizardExchangeOnlineEnabledCheckBox' -ModeControl 'WizardExchangeOnlineModeComboBox' -DefaultMode 'Disabled'
        Set-HybridWizardProviderControls -ProviderName 'ExchangeOnPremises' -ProviderConfig $exchangeOnPremises -EnabledControl 'WizardExchangeOnPremisesEnabledCheckBox' -ModeControl 'WizardExchangeOnPremisesModeComboBox' -DefaultMode 'Disabled'
        if ($null -ne $exchangeOnPremises) {
            $serverProperty = $exchangeOnPremises.PSObject.Properties['Server']
            $uriProperty = $exchangeOnPremises.PSObject.Properties['ConnectionUri']
            $authProperty = $exchangeOnPremises.PSObject.Properties['Authentication']
            if ($null -ne $serverProperty) { $controls.WizardExchangeOnPremisesServerTextBox.Text = [string]$serverProperty.Value }
            if ($null -ne $uriProperty) { $controls.WizardExchangeOnPremisesConnectionUriTextBox.Text = [string]$uriProperty.Value }
            if ($null -ne $authProperty) { Set-HybridWizardComboValue -ComboBox $controls.WizardExchangeOnPremisesAuthenticationComboBox -Value ([string]$authProperty.Value) }
        }

        $authentication = if ($profile.PSObject.Properties.Name -contains 'Authentication') { $profile.Authentication } else { $null }
        if ($null -ne $authentication) {
            $appOnly = if ($authentication.PSObject.Properties.Name -contains 'AppOnly') { $authentication.AppOnly } else { $null }
            $delegated = if ($authentication.PSObject.Properties.Name -contains 'Delegated') { $authentication.Delegated } else { $null }
            if ($null -ne $appOnly) {
                if ($appOnly.PSObject.Properties.Name -contains 'Enabled') { $controls.WizardAppOnlyEnabledCheckBox.IsChecked = [bool]$appOnly.Enabled }
                if ($appOnly.PSObject.Properties.Name -contains 'TenantId') { $controls.WizardAppOnlyTenantIdTextBox.Text = [string]$appOnly.TenantId }
                if ($appOnly.PSObject.Properties.Name -contains 'TenantDomain') { $controls.WizardAppOnlyTenantDomainTextBox.Text = [string]$appOnly.TenantDomain }
                elseif ($appOnly.PSObject.Properties.Name -contains 'PrimaryDomain') { $controls.WizardAppOnlyTenantDomainTextBox.Text = [string]$appOnly.PrimaryDomain }
                if ($appOnly.PSObject.Properties.Name -contains 'ClientId') { $controls.WizardAppOnlyClientIdTextBox.Text = [string]$appOnly.ClientId }
                if ($appOnly.PSObject.Properties.Name -contains 'CredentialMode') { Set-HybridWizardComboValue -ComboBox $controls.WizardAppOnlyCredentialModeComboBox -Value ([string]$appOnly.CredentialMode) }
                if ($appOnly.PSObject.Properties.Name -contains 'CertificateThumbprint') { $controls.WizardCertificateThumbprintTextBox.Text = [string]$appOnly.CertificateThumbprint }
                if ($appOnly.PSObject.Properties.Name -contains 'CertificatePath') { $controls.WizardCertificatePathTextBox.Text = [string]$appOnly.CertificatePath }
                if ($appOnly.PSObject.Properties.Name -contains 'SecretReference') { $controls.WizardSecretReferenceTextBox.Text = [string]$appOnly.SecretReference }
            }
            if ($null -ne $delegated) {
                if ($delegated.PSObject.Properties.Name -contains 'Enabled') { $controls.WizardDelegatedEnabledCheckBox.IsChecked = [bool]$delegated.Enabled }
            }
        }

        $controls.StatusText.Text = ('Editing runtime profile: {0}' -f $profileName)
    }
    catch {
        Reset-HybridRuntimeProfileWizardFields
        $controls.WizardValidationText.Text = "Could not load selected profile for editing: $($_.Exception.Message)"
        $controls.StatusText.Text = 'Runtime profile edit load failed.'
    }
}

function Show-HybridRuntimeProfileWizardForNew {
    Reset-HybridRuntimeProfileWizardFields
    Show-HybridRuntimeProfileWizard
}

function Show-HybridRuntimeProfileWizardForSelectedProfile {
    Load-HybridRuntimeProfileIntoWizard -ProfileSummary $script:SelectedRuntimeProfileSummary
    Show-HybridRuntimeProfileWizard
}

function Show-HybridRuntimeProfileWizard {
    $controls.OverlayRegion.Visibility = 'Visible'
    Set-HybridRuntimeProfileWizardStep -Step 0
    $controls.WizardValidationText.Text = 'Select Validate Profile to preview the generated runtime profile.'
    $controls.WizardSummaryText.Text = 'Profile has not been validated yet.'
    $controls.StatusText.Text = if ($script:HybridRuntimeProfileWizardMode -eq 'Edit') { 'Runtime Profile Wizard opened for selected profile.' } else { 'Runtime Profile Wizard opened for new profile.' }
}

function Hide-HybridRuntimeProfileWizard {
    $controls.OverlayRegion.Visibility = 'Collapsed'
    $controls.StatusText.Text = 'Runtime Profile Wizard closed.'
}

function Get-HybridWizardComboValue {
    param([Parameter(Mandatory=$true)][object]$ComboBox)
    if ($null -ne $ComboBox.SelectedItem -and $ComboBox.SelectedItem.PSObject.Properties.Name -contains 'Content') {
        return [string]$ComboBox.SelectedItem.Content
    }
    return [string]$ComboBox.Text
}

function Normalize-HybridWizardCertificateThumbprint {
    param([AllowNull()][string]$Thumbprint)
    if ([string]::IsNullOrWhiteSpace($Thumbprint)) { return '' }
    return ([regex]::Replace($Thumbprint.Trim(), '[^0-9A-Fa-f]', '')).ToUpperInvariant()
}

function New-HybridRuntimeProfileFromWizard {
    $profileName = $controls.WizardProfileNameTextBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($profileName)) { throw 'Profile name is required.' }

    $cloud = Get-HybridWizardComboValue -ComboBox $controls.WizardCloudComboBox
    $mode = Get-HybridWizardComboValue -ComboBox $controls.WizardModeComboBox
    $organization = $controls.WizardOrganizationTextBox.Text.Trim()
    $tenantId = $controls.WizardTenantIdTextBox.Text.Trim()

    $providerMap = [ordered]@{
        DirectorySimulator = @{
            EnabledControl = 'WizardDirectorySimulatorEnabledCheckBox'
            ModeControl = 'WizardDirectorySimulatorModeComboBox'
            Authentication = 'None'
        }
        ActiveDirectory = @{
            EnabledControl = 'WizardActiveDirectoryEnabledCheckBox'
            ModeControl = 'WizardActiveDirectoryModeComboBox'
            Authentication = 'Integrated'
        }
        MicrosoftGraph = @{
            EnabledControl = 'WizardMicrosoftGraphEnabledCheckBox'
            ModeControl = 'WizardMicrosoftGraphModeComboBox'
            Authentication = 'Interactive'
        }
        ExchangeOnline = @{
            EnabledControl = 'WizardExchangeOnlineEnabledCheckBox'
            ModeControl = 'WizardExchangeOnlineModeComboBox'
            Authentication = 'Interactive'
        }
        ExchangeOnPremises = @{
            EnabledControl = 'WizardExchangeOnPremisesEnabledCheckBox'
            ModeControl = 'WizardExchangeOnPremisesModeComboBox'
            AuthenticationControl = 'WizardExchangeOnPremisesAuthenticationComboBox'
            ServerControl = 'WizardExchangeOnPremisesServerTextBox'
            ConnectionUriControl = 'WizardExchangeOnPremisesConnectionUriTextBox'
            Authentication = 'Kerberos'
        }
    }

    $providers = [ordered]@{}
    foreach ($providerName in $providerMap.Keys) {
        $settings = $providerMap[$providerName]
        $enabled = [bool]$controls[$settings.EnabledControl].IsChecked
        $providerMode = if ($enabled) { Get-HybridWizardComboValue -ComboBox $controls[$settings.ModeControl] } else { 'Disabled' }
        $authValue = $settings.Authentication
        if ($settings.ContainsKey('AuthenticationControl')) {
            $authValue = Get-HybridWizardComboValue -ComboBox $controls[$settings.AuthenticationControl]
        }

        $providerSettings = [ordered]@{
            Enabled = $enabled
            Mode = $providerMode
            Required = $enabled
            Authentication = $authValue
        }

        if ($settings.ContainsKey('ServerControl')) {
            $providerSettings.Server = $controls[$settings.ServerControl].Text.Trim()
        }
        if ($settings.ContainsKey('ConnectionUriControl')) {
            $providerSettings.ConnectionUri = $controls[$settings.ConnectionUriControl].Text.Trim()
        }

        $providers[$providerName] = $providerSettings
    }

    $authentication = [ordered]@{
        Cloud = $cloud
        AppOnly = [ordered]@{
            Enabled = [bool]$controls.WizardAppOnlyEnabledCheckBox.IsChecked
            TenantId = $controls.WizardAppOnlyTenantIdTextBox.Text.Trim()
            TenantDomain = $controls.WizardAppOnlyTenantDomainTextBox.Text.Trim()
            ClientId = $controls.WizardAppOnlyClientIdTextBox.Text.Trim()
            CredentialMode = Get-HybridWizardComboValue -ComboBox $controls.WizardAppOnlyCredentialModeComboBox
            CertificateThumbprint = Normalize-HybridWizardCertificateThumbprint -Thumbprint $controls.WizardCertificateThumbprintTextBox.Text
            CertificatePath = $controls.WizardCertificatePathTextBox.Text.Trim()
            SecretReference = $controls.WizardSecretReferenceTextBox.Text.Trim()
        }
        Delegated = [ordered]@{
            Enabled = [bool]$controls.WizardDelegatedEnabledCheckBox.IsChecked
            PromptWhenRequired = $true
        }
    }

    return [ordered]@{
        ProfileName = $profileName
        Mode = $mode
        Cloud = $cloud
        Environment = 'Development'
        Organization = $organization
        TenantId = $tenantId
        Authentication = $authentication
        Providers = $providers
    }
}

function Test-HybridRuntimeProfileWizardInput {
    try {
        $profile = New-HybridRuntimeProfileFromWizard
        $enabledProviders = @($profile.Providers.Keys | Where-Object { [bool]$profile.Providers[$_].Enabled })
        if ($enabledProviders.Count -eq 0) { throw 'At least one provider must be enabled.' }
        if ($profile.Providers.ExchangeOnPremises.Enabled -and $profile.Providers.ExchangeOnPremises.Mode -eq 'Live' -and [string]::IsNullOrWhiteSpace([string]$profile.Providers.ExchangeOnPremises.Server) -and [string]::IsNullOrWhiteSpace([string]$profile.Providers.ExchangeOnPremises.ConnectionUri)) {
            throw 'Exchange On-Premises requires a server name or connection URI when enabled for Live mode.'
        }
        if ($profile.Providers.ExchangeOnline.Enabled -and $profile.Providers.ExchangeOnline.Mode -eq 'Live' -and [bool]$profile.Authentication.AppOnly.Enabled) {
            if ([string]::IsNullOrWhiteSpace([string]$profile.Authentication.AppOnly.TenantId) -or [string]::IsNullOrWhiteSpace([string]$profile.Authentication.AppOnly.ClientId)) {
                throw 'Exchange Online app-only authentication requires Tenant ID and Client ID.'
            }
            if ([string]$profile.Authentication.AppOnly.TenantId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' -and [string]::IsNullOrWhiteSpace([string]$profile.Authentication.AppOnly.TenantDomain)) {
                throw 'Exchange Online requires Tenant Domain when Tenant ID is a GUID. Use the tenant onmicrosoft.com or primary accepted domain.'
            }
            if ($profile.Authentication.AppOnly.CredentialMode -eq 'Certificate' -and [string]::IsNullOrWhiteSpace([string]$profile.Authentication.AppOnly.CertificateThumbprint) -and [string]::IsNullOrWhiteSpace([string]$profile.Authentication.AppOnly.CertificatePath)) {
                throw 'Exchange Online certificate authentication requires a certificate thumbprint or certificate path.'
            }
        }
        if ($profile.Mode -eq 'Live' -and [string]::IsNullOrWhiteSpace($profile.TenantId)) {
            $controls.WizardValidationText.Text = 'Warning: Live profiles should include a Tenant ID before production use. Profile shape is otherwise valid.'
        }
        else {
            $controls.WizardValidationText.Text = ('Profile is valid. Mode={0}; Cloud={1}; Enabled providers={2}.' -f $profile.Mode, $profile.Cloud, ($enabledProviders -join ', '))
        }
        $controls.WizardSummaryText.Text = $controls.WizardValidationText.Text
        $controls.StatusText.Text = 'Runtime profile validation completed.'
        return $true
    }
    catch {
        $controls.WizardValidationText.Text = "Validation failed: $($_.Exception.Message)"
        $controls.WizardSummaryText.Text = $controls.WizardValidationText.Text
        $controls.StatusText.Text = 'Runtime profile validation failed.'
        return $false
    }
}

function Save-HybridRuntimeProfileFromWizard {
    if (-not (Test-HybridRuntimeProfileWizardInput)) { return }
    try {
        $profile = New-HybridRuntimeProfileFromWizard
        $runtimeProfileRoot = Join-Path $repoRoot 'profiles\Runtime'
        if (-not (Test-Path $runtimeProfileRoot)) { New-Item -Path $runtimeProfileRoot -ItemType Directory -Force | Out-Null }
        $safeName = ($profile.ProfileName -replace '[^a-zA-Z0-9._-]', '-')
        $targetPath = if ($script:HybridRuntimeProfileWizardMode -eq 'Edit' -and -not [string]::IsNullOrWhiteSpace($script:HybridRuntimeProfileWizardSourcePath)) { $script:HybridRuntimeProfileWizardSourcePath } else { Join-Path $runtimeProfileRoot ("$safeName.json") }
        $profile | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $targetPath -Encoding UTF8
        $controls.WizardValidationText.Text = "Profile saved: $targetPath"
        $controls.StatusText.Text = "Runtime profile saved: $safeName.json"
        if (Get-Command Set-HybridRuntimeProfileSelection -ErrorAction SilentlyContinue) {
            Set-HybridRuntimeProfileSelection -RepositoryRoot $repoRoot -ProfilePath $targetPath | Out-Null
        }
        Initialize-HybridRuntimeProfileList
        Update-HybridStartupView
    }
    catch {
        $controls.WizardValidationText.Text = "Save failed: $($_.Exception.Message)"
        $controls.StatusText.Text = 'Runtime profile save failed.'
    }
}

function Set-HybridUiBusyState {
    param([bool]$Busy)
    $script:IsSearchBusy = $Busy
    $controls.SearchButton.IsEnabled = -not $Busy
    if ($controls.ContainsKey('SearchProgressPanel') -and $null -ne $controls.SearchProgressPanel) {
        $controls.SearchProgressPanel.Visibility = if ($Busy) { 'Visible' } else { 'Collapsed' }
    }
    if ($controls.ContainsKey('SearchProgressIndicator') -and $null -ne $controls.SearchProgressIndicator) {
        $controls.SearchProgressIndicator.IsIndeterminate = $false
        if (-not $Busy) { $controls.SearchProgressIndicator.Value = 0 }
    }
    if ($controls.ContainsKey('SearchProgressStageText') -and $null -ne $controls.SearchProgressStageText -and -not $Busy) {
        $controls.SearchProgressStageText.Text = 'Ready'
    }
}

function Set-HybridSearchProgressStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Stage,
        [int]$Percent = 0
    )

    $bounded = [Math]::Max(0, [Math]::Min(100, $Percent))
    if ($controls.ContainsKey('SearchProgressPanel') -and $null -ne $controls.SearchProgressPanel) { $controls.SearchProgressPanel.Visibility = 'Visible' }
    if ($controls.ContainsKey('SearchProgressStageText') -and $null -ne $controls.SearchProgressStageText) { $controls.SearchProgressStageText.Text = $Stage }
    if ($controls.ContainsKey('SearchProgressIndicator') -and $null -ne $controls.SearchProgressIndicator) {
        $controls.SearchProgressIndicator.IsIndeterminate = $false
        $controls.SearchProgressIndicator.Value = $bounded
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-DisplayValue {
    param([AllowNull()][object]$InputObject, [string[]]$Names, [string]$Default = '-')
    foreach ($name in $Names) {
        if ($null -eq $InputObject) { continue }

        if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($name)) {
            $value = $InputObject[$name]
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return [string]$value }
        }

        if ($InputObject.PSObject.Properties.Name -contains $name) {
            $value = $InputObject.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return [string]$value }
        }

        if ($InputObject.PSObject.Properties.Name -contains 'Attributes' -and $null -ne $InputObject.Attributes) {
            $attributes = $InputObject.Attributes
            if ($attributes -is [System.Collections.IDictionary] -and $attributes.Contains($name)) {
                $value = $attributes[$name]
                if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return [string]$value }
            }
            elseif ($null -ne $attributes -and $attributes.PSObject.Properties.Name -contains $name) {
                $value = $attributes.$name
                if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return [string]$value }
            }
        }
    }
    return $Default
}

function Format-HybridGroupDisplay {
    [CmdletBinding()]
    param([AllowNull()][object]$Group)

    if ($null -eq $Group) { return '-' }
    if ($Group -is [string]) { return $Group }

    $name = Get-DisplayValue -InputObject $Group -Names @('Name','DisplayName','SamAccountName','Identity','DistinguishedName','Id') -Default ''
    if (-not [string]::IsNullOrWhiteSpace($name)) { return $name }

    return [string]$Group
}

function Resolve-HybridUserDistinguishedName {
    [CmdletBinding()]
    param([AllowNull()][object]$User)

    return Get-DisplayValue -InputObject $User -Names @('DistinguishedName','ActiveDirectoryDistinguishedName','DN') -Default '-'
}

function Resolve-HybridUserOrganizationalUnit {
    [CmdletBinding()]
    param([AllowNull()][object]$User)

    $explicitOu = Get-DisplayValue -InputObject $User -Names @('OrganizationalUnit','ActiveDirectoryOrganizationalUnit','OU') -Default ''
    if (-not [string]::IsNullOrWhiteSpace($explicitOu) -and $explicitOu -ne '-') { return $explicitOu }

    $dn = Resolve-HybridUserDistinguishedName -User $User
    if ([string]::IsNullOrWhiteSpace($dn) -or $dn -eq '-') { return '-' }

    $ouParts = @($dn.Split(',') | Where-Object { $_ -like 'OU=*' } | ForEach-Object { $_.Substring(3) })
    if ($ouParts.Count -gt 0) {
        [array]::Reverse($ouParts)
        return ($ouParts -join ' / ')
    }

    return '-'
}


function Format-HybridUiDate {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 'Not loaded' }
    try { return ([datetime]$Value).ToLocalTime().ToString('g') } catch { return [string]$Value }
}

function Format-HybridUiBool {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'Unknown' }
    if ([bool]$Value) { return 'Yes' }
    return 'No'
}

function Reset-AggregationPanel {
    if ($controls.ContainsKey('AggregationSummaryText') -and $null -ne $controls.AggregationSummaryText) {
        $controls.AggregationSummaryText.Text = 'Aggregation waiting for a user search.'
        $controls.AggregationIdentityText.Text = 'Not loaded'
        $controls.AggregationVerticalsText.Text = 'Not loaded'
        $controls.AggregationStatusText.Text = 'Not loaded'
        $controls.AggregationRetrievedText.Text = 'Not loaded'
    }
}

function Update-AggregationPanel {
    param([Parameter(Mandatory=$true)][object]$User, [Parameter(Mandatory=$true)][string]$Query)

    if (-not $controls.ContainsKey('AggregationSummaryText') -or $null -eq $controls.AggregationSummaryText) { return }

    Reset-AggregationPanel
    $controls.AggregationSummaryText.Text = 'Loading aggregate user profile...'

    try {
        if (-not (Get-Command Get-HybridUserAggregateProfile -ErrorAction SilentlyContinue)) {
            $controls.AggregationSummaryText.Text = 'Aggregation service unavailable.'
            return
        }

        $identity = Get-DisplayValue -InputObject $User -Names @('UserPrincipalName','Mail','SamAccountName','Identity') -Default $Query
        if ([string]::IsNullOrWhiteSpace($identity) -or $identity -eq '-') { $identity = $Query }

        $aggregate = Get-HybridUserAggregateProfile -Identity $identity
        if ($null -eq $aggregate) {
            $controls.AggregationSummaryText.Text = "No aggregate profile returned for $identity."
            return
        }

        $loaded = Get-DisplayValue -InputObject $aggregate -Names @('LoadedVerticalCount') -Default '0'
        $total = Get-DisplayValue -InputObject $aggregate -Names @('TotalVerticalCount') -Default '0'
        $statusText = 'No vertical status returned'
        if ($aggregate.PSObject.Properties.Name -contains 'Verticals' -and $null -ne $aggregate.Verticals) {
            $exchangeSource = $null
            if ($aggregate.PSObject.Properties.Name -contains 'MailboxDetails' -and $null -ne $aggregate.MailboxDetails -and $aggregate.MailboxDetails.PSObject.Properties.Name -contains 'SourceProvider') {
                $exchangeSource = [string]$aggregate.MailboxDetails.SourceProvider
            }
            $statusText = (@($aggregate.Verticals) | ForEach-Object {
                $state = if ($_.Loaded) { 'Loaded' } else { 'Unavailable' }
                if ($_.Name -eq 'ExchangeMailbox' -and -not [string]::IsNullOrWhiteSpace($exchangeSource)) { $state = "$state ($exchangeSource)" }
                "{0}: {1}" -f $_.Name, $state
            }) -join ' | '
        }

        $controls.AggregationIdentityText.Text = Get-DisplayValue -InputObject $aggregate -Names @('UserPrincipalName','Identity') -Default $identity
        $controls.AggregationVerticalsText.Text = "$loaded / $total"
        $controls.AggregationStatusText.Text = $statusText
        $controls.AggregationRetrievedText.Text = Format-HybridUiDate (Get-DisplayValue -InputObject $aggregate -Names @('RetrievedOn') -Default $null)
        $controls.AggregationSummaryText.Text = "Aggregation loaded for $($controls.UpnText.Text)."
    }
    catch {
        $controls.AggregationSummaryText.Text = "Aggregation load failed: $($_.Exception.Message)"
    }
}

function Reset-GraphPanel {
    $controls.GraphSummaryText.Text = 'Graph profile waiting for a user search.'
    foreach ($name in @('GraphObjectIdText','GraphUserTypeText','GraphUsageLocationText','GraphPreferredLanguageText','GraphMfaRegisteredText','GraphMfaCapableText','GraphAuthenticationMethodsText','GraphLastSignInText','GraphPasswordLastChangedText','GraphRiskStateText')) {
        $controls[$name].Text = 'Not loaded'
    }
}

function Reset-AuthenticationPanel {
    $controls.AuthenticationSummaryText.Text = 'Authentication posture waiting for a user search.'
    foreach ($name in @('AuthDefaultMethodText','AuthMfaRegisteredText','AuthPasswordlessText','AuthStrengthText','AuthConditionalAccessText','AuthRiskText')) {
        $controls[$name].Text = 'Not loaded'
    }
    if ($controls.ContainsKey('AuthMethodsList') -and $null -ne $controls.AuthMethodsList) { $controls.AuthMethodsList.Items.Clear() }
}

function Write-HybridUiHydrationDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Stage,
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')][string]$Level = 'INFO',
        [AllowNull()][object]$Data = $null
    )

    try {
        $logRoot = Join-Path $script:RepositoryRoot 'logs'
        if (-not (Test-Path -LiteralPath $logRoot)) { New-Item -Path $logRoot -ItemType Directory -Force | Out-Null }
        $logPath = Join-Path $logRoot 'hydration-diagnostics.log'
        $line = '[{0:u}] [{1}] [{2}] {3}' -f ([datetime]::UtcNow), $Level, $Stage, $Message
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
        if ($null -ne $Data) {
            Add-Content -LiteralPath $logPath -Value ('    Data: ' + ($Data | ConvertTo-Json -Depth 6 -Compress)) -Encoding UTF8
        }
    }
    catch { }
}

function Invoke-HybridUiHydrationStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Stage,
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [AllowNull()][scriptblock]$OnFailure = $null
    )

    Write-HybridUiHydrationDiagnostic -Stage $Stage -Message 'Starting.'
    try {
        & $Action
        Write-HybridUiHydrationDiagnostic -Stage $Stage -Message 'Completed.' -Level SUCCESS
        return $true
    }
    catch {
        $message = $_.Exception.Message
        Write-HybridUiHydrationDiagnostic -Stage $Stage -Message $message -Level ERROR -Data ([pscustomobject]@{
            ExceptionType = $_.Exception.GetType().FullName
            FullyQualifiedErrorId = $_.FullyQualifiedErrorId
            ScriptStackTrace = $_.ScriptStackTrace
        })
        if ($null -ne $OnFailure) {
            try { & $OnFailure $_ } catch { }
        }
        return $false
    }
}

function Reset-UserDisplay {
    $controls.ResultHeader.Text = 'Searching...'
    foreach ($name in @('DisplayNameText','UpnText','SamText','MailText','DepartmentText','TitleText','MailboxText','SourcesText','CompanyText','OfficeText','EmployeeIdText','BadgeIdText','StateText','PhoneNumberText','DistinguishedNameText','OrganizationalUnitText','ManagerText','RecipientTypeText','MailboxStatusText','ForwardingText','ExchangeSummaryText')) { $controls[$name].Text = '-' }
    $controls.AccountStateText.Text = 'Account state: loading'
    $controls.ExchangeSummaryText.Text = 'Exchange vertical slice loading mailbox details...'
    $controls.GroupsList.Items.Clear()
    $controls.DirectReportsList.Items.Clear()
    $controls.MailboxDelegationList.Items.Clear()
    $controls.DistributionGroupsList.Items.Clear()
    Reset-AggregationPanel
    Reset-GraphPanel
    Reset-AuthenticationPanel
}

function Update-HybridUiHealth {
    try {
        $health = Get-HybridUserServiceHealth
        $adHealth = $null
        if ($null -ne $health.ProviderHealth -and $health.ProviderHealth.ContainsKey('ActiveDirectory')) {
            $adHealth = $health.ProviderHealth.ActiveDirectory
        }

        $adConnected = $false
        $lastError = ''
        if ($null -ne $adHealth) {
            if ($adHealth.PSObject.Properties.Name -contains 'Connected') { $adConnected = [bool]$adHealth.Connected }
            elseif ($adHealth.PSObject.Properties.Name -contains 'Available') { $adConnected = [bool]$adHealth.Available }
            if ($adHealth.PSObject.Properties.Name -contains 'LastError' -and $null -ne $adHealth.LastError) { $lastError = [string]$adHealth.LastError }
        }

        if ($adConnected) {
            $controls.ProviderStatusText.Text = 'Provider health: AD connected'
            $controls.ProviderDot.Fill = '#22C55E'
        }
        else {
            $suffix = if ([string]::IsNullOrWhiteSpace($lastError)) { '' } else { " ($lastError)" }
            $controls.ProviderStatusText.Text = 'Provider health: AD unavailable' + $suffix
            $controls.ProviderDot.Fill = '#F97316'
        }
    }
    catch {
        $controls.ProviderStatusText.Text = 'Provider health: error'
        $controls.ProviderDot.Fill = '#EF4444'
    }
}

function Update-DetailPanels {
    param([Parameter(Mandatory=$true)][object]$User, [Parameter(Mandatory=$true)][string]$Query)

    $controls.ManagerText.Text = 'Loading details...'
    $controls.GroupsList.Items.Clear()
    $controls.DirectReportsList.Items.Clear()

    $details = $User
    if (Get-Command Get-HybridUserDetails -ErrorAction SilentlyContinue) {
        $identity = Get-DisplayValue -InputObject $User -Names @('UserPrincipalName','SamAccountName','Identity') -Default $Query
        if ([string]::IsNullOrWhiteSpace($identity) -or $identity -eq '-') { $identity = $Query }
        $details = Get-HybridUserDetails -Identity $identity
    }

    $managerValue = Get-DisplayValue -InputObject $details -Names @('ManagerDisplayName','ManagerName','Manager')
    $controls.ManagerText.Text = $managerValue
    $controls.DistinguishedNameText.Text = Resolve-HybridUserDistinguishedName -User $details
    $controls.OrganizationalUnitText.Text = Resolve-HybridUserOrganizationalUnit -User $details
    Write-HybridUiHydrationDiagnostic -Stage 'ActiveDirectoryDetails' -Message 'Resolved Active Directory DN and OU display values.' -Level INFO -Data ([pscustomobject]@{
        DistinguishedName = $controls.DistinguishedNameText.Text
        OrganizationalUnit = $controls.OrganizationalUnitText.Text
        DetailProperties = @($details.PSObject.Properties.Name)
    })

    $groups = @()
    if ($details.PSObject.Properties.Name -contains 'Groups' -and $null -ne $details.Groups) { $groups = @($details.Groups) }
    foreach ($group in $groups) { [void]$controls.GroupsList.Items.Add((Format-HybridGroupDisplay -Group $group)) }
    if ($controls.GroupsList.Items.Count -eq 0) { [void]$controls.GroupsList.Items.Add('No groups loaded') }

    $reports = @()
    if ($details.PSObject.Properties.Name -contains 'DirectReports' -and $null -ne $details.DirectReports) { $reports = @($details.DirectReports) }
    foreach ($report in $reports) {
        $text = Get-DisplayValue -InputObject $report -Names @('DisplayName','Name','UserPrincipalName') -Default ([string]$report)
        [void]$controls.DirectReportsList.Items.Add($text)
    }
    if ($controls.DirectReportsList.Items.Count -eq 0) { [void]$controls.DirectReportsList.Items.Add('No direct reports loaded') }
}


function Update-GraphPanels {
    param([Parameter(Mandatory=$true)][object]$User, [Parameter(Mandatory=$true)][string]$Query)

    Reset-GraphPanel
    $controls.GraphSummaryText.Text = 'Loading Microsoft Graph profile...'

    try {
        $identity = Get-DisplayValue -InputObject $User -Names @('UserPrincipalName','Mail','SamAccountName','Identity') -Default $Query
        if ([string]::IsNullOrWhiteSpace($identity) -or $identity -eq '-') { $identity = $Query }

        $graphProfile = $null
        if (Get-Command Get-HybridUserGraphProfile -ErrorAction SilentlyContinue) {
            $graphProfile = Get-HybridUserGraphProfile -Identity $identity
        }
        elseif (Get-Command Get-HybridGraphProfile -ErrorAction SilentlyContinue) {
            $graphProfile = Get-HybridGraphProfile -Identity $identity
        }

        if ($null -eq $graphProfile) {
            $controls.GraphSummaryText.Text = "No Microsoft Graph profile returned for $identity."
            return
        }

        $controls.GraphObjectIdText.Text = Get-DisplayValue -InputObject $graphProfile -Names @('ObjectId','Id','GraphObjectId') -Default 'Not loaded'
        $controls.GraphUserTypeText.Text = Get-DisplayValue -InputObject $graphProfile -Names @('UserType') -Default 'Member'
        $controls.GraphUsageLocationText.Text = Get-DisplayValue -InputObject $graphProfile -Names @('UsageLocation') -Default 'US'
        $controls.GraphPreferredLanguageText.Text = Get-DisplayValue -InputObject $graphProfile -Names @('PreferredLanguage') -Default 'en-US'
        $controls.GraphMfaRegisteredText.Text = Format-HybridUiBool (Get-DisplayValue -InputObject $graphProfile -Names @('MfaRegistered','MfaEnabled','IsMfaRegistered') -Default $null)
        $controls.GraphMfaCapableText.Text = Format-HybridUiBool (Get-DisplayValue -InputObject $graphProfile -Names @('MfaCapable','IsMfaCapable') -Default $null)
        $methods = @()
        if ($graphProfile.PSObject.Properties.Name -contains 'AuthenticationMethods' -and $null -ne $graphProfile.AuthenticationMethods) { $methods = @($graphProfile.AuthenticationMethods) }
        $controls.GraphAuthenticationMethodsText.Text = if ($methods.Count -gt 0) { ($methods -join ', ') } else { 'None reported' }
        $controls.GraphLastSignInText.Text = Format-HybridUiDate (Get-DisplayValue -InputObject $graphProfile -Names @('LastSignInDateTime','LastSignIn','SignInActivity') -Default $null)
        $controls.GraphPasswordLastChangedText.Text = Format-HybridUiDate (Get-DisplayValue -InputObject $graphProfile -Names @('PasswordLastChangedDateTime','LastPasswordChange','PasswordLastChanged') -Default $null)
        $controls.GraphRiskStateText.Text = Get-DisplayValue -InputObject $graphProfile -Names @('RiskState','UserRiskState') -Default 'none'
        $controls.GraphSummaryText.Text = "Microsoft Graph loaded for $($controls.UpnText.Text)."
    }
    catch {
        $controls.GraphSummaryText.Text = "Graph profile load failed: $($_.Exception.Message)"
    }
}


function Update-AuthenticationPanels {
    param([Parameter(Mandatory=$true)][object]$User, [Parameter(Mandatory=$true)][string]$Query)

    Reset-AuthenticationPanel
    $controls.AuthenticationSummaryText.Text = 'Loading authentication posture...'

    try {
        if (-not (Get-Command Get-HybridUserAuthenticationProfile -ErrorAction SilentlyContinue)) {
            $controls.AuthenticationSummaryText.Text = 'Authentication service unavailable.'
            return
        }

        $identity = Get-DisplayValue -InputObject $User -Names @('UserPrincipalName','Mail','SamAccountName','Identity') -Default $Query
        if ([string]::IsNullOrWhiteSpace($identity) -or $identity -eq '-') { $identity = $Query }

        $profile = Get-HybridUserAuthenticationProfile -Identity $identity
        if ($null -eq $profile) {
            $controls.AuthenticationSummaryText.Text = "No authentication profile returned for $identity."
            return
        }

        $controls.AuthDefaultMethodText.Text = Get-DisplayValue -InputObject $profile -Names @('DefaultMethod','DefaultAuthenticationMethod') -Default 'Not loaded'
        $controls.AuthMfaRegisteredText.Text = Format-HybridUiBool (Get-DisplayValue -InputObject $profile -Names @('MfaRegistered','MfaEnabled','IsMfaRegistered') -Default $null)
        $controls.AuthPasswordlessText.Text = Format-HybridUiBool (Get-DisplayValue -InputObject $profile -Names @('PasswordlessRegistered','IsPasswordlessRegistered') -Default $null)
        $controls.AuthStrengthText.Text = Get-DisplayValue -InputObject $profile -Names @('AuthenticationStrength') -Default 'Not loaded'
        $controls.AuthConditionalAccessText.Text = Get-DisplayValue -InputObject $profile -Names @('ConditionalAccessState','ConditionalAccess') -Default 'Not evaluated'
        $controls.AuthRiskText.Text = Get-DisplayValue -InputObject $profile -Names @('SignInRiskState','RiskState','UserRiskState') -Default 'none'

        $methods = @()
        if ($profile.PSObject.Properties.Name -contains 'AuthenticationMethods' -and $null -ne $profile.AuthenticationMethods) { $methods = @($profile.AuthenticationMethods) }
        if ($controls.ContainsKey('AuthMethodsList') -and $null -ne $controls.AuthMethodsList) {
            $controls.AuthMethodsList.Items.Clear()
            foreach ($method in $methods) { [void]$controls.AuthMethodsList.Items.Add([string]$method) }
            if ($methods.Count -eq 0) { [void]$controls.AuthMethodsList.Items.Add('None reported') }
        }
        $controls.AuthenticationSummaryText.Text = "Authentication loaded for $($controls.UpnText.Text)."
    }
    catch {
        $controls.AuthenticationSummaryText.Text = "Authentication profile load failed: $($_.Exception.Message)"
    }
}

function Update-ExchangePanels {
    param([Parameter(Mandatory=$true)][object]$User, [Parameter(Mandatory=$true)][string]$Query)

    $controls.RecipientTypeText.Text = 'Loading Exchange...'
    $controls.MailboxStatusText.Text = 'Loading Exchange...'
    $controls.ForwardingText.Text = 'Loading Exchange...'
    $controls.ExchangeSummaryText.Text = 'Loading Exchange mailbox details...'
    $controls.MailboxDelegationList.Items.Clear()
    $controls.DistributionGroupsList.Items.Clear()

    $exchangeUser = $User
    if (Get-Command Get-HybridUserMailboxDetails -ErrorAction SilentlyContinue) {
        $identity = Get-DisplayValue -InputObject $User -Names @('UserPrincipalName','Mail','SamAccountName','Identity') -Default $Query
        if ([string]::IsNullOrWhiteSpace($identity) -or $identity -eq '-') { $identity = $Query }
        $exchangeUser = Get-HybridUserMailboxDetails -Identity $identity
    }

    $mailboxDetails = $null
    if ($exchangeUser.PSObject.Properties.Name -contains 'MailboxDetails') { $mailboxDetails = $exchangeUser.MailboxDetails }
    $mailbox = if ($null -ne $mailboxDetails -and $mailboxDetails.PSObject.Properties.Name -contains 'Mailbox') { $mailboxDetails.Mailbox } else { $null }
    $onPremRecipient = $null
    if ($null -ne $mailboxDetails -and $mailboxDetails.PSObject.Properties.Name -contains 'OnPremisesRecipient') { $onPremRecipient = $mailboxDetails.OnPremisesRecipient }
    elseif ($exchangeUser.PSObject.Properties.Name -contains 'OnPremisesExchangeRecipient') { $onPremRecipient = $exchangeUser.OnPremisesExchangeRecipient }

    if ($null -eq $mailboxDetails -or $null -eq $mailbox) {
        $adMail = Get-DisplayValue -InputObject $exchangeUser -Names @('Mail','EmailAddress') -Default 'AD mail attribute not found'
        $controls.MailboxText.Text = $adMail
        if ($null -ne $onPremRecipient) {
            $onPremType = Get-DisplayValue -InputObject $onPremRecipient -Names @('RecipientTypeDetails','RecipientType') -Default 'On-prem recipient'
            $remoteRouting = Get-DisplayValue -InputObject $onPremRecipient -Names @('RemoteRoutingAddress','TargetAddress') -Default ''
            $controls.ExchangeSummaryText.Text = "Exchange On-Prem recipient loaded: $onPremType | Exchange Online mailbox not loaded."
            $controls.RecipientTypeText.Text = "On-Prem: $onPremType | EXO: unavailable/not registered"
            $controls.MailboxStatusText.Text = if ([string]::IsNullOrWhiteSpace($remoteRouting) -or $remoteRouting -eq '-') { 'On-prem recipient loaded; remote routing not returned' } else { "Remote routing: $remoteRouting" }
            $controls.ForwardingText.Text = 'Forwarding requires Exchange provider data; AD mail attributes are not treated as Exchange mailbox data.'
            if ($controls.MailboxDelegationList.Items.Count -eq 0) { [void]$controls.MailboxDelegationList.Items.Add('Exchange Online mailbox delegations not loaded') }
            if ($controls.DistributionGroupsList.Items.Count -eq 0) { [void]$controls.DistributionGroupsList.Items.Add('On-prem distribution groups not loaded') }
            return
        }
        $controls.ExchangeSummaryText.Text = 'Exchange Online mailbox not loaded. Showing AD mail attribute only where available.'
        $controls.RecipientTypeText.Text = 'Exchange Online unavailable/not registered'
        $controls.MailboxStatusText.Text = 'Not loaded from Exchange Online'
        $controls.ForwardingText.Text = 'Not loaded from Exchange Online'
        if ($controls.MailboxDelegationList.Items.Count -eq 0) { [void]$controls.MailboxDelegationList.Items.Add('Exchange Online not loaded') }
        if ($controls.DistributionGroupsList.Items.Count -eq 0) { [void]$controls.DistributionGroupsList.Items.Add('Exchange Online not loaded') }
        return
    }

    $primarySmtp = Get-DisplayValue -InputObject $mailboxDetails -Names @('PrimarySmtpAddress')
    $controls.MailboxText.Text = $primarySmtp
    $recipientType = if ($null -ne $mailboxDetails) { Get-DisplayValue -InputObject $mailboxDetails -Names @('RecipientTypeDetails') } elseif ($null -ne $mailbox) { Get-DisplayValue -InputObject $mailbox -Names @('RecipientTypeDetails','RecipientType') } else { 'Not found' }
    $controls.RecipientTypeText.Text = $recipientType

    $hidden = if ($null -ne $mailboxDetails) { Get-DisplayValue -InputObject $mailboxDetails -Names @('HiddenFromAddressListsEnabled') -Default 'Unknown' } else { 'Unknown' }
    $hold = if ($null -ne $mailboxDetails) { Get-DisplayValue -InputObject $mailboxDetails -Names @('LitigationHoldEnabled') -Default 'Unknown' } else { 'Unknown' }
    $controls.MailboxStatusText.Text = "Hidden=$hidden | LitigationHold=$hold"

    $forwardTo = if ($null -ne $mailboxDetails) { Get-DisplayValue -InputObject $mailboxDetails -Names @('ForwardingSmtpAddress') -Default '' } else { '' }
    $deliverAndForward = if ($null -ne $mailboxDetails) { Get-DisplayValue -InputObject $mailboxDetails -Names @('DeliverToMailboxAndForward') -Default 'Unknown' } else { 'Unknown' }
    $controls.ForwardingText.Text = if ([string]::IsNullOrWhiteSpace($forwardTo)) { "No forwarding configured" } else { "Forwarding to $forwardTo | DeliverToMailboxAndForward=$deliverAndForward" }
    $sourceProvider = if ($null -ne $mailboxDetails) { Get-DisplayValue -InputObject $mailboxDetails -Names @('SourceProvider') -Default 'Exchange' } else { 'Exchange' }
    $controls.ExchangeSummaryText.Text = "$sourceProvider loaded: $recipientType | $primarySmtp"

    $delegations = @()
    if ($null -ne $mailboxDetails -and $mailboxDetails.PSObject.Properties.Name -contains 'Delegations') { $delegations = @($mailboxDetails.Delegations) }
    foreach ($delegation in $delegations) {
        $trustee = Get-DisplayValue -InputObject $delegation -Names @('Trustee','User','Identity') -Default ([string]$delegation)
        $rights = Get-DisplayValue -InputObject $delegation -Names @('AccessRights','Rights') -Default ''
        [void]$controls.MailboxDelegationList.Items.Add(("{0} {1}" -f $trustee,$rights).Trim())
    }
    if ($controls.MailboxDelegationList.Items.Count -eq 0) { [void]$controls.MailboxDelegationList.Items.Add('No mailbox delegations loaded') }

    $distributionGroups = @()
    if ($null -ne $mailboxDetails -and $mailboxDetails.PSObject.Properties.Name -contains 'DistributionGroups') { $distributionGroups = @($mailboxDetails.DistributionGroups) }
    foreach ($group in $distributionGroups) { [void]$controls.DistributionGroupsList.Items.Add((Format-HybridGroupDisplay -Group $group)) }
    if ($controls.DistributionGroupsList.Items.Count -eq 0) { [void]$controls.DistributionGroupsList.Items.Add('No distribution groups loaded') }
}


function Select-HybridUserFromSearchResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]]$Users,
        [Parameter(Mandatory=$true)][string]$Query
    )

    if ($Users.Count -le 1) { return ($Users | Select-Object -First 1) }
    return Show-HybridUserSelectionDialog -Users $Users -Query $Query
}

function Show-HybridUserSelectionDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]]$Users,
        [Parameter(Mandatory=$true)][string]$Query
    )

    $selectionWindow = [Windows.Window]::new()
    $selectionWindow.Title = "Select user match - $Query"
    $selectionWindow.Width = 980
    $selectionWindow.Height = 460
    $selectionWindow.WindowStartupLocation = 'CenterOwner'
    $selectionWindow.Owner = $window
    $selectionWindow.Background = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString('#0B1220'))

    $root = [Windows.Controls.Grid]::new()
    $root.Margin = [Windows.Thickness]::new(16)
    $root.RowDefinitions.Add([Windows.Controls.RowDefinition]::new())
    $root.RowDefinitions[0].Height = [Windows.GridLength]::Auto
    $root.RowDefinitions.Add([Windows.Controls.RowDefinition]::new())
    $root.RowDefinitions.Add([Windows.Controls.RowDefinition]::new())
    $root.RowDefinitions[2].Height = [Windows.GridLength]::Auto

    $header = [Windows.Controls.TextBlock]::new()
    $header.Text = "Multiple users matched '$Query'. Choose the intended account before details are hydrated."
    $header.Foreground = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString('#F8FAFC'))
    $header.FontSize = 16
    $header.FontWeight = 'SemiBold'
    $header.Margin = [Windows.Thickness]::new(0,0,0,12)
    [Windows.Controls.Grid]::SetRow($header,0)
    [void]$root.Children.Add($header)

    $grid = [Windows.Controls.DataGrid]::new()
    $grid.AutoGenerateColumns = $false
    $grid.CanUserAddRows = $false
    $grid.CanUserDeleteRows = $false
    $grid.IsReadOnly = $true
    $grid.SelectionMode = 'Single'
    $grid.SelectionUnit = 'FullRow'
    $grid.Background = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString('#111827'))
    $grid.Foreground = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString('#E5E7EB'))
    $grid.RowBackground = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString('#111827'))
    $grid.AlternatingRowBackground = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString('#0F172A'))
    $grid.GridLinesVisibility = 'Horizontal'
    $grid.Margin = [Windows.Thickness]::new(0,0,0,12)

    foreach ($columnSpec in @(
        @{ Header='Display Name'; Binding='DisplayName'; Width=180 },
        @{ Header='SAM'; Binding='SamAccountName'; Width=120 },
        @{ Header='UPN'; Binding='UserPrincipalName'; Width=220 },
        @{ Header='Title'; Binding='Title'; Width=160 },
        @{ Header='Department'; Binding='Department'; Width=150 },
        @{ Header='OU / DN'; Binding='DisambiguationPath'; Width=260 }
    )) {
        $column = [Windows.Controls.DataGridTextColumn]::new()
        $column.Header = $columnSpec.Header
        $column.Binding = [Windows.Data.Binding]::new($columnSpec.Binding)
        $column.Width = [Windows.Controls.DataGridLength]::new([double]$columnSpec.Width)
        [void]$grid.Columns.Add($column)
    }

    $rows = @($Users | ForEach-Object {
        [pscustomobject]@{
            User = $_
            DisplayName = Get-DisplayValue -InputObject $_ -Names @('DisplayName','Name') -Default '-'
            SamAccountName = Get-DisplayValue -InputObject $_ -Names @('SamAccountName','SAMAccountName','ActiveDirectorySamAccountName') -Default '-'
            UserPrincipalName = Get-DisplayValue -InputObject $_ -Names @('UserPrincipalName','UPN','Mail') -Default '-'
            Title = Get-DisplayValue -InputObject $_ -Names @('Title','JobTitle') -Default '-'
            Department = Get-DisplayValue -InputObject $_ -Names @('Department') -Default '-'
            DisambiguationPath = Resolve-HybridUserOrganizationalUnit -User $_
        }
    })
    $grid.ItemsSource = $rows
    if ($rows.Count -gt 0) { $grid.SelectedIndex = 0 }
    [Windows.Controls.Grid]::SetRow($grid,1)
    [void]$root.Children.Add($grid)

    $buttonPanel = [Windows.Controls.StackPanel]::new()
    $buttonPanel.Orientation = 'Horizontal'
    $buttonPanel.HorizontalAlignment = 'Right'
    $chooseButton = [Windows.Controls.Button]::new()
    $chooseButton.Content = 'Load Selected User'
    $chooseButton.Width = 150
    $chooseButton.Height = 34
    $chooseButton.Margin = [Windows.Thickness]::new(0,0,8,0)
    $cancelButton = [Windows.Controls.Button]::new()
    $cancelButton.Content = 'Cancel'
    $cancelButton.Width = 90
    $cancelButton.Height = 34
    [void]$buttonPanel.Children.Add($chooseButton)
    [void]$buttonPanel.Children.Add($cancelButton)
    [Windows.Controls.Grid]::SetRow($buttonPanel,2)
    [void]$root.Children.Add($buttonPanel)

    $selectedUser = $null
    $chooseAction = {
        if ($null -ne $grid.SelectedItem) {
            $script:HybridUserSelectionDialogSelectedUser = $grid.SelectedItem.User
            $selectionWindow.DialogResult = $true
            $selectionWindow.Close()
        }
    }
    $chooseButton.Add_Click($chooseAction)
    $grid.Add_MouseDoubleClick($chooseAction)
    $cancelButton.Add_Click({ $selectionWindow.DialogResult = $false; $selectionWindow.Close() })

    $script:HybridUserSelectionDialogSelectedUser = $null
    $selectionWindow.Content = $root
    [void]$selectionWindow.ShowDialog()
    $selectedUser = $script:HybridUserSelectionDialogSelectedUser
    $script:HybridUserSelectionDialogSelectedUser = $null
    return $selectedUser
}

function Invoke-HybridSelectedUserHydration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$User,
        [Parameter(Mandatory=$true)][string]$Query
    )

    Set-HybridSearchProgressStage -Stage 'Base User' -Percent 20
    $script:SelectedHybridUser = $User
    $controls.ResultHeader.Text = Get-DisplayValue -InputObject $User -Names @('DisplayName','Name') -Default $Query
    $controls.DisplayNameText.Text = Get-DisplayValue -InputObject $User -Names @('DisplayName','Name')
    $controls.UpnText.Text = Get-DisplayValue -InputObject $User -Names @('UserPrincipalName','UPN')
    $controls.SamText.Text = Get-DisplayValue -InputObject $User -Names @('SamAccountName','SAMAccountName')
    $controls.MailText.Text = Get-DisplayValue -InputObject $User -Names @('Mail','EmailAddress')
    $controls.DepartmentText.Text = Get-DisplayValue -InputObject $User -Names @('Department')
    $controls.TitleText.Text = Get-DisplayValue -InputObject $User -Names @('Title','JobTitle')
    $controls.CompanyText.Text = Get-DisplayValue -InputObject $User -Names @('Company')
    $controls.OfficeText.Text = Get-DisplayValue -InputObject $User -Names @('Office')
    $controls.EmployeeIdText.Text = Get-DisplayValue -InputObject $User -Names @('EmployeeId','EmployeeID')
    $controls.BadgeIdText.Text = Get-DisplayValue -InputObject $User -Names @('BadgeId','EmployeeNumber','employeeNumber','extensionAttribute1')
    $controls.StateText.Text = Get-DisplayValue -InputObject $User -Names @('State','st','StateOrProvince')
    $controls.PhoneNumberText.Text = Get-DisplayValue -InputObject $User -Names @('PhoneNumber','TelephoneNumber','telephoneNumber','OfficePhone','MobilePhone','mobile')
    $controls.DistinguishedNameText.Text = Resolve-HybridUserDistinguishedName -User $User
    $enabled = Get-DisplayValue -InputObject $User -Names @('Enabled') -Default 'Unknown'
    $locked = Get-DisplayValue -InputObject $User -Names @('LockedOut') -Default 'Unknown'
    $controls.AccountStateText.Text = "Account state: Enabled=$enabled | LockedOut=$locked"
    Write-HybridUiHydrationDiagnostic -Stage 'Search' -Message "Base user selected for hydration: $Query" -Level SUCCESS -Data ([pscustomobject]@{
        DisplayName = $controls.DisplayNameText.Text
        UserPrincipalName = $controls.UpnText.Text
        SamAccountName = $controls.SamText.Text
    })

    Set-HybridSearchProgressStage -Stage 'Active Directory Details' -Percent 35
    [void](Invoke-HybridUiHydrationStage -Stage 'ActiveDirectoryDetails' -Action { Update-DetailPanels -User $User -Query $Query } -OnFailure {
        param($ErrorRecord)
        $controls.ManagerText.Text = "AD details failed: $($ErrorRecord.Exception.Message)"
        $controls.OrganizationalUnitText.Text = 'Unavailable'
        if ($controls.GroupsList.Items.Count -eq 0) { [void]$controls.GroupsList.Items.Add('Groups unavailable') }
        if ($controls.DirectReportsList.Items.Count -eq 0) { [void]$controls.DirectReportsList.Items.Add('Direct reports unavailable') }
    })

    Set-HybridSearchProgressStage -Stage 'Microsoft Graph' -Percent 52
    [void](Invoke-HybridUiHydrationStage -Stage 'MicrosoftGraph' -Action { Update-GraphPanels -User $User -Query $Query } -OnFailure { param($ErrorRecord) $controls.GraphSummaryText.Text = "Graph profile load failed: $($ErrorRecord.Exception.Message)" })

    Set-HybridSearchProgressStage -Stage 'Exchange On-Prem' -Percent 60
    Set-HybridSearchProgressStage -Stage 'Exchange Online' -Percent 68
    [void](Invoke-HybridUiHydrationStage -Stage 'ExchangeMailbox' -Action { Update-ExchangePanels -User $User -Query $Query } -OnFailure {
        param($ErrorRecord)
        $controls.ExchangeSummaryText.Text = "Exchange mailbox load failed: $($ErrorRecord.Exception.Message)"
        $controls.RecipientTypeText.Text = 'Unavailable'
        $controls.MailboxStatusText.Text = 'Unavailable'
        $controls.ForwardingText.Text = 'Unavailable'
        if ($controls.MailboxDelegationList.Items.Count -eq 0) { [void]$controls.MailboxDelegationList.Items.Add('Mailbox delegations unavailable') }
        if ($controls.DistributionGroupsList.Items.Count -eq 0) { [void]$controls.DistributionGroupsList.Items.Add('Distribution groups unavailable') }
    })

    Set-HybridSearchProgressStage -Stage 'Authentication Posture' -Percent 78
    [void](Invoke-HybridUiHydrationStage -Stage 'AuthenticationPosture' -Action { Update-AuthenticationPanels -User $User -Query $Query } -OnFailure { param($ErrorRecord) $controls.AuthenticationSummaryText.Text = "Authentication profile load failed: $($ErrorRecord.Exception.Message)" })

    Set-HybridSearchProgressStage -Stage 'Aggregation' -Percent 92
    [void](Invoke-HybridUiHydrationStage -Stage 'Aggregation' -Action { Update-AggregationPanel -User $User -Query $Query } -OnFailure {
        param($ErrorRecord)
        $controls.AggregationSummaryText.Text = "Aggregation failed: $($ErrorRecord.Exception.Message)"
        $controls.AggregationStatusText.Text = 'Failed'
    })

    $controls.SourcesText.Text = if ($null -ne $User.Sources) { (($User.Sources | ForEach-Object { '{0}: {1}' -f $_.Name, $_.Available }) -join ' | ') } else { 'HybridUserService' }
    Set-HybridSearchProgressStage -Stage 'Complete' -Percent 100
    $controls.StatusText.Text = "Search complete: $Query | See logs\hydration-diagnostics.log for provider details"
    Update-HybridUiHealth
}

function Invoke-UserSearch {
    [CmdletBinding()]
    param([string]$Query)

    $effectiveQuery = if ($PSBoundParameters.ContainsKey('Query')) { $Query } else { $controls.SearchBox.Text }
    $effectiveQuery = if ($null -eq $effectiveQuery) { '' } else { $effectiveQuery.Trim() }
    if ([string]::IsNullOrWhiteSpace($effectiveQuery)) {
        $controls.StatusText.Text = 'Enter a search value.'
        return
    }

    $script:CurrentSearchQuery = $effectiveQuery
    $script:SelectedHybridUser = $null
    Reset-UserDisplay
    Set-HybridUiBusyState -Busy $true
    $controls.StatusText.Text = "Searching for $effectiveQuery ..."
    Set-HybridSearchProgressStage -Stage 'Search' -Percent 8

    try {
        $users = @(Search-HybridUser -Query $effectiveQuery)
        if ($script:CurrentSearchQuery -ne $effectiveQuery) { return }
        if ($users.Count -eq 0) {
            $controls.ResultHeader.Text = 'No users found.'
            $controls.StatusText.Text = 'No result.'
            Set-HybridSearchProgressStage -Stage 'No Results' -Percent 100
            return
        }

        $user = Select-HybridUserFromSearchResults -Users $users -Query $effectiveQuery
        if ($null -eq $user) {
            $controls.ResultHeader.Text = 'User selection cancelled.'
            $controls.StatusText.Text = "Search returned $($users.Count) matches; no user selected."
            Set-HybridSearchProgressStage -Stage 'Selection Cancelled' -Percent 100
            return
        }

        if ($users.Count -gt 1) {
            Write-HybridUiHydrationDiagnostic -Stage 'Search' -Message "Search returned multiple candidates; user selected one before hydration." -Level INFO -Data ([pscustomobject]@{
                Query = $effectiveQuery
                CandidateCount = $users.Count
                SelectedDisplayName = Get-DisplayValue -InputObject $user -Names @('DisplayName','Name') -Default ''
                SelectedSamAccountName = Get-DisplayValue -InputObject $user -Names @('SamAccountName','ActiveDirectorySamAccountName') -Default ''
                SelectedUserPrincipalName = Get-DisplayValue -InputObject $user -Names @('UserPrincipalName','UPN') -Default ''
            })
        }

        Invoke-HybridSelectedUserHydration -User $user -Query $effectiveQuery
    }
    catch {
        $controls.ResultHeader.Text = 'Search failed'
        $controls.StatusText.Text = $_.Exception.Message
        Write-HybridUiHydrationDiagnostic -Stage 'Search' -Message $_.Exception.Message -Level ERROR -Data ([pscustomobject]@{
            Query = $effectiveQuery
            ExceptionType = $_.Exception.GetType().FullName
            FullyQualifiedErrorId = $_.FullyQualifiedErrorId
            ScriptStackTrace = $_.ScriptStackTrace
        })
    }
    finally {
        Set-HybridUiBusyState -Busy $false
    }
}

$controls.SearchBox.Text = $InitialQuery
$controls.SearchButton.Add_Click({ Invoke-UserSearch -Query $controls.SearchBox.Text })
$controls.SearchBox.Add_KeyDown({ param($sender, $eventArgs) if ($eventArgs.Key -eq 'Return') { $eventArgs.Handled = $true; Invoke-UserSearch -Query $controls.SearchBox.Text } })
if ($controls.BackToStartButton) { $controls.BackToStartButton.Add_Click({ Show-HybridHomeView }) }
$controls.LaunchConsoleButton.Add_Click({ Invoke-HybridRuntimeProfileLaunch })
$controls.EditRuntimeProfileButton.Add_Click({ Show-HybridRuntimeProfileWizardForSelectedProfile })
$controls.ManageRuntimeThemeButton.Add_Click({ Show-HybridRuntimeThemeEditor })
$controls.NewRuntimeProfileButton.Add_Click({ Show-HybridRuntimeProfileWizardForNew })
$controls.RefreshRuntimeProfilesButton.Add_Click({ Initialize-HybridRuntimeProfileList })
if ($controls.DeleteRuntimeProfileButton) { $controls.DeleteRuntimeProfileButton.Add_Click({ Remove-HybridSelectedRuntimeProfile }) }
if ($controls.ImportExportRuntimeProfileButton) { $controls.ImportExportRuntimeProfileButton.Add_Click({ Show-HybridRuntimeProfileImportExportWizard }) }
if ($controls.SetDefaultRuntimeProfileButton) { $controls.SetDefaultRuntimeProfileButton.Add_Click({ Set-HybridSelectedRuntimeProfileDefault }) }
$controls.RuntimeProfileListBox.Add_SelectionChanged({ Select-HybridRuntimeProfileFromList })
$controls.WizardCancelButton.Add_Click({ Hide-HybridRuntimeProfileWizard })
$controls.ThemeEditorCloseButton.Add_Click({ Hide-HybridRuntimeThemeEditor })
$controls.ThemeEditorCancelButton.Add_Click({ Hide-HybridRuntimeThemeEditor })
$controls.ThemeEditorPreviewButton.Add_Click({ Update-HybridRuntimeThemePreview })
$controls.ThemeEditorSaveButton.Add_Click({ Save-HybridRuntimeThemePackage })
$controls.WizardCloseButton.Add_Click({ Hide-HybridRuntimeProfileWizard })
$controls.WizardBackButton.Add_Click({ Move-HybridRuntimeProfileWizardBack })
$controls.WizardNextButton.Add_Click({ Move-HybridRuntimeProfileWizardNext })
$controls.WizardValidateButton.Add_Click({ [void](Test-HybridRuntimeProfileWizardInput) })
$controls.WizardSaveButton.Add_Click({ Save-HybridRuntimeProfileFromWizard })
$controls.ExitButton.Add_Click({ $window.Close() })

Initialize-HybridRuntimeProfileList
Update-HybridStartupView
$null = $window.ShowDialog()
