using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using HAP.Application.Capabilities;
using HAP.Application.Devices;
using HAP.Application.NewUser;
using HAP.Application.RuntimeProfiles;
using HAP.Contracts;
using HAP.Providers.Abstractions;
using HAP.Providers.ActiveDirectory;
using HAP.Providers.ExchangeOnPremises;
using HAP.Providers.ExchangeOnline;
using HAP.Providers.Graph;
using HAP.Providers.Simulator;

namespace HAP.App;

public partial class NativeSimulationView : UserControl
{
    private readonly RuntimeProfileConfigurationDraft _profile;
    private readonly DirectorySimulatorProvider _simulator = new();
    private readonly BuiltInCapabilityCatalog _capabilityCatalog = new();
    private readonly NativeNewUserPreflightService _newUserPreflight;
    private readonly NativeNewUserExecutionService _newUserExecution;
    private readonly NativeDeviceManagementService _deviceManagement;
    private readonly IUserLookupCapability _userLookup;
    private readonly IDirectoryReadCapability _directoryRead;
    private readonly IDirectoryAttributeReadCapability _directoryAttributeRead;
    private readonly IDirectoryGroupLookupCapability _directoryGroupLookup;
    private readonly IGraphReadCapability? _graphRead;
    private readonly IExchangeReadCapability? _exchangeRead;
    private readonly ISimulatorWriteCapability _writer;
    private readonly IReadOnlyList<IProviderHealthCapability> _healthProviders;
    private readonly string _bindingSummary;
    private NewUserExecutionPlan? _currentNewUserPlan;
    private SimulatorUserSummary? _selectedUser;
    private bool _syncingSearchText;

    public NativeSimulationView(RuntimeProfileConfigurationDraft? profile = null)
    {
        _profile = profile ?? new RuntimeProfileConfigurationDraft { RuntimeMode = "Simulation", DirectorySimulatorEnabled = true };
        var providers = CreateRuntimeProviders(_profile, _simulator);
        _userLookup = providers.UserLookup;
        _directoryRead = providers.DirectoryRead;
        _directoryAttributeRead = providers.DirectoryAttributeRead;
        _directoryGroupLookup = providers.DirectoryGroupLookup;
        _graphRead = providers.GraphRead;
        _exchangeRead = providers.ExchangeRead;
        _writer = providers.Writer;
        _healthProviders = providers.HealthProviders;
        _bindingSummary = providers.BindingSummary;
        InitializeComponent();
        _newUserPreflight = new NativeNewUserPreflightService(_userLookup);
        _newUserExecution = new NativeNewUserExecutionService(_writer);
        _deviceManagement = new NativeDeviceManagementService(providers.DeviceProviders);
        Loaded += OnLoaded;
    }

    private static RuntimeProviderSet CreateRuntimeProviders(RuntimeProfileConfigurationDraft profile, DirectorySimulatorProvider simulator)
    {
        var runtimeMode = profile.RuntimeMode ?? string.Empty;
        var useSimulator = profile.DirectorySimulatorEnabled || runtimeMode.Equals("Simulation", StringComparison.OrdinalIgnoreCase);

        if (useSimulator)
        {
            return new RuntimeProviderSet(
                simulator,
                simulator,
                simulator,
                simulator,
                simulator,
                simulator,
                simulator,
                new[] { (ProviderId: "DirectorySimulator", Provider: (IDeviceReadCapability)simulator) },
                new IProviderHealthCapability[] { simulator },
                "DirectorySimulator simulation provider");
        }

        var healthProviders = new List<IProviderHealthCapability>();
        var deviceProviders = new List<(string ProviderId, IDeviceReadCapability Provider)>();

        var activeDirectory = profile.ActiveDirectoryEnabled
            ? new ActiveDirectoryProvider(new ActiveDirectoryProviderOptions
            {
                UseLiveDirectory = true,
                Domain = profile.ActiveDirectoryDomain,
                Server = profile.ActiveDirectoryServer,
                AllowWrites = true,
                DefaultUserContainer = profile.ActiveDirectoryDefaultUserContainer,
                ConnectionAvailable = true,
                AuthenticationSucceeded = true
            })
            : null;
        if (activeDirectory is not null)
        {
            healthProviders.Add(activeDirectory);
            deviceProviders.Add(("ActiveDirectory", activeDirectory));
        }

        var graph = profile.MicrosoftGraphEnabled
            ? new MicrosoftGraphProvider(new GraphProviderOptions
            {
                TenantId = profile.TenantId,
                ClientId = profile.AppOnlyClientId,
                ClientSecret = profile.SecretReference,
                CertificateThumbprint = profile.CertificateThumbprint,
                CertificatePath = profile.CertificatePath,
                CredentialMode = profile.AppOnlyCredentialMode,
                CloudEnvironment = profile.CloudEnvironment,
                AuthenticationMode = profile.DelegatedEnabled ? "Delegated" : "AppOnly",
                Scopes = Array.Empty<string>(),
                UseLiveGraph = true
            })
            : null;
        if (graph is not null)
        {
            healthProviders.Add(graph);
            deviceProviders.Add(("MicrosoftGraph", graph));
        }

        var exchangeOnline = profile.ExchangeOnlineEnabled
            ? new ExchangeOnlineProvider()
            : null;
        if (exchangeOnline is not null)
        {
            healthProviders.Add(exchangeOnline);
        }

        var exchangeOnPremises = profile.ExchangeOnPremisesEnabled
            ? new ExchangeOnPremisesProvider(new ExchangeOnPremisesProviderOptions
            {
                Server = profile.ExchangeOnPremisesServer,
                ConnectionAvailable = true,
                AuthenticationSucceeded = true,
                SupportedManagementApiAvailable = false
            })
            : null;
        if (exchangeOnPremises is not null)
        {
            healthProviders.Add(exchangeOnPremises);
        }

        var directoryRead = activeDirectory is not null ? (IDirectoryReadCapability)activeDirectory : simulator;
        var directoryAttributes = activeDirectory is not null ? (IDirectoryAttributeReadCapability)activeDirectory : simulator;
        var groupLookup = activeDirectory is not null ? (IDirectoryGroupLookupCapability)activeDirectory : simulator;
        var userLookup = activeDirectory is not null
            ? (IUserLookupCapability)activeDirectory
            : graph is not null
                ? graph
                : simulator;
        var graphRead = graph is not null ? (IGraphReadCapability)graph : null;
        var exchangeRead = exchangeOnPremises is not null
            ? (IExchangeReadCapability)exchangeOnPremises
            : exchangeOnline is not null
                ? exchangeOnline
                : null;
        var writer = activeDirectory is not null
            ? (ISimulatorWriteCapability)activeDirectory
            : graph is not null
                ? graph
                : simulator;

        return new RuntimeProviderSet(
            userLookup,
            directoryRead,
            directoryAttributes,
            groupLookup,
            graphRead,
            exchangeRead,
            writer,
            deviceProviders,
            healthProviders.Count > 0 ? healthProviders : new IProviderHealthCapability[] { simulator },
            $"Mode={profile.RuntimeMode}; Directory={ProviderName(directoryRead)}; Graph={ProviderName(graphRead)}; Exchange={ProviderName(exchangeRead)}");
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        LoadCapabilityGrid();
        LoadNewUserChoices();
        await RefreshDashboardAsync().ConfigureAwait(true);
        await SearchAsync().ConfigureAwait(true);
        await SearchDevicesAsync().ConfigureAwait(true);
    }

    private async void OnRefreshClicked(object sender, RoutedEventArgs e)
    {
        await RefreshDashboardAsync().ConfigureAwait(true);
        if (WorkflowTabs.SelectedIndex == 1)
        {
            await SearchAsync().ConfigureAwait(true);
        }
        else if (WorkflowTabs.SelectedIndex == 2)
        {
            await SearchDevicesAsync().ConfigureAwait(true);
        }
    }

    private async void OnSearchClicked(object sender, RoutedEventArgs e)
    {
        await SearchBothPanelsAsync().ConfigureAwait(true);
    }

