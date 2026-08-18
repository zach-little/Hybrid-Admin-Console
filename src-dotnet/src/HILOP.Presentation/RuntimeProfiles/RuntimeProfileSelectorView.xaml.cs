using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.ComponentModel;
using System.Windows.Media;
using HILOP.Application.RuntimeProfiles;
using HILOP.Presentation.Dialogs;

namespace HILOP.Presentation.RuntimeProfiles;

public partial class RuntimeProfileSelectorView : UserControl
{
    private bool _autoLicenseDialogAttempted;
    private RuntimeProfileSelectorViewModel? _subscribedViewModel;

    public RuntimeProfileSelectorView()
    {
        InitializeComponent();
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
        DataContextChanged += OnDataContextChanged;
    }

    private RuntimeProfileSelectorViewModel? ViewModel => DataContext as RuntimeProfileSelectorViewModel;

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        SubscribeToViewModel(ViewModel);
        TryShowAutomaticLicensingDialog();
    }

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        SubscribeToViewModel(null);
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        SubscribeToViewModel(e.NewValue as RuntimeProfileSelectorViewModel);
        TryShowAutomaticLicensingDialog();
    }

    private void SubscribeToViewModel(RuntimeProfileSelectorViewModel? viewModel)
    {
        if (ReferenceEquals(_subscribedViewModel, viewModel))
        {
            return;
        }

        if (_subscribedViewModel is not null)
        {
            _subscribedViewModel.PropertyChanged -= OnViewModelPropertyChanged;
        }

        _subscribedViewModel = viewModel;
        if (_subscribedViewModel is not null)
        {
            _subscribedViewModel.PropertyChanged += OnViewModelPropertyChanged;
        }
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(RuntimeProfileSelectorViewModel.HasLoadedLicensingStatus) or nameof(RuntimeProfileSelectorViewModel.ShouldAutoPromptForLicense))
        {
            TryShowAutomaticLicensingDialog();
        }
    }

    private void TryShowAutomaticLicensingDialog()
    {
        if (_autoLicenseDialogAttempted || !IsLoaded || ViewModel?.HasLoadedLicensingStatus != true)
        {
            return;
        }

        _autoLicenseDialogAttempted = true;
        if (ViewModel.ShouldAutoPromptForLicense)
        {
            Dispatcher.BeginInvoke(new Action(ShowLicensingDialog));
        }
    }

    private void OnFileMenuClicked(object sender, RoutedEventArgs e) => ToggleMenu(FileMenuPopup);

    private void OnProfileMenuClicked(object sender, RoutedEventArgs e) => ToggleMenu(ProfileMenuPopup);

    private void OnConfigurationMenuClicked(object sender, RoutedEventArgs e) => ToggleMenu(ConfigurationMenuPopup);

    private void ToggleMenu(System.Windows.Controls.Primitives.Popup popup)
    {
        var open = !popup.IsOpen;
        FileMenuPopup.IsOpen = false;
        ProfileMenuPopup.IsOpen = false;
        ConfigurationMenuPopup.IsOpen = false;
        popup.IsOpen = open;
    }

    private async void OnAddProfileClicked(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        var name = PromptForText("New Profile", "Enter the new profile name:");
        if (string.IsNullOrWhiteSpace(name))
        {
            return;
        }

        await ViewModel.CreateProfileAsync(name.Trim()).ConfigureAwait(true);
    }

    private void OnEditProfileClicked(object sender, RoutedEventArgs e)
    {
        ProfileConfigurationTabs.SelectedIndex = 1;
    }

    private async void OnDeleteProfileClicked(object sender, RoutedEventArgs e)
    {
        if (ViewModel?.SelectedProfile is null)
        {
            return;
        }

        var answer = HapDialog.Show(
            Window.GetWindow(this),
            "Delete Profile",
            $"Delete profile '{ViewModel.SelectedProfile.DisplayName}'? This removes the profile folder from disk.",
            MessageBoxButton.YesNo,
            isDestructive: true,
            yesText: "Delete");
        if (answer == MessageBoxResult.Yes)
        {
            await ViewModel.DeleteSelectedProfileAsync().ConfigureAwait(true);
        }
    }

    private async void OnImportExportClicked(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not null)
        {
            await ViewModel.ExportSelectedProfileAsync().ConfigureAwait(true);
        }
    }

    private async void OnSetDefaultClicked(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not null)
        {
            await ViewModel.SetSelectedProfileDefaultAsync().ConfigureAwait(true);
        }
    }

    private void OnProviderSetupClicked(object sender, RoutedEventArgs e)
    {
        ProfileConfigurationTabs.SelectedIndex = 2;
    }

    private void OnBrandingClicked(object sender, RoutedEventArgs e)
    {
        ProfileConfigurationTabs.SelectedIndex = 3;
    }

    private void OnLicensingClicked(object sender, RoutedEventArgs e)
    {
        ShowLicensingDialog();
    }

    private async void OnReloadProfileConfigurationClicked(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not null)
        {
            await ViewModel.LoadSelectedProfileConfigurationAsync().ConfigureAwait(true);
        }
    }

    private async void OnSaveProfileConfigurationClicked(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        var draft = new RuntimeProfileConfigurationDraft
        {
            ProfileName = ProfileNameTextBox.Text.Trim(),
            DisplayName = DisplayNameTextBox.Text.Trim(),
            Organization = OrganizationTextBox.Text.Trim(),
            Environment = EnvironmentTextBox.Text.Trim(),
            RuntimeMode = RuntimeModeComboBox.Text.Trim(),
            CloudEnvironment = CloudComboBox.Text.Trim(),
            TenantId = TenantIdTextBox.Text.Trim(),
            AppOnlyEnabled = AppOnlyEnabledCheckBox.IsChecked == true,
            AppOnlyTenantDomain = AppOnlyTenantDomainTextBox.Text.Trim(),
            AppOnlyClientId = AppOnlyClientIdTextBox.Text.Trim(),
            AppOnlyCredentialMode = AppOnlyCredentialModeComboBox.Text.Trim(),
            CertificateThumbprint = NormalizeThumbprint(CertificateThumbprintTextBox.Text),
            CertificatePath = CertificatePathTextBox.Text.Trim(),
            SecretReference = SecretReferenceTextBox.Text.Trim(),
            DelegatedEnabled = DelegatedEnabledCheckBox.IsChecked == true,
            DelegatedPromptWhenRequired = DelegatedPromptWhenRequiredCheckBox.IsChecked == true,
            ActiveDirectoryDomain = ActiveDirectoryDomainTextBox.Text.Trim(),
            ActiveDirectoryServer = ActiveDirectoryServerTextBox.Text.Trim(),
            ActiveDirectoryDefaultUserContainer = ActiveDirectoryDefaultUserContainerTextBox.Text.Trim(),
            ExchangeOnPremisesServer = ExchangeOnPremisesServerTextBox.Text.Trim(),
            ExchangeOnPremisesConnectionUri = ExchangeOnPremisesConnectionUriTextBox.Text.Trim(),
            ExchangeOnPremisesAuthentication = ExchangeOnPremisesAuthenticationComboBox.Text.Trim(),
            HybridConnectionServer = HybridConnectionServerTextBox.Text.Trim(),
            NotificationRecipient = ViewModel.ProfileConfiguration.NotificationRecipient,
            NotificationSender = ViewModel.ProfileConfiguration.NotificationSender,
            Departments = ViewModel.ProfileConfiguration.Departments,
            Locations = ViewModel.ProfileConfiguration.Locations,
            JobTitles = ViewModel.ProfileConfiguration.JobTitles,
            Portfolios = ViewModel.ProfileConfiguration.Portfolios,
            DefaultLicenseSet = ViewModel.ProfileConfiguration.DefaultLicenseSet,
            NewUserWizardJson = ViewModel.ProfileConfiguration.NewUserWizardJson,
            DirectorySimulatorEnabled = DirectorySimulatorCheckBox.IsChecked == true,
            ActiveDirectoryEnabled = ActiveDirectoryCheckBox.IsChecked == true,
            MicrosoftGraphEnabled = MicrosoftGraphCheckBox.IsChecked == true,
            ExchangeOnlineEnabled = ExchangeOnlineCheckBox.IsChecked == true,
            ExchangeOnPremisesEnabled = ExchangeOnPremisesCheckBox.IsChecked == true,
            CreateMailboxByDefault = ViewModel.ProfileConfiguration.CreateMailboxByDefault,
            SendOnboardingNotification = ViewModel.ProfileConfiguration.SendOnboardingNotification,
            RequireManagerValidation = ViewModel.ProfileConfiguration.RequireManagerValidation,
            WindowTitle = WindowTitleTextBox.Text.Trim(),
            ThemeName = ThemeNameTextBox.Text.Trim(),
            PrimaryColor = PrimaryColorTextBox.Text.Trim(),
            AccentColor = AccentColorTextBox.Text.Trim(),
            BackgroundColor = BackgroundColorTextBox.Text.Trim(),
            SurfaceColor = SurfaceColorTextBox.Text.Trim(),
            ForegroundColor = ForegroundColorTextBox.Text.Trim(),
            MutedTextColor = MutedTextColorTextBox.Text.Trim(),
            LogoPath = LogoPathTextBox.Text.Trim(),
            IconPath = IconPathTextBox.Text.Trim(),
            SplashPath = SplashPathTextBox.Text.Trim(),
            ThemeMode = ThemeModeComboBox.Text.Trim()
        };

        await ViewModel.SaveProfileConfigurationAsync(draft).ConfigureAwait(true);
    }

    private static string PromptForText(string title, string prompt)
    {
        var window = new Window
        {
            Title = title,
            Width = 440,
            Height = 190,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Background = System.Windows.Media.Brushes.Transparent,
            Owner = System.Windows.Application.Current.MainWindow,
            ResizeMode = ResizeMode.NoResize
        };

        var root = new Grid
        {
            Margin = new Thickness(16)
        };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var promptText = new TextBlock { Text = prompt, Margin = new Thickness(0, 0, 0, 10) };
        var input = new TextBox { Height = 32, Margin = new Thickness(0, 0, 0, 14) };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var ok = new Button { Content = "Create", Width = 96, Margin = new Thickness(0, 0, 8, 0), IsDefault = true };
        var cancel = new Button { Content = "Cancel", Width = 96, IsCancel = true };

        ok.Click += (_, _) =>
        {
            window.DialogResult = true;
            window.Close();
        };

        buttons.Children.Add(ok);
        buttons.Children.Add(cancel);
        Grid.SetRow(input, 1);
        Grid.SetRow(buttons, 2);
        root.Children.Add(promptText);
        root.Children.Add(input);
        root.Children.Add(buttons);
        window.Content = root;

        return window.ShowDialog() == true ? input.Text : string.Empty;
    }

    private static string NormalizeThumbprint(string value)
    {
        return new string((value ?? string.Empty)
            .Where(Uri.IsHexDigit)
            .Select(char.ToUpperInvariant)
            .ToArray());
    }

    private void OnActivationKeyPasswordChanged(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not null && sender is PasswordBox passwordBox)
        {
            ViewModel.ActivationKey = passwordBox.Password;
        }
    }

    private async void OnActivateLicenseClicked(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        await ViewModel.ActivateLicenseAsync().ConfigureAwait(true);
    }

    private async void OnRefreshLicenseClicked(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not null)
        {
            await ViewModel.RefreshLicenseAsync().ConfigureAwait(true);
        }
    }

    private async void OnDeactivateLicenseClicked(object sender, RoutedEventArgs e)
    {
        if (ViewModel is null)
        {
            return;
        }

        var answer = HapDialog.Show(
            Window.GetWindow(this),
            "Deactivate Installation",
            "Deactivate this HILOP installation? Configuration and cached license data are preserved.",
            MessageBoxButton.YesNo,
            isDestructive: true,
            yesText: "Deactivate");
        if (answer == MessageBoxResult.Yes)
        {
            await ViewModel.DeactivateLicenseAsync().ConfigureAwait(true);
        }
    }

    private void ShowLicensingDialog()
    {
        if (ViewModel is null)
        {
            return;
        }

        _ = ViewModel.LoadLicensingStatusAsync();

        var window = new Window
        {
            Title = "Application Licensing",
            Width = 900,
            Height = 620,
            MinWidth = 780,
            MinHeight = 520,
            Owner = Window.GetWindow(this),
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Background = BrushFrom("#0B1220")
        };

        var root = new Grid { Margin = new Thickness(18) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var header = new StackPanel { Margin = new Thickness(0, 0, 0, 16) };
        header.Children.Add(Text("HILOP Licensing", 24, FontWeights.SemiBold));
        var message = Text(string.Empty, 13, FontWeights.Normal, "#94A3B8");
        message.SetBinding(TextBlock.TextProperty, new Binding("LicensingStatus.Message"));
        header.Children.Add(message);
        root.Children.Add(header);

        var body = new Grid();
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(18) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetRow(body, 1);

        var statusPanel = Panel();
        statusPanel.Children.Add(Text("License Status", 18, FontWeights.SemiBold));
        AddBoundRow(statusPanel, "Status", "LicenseStateText");
        AddBoundRow(statusPanel, "Organization", "LicenseOrganizationText");
        AddBoundRow(statusPanel, "Edition", "LicenseEditionText");
        AddBoundRow(statusPanel, "License Type", "LicenseTypeText");
        AddBoundRow(statusPanel, "License Number", "LicenseNumberText");
        AddBoundRow(statusPanel, "Expiration", "LicenseExpirationText");
        AddBoundRow(statusPanel, "Grace Period", "LicenseGraceText");
        AddBoundRow(statusPanel, "Last Validation", "LicenseValidatedText");
        AddBoundRow(statusPanel, "Installation ID", "LicensingStatus.InstallationId");
        AddBoundRow(statusPanel, "Signing Key ID", "LicenseSigningKeyText");
        body.Children.Add(statusPanel);

        var actionsPanel = Panel();
        Grid.SetColumn(actionsPanel, 2);
        actionsPanel.Children.Add(Text("Activation", 18, FontWeights.SemiBold));
        actionsPanel.Children.Add(Text("Enter a Little Innovation Tech activation key. The key is exchanged for an installation credential and is not stored.", 13, FontWeights.Normal, "#94A3B8"));
        actionsPanel.Children.Add(Label("Activation Key"));
        var activationKeyBox = new PasswordBox
        {
            Height = 34,
            Background = BrushFrom("#0B1220"),
            Foreground = BrushFrom("#F8FAFC"),
            BorderBrush = BrushFrom("#475569"),
            Margin = new Thickness(0, 0, 0, 12)
        };
        activationKeyBox.PasswordChanged += (_, _) => ViewModel.ActivationKey = activationKeyBox.Password;
        actionsPanel.Children.Add(activationKeyBox);

        var buttons = new WrapPanel { Margin = new Thickness(0, 0, 0, 18) };
        buttons.Children.Add(Button("Activate License", async (_, _) =>
        {
            await ViewModel.ActivateLicenseAsync().ConfigureAwait(true);
            activationKeyBox.Clear();
        }));
        buttons.Children.Add(Button("Refresh License", async (_, _) => await ViewModel.RefreshLicenseAsync().ConfigureAwait(true)));
        buttons.Children.Add(Button("Deactivate Installation", async (_, _) =>
        {
            var answer = HapDialog.Show(window, "Deactivate Installation", "Deactivate this HILOP installation? Configuration and cached license data are preserved.", MessageBoxButton.YesNo, isDestructive: true, yesText: "Deactivate");
            if (answer == MessageBoxResult.Yes)
            {
                await ViewModel.DeactivateLicenseAsync().ConfigureAwait(true);
            }
        }));
        actionsPanel.Children.Add(buttons);

        actionsPanel.Children.Add(Text("Entitlement Limits", 18, FontWeights.SemiBold));
        AddBoundRow(actionsPanel, "Managed Identities", "ManagedIdentitiesText");
        AddBoundRow(actionsPanel, "Administrators", "AdministratorsText");
        AddBoundRow(actionsPanel, "Directories", "DirectoriesText");
        body.Children.Add(actionsPanel);
        root.Children.Add(body);

        var closeButton = Button("Close", (_, _) => window.Close());
        closeButton.HorizontalAlignment = HorizontalAlignment.Right;
        Grid.SetRow(closeButton, 2);
        root.Children.Add(closeButton);

        window.Content = root;
        window.DataContext = ViewModel;
        window.ShowDialog();
    }

    private static StackPanel Panel()
    {
        return new StackPanel
        {
            Background = BrushFrom("#1E293B"),
            Margin = new Thickness(0, 0, 0, 12)
        };
    }

    private static void AddBoundRow(Panel parent, string label, string path)
    {
        parent.Children.Add(Label(label));
        var value = Text(string.Empty, 14, FontWeights.SemiBold);
        value.Margin = new Thickness(0, 0, 0, 10);
        value.SetBinding(TextBlock.TextProperty, new Binding(path));
        parent.Children.Add(value);
    }

    private static TextBlock Label(string text)
    {
        return Text(text, 12, FontWeights.Normal, "#94A3B8");
    }

    private static TextBlock Text(string text, double size, FontWeight weight, string color = "#F8FAFC")
    {
        return new TextBlock
        {
            Text = text,
            FontSize = size,
            FontWeight = weight,
            Foreground = BrushFrom(color),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 5)
        };
    }

    private static Button Button(string text, RoutedEventHandler handler)
    {
        var button = new Button
        {
            Content = text,
            MinWidth = 118,
            Height = 34,
            Padding = new Thickness(14, 0, 14, 0),
            Margin = new Thickness(0, 0, 8, 8),
            Background = BrushFrom("#0F172A"),
            Foreground = BrushFrom("#F8FAFC"),
            BorderBrush = BrushFrom("#475569"),
            FontWeight = FontWeights.SemiBold
        };
        button.Click += handler;
        return button;
    }

    private static Brush BrushFrom(string color)
    {
        return (Brush)new BrushConverter().ConvertFromString(color)!;
    }
}
