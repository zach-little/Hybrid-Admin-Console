[CmdletBinding()]
param(
    [switch]$Mock,
    [string]$InitialQuery = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$serviceModule = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'

if (-not (Test-Path $serviceModule)) {
    throw "Application service module not found: $serviceModule"
}

Import-Module $serviceModule -Force

function New-HybridMockProviderSet {
    [CmdletBinding()]
    param()

    $mockAd = [pscustomobject]@{
        SearchUser = {
            param([string]$Query)
            @([pscustomobject]@{
                PSTypeName        = 'Hybrid.User'
                DisplayName       = 'Alex Morgan'
                SamAccountName    = 'amorgan'
                UserPrincipalName = 'amorgan@atlas-tech.com'
                Mail              = 'amorgan@atlas-tech.com'
                Department        = 'Information Technology'
                Title             = 'Systems Administrator'
                Company           = 'Atlas Tech'
                Office            = 'Charleston'
                EmployeeId        = '10042'
                DistinguishedName = 'CN=Alex Morgan,OU=Users,DC=atlas-tech,DC=com'
                Enabled           = $true
                LockedOut         = $false
                Manager           = 'CN=Taylor Reed,OU=Users,DC=atlas-tech,DC=com'
                Source            = 'ActiveDirectory'
            })
        }.GetNewClosure()
        GetUser = {
            param([string]$Identity)
            [pscustomobject]@{
                PSTypeName        = 'Hybrid.User'
                DisplayName       = 'Alex Morgan'
                SamAccountName    = 'amorgan'
                UserPrincipalName = 'amorgan@atlas-tech.com'
                Mail              = 'amorgan@atlas-tech.com'
                Department        = 'Information Technology'
                Title             = 'Systems Administrator'
                Company           = 'Atlas Tech'
                Office            = 'Charleston'
                EmployeeId        = '10042'
                DistinguishedName = 'CN=Alex Morgan,OU=Users,DC=atlas-tech,DC=com'
                Enabled           = $true
                LockedOut         = $false
                Manager           = 'CN=Taylor Reed,OU=Users,DC=atlas-tech,DC=com'
                Source            = 'ActiveDirectory'
            }
        }.GetNewClosure()
        GetHealth = {
            [pscustomobject]@{
                PSTypeName  = 'Hybrid.ProviderHealth.Mock'
                Initialized = $true
                Available   = $true
                Connected   = $true
                LastError   = $null
            }
        }.GetNewClosure()
    }

    $mockGraph = [pscustomobject]@{
        SearchUser = { param([string]$Query) @() }.GetNewClosure()
        GetUser    = { param([string]$Identity) $null }.GetNewClosure()
        GetHealth  = {
            [pscustomobject]@{
                PSTypeName  = 'Hybrid.ProviderHealth.Mock'
                Initialized = $false
                Available   = $false
                Connected   = $false
                LastError   = 'Graph is not part of Milestone 7 Phase 2.'
            }
        }.GetNewClosure()
    }

    $mockExchange = [pscustomobject]@{
        GetMailbox = { param([string]$Identity) $null }.GetNewClosure()
        GetHealth  = {
            [pscustomobject]@{
                PSTypeName  = 'Hybrid.ProviderHealth.Mock'
                Initialized = $false
                Available   = $false
                Connected   = $false
                LastError   = 'Exchange Online is not part of Milestone 7 Phase 2.'
            }
        }.GetNewClosure()
    }

    [pscustomobject]@{
        ActiveDirectory = $mockAd
        MicrosoftGraph  = $mockGraph
        ExchangeOnline  = $mockExchange
    }
}

function Format-HybridUiValue {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '—' }
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return '—' }
    return [string]$Value
}

function Format-HybridUiBool {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return 'Unknown' }
    if ([bool]$Value) { return 'Yes' }
    return 'No'
}

