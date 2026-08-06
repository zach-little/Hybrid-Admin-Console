using System.IO;
using System.Windows;
using HAP.Presentation.RuntimeProfiles;

namespace HAP.App;

public partial class MainWindow : Window
{
    private readonly RuntimeProfileSelectorViewModel _viewModel;

    public MainWindow()
    {
        InitializeComponent();
        _viewModel = new RuntimeProfileSelectorViewModel(
            new NativeRuntimeProfileCatalogService(),
            new NativeRuntimeSessionService());
        ContentHost.Content = new RuntimeProfileSelectorView { DataContext = _viewModel };
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
            LaunchButton.Content = "Running";
        }
    }

    private Task LoadProfilesAsync()
    {
        return _viewModel.LoadAsync(GetRepositoryRoot());
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
