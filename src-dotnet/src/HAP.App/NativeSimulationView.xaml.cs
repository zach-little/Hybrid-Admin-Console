using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using HAP.Application.Capabilities;
using HAP.Application.Devices;
using HAP.Application.NewUser;
using HAP.Contracts;
using HAP.Providers.Abstractions;
using HAP.Providers.Simulator;

namespace HAP.App;

public partial class NativeSimulationView : UserControl
{
    private readonly DirectorySimulatorProvider _simulator = new();
    private readonly BuiltInCapabilityCatalog _capabilityCatalog = new();
    private readonly NativeNewUserPreflightService _newUserPreflight;
    private readonly NativeNewUserExecutionService _newUserExecution;
    private readonly NativeDeviceManagementService _deviceManagement;
    private NewUserExecutionPlan? _currentNewUserPlan;
    private SimulatorUserSummary? _selectedUser;

    public NativeSimulationView()
    {
        InitializeComponent();
        _newUserPreflight = new NativeNewUserPreflightService(_simulator);
        _newUserExecution = new NativeNewUserExecutionService(_simulator);
        _deviceManagement = new NativeDeviceManagementService(new[] { ("DirectorySimulator", (IDeviceReadCapability)_simulator) });
        Loaded += OnLoaded;
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
        await SearchAsync().ConfigureAwait(true);
    }