function Get-HybridUiSourceSummary {
    [CmdletBinding()]
    param([AllowNull()][object]$User)

    if ($null -eq $User -or -not ($User.PSObject.Properties.Name -contains 'Sources')) {
        return 'Provider status unavailable.'
    }

    $parts = @()
    foreach ($source in @($User.Sources)) {
        $name = Format-HybridUiValue $source.Name
        $state = if ($source.Connected) { 'Connected' } elseif ($source.Available) { 'Available' } else { 'Unavailable' }
        $parts += ('{0}: {1}' -f $name, $state)
    }

    if ($parts.Count -eq 0) { return 'Provider status unavailable.' }
    return ($parts -join '  •  ')
}

function Set-HybridUiText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Control,
        [AllowNull()][object]$Value
    )

    $Control.Text = Format-HybridUiValue $Value
}

if ($Mock) {
    $providers = New-HybridMockProviderSet
    Initialize-HybridUserService `
        -ActiveDirectoryProvider $providers.ActiveDirectory `
        -MicrosoftGraphProvider $providers.MicrosoftGraph `
        -ExchangeOnlineProvider $providers.ExchangeOnline | Out-Null
}
else {
    Initialize-HybridUserService | Out-Null
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Hybrid Admin Console"
        Width="1060"
        Height="720"
        MinWidth="980"
        MinHeight="640"
        WindowStartupLocation="CenterScreen"
        Background="#08111f">
    <Window.Resources>
        <SolidColorBrush x:Key="PanelBrush" Color="#111c2e" />
        <SolidColorBrush x:Key="CardBrush" Color="#16243a" />
        <SolidColorBrush x:Key="TextBrush" Color="#f5f8ff" />
        <SolidColorBrush x:Key="MutedBrush" Color="#a7b3c7" />
        <SolidColorBrush x:Key="AccentBrush" Color="#39d8ff" />
        <SolidColorBrush x:Key="GoodBrush" Color="#55f2a6" />
        <SolidColorBrush x:Key="WarnBrush" Color="#ffd166" />
        <SolidColorBrush x:Key="ErrorBrush" Color="#ff6b7a" />
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource TextBrush}" />
            <Setter Property="FontFamily" Value="Segoe UI" />
        </Style>
        <Style x:Key="MutedText" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource MutedBrush}" />
            <Setter Property="FontFamily" Value="Segoe UI" />
            <Setter Property="FontSize" Value="13" />
        </Style>
        <Style x:Key="FieldLabel" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource MutedBrush}" />
            <Setter Property="FontFamily" Value="Segoe UI" />
            <Setter Property="FontSize" Value="12" />
            <Setter Property="Margin" Value="0,0,0,4" />
        </Style>
        <Style x:Key="FieldValue" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource TextBrush}" />
            <Setter Property="FontFamily" Value="Segoe UI Semibold" />
            <Setter Property="FontSize" Value="15" />
            <Setter Property="TextWrapping" Value="Wrap" />
        </Style>
        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource CardBrush}" />
            <Setter Property="BorderBrush" Value="#27415f" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="CornerRadius" Value="18" />
            <Setter Property="Padding" Value="18" />
            <Setter Property="Margin" Value="0,0,0,16" />
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#0d1828" Padding="28,24,28,20" BorderBrush="#1d334d" BorderThickness="0,0,0,1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <TextBlock Text="Hybrid Admin Console" FontSize="26" FontFamily="Segoe UI Semibold" />
                    <TextBlock Text="Milestone 7 Phase 2 — Live Active Directory vertical slice" Style="{StaticResource MutedText}" Margin="0,4,0,0" />
                </StackPanel>
                <Border Grid.Column="1" x:Name="ProviderBadge" Background="#24334a" CornerRadius="18" Padding="14,7" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal">
                        <Ellipse x:Name="ProviderDot" Width="9" Height="9" Fill="{StaticResource WarnBrush}" Margin="0,0,8,0" VerticalAlignment="Center" />
                        <TextBlock x:Name="ProviderStatusText" Text="Checking providers" FontSize="13" FontFamily="Segoe UI Semibold" />
                    </StackPanel>
                </Border>
            </Grid>
        </Border>

        <Border Grid.Row="1" Background="#0a1423" Padding="28,18">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>
                <TextBox x:Name="SearchBox"
                         Height="46"
                         FontSize="17"
                         Padding="14,10"
                         Foreground="#f5f8ff"
                         Background="#101e33"
                         BorderBrush="#2c4968"
                         BorderThickness="1"
                         CaretBrush="#39d8ff"
                         VerticalContentAlignment="Center" />
                <Button x:Name="SearchButton"
                        Grid.Column="1"
                        Width="150"
                        Height="46"
                        Margin="16,0,0,0"
                        Content="Search"
                        FontSize="15"
                        FontFamily="Segoe UI Semibold"
                        Foreground="#04111f"
                        Background="{StaticResource AccentBrush}"
                        BorderThickness="0" />
            </Grid>
        </Border>

        <Grid Grid.Row="2" Margin="28,22,28,18">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="2*" />
                <ColumnDefinition Width="18" />
                <ColumnDefinition Width="1.15*" />
            </Grid.ColumnDefinitions>

            <StackPanel Grid.Column="0">
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock x:Name="ResultHeader" Text="Search for a user" FontSize="25" FontFamily="Segoe UI Semibold" />
                        <TextBlock x:Name="ResultSubHeader" Text="Live Active Directory results will appear here." Style="{StaticResource MutedText}" Margin="0,6,0,0" />
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*" />
                            <ColumnDefinition Width="*" />
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto" />
                            <RowDefinition Height="Auto" />
                            <RowDefinition Height="Auto" />
                        </Grid.RowDefinitions>

                        <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,16,14">
                            <TextBlock Text="Display Name" Style="{StaticResource FieldLabel}" />
                            <TextBlock x:Name="DisplayNameText" Text="—" Style="{StaticResource FieldValue}" />
                        </StackPanel>
                        <StackPanel Grid.Row="0" Grid.Column="1" Margin="0,0,0,14">
                            <TextBlock Text="User Principal Name" Style="{StaticResource FieldLabel}" />
                            <TextBlock x:Name="UpnText" Text="—" Style="{StaticResource FieldValue}" />
                        </StackPanel>
                        <StackPanel Grid.Row="1" Grid.Column="0" Margin="0,0,16,14">
                            <TextBlock Text="SAM Account" Style="{StaticResource FieldLabel}" />
                            <TextBlock x:Name="SamText" Text="—" Style="{StaticResource FieldValue}" />
                        </StackPanel>
                        <StackPanel Grid.Row="1" Grid.Column="1" Margin="0,0,0,14">
                            <TextBlock Text="Mail" Style="{StaticResource FieldLabel}" />
                            <TextBlock x:Name="MailText" Text="—" Style="{StaticResource FieldValue}" />
                        </StackPanel>
                        <StackPanel Grid.Row="2" Grid.Column="0" Margin="0,0,16,0">
                            <TextBlock Text="Department" Style="{StaticResource FieldLabel}" />
                            <TextBlock x:Name="DepartmentText" Text="—" Style="{StaticResource FieldValue}" />
                        </StackPanel>
                        <StackPanel Grid.Row="2" Grid.Column="1">
                            <TextBlock Text="Title" Style="{StaticResource FieldLabel}" />
                            <TextBlock x:Name="TitleText" Text="—" Style="{StaticResource FieldValue}" />
                        </StackPanel>
                    </Grid>
                </Border>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="Active Directory Properties" FontSize="18" FontFamily="Segoe UI Semibold" Margin="0,0,0,12" />
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*" />
                                <ColumnDefinition Width="*" />
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto" />
                                <RowDefinition Height="Auto" />
                                <RowDefinition Height="Auto" />
                            </Grid.RowDefinitions>
                            <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,16,14">
                                <TextBlock Text="Company" Style="{StaticResource FieldLabel}" />
                                <TextBlock x:Name="CompanyText" Text="—" Style="{StaticResource FieldValue}" />
                            </StackPanel>
                            <StackPanel Grid.Row="0" Grid.Column="1" Margin="0,0,0,14">
                                <TextBlock Text="Office" Style="{StaticResource FieldLabel}" />
                                <TextBlock x:Name="OfficeText" Text="—" Style="{StaticResource FieldValue}" />
                            </StackPanel>
                            <StackPanel Grid.Row="1" Grid.Column="0" Margin="0,0,16,14">
                                <TextBlock Text="Employee ID" Style="{StaticResource FieldLabel}" />
                                <TextBlock x:Name="EmployeeIdText" Text="—" Style="{StaticResource FieldValue}" />
                            </StackPanel>
                            <StackPanel Grid.Row="1" Grid.Column="1" Margin="0,0,0,14">
                                <TextBlock Text="Account State" Style="{StaticResource FieldLabel}" />
                                <TextBlock x:Name="AccountStateText" Text="—" Style="{StaticResource FieldValue}" />
                            </StackPanel>
                            <StackPanel Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="2">
                                <TextBlock Text="Distinguished Name" Style="{StaticResource FieldLabel}" />
                                <TextBlock x:Name="DistinguishedNameText" Text="—" Style="{StaticResource FieldValue}" />
                            </StackPanel>
                        </Grid>
                    </StackPanel>
                </Border>
            </StackPanel>

            <StackPanel Grid.Column="2">
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="Provider Health" FontSize="18" FontFamily="Segoe UI Semibold" Margin="0,0,0,12" />
                        <TextBlock x:Name="SourcesText" Text="No provider snapshot yet." Style="{StaticResource MutedText}" TextWrapping="Wrap" />
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="Search Activity" FontSize="18" FontFamily="Segoe UI Semibold" Margin="0,0,0,12" />
                        <TextBlock x:Name="StatusText" Text="Ready." Style="{StaticResource MutedText}" TextWrapping="Wrap" />
                        <ProgressBar x:Name="SearchProgress" Height="8" Margin="0,16,0,0" IsIndeterminate="False" Visibility="Collapsed" />
                    </StackPanel>
                </Border>
            </StackPanel>
        </Grid>

        <Border Grid.Row="3" Background="#0d1828" Padding="28,10" BorderBrush="#1d334d" BorderThickness="0,1,0,0">
            <TextBlock x:Name="FooterText" Text="UI is service-driven. Providers remain behind the application service boundary." Style="{StaticResource MutedText}" />
        </Border>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [Windows.Markup.XamlReader]::Load($reader)

$searchBox = $window.FindName('SearchBox')
$searchButton = $window.FindName('SearchButton')
$resultHeader = $window.FindName('ResultHeader')
$resultSubHeader = $window.FindName('ResultSubHeader')
$statusText = $window.FindName('StatusText')
$providerStatusText = $window.FindName('ProviderStatusText')
$providerDot = $window.FindName('ProviderDot')
$searchProgress = $window.FindName('SearchProgress')
$displayNameText = $window.FindName('DisplayNameText')
$upnText = $window.FindName('UpnText')
$samText = $window.FindName('SamText')
$mailText = $window.FindName('MailText')
$departmentText = $window.FindName('DepartmentText')
$titleText = $window.FindName('TitleText')
$companyText = $window.FindName('CompanyText')
$officeText = $window.FindName('OfficeText')
$employeeIdText = $window.FindName('EmployeeIdText')
$accountStateText = $window.FindName('AccountStateText')
$distinguishedNameText = $window.FindName('DistinguishedNameText')
$sourcesText = $window.FindName('SourcesText')

function Set-HybridUiBusyState {
    [CmdletBinding()]
    param([bool]$Busy)

    $searchButton.IsEnabled = -not $Busy
    $searchBox.IsEnabled = -not $Busy
    $searchProgress.Visibility = if ($Busy) { 'Visible' } else { 'Collapsed' }
    $searchProgress.IsIndeterminate = $Busy
    $null = $window.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Render)
}

function Update-HybridUiHealth {
    [CmdletBinding()]
    param()

    try {
        $health = Get-HybridUserServiceHealth
        $adHealth = $health.ProviderHealth.ActiveDirectory
        $adConnected = [bool]$adHealth.Connected
        if ($adConnected) {
            $providerStatusText.Text = 'Active Directory connected'
            $providerDot.Fill = [Windows.Media.Brushes]::LightGreen
        }
        elseif ($adHealth.Available) {
            $providerStatusText.Text = 'Active Directory available'
            $providerDot.Fill = [Windows.Media.Brushes]::Gold
        }
        else {
            $providerStatusText.Text = 'Active Directory unavailable'
            $providerDot.Fill = [Windows.Media.Brushes]::IndianRed
        }
    }
    catch {
        $providerStatusText.Text = 'Provider health unavailable'
        $providerDot.Fill = [Windows.Media.Brushes]::IndianRed
    }
}

function Show-HybridUiUser {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$User)

    $resultHeader.Text = Format-HybridUiValue $User.DisplayName
    $resultSubHeader.Text = 'Live AD vertical slice result returned through HybridUserService.'
    Set-HybridUiText -Control $displayNameText -Value $User.DisplayName
    Set-HybridUiText -Control $upnText -Value $User.UserPrincipalName
    Set-HybridUiText -Control $samText -Value $User.SamAccountName
    Set-HybridUiText -Control $mailText -Value $User.Mail
    Set-HybridUiText -Control $departmentText -Value $User.Department
    Set-HybridUiText -Control $titleText -Value $User.Title
    Set-HybridUiText -Control $companyText -Value $User.Company
    Set-HybridUiText -Control $officeText -Value $User.Office
    Set-HybridUiText -Control $employeeIdText -Value $User.EmployeeId
    Set-HybridUiText -Control $distinguishedNameText -Value $User.DistinguishedName

    $enabled = Format-HybridUiBool $User.Enabled
    $locked = Format-HybridUiBool $User.LockedOut
    $accountStateText.Text = "Enabled: $enabled | Locked: $locked"
    $sourcesText.Text = Get-HybridUiSourceSummary -User $User
}

$searchBox.Text = $InitialQuery
Update-HybridUiHealth

$searchAction = {
    $query = $searchBox.Text
    if ([string]::IsNullOrWhiteSpace($query)) {
        $statusText.Text = 'Enter a user name, SAM account, UPN, or email address.'
        return
    }

    try {
        Set-HybridUiBusyState -Busy $true
        $statusText.Text = "Searching Active Directory for '$query'..."
        $resultSubHeader.Text = 'Query submitted through the application service.'
        $started = Get-Date

        $users = @(Search-HybridUser -Query $query)
        if ($users.Count -eq 0) {
            $resultHeader.Text = 'No users found'
            $resultSubHeader.Text = "No Active Directory result matched '$query'."
            $statusText.Text = 'Search complete. No result returned.'
            $sourcesText.Text = 'No source returned a matching user.'
            return
        }

        $user = $users[0]
        Show-HybridUiUser -User $user
        $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
        $statusText.Text = "Search complete in $elapsed seconds. Showing the first result."
    }
    catch {
        $resultHeader.Text = 'Search failed'
        $resultSubHeader.Text = 'The application service returned an error.'
        $statusText.Text = $_.Exception.Message
        $sourcesText.Text = 'Review provider health, authentication, and Active Directory connectivity.'
    }
    finally {
        Set-HybridUiBusyState -Busy $false
        Update-HybridUiHealth
    }
}

$searchButton.Add_Click($searchAction)
$searchBox.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.Key -eq 'Return') {
        & $searchAction
    }
})

if (-not [string]::IsNullOrWhiteSpace($InitialQuery)) {
    & $searchAction
}

$null = $window.ShowDialog()
