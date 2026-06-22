Set-StrictMode -Version Latest

function New-HybridLaunchButtonContent {
    [CmdletBinding()]
    param(
        [string]$ProfileName = 'Console',
        [string]$ShortcutText = 'Enter'
    )

    $name = if ([string]::IsNullOrWhiteSpace($ProfileName)) { 'Console' } else { $ProfileName.Trim() }
    $display = if ($name -eq 'Console') { 'Launch Console' } else { "Launch $name" }

    $panel = [System.Windows.Controls.StackPanel]::new()
    $panel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $panel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $title = [System.Windows.Controls.TextBlock]::new()
    $title.Text = $display
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F0FDF4')
    $title.FontWeight = [System.Windows.FontWeights]::Bold
    $title.FontSize = 14
    $title.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $title.TextAlignment = [System.Windows.TextAlignment]::Center
    $title.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $title.MaxWidth = 118

    $shortcut = [System.Windows.Controls.TextBlock]::new()
    $shortcut.Text = $ShortcutText
    $shortcut.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#BBF7D0')
    $shortcut.FontSize = 12
    $shortcut.Margin = [System.Windows.Thickness]::new(0,8,0,0)
    $shortcut.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center

    $panel.Children.Add($title) | Out-Null
    $panel.Children.Add($shortcut) | Out-Null
    return $panel
}

function Set-HybridLaunchButtonProfileLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Controls.Button]$Button,
        [AllowNull()][object]$Profile
    )

    $name = if ($null -eq $Profile -or [string]::IsNullOrWhiteSpace([string]$Profile.ProfileName)) { 'Console' } else { [string]$Profile.ProfileName }
    $Button.Content = New-HybridLaunchButtonContent -ProfileName $name
    $Button.ToolTip = if ($name -eq 'Console') { 'Launch Hybrid Admin Console' } else { "Launch $name" }
}

Export-ModuleMember -Function @('New-HybridLaunchButtonContent','Set-HybridLaunchButtonProfileLabel')