    private async void OnSearchKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Return)
        {
            e.Handled = true;
            await SearchAsync().ConfigureAwait(true);
        }
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
        await SearchDevicesAsync().ConfigureAwait(true);
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
            $"Runtime preferences\n\nSelected identity: {selected}\nDefault lookup tab: User Lookup\nTheme: Native dark\nProvider mode: Simulation-backed native services\n\nProfile-level preferences are managed from Back to Profiles > Configuration.",
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
            await Task.Delay(350).ConfigureAwait(true);
            var status = new[]
            {
                $"[{DateTimeOffset.Now:g}] Status: Completed",
                "Provider: DirectorySimulator.HybridConnection",
                "Remote request: Simulated",
                "Remote server: Runtime profile Hybrid Wizard Remote Server",
                "Result: Hybrid connection sync completed for simulation runtime.",
                "Live mode will replace this with the remote invocation response, exit code, and returned output."
            };
            UtilityStatusTextBox.Text = string.Join(Environment.NewLine, status);
            StatusText.Text = "Hybrid connection sync completed for simulation runtime.";
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

        var result = await _simulator.UpdateUserAttributesAsync(
            new UserUpdateRequest { Identity = user.SamAccountName, Attributes = values },
            CorrelationId.New()).ConfigureAwait(true);
        await CompleteUserMutationAsync("Edit Current User", result).ConfigureAwait(true);
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

        var reports = await _simulator.GetDirectReportsAsync(_selectedUser!.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
        var messages = new List<string>();
        foreach (var report in reports.Value ?? Array.Empty<SimulatorUserSummary>())
        {
            var result = await _simulator.SetManagerAsync(
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

        var result = await _simulator.SetManagerAsync(
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
            ? await _simulator.AddGroupMembershipAsync(new MembershipChangeRequest { Identity = _selectedUser!.SamAccountName, Group = group.Trim() }, CorrelationId.New()).ConfigureAwait(true)
            : await _simulator.RemoveGroupMembershipAsync(new MembershipChangeRequest { Identity = _selectedUser!.SamAccountName, Group = group.Trim() }, CorrelationId.New()).ConfigureAwait(true);
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

        var result = await _simulator.SetGalVisibilityAsync(
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

        var result = await _simulator.AddMailboxDelegationAsync(
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
        var result = await _simulator.SetMailboxForwardingAsync(
            new MailboxForwardingRequest { Identity = _selectedUser!.SamAccountName, ForwardingSmtpAddress = forwarding.Trim(), DeliverToMailboxAndForward = !string.IsNullOrWhiteSpace(forwarding) },
            CorrelationId.New()).ConfigureAwait(true);
        await CompleteUserMutationAsync("E-mail Forwarding", result).ConfigureAwait(true);
    }

    private async Task RefreshDashboardAsync()
    {
        var health = await _simulator.GetHealthAsync(CorrelationId.New()).ConfigureAwait(true);
        ProviderStatusList.ItemsSource = new[]
        {
            health.Value is null
                ? "DirectorySimulator: unavailable"
                : $"{health.Value.ProviderId}: {health.Value.Status} ({health.Value.Mode}) - {health.Value.Message}",
            "ActiveDirectory: native provider registered",
            "MicrosoftGraph: native provider registered",
            "ExchangeOnline: native provider registered",
            "ExchangeOnPremises: native provider registered"
        };
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

    private async Task SearchAsync(string? query)
    {
        var effectiveQuery = string.IsNullOrWhiteSpace(query) ? "amorgan" : query.Trim();
        SearchBox.Text = effectiveQuery;
        SetBusy(true, $"Searching for {effectiveQuery}...");
        ClearUserDetails();

        try
        {
            var result = await _simulator.SearchUsersAsync(effectiveQuery, CorrelationId.New()).ConfigureAwait(true);
            if (!result.Succeeded)
            {
                UsersGrid.ItemsSource = null;
                StatusText.Text = string.Join(" ", result.Errors.Select(error => error.Message));
                return;
            }

            var users = result.Value ?? Array.Empty<SimulatorUserSummary>();
            UsersGrid.ItemsSource = users;
            UsersGrid.SelectedIndex = users.Count > 0 ? 0 : -1;
            StatusText.Text = users.Count == 0 ? "No user result." : $"Loaded {users.Count} user result(s).";
        }
        finally
        {
            SetBusy(false);
        }
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

            var manager = await _simulator.GetManagerAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
            ManagerText.Text = Safe(manager.Value?.DisplayName ?? user.ManagerSamAccountName);

            var reports = await _simulator.GetDirectReportsAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
            DirectReportsText.Text = reports.Value is { Count: > 0 }
                ? string.Join(", ", reports.Value.Select(report => report.SamAccountName))
                : "None";

            var groups = await _simulator.GetGroupsAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
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
        var graph = await _simulator.GetGraphProfileAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
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

        var auth = await _simulator.GetAuthenticationPostureAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
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
        var mailbox = await _simulator.GetMailboxAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
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

        var stats = await _simulator.GetMailboxStatisticsAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
        ItemCountText.Text = stats.Value is null ? "Not loaded" : $"{stats.Value.ItemCount:N0} items, {stats.Value.TotalItemSize}";
        LastMailboxLogonText.Text = FormatDate(stats.Value?.LastLogonTime);

        var delegations = await _simulator.GetMailboxDelegationsAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
        MailboxDelegationList.ItemsSource = delegations.Value?.Select(item => $"{item.Trustee}: {item.AccessRights}").ToArray() ?? Array.Empty<string>();

        var distributionGroups = await _simulator.GetDistributionGroupsAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
        DistributionGroupsList.ItemsSource = distributionGroups.Value?.Select(item => $"{item.DisplayName} <{item.Mail}>").ToArray() ?? Array.Empty<string>();
    }

    private async Task SearchDevicesAsync()
    {
        var query = string.IsNullOrWhiteSpace(DeviceSearchBox.Text) ? SearchBox.Text : DeviceSearchBox.Text;
        SetBusy(true, $"Searching devices for {query}...");

        try
        {
            var result = await _deviceManagement.SearchDevicesAsync(query, CorrelationId.New()).ConfigureAwait(true);
            DevicesGrid.ItemsSource = result.Value?.Select(device => new DeviceRow(
                device.Name,
                device.OperatingSystem,
                device.ComplianceState,
                device.PrimaryUser,
                FormatDate(device.LastCheckInUtc),
                device.Source)).ToArray() ?? Array.Empty<DeviceRow>();
            StatusText.Text = $"Loaded {result.Value?.Count ?? 0} device result(s).";
        }
        finally
        {
            SetBusy(false);
        }
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
            var userResult = await _simulator.GetUserAsync(_selectedUser.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
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
        var attributeResult = await _simulator.GetDirectoryAttributesAsync(user.SamAccountName, CorrelationId.New()).ConfigureAwait(true);
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
                var result = await _simulator.SearchUsersAsync(query, CorrelationId.New()).ConfigureAwait(true);
                return result.Value?.Select(user => $"{user.SamAccountName} | {user.DisplayName}").ToArray() ?? Array.Empty<string>();
            },
            value => value.Split('|')[0].Trim()));

        var groupsPanel = CreatePickerPanel(
            "Groups",
            "Search groups",
            currentGroups,
            async query =>
            {
                var result = await _simulator.SearchGroupsAsync(query, CorrelationId.New()).ConfigureAwait(true);
                return result.Value?.Select(group => $"{group.DisplayName} | {group.Source}").ToArray() ?? Array.Empty<string>();
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
        SelectedIdentityStatusText.Text = "No selected user";
        DashboardSelectedUserText.Text = "-";
        DashboardSelectedUserSubText.Text = "Search for a user to hydrate dashboard cards.";
        DashboardGraphText.Text = "Not loaded";
        DashboardExchangeText.Text = "Not loaded";
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

    private static string Safe(string? value) => string.IsNullOrWhiteSpace(value) ? "-" : value;

    private static string JoinOrNone(IEnumerable<string> values)
    {
        var materialized = values.Where(value => !string.IsNullOrWhiteSpace(value)).ToArray();
        return materialized.Length == 0 ? "None" : string.Join(", ", materialized);
    }

    private static string FormatDate(DateTimeOffset? value) => value?.ToLocalTime().ToString("g") ?? "Not loaded";

    private sealed record CapabilityRow(string Provider, string Capability, string Disposition, string Reason);

    private sealed record DeviceRow(string Name, string OperatingSystem, string ComplianceState, string PrimaryUser, string LastCheckIn, string Source);

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
