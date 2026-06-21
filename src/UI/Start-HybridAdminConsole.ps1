[CmdletBinding()]
param(
    [switch]$Mock,
    [string]$InitialQuery = ''
)

Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$serviceModule = Join-Path $repoRoot 'src\Application\Application.HybridUserService.psm1'

if (-not (Test-Path $serviceModule)) {
    throw "Application service module not found: $serviceModule"
}

Import-Module $serviceModule -Force

if ($Mock) {
    $mockAd = [pscustomobject]@{
        SearchUser = { param([string]$Query)
            @([pscustomobject]@{
                PSTypeName = 'Hybrid.User'
                DisplayName = 'Alex Morgan'
                SamAccountName = 'amorgan'
                UserPrincipalName = 'amorgan@atlas-tech.com'
                Mail = 'amorgan@atlas-tech.com'
                Department = 'Information Technology'
                Title = 'Systems Administrator'
                Manager = 'CN=Taylor Reed,OU=Users,DC=atlas-tech,DC=com'
                Source = 'ActiveDirectory'
            })
        }.GetNewClosure()
        GetUser = { param([string]$Identity)
            [pscustomobject]@{
                PSTypeName = 'Hybrid.User'
                DisplayName = 'Alex Morgan'
                SamAccountName = 'amorgan'
                UserPrincipalName = 'amorgan@atlas-tech.com'
                Mail = 'amorgan@atlas-tech.com'
                Department = 'Information Technology'
                Title = 'Systems Administrator'
                Manager = 'CN=Taylor Reed,OU=Users,DC=atlas-tech,DC=com'
                Source = 'ActiveDirectory'
            }
        }.GetNewClosure()
    }

    $mockGraph = [pscustomobject]@{
        SearchUser = { param([string]$Query)
            @([pscustomobject]@{
                PSTypeName = 'Hybrid.User'
                DisplayName = 'Alex Morgan'
                UserPrincipalName = 'amorgan@atlas-tech.com'
                Mail = 'amorgan@atlas-tech.com'
                Department = 'Information Technology'
                JobTitle = 'Systems Administrator'
                Source = 'MicrosoftGraph'
            })
        }.GetNewClosure()
        GetUser = { param([string]$Identity)
            [pscustomobject]@{
                PSTypeName = 'Hybrid.User'
                DisplayName = 'Alex Morgan'
                UserPrincipalName = 'amorgan@atlas-tech.com'
                Mail = 'amorgan@atlas-tech.com'
                Department = 'Information Technology'
                JobTitle = 'Systems Administrator'
                Source = 'MicrosoftGraph'
            }
        }.GetNewClosure()
    }

    $mockExchange = [pscustomobject]@{
        GetMailbox = { param([string]$Identity)
            [pscustomobject]@{
                PSTypeName = 'Hybrid.Mailbox'
                DisplayName = 'Alex Morgan'
                PrimarySmtpAddress = 'amorgan@atlas-tech.com'
                RecipientTypeDetails = 'UserMailbox'
                Source = 'ExchangeOnline'
            }
        }.GetNewClosure()
    }

    Initialize-HybridUserService -ActiveDirectoryProvider $mockAd -MicrosoftGraphProvider $mockGraph -ExchangeOnlineProvider $mockExchange | Out-Null
}
else {
    Initialize-HybridUserService | Out-Null
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Hybrid Admin Console - Vertical Slice"
        Height="620"
        Width="980"
        WindowStartupLocation="CenterScreen"
        Background="#101820">
    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,20">
            <TextBlock Text="Hybrid Admin Console"
                       Foreground="#EAF6FF"
                       FontSize="30"
                       FontWeight="SemiBold"/>
            <TextBlock Text="Milestone 7 Phase 1 - First Vertical Slice"
                       Foreground="#8FB3C8"
                       FontSize="14"/>
        </StackPanel>

        <Grid Grid.Row="1" Margin="0,0,0,20">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="140"/>
            </Grid.ColumnDefinitions>
            <TextBox Name="SearchBox"
                     Grid.Column="0"
                     Height="44"
                     FontSize="18"
                     Padding="12,8"/>
            <Button Name="SearchButton"
                    Grid.Column="1"
                    Margin="12,0,0,0"
                    Height="44"
                    Content="Search"
                    FontSize="16"/>
        </Grid>

        <Border Grid.Row="2"
                Background="#182631"
                CornerRadius="14"
                Padding="24">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <TextBlock Name="ResultHeader"
                           Grid.Row="0"
                           Text="Search for a user to populate the vertical slice."
                           Foreground="#EAF6FF"
                           FontSize="20"
                           Margin="0,0,0,18"/>

                <Grid Grid.Row="1">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0">
                        <TextBlock Text="Display Name" Foreground="#8FB3C8"/>
                        <TextBlock Name="DisplayNameText" Foreground="#FFFFFF" FontSize="18" Margin="0,0,0,14"/>

                        <TextBlock Text="UPN" Foreground="#8FB3C8"/>
                        <TextBlock Name="UpnText" Foreground="#FFFFFF" FontSize="18" Margin="0,0,0,14"/>

                        <TextBlock Text="SAM Account" Foreground="#8FB3C8"/>
                        <TextBlock Name="SamText" Foreground="#FFFFFF" FontSize="18" Margin="0,0,0,14"/>

                        <TextBlock Text="Mail" Foreground="#8FB3C8"/>
                        <TextBlock Name="MailText" Foreground="#FFFFFF" FontSize="18" Margin="0,0,0,14"/>
                    </StackPanel>

                    <StackPanel Grid.Column="1">
                        <TextBlock Text="Department" Foreground="#8FB3C8"/>
                        <TextBlock Name="DepartmentText" Foreground="#FFFFFF" FontSize="18" Margin="0,0,0,14"/>

                        <TextBlock Text="Title" Foreground="#8FB3C8"/>
                        <TextBlock Name="TitleText" Foreground="#FFFFFF" FontSize="18" Margin="0,0,0,14"/>

                        <TextBlock Text="Mailbox" Foreground="#8FB3C8"/>
                        <TextBlock Name="MailboxText" Foreground="#FFFFFF" FontSize="18" Margin="0,0,0,14"/>

                        <TextBlock Text="Sources" Foreground="#8FB3C8"/>
                        <TextBlock Name="SourcesText" Foreground="#FFFFFF" FontSize="18" TextWrapping="Wrap"/>
                    </StackPanel>
                </Grid>
            </Grid>
        </Border>

        <TextBlock Name="StatusText"
                   Grid.Row="3"
                   Foreground="#8FB3C8"
                   Margin="0,16,0,0"
                   Text="Ready."/>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [Windows.Markup.XamlReader]::Load($reader)

$searchBox = $window.FindName('SearchBox')
$searchButton = $window.FindName('SearchButton')
$resultHeader = $window.FindName('ResultHeader')
$statusText = $window.FindName('StatusText')

$displayNameText = $window.FindName('DisplayNameText')
$upnText = $window.FindName('UpnText')
$samText = $window.FindName('SamText')
$mailText = $window.FindName('MailText')
$departmentText = $window.FindName('DepartmentText')
$titleText = $window.FindName('TitleText')
$mailboxText = $window.FindName('MailboxText')
$sourcesText = $window.FindName('SourcesText')

$searchBox.Text = $InitialQuery

$searchAction = {
    try {
        $query = $searchBox.Text
        $statusText.Text = "Searching for $query ..."
        $users = @(Search-HybridUser -Query $query)
        if ($users.Count -eq 0) {
            $resultHeader.Text = 'No users found.'
            $statusText.Text = 'No result.'
            return
        }

        $user = $users[0]
        $resultHeader.Text = $user.DisplayName
        $displayNameText.Text = $user.DisplayName
        $upnText.Text = $user.UserPrincipalName
        $samText.Text = $user.SamAccountName
        $mailText.Text = $user.Mail
        $departmentText.Text = $user.Department
        $titleText.Text = $user.Title
        $mailboxText.Text = if ($null -ne $user.Mailbox) { [string]$user.Mailbox.PrimarySmtpAddress } else { 'Not found' }
        $sourcesText.Text = (($user.Sources | ForEach-Object { '{0}: {1}' -f $_.Name, $_.Available }) -join '  |  ')
        $statusText.Text = 'Search complete.'
    }
    catch {
        $statusText.Text = $_.Exception.Message
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