    private async void OnSearchKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Return)
        {
            e.Handled = true;
            await SearchBothPanelsAsync().ConfigureAwait(true);
        }
    }

    private void OnSharedSearchTextChanged(object sender, TextChangedEventArgs e)
    {
        if (_syncingSearchText || sender is not TextBox source)
        {
            return;
        }

        SyncSearchText(source.Text, source);
    }

    private async void OnUserSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (UsersGrid.SelectedItem is SimulatorUserSummary user)
        {
            await LoadUserDetailsAsync(user).ConfigureAwait(true);
        }
    }

    private async void OnDeviceSearchClicked(object sender, RoutedEventArgs e)
    {
        await SearchBothPanelsAsync().ConfigureAwait(true);
    }

    private async void OnDeviceSearchKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Return)
        {
            e.Handled = true;
            await SearchBothPanelsAsync().ConfigureAwait(true);
        }
    }

    private void OnDeviceSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        UpdateSelectedDeviceDisplay();
    }

    private async void OnValidateNewUserClicked(object sender, RoutedEventArgs e)
    {
        await ValidateNewUserAsync().ConfigureAwait(true);
    }

    private async void OnExecuteNewUserClicked(object sender, RoutedEventArgs e)
    {
        if (_currentNewUserPlan is null)
        {
            await ValidateNewUserAsync().ConfigureAwait(true);
        }

        if (_currentNewUserPlan is null)
        {
            return;
        }

        var result = await _newUserExecution.ExecuteAsync(_currentNewUserPlan, CorrelationId.New()).ConfigureAwait(true);
        NewUserExecutionList.ItemsSource = result.Value?.Steps.Select(step =>
            $"{step.ProviderId} {step.Operation}: {(step.Succeeded ? "Succeeded" : "Failed")} - {step.Message}").ToArray()
            ?? result.Errors.Select(error => error.Message).ToArray();

        StatusText.Text = result.Succeeded ? "New User Wizard execution completed." : "New User Wizard execution blocked or failed.";
        await SearchAsync(_currentNewUserPlan.Request.SamAccountName).ConfigureAwait(true);
    }

    private void OnClearNewUserClicked(object sender, RoutedEventArgs e)
    {
        NewUserFirstNameTextBox.Text = string.Empty;
        NewUserLastNameTextBox.Text = string.Empty;
        NewUserSamTextBox.Text = string.Empty;
        NewUserManagerTextBox.Text = string.Empty;
        NewUserTitleTextBox.Text = string.Empty;
        NewUserDepartmentComboBox.Text = string.Empty;
        NewUserOfficeComboBox.Text = string.Empty;
        NewUserPlanGrid.ItemsSource = null;
        NewUserExecutionList.ItemsSource = null;
        NewUserPreviewText.Text = "Validate a request to build the native execution plan.";
        _currentNewUserPlan = null;
    }

    private void OnPreferencesClicked(object sender, RoutedEventArgs e)
    {
        var selected = _selectedUser is null ? "No selected user" : $"{_selectedUser.DisplayName} ({_selectedUser.SamAccountName})";
        MessageBox.Show(
            $"Runtime preferences\n\nSelected identity: {selected}\nDefault lookup tab: User Lookup\nTheme: Native dark\nProvider binding: {_bindingSummary}\n\nProfile-level preferences are managed from Back to Profiles > Configuration.",
            "Preferences",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void OnExitClicked(object sender, RoutedEventArgs e)
    {
        Window.GetWindow(this)?.Close();
    }

    private void OnOpenUserLookupClicked(object sender, RoutedEventArgs e)
    {
        WorkflowTabs.SelectedIndex = 1;
        SearchBox.Focus();
    }

    private void OnOpenDeviceManagementClicked(object sender, RoutedEventArgs e)
    {
        WorkflowTabs.SelectedIndex = 2;
        DeviceSearchBox.Focus();
    }

    private void OnOpenNewUserWizardClicked(object sender, RoutedEventArgs e)
    {
        WorkflowTabs.SelectedIndex = 3;
        NewUserFirstNameTextBox.Focus();
    }

    private void OnOpenUtilitiesClicked(object sender, RoutedEventArgs e)
    {
        WorkflowTabs.SelectedIndex = 4;
    }

    private async void OnSyncHybridConnectionClicked(object sender, RoutedEventArgs e)
    {
        SetBusy(true, "Syncing hybrid connection...");
        try
        {
            UtilityStatusTextBox.Text = $"[{DateTimeOffset.Now:g}] Hybrid connection sync requested...\n";
            if (_profile.DirectorySimulatorEnabled || (_profile.RuntimeMode ?? string.Empty).Equals("Simulation", StringComparison.OrdinalIgnoreCase))
            {
                await Task.Delay(350).ConfigureAwait(true);
                var status = new[]
                {
                    $"[{DateTimeOffset.Now:g}] Status: Completed",
                    "Provider: DirectorySimulator.HybridConnection",
                    "Remote request: Simulated",
                    "Remote server: Runtime profile Hybrid Wizard Remote Server",
                    "Result: Hybrid connection sync completed for simulation runtime."
                };
                UtilityStatusTextBox.Text = string.Join(Environment.NewLine, status);
                StatusText.Text = "Hybrid connection sync completed for simulation runtime.";
                return;
            }

            var result = await RunHybridSyncAsync(_profile.HybridConnectionServer).ConfigureAwait(true);
            UtilityStatusTextBox.Text = result;
            StatusText.Text = result.Contains("Exit code: 0", StringComparison.OrdinalIgnoreCase)
                ? "Hybrid connection sync request completed."
                : "Hybrid connection sync request returned an error.";
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async void OnEditCurrentUserClicked(object sender, RoutedEventArgs e)
    {
        if (!EnsureSelectedUser("Edit Current User"))
        {
            return;
        }

        var user = _selectedUser!;
        var values = await ShowEditUserDialogAsync(user).ConfigureAwait(true);
        if (values.Count == 0)
        {
            return;
        }

        var desiredGroups = values.TryGetValue("Groups", out var groupsValue)
            ? SplitEditorValues(groupsValue)
            : user.Groups;
        values.Remove("Groups");
        values.Remove("DirectReportSamAccountNames");

        var result = await _writer.UpdateUserAttributesAsync(
            new UserUpdateRequest { Identity = user.SamAccountName, Attributes = values },
            CorrelationId.New()).ConfigureAwait(true);
        await ApplyGroupRelationshipChangesAsync(user, desiredGroups).ConfigureAwait(true);
        await CompleteUserMutationAsync("Edit Current User", result).ConfigureAwait(true);
    }

    private static async Task<string> RunHybridSyncAsync(string remoteServer)
    {
        var target = string.IsNullOrWhiteSpace(remoteServer) ? "Local ADSync host" : remoteServer.Trim();
        var scriptBlock = "Import-Module ADSync -ErrorAction SilentlyContinue; if (-not (Get-Command Start-ADSyncSyncCycle -ErrorAction SilentlyContinue)) { throw 'Start-ADSyncSyncCycle was not found. Install/run on the Azure AD Connect server or set the Hybrid Wizard Remote Server profile field.' }; Start-ADSyncSyncCycle -PolicyType Delta";
        var command = string.IsNullOrWhiteSpace(remoteServer)
            ? $"$ErrorActionPreference='Stop'; {scriptBlock}"
            : $"$ErrorActionPreference='Stop'; Invoke-Command -ComputerName '{EscapePowerShellSingleQuoted(remoteServer)}' -ScriptBlock {{ {scriptBlock} }}";

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"{command.Replace("\"", "\\\"", StringComparison.Ordinal)}\"",
            CreateNoWindow = false,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Unable to start PowerShell for hybrid sync.");
        var stdout = await process.StandardOutput.ReadToEndAsync().ConfigureAwait(false);
        var stderr = await process.StandardError.ReadToEndAsync().ConfigureAwait(false);
        await process.WaitForExitAsync().ConfigureAwait(false);

        return string.Join(
            Environment.NewLine,
            new[]
            {
                $"[{DateTimeOffset.Now:g}] Hybrid connection sync completed",
                "Provider: ADSync.PowerShell",
                $"Target: {target}",
                $"Exit code: {process.ExitCode}",
                string.IsNullOrWhiteSpace(stdout) ? "Output: <none>" : $"Output:{Environment.NewLine}{stdout.Trim()}",
                string.IsNullOrWhiteSpace(stderr) ? "Error: <none>" : $"Error:{Environment.NewLine}{stderr.Trim()}"
            });
    }

    private static string EscapePowerShellSingleQuoted(string value)
    {
        return (value ?? string.Empty).Replace("'", "''", StringComparison.Ordinal);
    }

    private async void OnMoveReportsClicked(object sender, RoutedEventArgs e)
    {
        if (!EnsureSelectedUser("Move Reports"))
        {
            return;
        }

        var manager = PromptForText("Move Reports", "New manager SAM/UPN for all direct reports:");
        if (string.IsNullOrWhiteSpace(manager))
        {
            return;
        }

        var reports = await _directoryRead.GetDirectReportsAsync(_selectedUser!.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
        var messages = new List<string>();
        foreach (var report in reports.Value ?? Array.Empty<SimulatorUserSummary>())
        {
            var result = await _writer.SetManagerAsync(
                new ManagerChangeRequest { Identity = report.SamAccountName, ManagerIdentity = manager.Trim() },
                CorrelationId.New()).ConfigureAwait(true);
            messages.Add($"{report.SamAccountName}: {(result.Succeeded ? result.Value?.Message : string.Join(" ", result.Errors.Select(error => error.Message)))}");
        }

        await LoadUserDetailsAsync(_selectedUser!).ConfigureAwait(true);
        MessageBox.Show(messages.Count == 0 ? "Selected user has no direct reports." : string.Join(Environment.NewLine, messages), "Move Reports", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private async void OnChangeManagerClicked(object sender, RoutedEventArgs e)
    {
        if (!EnsureSelectedUser("Change Manager"))
        {
            return;
        }

        var manager = PromptForText("Change Manager", "New manager SAM/UPN:");
        if (string.IsNullOrWhiteSpace(manager))
        {
            return;
        }

        var result = await _writer.SetManagerAsync(
            new ManagerChangeRequest { Identity = _selectedUser!.SamAccountName, ManagerIdentity = manager.Trim() },
            CorrelationId.New()).ConfigureAwait(true);
        await CompleteUserMutationAsync("Change Manager", result).ConfigureAwait(true);
    }

    private async void OnUpdateDistributionGroupsClicked(object sender, RoutedEventArgs e)
    {
        if (!EnsureSelectedUser("Update Distribution Groups"))
        {
            return;
        }

        var group = PromptForText("Update Distribution Groups", "Distribution group name:");
        if (string.IsNullOrWhiteSpace(group))
        {
            return;
        }

        var add = MessageBox.Show("Choose Yes to add membership. Choose No to remove membership.", "Update Distribution Groups", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
        if (add == MessageBoxResult.Cancel)
        {
            return;
        }

        var result = add == MessageBoxResult.Yes
            ? await _writer.AddGroupMembershipAsync(new MembershipChangeRequest { Identity = _selectedUser!.SamAccountName, Group = group.Trim() }, CorrelationId.New()).ConfigureAwait(true)
            : await _writer.RemoveGroupMembershipAsync(new MembershipChangeRequest { Identity = _selectedUser!.SamAccountName, Group = group.Trim() }, CorrelationId.New()).ConfigureAwait(true);
        await CompleteUserMutationAsync("Update Distribution Groups", result).ConfigureAwait(true);
    }

    private async void OnGalVisibilityClicked(object sender, RoutedEventArgs e)
    {
        if (!EnsureSelectedUser("Show/Hide GAL"))
        {
            return;
        }

        var answer = MessageBox.Show("Choose Yes to hide this mailbox from the GAL. Choose No to show it.", "Show/Hide GAL", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
        if (answer == MessageBoxResult.Cancel)
        {
            return;
        }

        var result = await _writer.SetGalVisibilityAsync(
            new GalVisibilityRequest { Identity = _selectedUser!.SamAccountName, HiddenFromAddressListsEnabled = answer == MessageBoxResult.Yes },
            CorrelationId.New()).ConfigureAwait(true);
        await CompleteUserMutationAsync("Show/Hide GAL", result).ConfigureAwait(true);
    }

    private async void OnAddDelegatesClicked(object sender, RoutedEventArgs e)
    {
        if (!EnsureSelectedUser("Add Delegates"))
        {
            return;
        }

        var trustee = PromptForText("Add Delegates", "Trustee to grant FullAccess:");
        if (string.IsNullOrWhiteSpace(trustee))
        {
            return;
        }

        var result = await _writer.AddMailboxDelegationAsync(
            new MailboxDelegationChangeRequest { Identity = _selectedUser!.SamAccountName, Trustee = trustee.Trim(), AccessRights = "FullAccess" },
            CorrelationId.New()).ConfigureAwait(true);
        await CompleteUserMutationAsync("Add Delegates", result).ConfigureAwait(true);
    }

    private async void OnEmailForwardingClicked(object sender, RoutedEventArgs e)
    {
        if (!EnsureSelectedUser("E-mail Forwarding"))
        {
            return;
        }

        var forwarding = PromptForText("E-mail Forwarding", "Forwarding SMTP address. Leave blank to clear:");
        var result = await _writer.SetMailboxForwardingAsync(
            new MailboxForwardingRequest { Identity = _selectedUser!.SamAccountName, ForwardingSmtpAddress = forwarding.Trim(), DeliverToMailboxAndForward = !string.IsNullOrWhiteSpace(forwarding) },
            CorrelationId.New()).ConfigureAwait(true);
        await CompleteUserMutationAsync("E-mail Forwarding", result).ConfigureAwait(true);
    }

    private async Task RefreshDashboardAsync()
    {
        var statuses = new List<string> { $"Runtime binding: {_bindingSummary}" };
        foreach (var provider in _healthProviders)
        {
            var health = await provider.GetHealthAsync(CorrelationId.New()).ConfigureAwait(true);
            statuses.Add(health.Value is null
                ? $"{provider.GetType().Name}: {health.Status} - {string.Join(" ", health.Errors.Select(error => error.Message))}"
                : $"{health.Value.ProviderId}: {health.Value.Status} ({health.Value.Mode}) - {health.Value.Message}");
        }

        ProviderStatusList.ItemsSource = statuses;
    }

    private void LoadCapabilityGrid()
    {
        CapabilityGrid.ItemsSource = _capabilityCatalog.GetAll()
            .Select(item => new CapabilityRow(item.ProviderId, item.CapabilityId, item.Disposition.ToString(), item.Reason))
            .ToArray();
    }

    private void LoadNewUserChoices()
    {
        NewUserDepartmentComboBox.ItemsSource = new[] { "Operations", "Information Technology", "Finance", "Human Resources", "Security" };
        NewUserOfficeComboBox.ItemsSource = new[] { "Headquarters", "Remote", "East Campus", "West Campus", "Field Office" };
        NewUserDepartmentComboBox.SelectedIndex = 0;
        NewUserOfficeComboBox.SelectedIndex = 0;
    }

    private Task SearchAsync() => SearchAsync(SearchBox.Text);

    private async Task SearchBothPanelsAsync()
    {
        var query = CurrentSearchQuery();
        SyncSearchText(query);
        await SearchAsync(query).ConfigureAwait(true);
        await SearchDevicesAsync(query).ConfigureAwait(true);
        StatusText.Text = $"Loaded user and device results for {query}.";
    }

    private async Task SearchAsync(string? query)
    {
        var effectiveQuery = string.IsNullOrWhiteSpace(query) ? "amorgan" : query.Trim();
        SyncSearchText(effectiveQuery);
        SetBusy(true, $"Searching for {effectiveQuery}...");
        ClearUserDetails();

        try
        {
            var result = await _userLookup.SearchUsersAsync(effectiveQuery, CorrelationId.New()).ConfigureAwait(true);
            if (!result.Succeeded)
            {
                UsersGrid.ItemsSource = null;
                StatusText.Text = string.Join(" ", result.Errors.Select(error => error.Message));
                return;
            }

            var users = result.Value ?? Array.Empty<SimulatorUserSummary>();
            if (users.Count == 0)
            {
                users = await ResolveDeviceUserMatchesAsync(effectiveQuery).ConfigureAwait(true);
            }

            UsersGrid.ItemsSource = users;
            UsersGrid.SelectedIndex = users.Count > 0 ? 0 : -1;
            StatusText.Text = users.Count == 0 ? "No user result." : $"Loaded {users.Count} user result(s).";
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task<IReadOnlyList<SimulatorUserSummary>> ResolveDeviceUserMatchesAsync(string query)
    {
        var devices = await LoadDeviceContextAsync(query, hydrateDeviceGrid: true).ConfigureAwait(true);
        var primaryUsers = devices
            .Select(device => device.PrimaryUser)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        if (primaryUsers.Length == 0)
        {
            return Array.Empty<SimulatorUserSummary>();
        }

        var users = new List<SimulatorUserSummary>();
        foreach (var primaryUser in primaryUsers)
        {
            var result = await _userLookup.SearchUsersAsync(primaryUser, CorrelationId.New()).ConfigureAwait(true);
            if (result.Succeeded)
            {
                users.AddRange(result.Value ?? Array.Empty<SimulatorUserSummary>());
            }
        }

        return users
            .GroupBy(user => FirstNonEmpty(user.SamAccountName, user.UserPrincipalName, user.Mail), StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .OrderBy(user => user.DisplayName, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private async Task<IReadOnlyList<ManagedDeviceSummary>> LoadDeviceContextAsync(string query, bool hydrateDeviceGrid)
    {
        var deviceResult = await _deviceManagement.SearchDevicesAsync(query, CorrelationId.New()).ConfigureAwait(true);
        var devices = deviceResult.Value ?? Array.Empty<ManagedDeviceSummary>();
        if (hydrateDeviceGrid)
        {
            SetDeviceGridItems(devices);
        }

        UserLookupDeviceContextText.Text = devices.Count == 0
            ? "No computer account or managed device matched this search."
            : string.Join(Environment.NewLine, devices.Select(device =>
                $"{Safe(device.Name)} | Primary user: {Safe(device.PrimaryUser)} | AD identity: {Safe(device.ActiveDirectoryIdentity)} | Source: {Safe(device.Source)}"));
        return devices;
    }

    private async Task LoadUserDetailsAsync(SimulatorUserSummary user)
    {
        _selectedUser = user;
        SetBusy(true, $"Hydrating {user.SamAccountName}...");

        try
        {
            DisplayNameText.Text = Safe(user.DisplayName);
            UpnText.Text = Safe(user.UserPrincipalName);
            SamText.Text = Safe(user.SamAccountName);
            MailText.Text = Safe(user.Mail);
            DepartmentText.Text = Safe(user.Department);
            TitleText.Text = Safe(user.Title);
            OfficeText.Text = Safe(user.Office);
            EmployeeIdText.Text = Safe(user.EmployeeId);
            DistinguishedNameText.Text = Safe(user.DistinguishedName);
            SelectedIdentityStatusText.Text = $"Selected: {user.SamAccountName}";
            DashboardSelectedUserText.Text = user.DisplayName;
            DashboardSelectedUserSubText.Text = $"{user.SamAccountName} | {user.Department} | {user.Title}";

            var manager = await _directoryRead.GetManagerAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
            ManagerText.Text = Safe(manager.Value?.DisplayName ?? user.ManagerSamAccountName);

            var reports = await _directoryRead.GetDirectReportsAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
            DirectReportsText.Text = reports.Value is { Count: > 0 }
                ? string.Join(", ", reports.Value.Select(report => report.SamAccountName))
                : "None";

            var groups = await _directoryRead.GetGroupsAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
            GroupsList.ItemsSource = groups.Value?.Select(group => $"{group.DisplayName} ({group.Source})").ToArray() ?? Array.Empty<string>();

            await LoadGraphAndAuthenticationAsync(user).ConfigureAwait(true);
            await LoadExchangeAsync(user).ConfigureAwait(true);
            StatusText.Text = $"Search complete: {user.SamAccountName}.";
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task LoadGraphAndAuthenticationAsync(SimulatorUserSummary user)
    {
        if (_graphRead is null)
        {
            LicensesText.Text = "Not loaded";
            PimRolesText.Text = "Not loaded";
            RiskStateText.Text = "Not loaded";
            LastSignInText.Text = "Not loaded";
            PasswordChangedText.Text = "Not loaded";
            GraphMethodsText.Text = "Not loaded";
            DashboardGraphText.Text = "Microsoft Graph provider disabled in profile.";
            AuthDefaultText.Text = "Not loaded";
            AuthStrengthText.Text = "Not loaded";
            ConditionalAccessText.Text = "Not loaded";
            SignInRiskText.Text = "Not loaded";
            MfaRegisteredText.Text = "Not loaded";
            PasswordlessText.Text = "Not loaded";
            return;
        }

        var graph = await _graphRead.GetGraphProfileAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
        if (graph.Value is null)
        {
            LicensesText.Text = "None";
            PimRolesText.Text = "None";
            RiskStateText.Text = "None";
            LastSignInText.Text = "Not loaded";
            PasswordChangedText.Text = "Not loaded";
            GraphMethodsText.Text = "None";
            DashboardGraphText.Text = "Graph profile not loaded";
        }
        else
        {
            LicensesText.Text = JoinOrNone(graph.Value.Licenses.Select(license => license.FriendlyName));
            PimRolesText.Text = JoinOrNone(graph.Value.PimRoles);
            RiskStateText.Text = Safe(graph.Value.RiskState);
            LastSignInText.Text = FormatDate(graph.Value.LastSignInDateTime);
            PasswordChangedText.Text = FormatDate(graph.Value.PasswordLastChangedDateTime);
            GraphMethodsText.Text = JoinOrNone(graph.Value.AuthenticationMethods);
            DashboardGraphText.Text = $"{graph.Value.Licenses.Count} license(s), {graph.Value.PimRoles.Count} PIM role(s), risk {graph.Value.RiskState}";
        }

        var auth = await _graphRead.GetAuthenticationPostureAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
        if (auth.Value is null)
        {
            AuthDefaultText.Text = "Not loaded";
            AuthStrengthText.Text = "Not loaded";
            ConditionalAccessText.Text = "Not loaded";
            SignInRiskText.Text = "Not loaded";
            MfaRegisteredText.Text = "Not loaded";
            PasswordlessText.Text = "Not loaded";
        }
        else
        {
            AuthDefaultText.Text = Safe(auth.Value.DefaultMethod);
            AuthStrengthText.Text = Safe(auth.Value.AuthenticationStrength);
            ConditionalAccessText.Text = Safe(auth.Value.ConditionalAccessState);
            SignInRiskText.Text = Safe(auth.Value.SignInRiskState);
            MfaRegisteredText.Text = auth.Value.MfaRegistered ? "Yes" : "No";
            PasswordlessText.Text = auth.Value.PasswordlessRegistered ? "Yes" : "No";
        }
    }

    private async Task LoadExchangeAsync(SimulatorUserSummary user)
    {
        if (_exchangeRead is null)
        {
            MailboxText.Text = "Not loaded";
            RecipientTypeText.Text = "Not loaded";
            HiddenGalText.Text = "Not loaded";
            ForwardingText.Text = "Not loaded";
            ItemCountText.Text = "Not loaded";
            LastMailboxLogonText.Text = "Not loaded";
            MailboxDelegationList.ItemsSource = Array.Empty<string>();
            DistributionGroupsList.ItemsSource = Array.Empty<string>();
            DashboardExchangeText.Text = "Exchange provider disabled in profile.";
            return;
        }

        var mailbox = await _exchangeRead.GetMailboxAsync(FirstNonEmpty(user.Mail, user.UserPrincipalName, user.SamAccountName), CorrelationId.New()).ConfigureAwait(true);
        if (mailbox.Value is null)
        {
            MailboxText.Text = "Not loaded";
            RecipientTypeText.Text = "Not loaded";
            HiddenGalText.Text = "Not loaded";
            ForwardingText.Text = "Not loaded";
            DashboardExchangeText.Text = "Mailbox not loaded";
        }
        else
        {
            MailboxText.Text = Safe(mailbox.Value.PrimarySmtpAddress);
            RecipientTypeText.Text = Safe(mailbox.Value.RecipientTypeDetails);
            HiddenGalText.Text = mailbox.Value.HiddenFromAddressListsEnabled ? "Hidden" : "Visible";
            ForwardingText.Text = string.IsNullOrWhiteSpace(mailbox.Value.ForwardingSmtpAddress)
                ? "No forwarding configured"
                : $"{mailbox.Value.ForwardingSmtpAddress} (deliver copy: {mailbox.Value.DeliverToMailboxAndForward})";
            DashboardExchangeText.Text = $"{mailbox.Value.RecipientTypeDetails} | {mailbox.Value.PrimarySmtpAddress}";
        }

        var stats = await _exchangeRead.GetMailboxStatisticsAsync(FirstNonEmpty(user.Mail, user.UserPrincipalName, user.SamAccountName), CorrelationId.New()).ConfigureAwait(true);
        ItemCountText.Text = stats.Value is null ? "Not loaded" : $"{stats.Value.ItemCount:N0} items, {stats.Value.TotalItemSize}";
        LastMailboxLogonText.Text = FormatDate(stats.Value?.LastLogonTime);

        var delegations = await _exchangeRead.GetMailboxDelegationsAsync(FirstNonEmpty(user.Mail, user.UserPrincipalName, user.SamAccountName), CorrelationId.New()).ConfigureAwait(true);
        MailboxDelegationList.ItemsSource = delegations.Value?.Select(item => $"{item.Trustee}: {item.AccessRights}").ToArray() ?? Array.Empty<string>();

        var distributionGroups = await _exchangeRead.GetDistributionGroupsAsync(FirstNonEmpty(user.Mail, user.UserPrincipalName, user.SamAccountName), CorrelationId.New()).ConfigureAwait(true);
        DistributionGroupsList.ItemsSource = distributionGroups.Value?.Select(item => $"{item.DisplayName} <{item.Mail}>").ToArray() ?? Array.Empty<string>();
    }

    private async Task SearchDevicesAsync(string? searchQuery = null)
    {
        var query = string.IsNullOrWhiteSpace(searchQuery)
            ? CurrentSearchQuery()
            : searchQuery.Trim();
        SyncSearchText(query);
        SetBusy(true, $"Searching devices for {query}...");

        try
        {
            var result = await _deviceManagement.SearchDevicesAsync(query, CorrelationId.New()).ConfigureAwait(true);
            SetDeviceGridItems(result.Value ?? Array.Empty<ManagedDeviceSummary>());
            StatusText.Text = $"Loaded {result.Value?.Count ?? 0} device result(s).";
            DeviceActionOutputTextBox.Text = result.Warnings.Count == 0
                ? "Select a device, then reveal a protected secret or run a lifecycle action."
                : string.Join(Environment.NewLine, result.Warnings.Select(warning => warning.Message));
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void SetDeviceGridItems(IReadOnlyList<ManagedDeviceSummary> devices)
    {
        DevicesGrid.ItemsSource = devices.Select(device => new DeviceRow(
            device,
            device.Name,
            device.OperatingSystem,
            device.ComplianceState,
            device.PrimaryUser,
            FormatDate(device.LastCheckInUtc),
            device.Source)).ToArray();
        DevicesGrid.SelectedIndex = devices.Count > 0 ? 0 : -1;
        UpdateSelectedDeviceDisplay();
    }

    private async void OnRevealBitLockerClicked(object sender, RoutedEventArgs e)
    {
        await RevealDeviceSecretAsync(DeviceSecretKind.BitLockerRecoveryKey).ConfigureAwait(true);
    }

    private async void OnRevealLapsClicked(object sender, RoutedEventArgs e)
    {
        await RevealDeviceSecretAsync(DeviceSecretKind.LapsPassword).ConfigureAwait(true);
    }

    private async void OnRetireIntuneDeviceClicked(object sender, RoutedEventArgs e)
    {
        await RunDeviceLifecycleAsync(DeviceActionTarget.Intune, retire: true).ConfigureAwait(true);
    }

    private async void OnDeleteIntuneDeviceClicked(object sender, RoutedEventArgs e)
    {
        await RunDeviceLifecycleAsync(DeviceActionTarget.Intune, retire: false).ConfigureAwait(true);
    }

    private async void OnDeleteEntraDeviceClicked(object sender, RoutedEventArgs e)
    {
        await RunDeviceLifecycleAsync(DeviceActionTarget.EntraId, retire: false).ConfigureAwait(true);
    }

    private async void OnDeleteAdDeviceClicked(object sender, RoutedEventArgs e)
    {
        await RunDeviceLifecycleAsync(DeviceActionTarget.ActiveDirectory, retire: false).ConfigureAwait(true);
    }

    private async void OnDeleteAllDeviceClicked(object sender, RoutedEventArgs e)
    {
        await RunDeviceLifecycleAsync(DeviceActionTarget.All, retire: false).ConfigureAwait(true);
    }

    private async Task RevealDeviceSecretAsync(DeviceSecretKind secretKind)
    {
        if (GetSelectedDevice() is not { } device)
        {
            ShowThemedDeviceNotice("Device Management", "Select a device first.");
            return;
        }

        var label = secretKind == DeviceSecretKind.BitLockerRecoveryKey ? "BitLocker recovery key" : "LAPS password";
        if (!ShowThemedDeviceConfirmation(
                "Reveal Protected Secret",
                $"Reveal the {label} for {device.Name}?",
                "Reveal"))
        {
            return;
        }

        SetBusy(true, $"Revealing {label}...");
        try
        {
            var result = await _deviceManagement.RevealDeviceSecretAsync(new DeviceSecretRevealRequest { Device = device, SecretKind = secretKind }, CorrelationId.New()).ConfigureAwait(true);
            DeviceActionOutputTextBox.Text = result.Succeeded && result.Value is not null
                ? $"{label} for {result.Value.DeviceName}:{Environment.NewLine}{result.Value.Secret}{Environment.NewLine}{Environment.NewLine}{result.Value.Metadata}{Environment.NewLine}Source: {result.Value.Source}"
                : string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task RunDeviceLifecycleAsync(DeviceActionTarget target, bool retire)
    {
        if (GetSelectedDevice() is not { } device)
        {
            ShowThemedDeviceNotice("Device Management", "Select a device first.");
            return;
        }

        var action = retire ? "retire" : "delete";
        if (!ShowThemedDeviceConfirmation(
                "Device Lifecycle Action",
                $"Confirm {action} for {device.Name} on {target}?",
                retire ? "Retire" : "Delete",
                isDestructive: !retire))
        {
            return;
        }

        SetBusy(true, $"{action} device...");
        try
        {
            var request = new DeviceLifecycleRequest { Device = device, Target = target };
            var result = retire
                ? await _deviceManagement.RetireDeviceAsync(request, CorrelationId.New()).ConfigureAwait(true)
                : await _deviceManagement.DeleteDeviceAsync(request, CorrelationId.New()).ConfigureAwait(true);
            DeviceActionOutputTextBox.Text = result.Succeeded
                ? string.Join(Environment.NewLine, result.Value?.Select(item => $"{item.Source} [{item.Target}]: {item.Message}") ?? Array.Empty<string>())
                : string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
            await SearchDevicesAsync().ConfigureAwait(true);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private ManagedDeviceSummary? GetSelectedDevice()
    {
        return DevicesGrid.SelectedItem is DeviceRow row ? row.Device : null;
    }

    private void UpdateSelectedDeviceDisplay()
    {
        if (SelectedDeviceText is null)
        {
            return;
        }

        var device = GetSelectedDevice();
        SelectedDeviceText.Text = device is null
            ? "Selected device: none"
            : $"Selected device: {Safe(device.Name)} | Primary user: {Safe(device.PrimaryUser)} | Source: {Safe(device.Source)}";
    }

    private async Task ValidateNewUserAsync()
    {
        var request = new NewUserPreflightRequest
        {
            GivenName = NewUserFirstNameTextBox.Text.Trim(),
            Surname = NewUserLastNameTextBox.Text.Trim(),
            SamAccountName = NewUserSamTextBox.Text.Trim(),
            Department = NewUserDepartmentComboBox.Text.Trim(),
            Title = NewUserTitleTextBox.Text.Trim(),
            ManagerSamAccountName = NewUserManagerTextBox.Text.Trim(),
            Office = NewUserOfficeComboBox.Text.Trim()
        };

        SetBusy(true, "Validating New User Wizard request...");
        try
        {
            var result = await _newUserPreflight.BuildPlanAsync(request, CorrelationId.New()).ConfigureAwait(true);
            _currentNewUserPlan = result.Value;
            NewUserPlanGrid.ItemsSource = _currentNewUserPlan?.Steps;
            NewUserExecutionList.ItemsSource = null;
            NewUserPreviewText.Text = _currentNewUserPlan is null
                ? string.Join(" ", result.Errors.Select(error => error.Message))
                : $"Plan {_currentNewUserPlan.PlanId}: {(_currentNewUserPlan.CanExecute ? "Ready" : "Blocked")} for {request.SamAccountName}.";
            StatusText.Text = _currentNewUserPlan?.CanExecute == true ? "New User Wizard plan ready." : "New User Wizard plan blocked.";
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task CompleteUserMutationAsync(string title, OperationResult<ProviderChangeResult> result)
    {
        var message = result.Succeeded
            ? result.Value?.Message ?? "Action completed."
            : string.Join(" ", result.Errors.Select(error => error.Message));
        StatusText.Text = $"{title}: {message}";

        if (_selectedUser is not null)
        {
            var userResult = await _directoryRead.GetUserAsync(_selectedUser.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
            if (userResult.Value is not null)
            {
                await LoadUserDetailsAsync(userResult.Value).ConfigureAwait(true);
            }
        }

        MessageBox.Show(message, title, MessageBoxButton.OK, result.Succeeded ? MessageBoxImage.Information : MessageBoxImage.Warning);
    }

    private bool EnsureSelectedUser(string title)
    {
        if (_selectedUser is not null)
        {
            return true;
        }

        MessageBox.Show("Search for and select a user first.", title, MessageBoxButton.OK, MessageBoxImage.Information);
        return false;
    }

    private static string PromptForText(string title, string prompt)
    {
        var fields = PromptForFields(title, new Dictionary<string, string> { [prompt] = string.Empty });
        return fields.TryGetValue(prompt, out var value) ? value : string.Empty;
    }

    private static Dictionary<string, string> PromptForFields(string title, IReadOnlyDictionary<string, string> fields)
    {
        var window = new Window
        {
            Title = title,
            Width = 520,
            Height = Math.Max(190, 118 + fields.Count * 58),
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Owner = System.Windows.Application.Current.MainWindow,
            ResizeMode = ResizeMode.NoResize,
            Background = BrushResource("HapBackgroundBrush")
        };

        var root = new Grid { Margin = new Thickness(16) };
        root.SetValue(System.Windows.Documents.TextElement.ForegroundProperty, BrushResource("HapInkBrush"));
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var stack = new StackPanel();
        var inputs = new Dictionary<string, TextBox>(StringComparer.OrdinalIgnoreCase);
        foreach (var field in fields)
        {
            stack.Children.Add(new TextBlock { Text = field.Key, Foreground = BrushResource("HapMutedBrush"), Margin = new Thickness(0, 0, 0, 4) });
            var input = new TextBox { Text = field.Value, Height = 32, Margin = new Thickness(0, 0, 0, 10) };
            inputs[field.Key] = input;
            stack.Children.Add(input);
        }

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 8, 0, 0) };
        var ok = new Button { Content = "OK", Width = 92, IsDefault = true, Margin = new Thickness(0, 0, 8, 0) };
        var cancel = new Button { Content = "Cancel", Width = 92, IsCancel = true };
        ok.Click += (_, _) =>
        {
            window.DialogResult = true;
            window.Close();
        };
        buttons.Children.Add(ok);
        buttons.Children.Add(cancel);

        Grid.SetRow(buttons, 1);
        root.Children.Add(stack);
        root.Children.Add(buttons);
        window.Content = root;

        if (window.ShowDialog() != true)
        {
            return new Dictionary<string, string>();
        }

        return inputs.ToDictionary(pair => pair.Key, pair => pair.Value.Text.Trim(), StringComparer.OrdinalIgnoreCase);
    }

    private async Task<Dictionary<string, string>> ShowEditUserDialogAsync(SimulatorUserSummary user)
    {
        var attributeResult = await _directoryAttributeRead.GetDirectoryAttributesAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
        var rows = attributeResult.Value is null
            ? BuildAttributeRows(user)
            : BuildAttributeRows(user, attributeResult.Value);
        var rowMap = BuildAttributeRowLookup(rows);
        var currentReports = new ObservableCollection<string>(user.DirectReportSamAccountNames);
        var currentGroups = new ObservableCollection<string>(user.Groups);

        var window = new Window
        {
            Title = $"Edit User - {user.DisplayName}",
            Width = 860,
            Height = 680,
            MinWidth = 720,
            MinHeight = 520,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Owner = System.Windows.Application.Current.MainWindow,
            Background = BrushResource("HapBackgroundBrush"),
            Foreground = BrushResource("HapInkBrush")
        };

        var root = new Grid { Margin = new Thickness(18) };
        root.SetValue(System.Windows.Documents.TextElement.ForegroundProperty, BrushResource("HapInkBrush"));
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var header = new StackPanel { Margin = new Thickness(0, 0, 0, 14) };
        header.Children.Add(new TextBlock { Text = user.DisplayName, FontSize = 24, FontWeight = FontWeights.SemiBold, Foreground = BrushResource("HapInkBrush") });
        header.Children.Add(new TextBlock { Text = $"{user.SamAccountName} | {user.UserPrincipalName} | {attributeResult.Value?.SchemaSource ?? "Summary attributes"}", Foreground = BrushResource("HapMutedBrush") });
        Grid.SetRow(header, 0);
        root.Children.Add(header);

        var tabs = new TabControl();
        Grid.SetRow(tabs, 1);
        root.Children.Add(tabs);

        tabs.Items.Add(CreateEditTab(
            "General",
            new[]
            {
                ("DisplayName", "Display name"),
                ("GivenName", "First name"),
                ("Surname", "Last name"),
                ("SamAccountName", "SAM account"),
                ("UserPrincipalName", "User logon name"),
                ("Mail", "E-mail")
            },
            rowMap));

        tabs.Items.Add(CreateEditTab(
            "Organization",
            new[]
            {
                ("Department", "Department"),
                ("Title", "Job title"),
                ("Company", "Company"),
                ("Office", "Office"),
                ("EmployeeId", "Employee / Badge ID"),
                ("ManagerSamAccountName", "Manager")
            },
            rowMap));

        tabs.Items.Add(CreateEditTab(
            "Account",
            new[]
            {
                ("Enabled", "Enabled"),
                ("LockedOut", "Locked out"),
                ("DistinguishedName", "Distinguished name")
            },
            rowMap));

        tabs.Items.Add(CreateRelationshipsTab(currentReports, currentGroups));

        var attributeGrid = new DataGrid
        {
            AutoGenerateColumns = false,
            CanUserAddRows = false,
            CanUserDeleteRows = false,
            ItemsSource = rows,
            Margin = new Thickness(0, 10, 0, 0)
        };
        attributeGrid.Columns.Add(new DataGridTextColumn { Header = "Attribute", Binding = new System.Windows.Data.Binding(nameof(AttributeEditorRow.Attribute)), IsReadOnly = true, Width = 230 });
        attributeGrid.Columns.Add(new DataGridTextColumn { Header = "Value", Binding = new System.Windows.Data.Binding(nameof(AttributeEditorRow.Value)) { UpdateSourceTrigger = System.Windows.Data.UpdateSourceTrigger.PropertyChanged }, Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        tabs.Items.Add(new TabItem
        {
            Header = "Attribute Editor",
            Content = new DockPanel
            {
                Margin = new Thickness(12),
                Children =
                {
                    new TextBlock
                    {
                        Text = "Simulation shows the attributes currently exposed by the native provider model. Live AD schema-backed reads will expand this into the full directory attribute set.",
                        Foreground = BrushResource("HapMutedBrush"),
                        Margin = new Thickness(0, 0, 0, 8)
                    },
                    attributeGrid
                }
            }
        });
        DockPanel.SetDock(((DockPanel)((TabItem)tabs.Items[^1]).Content).Children[0], Dock.Top);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 14, 0, 0) };
        var ok = new Button { Content = "Save", Width = 110, IsDefault = true, Margin = new Thickness(0, 0, 8, 0) };
        var cancel = new Button { Content = "Cancel", Width = 110, IsCancel = true };
        ok.Click += (_, _) =>
        {
            attributeGrid.CommitEdit(DataGridEditingUnit.Cell, true);
            attributeGrid.CommitEdit(DataGridEditingUnit.Row, true);
            if (rowMap.TryGetValue("DirectReportSamAccountNames", out var reportsRow))
            {
                reportsRow.Value = string.Join("; ", currentReports);
            }

            if (rowMap.TryGetValue("Groups", out var groupsRow))
            {
                groupsRow.Value = string.Join("; ", currentGroups);
            }

            window.DialogResult = true;
            window.Close();
        };
        buttons.Children.Add(ok);
        buttons.Children.Add(cancel);
        Grid.SetRow(buttons, 2);
        root.Children.Add(buttons);

        window.Content = root;
        await Task.CompletedTask.ConfigureAwait(true);
        return window.ShowDialog() == true
            ? BuildAttributeValueMap(rows)
            : new Dictionary<string, string>();
    }

    private static IReadOnlyDictionary<string, AttributeEditorRow> BuildAttributeRowLookup(IEnumerable<AttributeEditorRow> rows)
    {
        var lookup = new Dictionary<string, AttributeEditorRow>(StringComparer.OrdinalIgnoreCase);
        foreach (var row in rows)
        {
            lookup.TryAdd(row.Attribute, row);
        }

        return lookup;
    }

    private static Dictionary<string, string> BuildAttributeValueMap(IEnumerable<AttributeEditorRow> rows)
    {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var row in rows)
        {
            values[row.Attribute] = row.Value.Trim();
        }

        return values;
    }

    private async Task ApplyGroupRelationshipChangesAsync(SimulatorUserSummary user, IReadOnlyList<string> desiredGroups)
    {
        var current = new HashSet<string>(user.Groups.Where(value => !string.IsNullOrWhiteSpace(value)), StringComparer.OrdinalIgnoreCase);
        var desired = new HashSet<string>(desiredGroups.Where(value => !string.IsNullOrWhiteSpace(value)), StringComparer.OrdinalIgnoreCase);

        foreach (var group in desired.Except(current, StringComparer.OrdinalIgnoreCase))
        {
            await _writer.AddGroupMembershipAsync(
                new MembershipChangeRequest { Identity = user.SamAccountName, Group = group },
                CorrelationId.New()).ConfigureAwait(true);
        }

        foreach (var group in current.Except(desired, StringComparer.OrdinalIgnoreCase))
        {
            await _writer.RemoveGroupMembershipAsync(
                new MembershipChangeRequest { Identity = user.SamAccountName, Group = group },
                CorrelationId.New()).ConfigureAwait(true);
        }
    }

    private static IReadOnlyList<string> SplitEditorValues(string value)
    {
        return (value ?? string.Empty)
            .Split(new[] { ';', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(item => !string.IsNullOrWhiteSpace(item))
            .ToArray();
    }

    private TabItem CreateRelationshipsTab(ObservableCollection<string> currentReports, ObservableCollection<string> currentGroups)
    {
        var root = new Grid { Margin = new Thickness(12) };
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(16) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        root.Children.Add(CreatePickerPanel(
            "Direct Reports",
            "Search users",
            currentReports,
            async query =>
            {
                var result = await _userLookup.SearchUsersAsync(query, CorrelationId.New()).ConfigureAwait(true);
                return result.Value?.Select(user => $"{user.SamAccountName} | {user.DisplayName}").ToArray() ?? Array.Empty<string>();
            },
            value => value.Split('|')[0].Trim()));

        var groupsPanel = CreatePickerPanel(
            "Groups",
            "Search groups",
            currentGroups,
            async query =>
            {
                var result = await _directoryGroupLookup.SearchGroupsAsync(query, CorrelationId.New()).ConfigureAwait(true);
                return result.Value?.Select(group => $"{group.Id} | {group.DisplayName}").ToArray() ?? Array.Empty<string>();
            },
            value => value.Split('|')[0].Trim());
        Grid.SetColumn(groupsPanel, 2);
        root.Children.Add(groupsPanel);

        return new TabItem { Header = "Relationships", Content = root };
    }

    private static Grid CreatePickerPanel(
        string title,
        string searchWatermark,
        ObservableCollection<string> selectedItems,
        Func<string, Task<IReadOnlyList<string>>> lookup,
        Func<string, string> normalizeSelection)
    {
        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(150) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        root.Children.Add(new TextBlock { Text = title, FontSize = 17, FontWeight = FontWeights.SemiBold, Foreground = BrushResource("HapInkBrush"), Margin = new Thickness(0, 0, 0, 8) });

        var searchRow = new Grid { Margin = new Thickness(0, 0, 0, 8) };
        searchRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        searchRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var searchBox = new TextBox { Height = 32, ToolTip = searchWatermark };
        var searchButton = new Button { Content = "Lookup", Width = 92, Margin = new Thickness(8, 0, 0, 0) };
        Grid.SetColumn(searchButton, 1);
        searchRow.Children.Add(searchBox);
        searchRow.Children.Add(searchButton);
        Grid.SetRow(searchRow, 1);
        root.Children.Add(searchRow);

        var results = new ListBox { MinHeight = 120 };
        Grid.SetRow(results, 2);
        root.Children.Add(results);

        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 8, 0, 8) };
        var add = new Button { Content = "Add", Width = 84, Margin = new Thickness(0, 0, 8, 0) };
        var remove = new Button { Content = "Remove", Width = 94 };
        actions.Children.Add(add);
        actions.Children.Add(remove);
        Grid.SetRow(actions, 3);
        root.Children.Add(actions);

        var selected = new ListBox { ItemsSource = selectedItems, MinHeight = 140 };
        Grid.SetRow(selected, 4);
        root.Children.Add(selected);

        async Task RunLookupAsync()
        {
            var query = searchBox.Text.Trim();
            if (string.IsNullOrWhiteSpace(query))
            {
                results.ItemsSource = Array.Empty<string>();
                return;
            }

            results.ItemsSource = await lookup(query).ConfigureAwait(true);
        }

        searchButton.Click += async (_, _) => await RunLookupAsync().ConfigureAwait(true);
        searchBox.KeyDown += async (_, args) =>
        {
            if (args.Key == Key.Return)
            {
                args.Handled = true;
                await RunLookupAsync().ConfigureAwait(true);
            }
        };

        add.Click += (_, _) =>
        {
            if (results.SelectedItem is not string value)
            {
                return;
            }

            var normalized = normalizeSelection(value);
            if (!selectedItems.Contains(normalized, StringComparer.OrdinalIgnoreCase))
            {
                selectedItems.Add(normalized);
            }
        };

        remove.Click += (_, _) =>
        {
            if (selected.SelectedItem is string value)
            {
                selectedItems.Remove(value);
            }
        };

        return root;
    }

    private static TabItem CreateEditTab(
        string header,
        IEnumerable<(string Attribute, string Label)> fields,
        IReadOnlyDictionary<string, AttributeEditorRow> rowMap)
    {
        var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        var panel = new Grid { Margin = new Thickness(12) };
        panel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(190) });
        panel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var rowIndex = 0;
        foreach (var field in fields)
        {
            if (!rowMap.TryGetValue(field.Attribute, out var row))
            {
                continue;
            }

            panel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var label = new TextBlock
            {
                Text = field.Label,
                Foreground = BrushResource("HapMutedBrush"),
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 16, 10)
            };
            Grid.SetRow(label, rowIndex);
            Grid.SetColumn(label, 0);
            panel.Children.Add(label);

            var input = new TextBox
            {
                Text = row.Value,
                MinHeight = 32,
                Margin = new Thickness(0, 0, 0, 10)
            };
            input.TextChanged += (_, _) => row.Value = input.Text;
            Grid.SetRow(input, rowIndex);
            Grid.SetColumn(input, 1);
            panel.Children.Add(input);
            rowIndex++;
        }

        scroll.Content = panel;
        return new TabItem { Header = header, Content = scroll };
    }

    private static List<AttributeEditorRow> BuildAttributeRows(SimulatorUserSummary user)
    {
        return new List<AttributeEditorRow>
        {
            new("DisplayName", user.DisplayName),
            new("GivenName", user.GivenName),
            new("Surname", user.Surname),
            new("SamAccountName", user.SamAccountName),
            new("UserPrincipalName", user.UserPrincipalName),
            new("Mail", user.Mail),
            new("Department", user.Department),
            new("Title", user.Title),
            new("Company", user.Company),
            new("Office", user.Office),
            new("EmployeeId", user.EmployeeId),
            new("DistinguishedName", user.DistinguishedName),
            new("ManagerSamAccountName", user.ManagerSamAccountName),
            new("DirectReportSamAccountNames", string.Join("; ", user.DirectReportSamAccountNames)),
            new("Groups", string.Join("; ", user.Groups)),
            new("Enabled", user.Enabled.ToString()),
            new("LockedOut", user.LockedOut.ToString()),
            new("Source", user.Source)
        };
    }

    private static List<AttributeEditorRow> BuildAttributeRows(SimulatorUserSummary user, DirectoryObjectAttributeSet attributeSet)
    {
        var rows = attributeSet.Attributes
            .OrderBy(attribute => attribute.Name, StringComparer.OrdinalIgnoreCase)
            .Select(attribute => new AttributeEditorRow(
                attribute.Name,
                string.Join("; ", attribute.Values),
                attribute.IsReadOnly,
                attribute.IsSingleValued,
                attribute.Syntax))
            .ToList();

        void Ensure(string name, string value)
        {
            if (!rows.Any(row => string.Equals(row.Attribute, name, StringComparison.OrdinalIgnoreCase)))
            {
                rows.Add(new AttributeEditorRow(name, value));
            }
        }

        Ensure("DisplayName", user.DisplayName);
        Ensure("GivenName", user.GivenName);
        Ensure("Surname", user.Surname);
        Ensure("SamAccountName", user.SamAccountName);
        Ensure("UserPrincipalName", user.UserPrincipalName);
        Ensure("Mail", user.Mail);
        Ensure("Department", user.Department);
        Ensure("Title", user.Title);
        Ensure("Company", user.Company);
        Ensure("Office", user.Office);
        Ensure("EmployeeId", user.EmployeeId);
        Ensure("DirectReportSamAccountNames", string.Join("; ", user.DirectReportSamAccountNames));
        Ensure("Groups", string.Join("; ", user.Groups));
        Ensure("Enabled", user.Enabled.ToString());
        Ensure("LockedOut", user.LockedOut.ToString());

        return rows.OrderBy(row => row.Attribute, StringComparer.OrdinalIgnoreCase).ToList();
    }

    private static System.Windows.Media.Brush BrushResource(string key)
    {
        return System.Windows.Application.Current.Resources[key] as System.Windows.Media.Brush
            ?? System.Windows.Media.Brushes.White;
    }

    private void ShowActionGate(string title, string providerId, string capabilityId)
    {
        if (!EnsureSelectedUser(title))
        {
            return;
        }

        var availability = _capabilityCatalog.Get(providerId, capabilityId);
        MessageBox.Show(
            $"{title} is visible in the native shell for workflow parity.\n\nProvider: {providerId}\nCapability: {capabilityId}\nDisposition: {availability.Disposition}\n\n{availability.Reason}",
            title,
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void ClearUserDetails()
    {
        _selectedUser = null;
        foreach (var text in new[]
        {
            DisplayNameText, UpnText, SamText, MailText, DepartmentText, TitleText, OfficeText,
            EmployeeIdText, DistinguishedNameText, ManagerText, DirectReportsText, LicensesText,
            PimRolesText, RiskStateText, LastSignInText, PasswordChangedText, GraphMethodsText,
            AuthDefaultText, AuthStrengthText, ConditionalAccessText, SignInRiskText, MfaRegisteredText,
            PasswordlessText, MailboxText, RecipientTypeText, HiddenGalText, ForwardingText, ItemCountText,
            LastMailboxLogonText
        })
        {
            text.Text = "-";
        }

        GroupsList.ItemsSource = null;
        MailboxDelegationList.ItemsSource = null;
        DistributionGroupsList.ItemsSource = null;
        UserLookupDeviceContextText.Text = "No device lookup context.";
        SelectedIdentityStatusText.Text = "No selected user";
        DashboardSelectedUserText.Text = "-";
        DashboardSelectedUserSubText.Text = "Search for a user to hydrate dashboard cards.";
        DashboardGraphText.Text = "Not loaded";
        DashboardExchangeText.Text = "Not loaded";
    }

    private void SyncSearchText(string? value, TextBox? source = null)
    {
        var next = value ?? string.Empty;
        if (_syncingSearchText)
        {
            return;
        }

        _syncingSearchText = true;
        try
        {
            if (SearchBox is not null &&
                !ReferenceEquals(source, SearchBox) &&
                !string.Equals(SearchBox.Text, next, StringComparison.Ordinal))
            {
                SearchBox.Text = next;
            }

            if (DeviceSearchBox is not null &&
                !ReferenceEquals(source, DeviceSearchBox) &&
                !string.Equals(DeviceSearchBox.Text, next, StringComparison.Ordinal))
            {
                DeviceSearchBox.Text = next;
            }
        }
        finally
        {
            _syncingSearchText = false;
        }
    }

    private string CurrentSearchQuery()
    {
        return FirstNonEmpty(DeviceSearchBox?.Text?.Trim() ?? string.Empty, SearchBox?.Text?.Trim() ?? string.Empty, "amorgan");
    }

    private void SetBusy(bool busy, string? status = null)
    {
        SearchProgressBar.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        SearchProgressBar.IsIndeterminate = busy;
        if (!string.IsNullOrWhiteSpace(status))
        {
            StatusText.Text = status;
        }
    }

    private void ShowThemedDeviceNotice(string title, string message)
    {
        ShowThemedDeviceDialog(title, message, primaryText: "OK", showCancel: false, isDestructive: false);
    }

    private bool ShowThemedDeviceConfirmation(string title, string message, string primaryText, bool isDestructive = false)
    {
        return ShowThemedDeviceDialog(title, message, primaryText, showCancel: true, isDestructive);
    }

    private bool ShowThemedDeviceDialog(string title, string message, string primaryText, bool showCancel, bool isDestructive)
    {
        var owner = Window.GetWindow(this);
        var accent = isDestructive ? "#B91C1C" : "#0369A1";
        var primaryButton = new Button
        {
            Content = primaryText,
            MinWidth = 104,
            Height = 34,
            Padding = new Thickness(14, 0, 14, 0),
            Margin = new Thickness(8, 0, 0, 0),
            Background = BrushFrom(accent),
            Foreground = BrushFrom("#F8FAFC"),
            BorderBrush = BrushFrom(isDestructive ? "#EF4444" : "#38BDF8"),
            BorderThickness = new Thickness(1),
            FontWeight = FontWeights.SemiBold,
            IsDefault = true
        };
        var cancelButton = new Button
        {
            Content = "Cancel",
            MinWidth = 104,
            Height = 34,
            Padding = new Thickness(14, 0, 14, 0),
            Margin = new Thickness(8, 0, 0, 0),
            Background = BrushFrom("#0F172A"),
            Foreground = BrushFrom("#F8FAFC"),
            BorderBrush = BrushFrom("#475569"),
            BorderThickness = new Thickness(1),
            FontWeight = FontWeights.SemiBold,
            IsCancel = true
        };
        var buttonPanel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 22, 0, 0)
        };
        if (showCancel)
        {
            buttonPanel.Children.Add(cancelButton);
        }

        buttonPanel.Children.Add(primaryButton);

        var shell = new Border
        {
            Background = BrushFrom("#111827"),
            BorderBrush = BrushFrom("#334155"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(20),
            Child = new StackPanel
            {
                Children =
                {
                    new TextBlock
                    {
                        Text = title,
                        Foreground = BrushFrom("#F8FAFC"),
                        FontSize = 20,
                        FontWeight = FontWeights.SemiBold,
                        TextWrapping = TextWrapping.Wrap
                    },
                    new Border
                    {
                        Height = 1,
                        Background = BrushFrom("#334155"),
                        Margin = new Thickness(0, 12, 0, 14)
                    },
                    new TextBlock
                    {
                        Text = message,
                        Foreground = BrushFrom("#CBD5E1"),
                        FontSize = 13,
                        TextWrapping = TextWrapping.Wrap,
                        LineHeight = 19
                    },
                    buttonPanel
                }
            }
        };

        var dialog = new Window
        {
            Title = title,
            Width = 440,
            SizeToContent = SizeToContent.Height,
            MinHeight = 190,
            WindowStartupLocation = owner is null ? WindowStartupLocation.CenterScreen : WindowStartupLocation.CenterOwner,
            Owner = owner,
            ResizeMode = ResizeMode.NoResize,
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            Content = shell,
            ShowInTaskbar = false
        };

        primaryButton.Click += (_, _) =>
        {
            dialog.DialogResult = true;
            dialog.Close();
        };
        cancelButton.Click += (_, _) =>
        {
            dialog.DialogResult = false;
            dialog.Close();
        };

        return dialog.ShowDialog() == true;
    }

    private static Brush BrushFrom(string color)
    {
        return (Brush)new BrushConverter().ConvertFromString(color)!;
    }

    private static string Safe(string? value) => string.IsNullOrWhiteSpace(value) ? "-" : value;

    private static string FirstNonEmpty(params string[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;
    }

    private static string ProviderName(object? provider)
    {
        return provider?.GetType().Name ?? "Disabled";
    }

    private static string JoinOrNone(IEnumerable<string> values)
    {
        var materialized = values.Where(value => !string.IsNullOrWhiteSpace(value)).ToArray();
        return materialized.Length == 0 ? "None" : string.Join(", ", materialized);
    }

    private static string FormatDate(DateTimeOffset? value) => value?.ToLocalTime().ToString("g") ?? "Not loaded";

    private sealed record CapabilityRow(string Provider, string Capability, string Disposition, string Reason);

    private sealed record DeviceRow(ManagedDeviceSummary Device, string Name, string OperatingSystem, string ComplianceState, string PrimaryUser, string LastCheckIn, string Source);

    private sealed record RuntimeProviderSet(
        IUserLookupCapability UserLookup,
        IDirectoryReadCapability DirectoryRead,
        IDirectoryAttributeReadCapability DirectoryAttributeRead,
        IDirectoryGroupLookupCapability DirectoryGroupLookup,
        IGraphReadCapability? GraphRead,
        IExchangeReadCapability? ExchangeRead,
        ISimulatorWriteCapability Writer,
        IReadOnlyList<(string ProviderId, IDeviceReadCapability Provider)> DeviceProviders,
        IReadOnlyList<IProviderHealthCapability> HealthProviders,
        string BindingSummary);

    private sealed class AttributeEditorRow
    {
        public AttributeEditorRow(string attribute, string value, bool isReadOnly = false, bool isSingleValued = true, string syntax = "String")
        {
            Attribute = attribute;
            Value = value;
            IsReadOnly = isReadOnly;
            IsSingleValued = isSingleValued;
            Syntax = syntax;
        }

        public string Attribute { get; set; }

        public string Value { get; set; }

        public bool IsReadOnly { get; set; }

        public bool IsSingleValued { get; set; }

        public string Syntax { get; set; }
    }
}
