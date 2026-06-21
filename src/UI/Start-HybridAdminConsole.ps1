[CmdletBinding()]
param(
    [switch]$Mock,
    [string]$InitialQuery = ''
)

Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$serviceModule = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'
if (-not (Test-Path $serviceModule)) { throw "Application service module not found: $serviceModule" }
Import-Module $serviceModule -Force
$simulatorModule = Join-Path $repoRoot 'src\Infrastructure\Mock\Infrastructure.DirectorySimulator.psm1'
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

if ($Mock) {
    if (-not (Test-Path $simulatorModule)) { throw "Directory simulator module not found: $simulatorModule" }
    Import-Module $simulatorModule -Force
    $simulatorProviders = New-HybridDirectorySimulatorProviders
    Initialize-HybridUserService `
        -ActiveDirectoryProvider $simulatorProviders.ActiveDirectory `
        -MicrosoftGraphProvider $simulatorProviders.MicrosoftGraph `
        -ExchangeOnlineProvider $simulatorProviders.ExchangeOnline | Out-Null
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
        Title="Hybrid Admin Console" Height="760" Width="1180" WindowStartupLocation="CenterScreen" Background="#101826">
    <Window.Resources>
        <Style x:Key="Card" TargetType="Border"><Setter Property="Background" Value="#172337"/><Setter Property="CornerRadius" Value="14"/><Setter Property="Padding" Value="16"/><Setter Property="Margin" Value="0,0,0,12"/></Style>
        <Style x:Key="LabelText" TargetType="TextBlock"><Setter Property="Foreground" Value="#94A3B8"/><Setter Property="FontSize" Value="12"/></Style>
        <Style x:Key="ValueText" TargetType="TextBlock"><Setter Property="Foreground" Value="#E5E7EB"/><Setter Property="FontSize" Value="15"/><Setter Property="Margin" Value="0,2,0,10"/></Style>
    </Window.Resources>
    <Grid Margin="22">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

        <StackPanel Grid.Row="0" Grid.ColumnSpan="2" Margin="0,0,0,18">
            <TextBlock Text="Hybrid Admin Console" Foreground="#E5E7EB" FontSize="30" FontWeight="SemiBold"/>
            <TextBlock Text="Service-backed vertical slice" Foreground="#38BDF8" FontSize="13"/>
        </StackPanel>

        <Border Grid.Row="1" Grid.ColumnSpan="2" Style="{StaticResource Card}">
            <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="140"/><ColumnDefinition Width="230"/></Grid.ColumnDefinitions>
                <TextBox x:Name="SearchBox" Grid.Column="0" Height="38" FontSize="16" Padding="10" VerticalContentAlignment="Center"/>
                <Button x:Name="SearchButton" Grid.Column="1" Content="Search" Height="38" Margin="12,0,0,0"/>
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="18,0,0,0">
                    <Ellipse x:Name="ProviderDot" Width="12" Height="12" Fill="#22C55E" Margin="0,0,8,0"/>
                    <TextBlock x:Name="ProviderStatusText" Text="Provider health: checking" Foreground="#CBD5E1" VerticalAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>

        <Grid Grid.Row="2" Grid.ColumnSpan="2">
            <Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto" Margin="0,0,12,0">
                <StackPanel>
                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <TextBlock x:Name="ResultHeader" Text="Search for a user" Foreground="#F8FAFC" FontSize="24" FontWeight="SemiBold"/>
                            <TextBlock x:Name="AccountStateText" Text="Account state: waiting" Foreground="#38BDF8" FontWeight="SemiBold" Margin="0,4,0,14"/>
                            <TextBlock Text="Display Name" Style="{StaticResource LabelText}"/><TextBlock x:Name="DisplayNameText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="UPN" Style="{StaticResource LabelText}"/><TextBlock x:Name="UpnText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="SAM Account" Style="{StaticResource LabelText}"/><TextBlock x:Name="SamText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="Mail" Style="{StaticResource LabelText}"/><TextBlock x:Name="MailText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="Department" Style="{StaticResource LabelText}"/><TextBlock x:Name="DepartmentText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="Title" Style="{StaticResource LabelText}"/><TextBlock x:Name="TitleText" Text="—" Style="{StaticResource ValueText}"/>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource Card}">
                        <StackPanel>
                            <TextBlock Text="Live Active Directory Properties" Foreground="#F8FAFC" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,12"/>
                            <TextBlock Text="Company" Style="{StaticResource LabelText}"/><TextBlock x:Name="CompanyText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="Office" Style="{StaticResource LabelText}"/><TextBlock x:Name="OfficeText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="Employee ID" Style="{StaticResource LabelText}"/><TextBlock x:Name="EmployeeIdText" Text="—" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="Distinguished Name" Style="{StaticResource LabelText}"/><TextBlock x:Name="DistinguishedNameText" Text="—" TextWrapping="Wrap" Style="{StaticResource ValueText}"/>
                            <TextBlock Text="Organizational Unit" Style="{StaticResource LabelText}"/><TextBlock x:Name="OrganizationalUnitText" Text="—" Style="{StaticResource ValueText}"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </ScrollViewer>

            <StackPanel Grid.Column="1">
                <Border x:Name="ManagerCard" Style="{StaticResource Card}">
                    <StackPanel><TextBlock Text="Manager" Foreground="#F8FAFC" FontSize="18" FontWeight="SemiBold"/><TextBlock x:Name="ManagerText" Text="—" Style="{StaticResource ValueText}"/></StackPanel>
                </Border>
                <Border Style="{StaticResource Card}">
                    <StackPanel><TextBlock Text="Groups" Foreground="#F8FAFC" FontSize="18" FontWeight="SemiBold"/><ListBox x:Name="GroupsList" MinHeight="120"/></StackPanel>
                </Border>
                <Border Style="{StaticResource Card}">
                    <StackPanel><TextBlock Text="Direct Reports" Foreground="#F8FAFC" FontSize="18" FontWeight="SemiBold"/><ListBox x:Name="DirectReportsList" MinHeight="120"/></StackPanel>
                </Border>
                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="Exchange Mailbox" Foreground="#F8FAFC" FontSize="18" FontWeight="SemiBold"/>
                        <TextBlock Text="Primary SMTP" Style="{StaticResource LabelText}"/><TextBlock x:Name="MailboxText" Text="—" Style="{StaticResource ValueText}"/>
                        <TextBlock Text="Recipient Type" Style="{StaticResource LabelText}"/><TextBlock x:Name="RecipientTypeText" Text="—" Style="{StaticResource ValueText}"/>
                        <TextBlock Text="Mailbox Status" Style="{StaticResource LabelText}"/><TextBlock x:Name="MailboxStatusText" Text="—" Style="{StaticResource ValueText}"/>
                        <TextBlock Text="Forwarding" Style="{StaticResource LabelText}"/><TextBlock x:Name="ForwardingText" Text="—" TextWrapping="Wrap" Style="{StaticResource ValueText}"/>
                        <TextBlock Text="Delegation" Style="{StaticResource LabelText}"/><ListBox x:Name="MailboxDelegationList" MinHeight="78"/>
                        <TextBlock Text="Distribution Groups" Style="{StaticResource LabelText}" Margin="0,10,0,0"/><ListBox x:Name="DistributionGroupsList" MinHeight="78"/>
                        <TextBlock Text="Sources" Style="{StaticResource LabelText}" Margin="0,10,0,0"/><TextBlock x:Name="SourcesText" Text="—" TextWrapping="Wrap" Style="{StaticResource ValueText}"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </Grid>

        <Grid Grid.Row="3" Grid.ColumnSpan="2" Margin="0,12,0,0">
            <ProgressBar x:Name="SearchProgressIndicator" Height="8" IsIndeterminate="False" Visibility="Collapsed"/>
            <TextBlock x:Name="StatusText" Text="Ready." Foreground="#CBD5E1" Margin="0,14,0,0"/>
        </Grid>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [Windows.Markup.XamlReader]::Load($reader)

$controls = @{}
@('SearchBox','SearchButton','ResultHeader','StatusText','DisplayNameText','UpnText','SamText','MailText','DepartmentText','TitleText','MailboxText','SourcesText','ProviderStatusText','ProviderDot','SearchProgressIndicator','CompanyText','OfficeText','EmployeeIdText','DistinguishedNameText','AccountStateText','OrganizationalUnitText','ManagerText','GroupsList','DirectReportsList','RecipientTypeText','MailboxStatusText','ForwardingText','MailboxDelegationList','DistributionGroupsList') | ForEach-Object { $controls[$_] = $window.FindName($_) }

$script:IsSearchBusy = $false
$script:CurrentSearchQuery = $null
$script:SelectedHybridUser = $null

function Set-HybridUiBusyState {
    param([bool]$Busy)
    $script:IsSearchBusy = $Busy
    $controls.SearchButton.IsEnabled = -not $Busy
    $controls.SearchProgressIndicator.Visibility = if ($Busy) { 'Visible' } else { 'Collapsed' }
    $controls.SearchProgressIndicator.IsIndeterminate = $Busy
}

function Get-DisplayValue {
    param([AllowNull()][object]$InputObject, [string[]]$Names, [string]$Default = '—')
    foreach ($name in $Names) {
        if ($null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains $name) {
            $value = $InputObject.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return [string]$value }
        }
    }
    return $Default
}

function Reset-UserDisplay {
    $controls.ResultHeader.Text = 'Searching...'
    foreach ($name in @('DisplayNameText','UpnText','SamText','MailText','DepartmentText','TitleText','MailboxText','SourcesText','CompanyText','OfficeText','EmployeeIdText','DistinguishedNameText','OrganizationalUnitText','ManagerText','RecipientTypeText','MailboxStatusText','ForwardingText')) { $controls[$name].Text = '—' }
    $controls.AccountStateText.Text = 'Account state: loading'
    $controls.GroupsList.Items.Clear()
    $controls.DirectReportsList.Items.Clear()
    $controls.MailboxDelegationList.Items.Clear()
    $controls.DistributionGroupsList.Items.Clear()
}

function Update-HybridUiHealth {
    try {
        $health = Get-HybridUserServiceHealth
        $adAvailable = $false
        if ($null -ne $health.Providers -and $health.Providers.ContainsKey('ActiveDirectory')) { $adAvailable = [bool]$health.Providers.ActiveDirectory }
        $controls.ProviderStatusText.Text = if ($adAvailable) { 'Provider health: AD connected' } else { 'Provider health: AD unavailable' }
        $controls.ProviderDot.Fill = if ($adAvailable) { '#22C55E' } else { '#F97316' }
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
        if ([string]::IsNullOrWhiteSpace($identity) -or $identity -eq '—') { $identity = $Query }
        $details = Get-HybridUserDetails -Identity $identity
    }

    $managerValue = Get-DisplayValue -InputObject $details -Names @('ManagerDisplayName','ManagerName','Manager')
    $controls.ManagerText.Text = $managerValue
    $controls.OrganizationalUnitText.Text = Get-DisplayValue -InputObject $details -Names @('OrganizationalUnit','OU')

    $groups = @()
    if ($details.PSObject.Properties.Name -contains 'Groups' -and $null -ne $details.Groups) { $groups = @($details.Groups) }
    foreach ($group in $groups) { [void]$controls.GroupsList.Items.Add([string]$group) }
    if ($controls.GroupsList.Items.Count -eq 0) { [void]$controls.GroupsList.Items.Add('No groups loaded') }

    $reports = @()
    if ($details.PSObject.Properties.Name -contains 'DirectReports' -and $null -ne $details.DirectReports) { $reports = @($details.DirectReports) }
    foreach ($report in $reports) {
        $text = Get-DisplayValue -InputObject $report -Names @('DisplayName','Name','UserPrincipalName') -Default ([string]$report)
        [void]$controls.DirectReportsList.Items.Add($text)
    }
    if ($controls.DirectReportsList.Items.Count -eq 0) { [void]$controls.DirectReportsList.Items.Add('No direct reports loaded') }
}

function Update-ExchangePanels {
    param([Parameter(Mandatory=$true)][object]$User, [Parameter(Mandatory=$true)][string]$Query)

    $controls.RecipientTypeText.Text = 'Loading Exchange...'
    $controls.MailboxStatusText.Text = 'Loading Exchange...'
    $controls.ForwardingText.Text = 'Loading Exchange...'
    $controls.MailboxDelegationList.Items.Clear()
    $controls.DistributionGroupsList.Items.Clear()

    $exchangeUser = $User
    if (Get-Command Get-HybridUserMailboxDetails -ErrorAction SilentlyContinue) {
        $identity = Get-DisplayValue -InputObject $User -Names @('UserPrincipalName','Mail','SamAccountName','Identity') -Default $Query
        if ([string]::IsNullOrWhiteSpace($identity) -or $identity -eq '—') { $identity = $Query }
        $exchangeUser = Get-HybridUserMailboxDetails -Identity $identity
    }

    $mailboxDetails = $null
    if ($exchangeUser.PSObject.Properties.Name -contains 'MailboxDetails') { $mailboxDetails = $exchangeUser.MailboxDetails }
    $mailbox = if ($null -ne $mailboxDetails -and $mailboxDetails.PSObject.Properties.Name -contains 'Mailbox') { $mailboxDetails.Mailbox } else { $exchangeUser.Mailbox }

    $controls.MailboxText.Text = if ($null -ne $mailboxDetails) { Get-DisplayValue -InputObject $mailboxDetails -Names @('PrimarySmtpAddress') } elseif ($null -ne $mailbox) { Get-DisplayValue -InputObject $mailbox -Names @('PrimarySmtpAddress','Mail') } else { 'Not found' }
    $controls.RecipientTypeText.Text = if ($null -ne $mailboxDetails) { Get-DisplayValue -InputObject $mailboxDetails -Names @('RecipientTypeDetails') } elseif ($null -ne $mailbox) { Get-DisplayValue -InputObject $mailbox -Names @('RecipientTypeDetails','RecipientType') } else { 'Not found' }

    $hidden = if ($null -ne $mailboxDetails) { Get-DisplayValue -InputObject $mailboxDetails -Names @('HiddenFromAddressListsEnabled') -Default 'Unknown' } else { 'Unknown' }
    $hold = if ($null -ne $mailboxDetails) { Get-DisplayValue -InputObject $mailboxDetails -Names @('LitigationHoldEnabled') -Default 'Unknown' } else { 'Unknown' }
    $controls.MailboxStatusText.Text = "Hidden=$hidden | LitigationHold=$hold"

    $forwardTo = if ($null -ne $mailboxDetails) { Get-DisplayValue -InputObject $mailboxDetails -Names @('ForwardingSmtpAddress') -Default '' } else { '' }
    $deliverAndForward = if ($null -ne $mailboxDetails) { Get-DisplayValue -InputObject $mailboxDetails -Names @('DeliverToMailboxAndForward') -Default 'Unknown' } else { 'Unknown' }
    $controls.ForwardingText.Text = if ([string]::IsNullOrWhiteSpace($forwardTo)) { "No forwarding configured" } else { "Forwarding to $forwardTo | DeliverToMailboxAndForward=$deliverAndForward" }

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
    foreach ($group in $distributionGroups) { [void]$controls.DistributionGroupsList.Items.Add([string]$group) }
    if ($controls.DistributionGroupsList.Items.Count -eq 0) { [void]$controls.DistributionGroupsList.Items.Add('No distribution groups loaded') }
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

    try {
        $users = @(Search-HybridUser -Query $effectiveQuery)
        if ($script:CurrentSearchQuery -ne $effectiveQuery) { return }
        if ($users.Count -eq 0) {
            $controls.ResultHeader.Text = 'No users found.'
            $controls.StatusText.Text = 'No result.'
            return
        }

        $user = $users[0]
        $script:SelectedHybridUser = $user
        $controls.ResultHeader.Text = Get-DisplayValue -InputObject $user -Names @('DisplayName','Name') -Default $effectiveQuery
        $controls.DisplayNameText.Text = Get-DisplayValue -InputObject $user -Names @('DisplayName','Name')
        $controls.UpnText.Text = Get-DisplayValue -InputObject $user -Names @('UserPrincipalName','UPN')
        $controls.SamText.Text = Get-DisplayValue -InputObject $user -Names @('SamAccountName','SAMAccountName')
        $controls.MailText.Text = Get-DisplayValue -InputObject $user -Names @('Mail','EmailAddress')
        $controls.DepartmentText.Text = Get-DisplayValue -InputObject $user -Names @('Department')
        $controls.TitleText.Text = Get-DisplayValue -InputObject $user -Names @('Title','JobTitle')
        $controls.CompanyText.Text = Get-DisplayValue -InputObject $user -Names @('Company')
        $controls.OfficeText.Text = Get-DisplayValue -InputObject $user -Names @('Office')
        $controls.EmployeeIdText.Text = Get-DisplayValue -InputObject $user -Names @('EmployeeId','EmployeeID')
        $controls.DistinguishedNameText.Text = Get-DisplayValue -InputObject $user -Names @('DistinguishedName')
        $enabled = Get-DisplayValue -InputObject $user -Names @('Enabled') -Default 'Unknown'
        $locked = Get-DisplayValue -InputObject $user -Names @('LockedOut') -Default 'Unknown'
        $controls.AccountStateText.Text = "Account state: Enabled=$enabled | LockedOut=$locked"
        Update-ExchangePanels -User $user -Query $effectiveQuery
        $controls.SourcesText.Text = if ($null -ne $user.Sources) { (($user.Sources | ForEach-Object { '{0}: {1}' -f $_.Name, $_.Available }) -join ' | ') } else { 'HybridUserService' }
        Update-DetailPanels -User $user -Query $effectiveQuery
        $controls.StatusText.Text = "Search complete: $effectiveQuery | Live AD vertical slice result returned through HybridUserService | Live AD and Exchange vertical slice result returned through HybridUserService"
        Update-HybridUiHealth
    }
    catch {
        $controls.ResultHeader.Text = 'Search failed'
        $controls.StatusText.Text = $_.Exception.Message
    }
    finally {
        Set-HybridUiBusyState -Busy $false
    }
}

$controls.SearchBox.Text = $InitialQuery
$controls.SearchButton.Add_Click({ Invoke-UserSearch -Query $controls.SearchBox.Text })
$controls.SearchBox.Add_KeyDown({ param($sender, $eventArgs) if ($eventArgs.Key -eq 'Return') { $eventArgs.Handled = $true; Invoke-UserSearch -Query $controls.SearchBox.Text } })

Update-HybridUiHealth
if (-not [string]::IsNullOrWhiteSpace($InitialQuery)) { Invoke-UserSearch -Query $InitialQuery }
$null = $window.ShowDialog()
