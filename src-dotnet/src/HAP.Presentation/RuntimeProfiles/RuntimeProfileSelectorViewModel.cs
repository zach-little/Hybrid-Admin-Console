using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using HAP.Application.RuntimeProfiles;
using HAP.Contracts;

namespace HAP.Presentation.RuntimeProfiles;

public sealed class RuntimeProfileSelectorViewModel : INotifyPropertyChanged
{
    private readonly IRuntimeProfileCatalogService _catalogService;
    private readonly IRuntimeSessionService? _runtimeSessionService;
    private CancellationTokenSource? _loadCancellation;
    private RuntimeProfileItemViewModel? _selectedProfile;
    private bool _isLoading;
    private bool _isRuntimeStarted;
    private string _progressMessage = "Ready";
    private string _errorMessage = string.Empty;
    private string _runtimeStatus = "Not started";

    public RuntimeProfileSelectorViewModel(IRuntimeProfileCatalogService catalogService)
        : this(catalogService, runtimeSessionService: null)
    {
    }

    public RuntimeProfileSelectorViewModel(
        IRuntimeProfileCatalogService catalogService,
        IRuntimeSessionService? runtimeSessionService)
    {
        _catalogService = catalogService ?? throw new ArgumentNullException(nameof(catalogService));
        _runtimeSessionService = runtimeSessionService;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<RuntimeProfileItemViewModel> Profiles { get; } = new();

    public ObservableCollection<ProviderHealthItemViewModel> ProviderHealth { get; } = new();

    public RuntimeProfileItemViewModel? SelectedProfile
    {
        get => _selectedProfile;
        set
        {
            if (ReferenceEquals(_selectedProfile, value))
            {
                return;
            }

            _selectedProfile = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(HasSelection));
            OnPropertyChanged(nameof(IsSelectionValid));
            OnPropertyChanged(nameof(ValidationMessage));
        }
    }

    public bool IsLoading
    {
        get => _isLoading;
        private set
        {
            if (_isLoading == value)
            {
                return;
            }

            _isLoading = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanCancel));
        }
    }

    public bool CanCancel => IsLoading;

    public bool HasSelection => SelectedProfile is not null;

    public bool IsSelectionValid => SelectedProfile?.IsValid == true;

    public bool IsRuntimeStarted
    {
        get => _isRuntimeStarted;
        private set => SetField(ref _isRuntimeStarted, value);
    }

    public string ValidationMessage => SelectedProfile?.ValidationMessage ?? "Select a runtime profile.";

    public string ProgressMessage
    {
        get => _progressMessage;
        private set => SetField(ref _progressMessage, value);
    }

    public string RuntimeStatus
    {
        get => _runtimeStatus;
        private set => SetField(ref _runtimeStatus, value);
    }

    public string ErrorMessage
    {
        get => _errorMessage;
        private set
        {
            if (SetField(ref _errorMessage, value))
            {
                OnPropertyChanged(nameof(HasError));
            }
        }
    }

    public bool HasError => !string.IsNullOrWhiteSpace(ErrorMessage);

    public async Task LoadAsync(string repositoryRoot, CancellationToken cancellationToken = default)
    {
        CancelLoad();
        _loadCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        IsLoading = true;
        ErrorMessage = string.Empty;
        ProgressMessage = "Loading runtime profiles...";

        try
        {
            var result = await _catalogService.GetRuntimeProfilesAsync(
                repositoryRoot,
                CorrelationId.New(),
                _loadCancellation.Token).ConfigureAwait(true);

            Profiles.Clear();
            if (!result.Succeeded || result.Value is null)
            {
                ErrorMessage = string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
                ProgressMessage = "Runtime profiles failed to load.";
                SelectedProfile = null;
                return;
            }

            foreach (var profile in result.Value.Select(profile => new RuntimeProfileItemViewModel(profile)))
            {
                Profiles.Add(profile);
            }

            SelectedProfile = Profiles.FirstOrDefault(profile => profile.IsDefault)
                ?? Profiles.FirstOrDefault(profile => profile.IsLastUsed)
                ?? Profiles.FirstOrDefault(profile => profile.IsValid)
                ?? Profiles.FirstOrDefault();
            ProgressMessage = Profiles.Count == 0 ? "No runtime profiles found." : $"Loaded {Profiles.Count} runtime profiles.";
        }
        catch (OperationCanceledException)
        {
            ProgressMessage = "Runtime profile loading cancelled.";
        }
        finally
        {
            IsLoading = false;
            _loadCancellation?.Dispose();
            _loadCancellation = null;
        }
    }

    public void CancelLoad()
    {
        if (_loadCancellation is { IsCancellationRequested: false })
        {
            _loadCancellation.Cancel();
        }
    }

    public async Task StartSelectedRuntimeAsync(string repositoryRoot, CancellationToken cancellationToken = default)
    {
        if (_runtimeSessionService is null)
        {
            ErrorMessage = "Runtime session service is not configured.";
            return;
        }

        if (SelectedProfile is null)
        {
            ErrorMessage = "Select a runtime profile before launching.";
            return;
        }

        if (!SelectedProfile.IsValid)
        {
            ErrorMessage = SelectedProfile.ValidationMessage;
            return;
        }

        IsLoading = true;
        ErrorMessage = string.Empty;
        ProgressMessage = $"Launching {SelectedProfile.DisplayName}...";

        try
        {
            var result = await _runtimeSessionService.StartAsync(
                repositoryRoot,
                SelectedProfile.Name,
                CorrelationId.New(),
                cancellationToken).ConfigureAwait(true);

            ProviderHealth.Clear();
            if (!result.Succeeded || result.Value is null)
            {
                ErrorMessage = string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
                RuntimeStatus = "Launch failed";
                IsRuntimeStarted = false;
                ProgressMessage = "Runtime launch failed.";
                return;
            }

            foreach (var provider in result.Value.ProviderHealth.Select(health => new ProviderHealthItemViewModel(health)))
            {
                ProviderHealth.Add(provider);
            }

            RuntimeStatus = result.Value.OverallStatus;
            IsRuntimeStarted = !result.Value.HasErrors;
            ProgressMessage = $"Runtime initialized in {result.Value.DurationMs} ms.";
        }
        catch (OperationCanceledException)
        {
            RuntimeStatus = "Cancelled";
            ProgressMessage = "Runtime launch cancelled.";
        }
        finally
        {
            IsLoading = false;
        }
    }

    public async Task ShutdownRuntimeAsync(string repositoryRoot, CancellationToken cancellationToken = default)
    {
        if (_runtimeSessionService is null)
        {
            ErrorMessage = "Runtime session service is not configured.";
            return;
        }

        var result = await _runtimeSessionService.ShutdownAsync(repositoryRoot, CorrelationId.New(), cancellationToken)
            .ConfigureAwait(true);
        if (!result.Succeeded)
        {
            ErrorMessage = string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
            return;
        }

        ProviderHealth.Clear();
        IsRuntimeStarted = false;
        RuntimeStatus = "Stopped";
        ProgressMessage = "Runtime session stopped.";
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string propertyName = "")
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string propertyName = "")
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
