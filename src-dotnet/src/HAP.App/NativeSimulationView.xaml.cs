using System.Windows;
using System.Windows.Controls;
using HAP.Contracts;
using HAP.Providers.Abstractions;
using HAP.Providers.Simulator;

namespace HAP.App;

public partial class NativeSimulationView : UserControl
{
    private readonly DirectorySimulatorProvider _simulator = new();

    public NativeSimulationView()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        await SearchAsync().ConfigureAwait(true);
    }

    private async void OnSearchClicked(object sender, RoutedEventArgs e)
    {
        await SearchAsync().ConfigureAwait(true);
    }

    private async void OnUserSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (UsersList.SelectedItem is SimulatorUserSummary user)
        {
            await LoadUserDetailsAsync(user).ConfigureAwait(true);
        }
    }

    private async Task SearchAsync()
    {
        StatusText.Text = "Searching native simulator...";
        UsersList.ItemsSource = null;
        var result = await _simulator.SearchUsersAsync(SearchBox.Text, CorrelationId.New()).ConfigureAwait(true);
        if (!result.Succeeded)
        {
            StatusText.Text = string.Join(" ", result.Errors.Select(error => error.Message));
            return;
        }

        UsersList.ItemsSource = result.Value;
        UsersList.SelectedIndex = result.Value?.Count > 0 ? 0 : -1;
        StatusText.Text = $"Loaded {result.Value?.Count ?? 0} user result(s) from the native simulator.";
    }

    private async Task LoadUserDetailsAsync(SimulatorUserSummary user)
    {
        SelectedNameText.Text = user.DisplayName;
        UpnText.Text = user.UserPrincipalName;
        DepartmentText.Text = user.Department;
        TitleText.Text = user.Title;
        ManagerText.Text = string.IsNullOrWhiteSpace(user.ManagerSamAccountName) ? "-" : user.ManagerSamAccountName;

        var groups = await _simulator.GetGroupsAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
        GroupsList.ItemsSource = groups.Value?.Select(group => group.DisplayName).ToArray() ?? Array.Empty<string>();

        var devices = await _simulator.GetManagedDevicesAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
        DevicesList.ItemsSource = devices.Value?.Select(device => $"{device.Name} - {device.ComplianceState}").ToArray() ?? Array.Empty<string>();

        var graph = await _simulator.GetGraphProfileAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
        if (graph.Value is null)
        {
            GraphText.Text = "-";
            return;
        }

        GraphText.Text = $"Licenses: {string.Join(", ", graph.Value.Licenses.Select(license => license.FriendlyName))}\n" +
                         $"PIM Roles: {string.Join(", ", graph.Value.PimRoles.DefaultIfEmpty("None"))}\n" +
                         $"Methods: {string.Join(", ", graph.Value.AuthenticationMethods)}";
    }
}
