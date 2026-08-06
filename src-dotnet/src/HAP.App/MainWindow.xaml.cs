using System.IO;
using System.Windows;
using HAP.Presentation.RuntimeProfiles;

namespace HAP.App;

public partial class MainWindow : Window
{
    private readonly RuntimeProfileSelectorViewModel _viewModel;
    private readonly NativeRuntimeProfileCatalogService _runtimeProfileService = new();

    public MainWindow()
    {
        InitializeComponent();
        _viewModel = new RuntimeProfileSelectorViewModel(
            _runtimeProfileService,
            new NativeRuntimeSessionService(),
            _runtimeProfileService);
        ShowProfileSelector();
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        await LoadProfilesAsync().ConfigureAwait(true);
    }

    private async void OnRefreshClicked(object sender, RoutedEventArgs e)
    {
        await LoadProfilesAsync().ConfigureAwait(true);
    }

    private async void OnLaunchClicked(object sender, RoutedEventArgs e)
    {
        await _viewModel.StartSelectedRuntimeAsync(GetRepositoryRoot()).ConfigureAwait(true);
        if (_viewModel.IsRuntimeStarted)
        {
            ContentHost.Content = new NativeSimulationView();
            LaunchButton.Visibility = Visibility.Collapsed;
            RefreshButton.Visibility = Visibility.Collapsed;
            BackToProfilesButton.Visibility = Visibility.Visible;
        }
    }

    private async void OnBackToProfilesClicked(object sender, RoutedEventArgs e)
    {
        await _viewModel.ShutdownRuntimeAsync(GetRepositoryRoot()).ConfigureAwait(true);
        ShowProfileSelector();
        await LoadProfilesAsync().ConfigureAwait(true);
    }

    private Task LoadProfilesAsync()
    {
        return _viewModel.LoadAsync(GetRepositoryRoot());
    }

    private void ShowProfileSelector()
    {
        ContentHost.Content = new RuntimeProfileSelectorView { DataContext = _viewModel };
        LaunchButton.Visibility = Visibility.Visible;
        RefreshButton.Visibility = Visibility.Visible;
        BackToProfilesButton.Visibility = Visibility.Collapsed;
    }

    private static string GetRepositoryRoot()
    {
        var current = AppContext.BaseDirectory;
        while (!string.IsNullOrWhiteSpace(current))
        {
            if (Directory.Exists(Path.Combine(current, "profiles")) ||
                Directory.Exists(Path.Combine(current, "src-dotnet")))
            {
                return current;
            }

            var parent = Directory.GetParent(current);
            if (parent is null)
            {
                break;
            }

            current = parent.FullName;
        }

        return Directory.GetCurrentDirectory();
    }
}
