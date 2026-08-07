using System.Windows;
using System.Windows.Controls;
using HAP.Application.RuntimeProfiles;

namespace HAP.Presentation.RuntimeProfiles;

public partial class RuntimeProfileSelectorView : UserControl
{
    public RuntimeProfileSelectorView()
    {
        InitializeComponent();
    }

    private RuntimeProfileSelectorViewModel? ViewModel => DataContext as RuntimeProfileSelectorViewModel;

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

        var answer = MessageBox.Show(
            $"Delete profile '{ViewModel.SelectedProfile.DisplayName}'? This removes the profile folder from disk.",
            "Delete Profile",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
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

    private void OnNewUserWizardConfigClicked(object sender, RoutedEventArgs e)
    {
        ProfileConfigurationTabs.SelectedIndex = 3;
    }

    private void OnBrandingClicked(object sender, RoutedEventArgs e)
    {
        ProfileConfigurationTabs.SelectedIndex = 4;
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
            NotificationRecipient = NotificationRecipientTextBox.Text.Trim(),
            NotificationSender = NotificationSenderTextBox.Text.Trim(),
            Departments = DepartmentsTextBox.Text.Trim(),
            Locations = LocationsTextBox.Text.Trim(),
            JobTitles = JobTitlesTextBox.Text.Trim(),
            Portfolios = PortfoliosTextBox.Text.Trim(),
            DefaultLicenseSet = DefaultLicenseSetTextBox.Text.Trim(),
            NewUserWizardJson = NewUserWizardJsonTextBox.Text,
            DirectorySimulatorEnabled = DirectorySimulatorCheckBox.IsChecked == true,
            ActiveDirectoryEnabled = ActiveDirectoryCheckBox.IsChecked == true,
            MicrosoftGraphEnabled = MicrosoftGraphCheckBox.IsChecked == true,
            ExchangeOnlineEnabled = ExchangeOnlineCheckBox.IsChecked == true,
            ExchangeOnPremisesEnabled = ExchangeOnPremisesCheckBox.IsChecked == true,
            CreateMailboxByDefault = CreateMailboxCheckBox.IsChecked == true,
            SendOnboardingNotification = SendNoticeCheckBox.IsChecked == true,
            RequireManagerValidation = RequireManagerCheckBox.IsChecked == true,
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
}
