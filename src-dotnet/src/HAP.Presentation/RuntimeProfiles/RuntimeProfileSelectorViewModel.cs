using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using HAP.Application.Licensing;
using HAP.Application.RuntimeProfiles;
using HAP.Contracts;

namespace HAP.Presentation.RuntimeProfiles;

public sealed class RuntimeProfileSelectorViewModel : INotifyPropertyChanged
{
    private readonly IRuntimeProfileCatalogService _catalogService;
    private readonly IRuntimeSessionService? _runtimeSessionService;
    private readonly IRuntimeProfileManagementService? _profileManagementService;
    private readonly ILicensingService _licensingService;
    private CancellationTokenSource? _loadCancellation;
    private RuntimeProfileItemViewModel? _selectedProfile;
    private RuntimeProfileConfigurationDraft _profileConfiguration = new();
    private bool _isLoading;
    private bool _isRuntimeStarted;
    private string _repositoryRoot = string.Empty;
    private string _progressMessage = "Ready";
    private string _errorMessage = string.Empty;
    private string _runtimeStatus = "Not started";
    private LicensingStatus _licensingStatus = new() { Message = "Licensing status has not loaded." };
    private string _activationKey = string.Empty;

    public RuntimeProfileSelectorViewModel(IRuntimeProfileCatalogService catalogService)
        : this(catalogService, runtimeSessionService: null)
    {
    }

    public RuntimeProfileSelectorViewModel(
        IRuntimeProfileCatalogService catalogService,
        IRuntimeSessionService? runtimeSessionService,
        IRuntimeProfileManagementService? profileManagementService = null,
        ILicensingService? licensingService = null)
    {
        _catalogService = catalogService ?? throw new ArgumentNullException(nameof(catalogService));
        _runtimeSessionService = runtimeSessionService;
        _profileManagementService = profileManagementService;
        _licensingService = licensingService ?? CreateDefaultLicensingService();
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
            _ = LoadSelectedProfileConfigurationAsync();
        }
    }

    public RuntimeProfileConfigurationDraft ProfileConfiguration
    {
        get => _profileConfiguration;
        private set => SetField(ref _profileConfiguration, value ?? new RuntimeProfileConfigurationDraft());
    }

    public bool IsLoading
    {
        get => _isLoading;
        private set
        {
            if (SetField(ref _isLoading, value))
            {
                OnPropertyChanged(nameof(CanCancel));
                OnPropertyChanged(nameof(CanManageProfiles));
            }
        }
    }

    public bool CanCancel => IsLoading;

    public bool CanManageProfiles => _profileManagementService is not null && !IsLoading;

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

    public LicensingStatus LicensingStatus
    {
        get => _licensingStatus;
        private set
        {
            if (SetField(ref _licensingStatus, value))
            {
                OnPropertyChanged(nameof(LicenseStateText));
                OnPropertyChanged(nameof(LicenseOrganizationText));
                OnPropertyChanged(nameof(LicenseEditionText));
                OnPropertyChanged(nameof(LicenseTypeText));
                OnPropertyChanged(nameof(LicenseNumberText));
                OnPropertyChanged(nameof(LicenseExpirationText));
                OnPropertyChanged(nameof(LicenseGraceText));
                OnPropertyChanged(nameof(LicenseValidatedText));
                OnPropertyChanged(nameof(LicenseSigningKeyText));
                OnPropertyChanged(nameof(ManagedIdentitiesText));
                OnPropertyChanged(nameof(AdministratorsText));
                OnPropertyChanged(nameof(DirectoriesText));
            }
        }
    }

    public string ActivationKey
    {
        get => _activationKey;
        set => SetField(ref _activationKey, value);
    }

    public string LicenseStateText => LicensingStatus.State.ToString();

    public string LicenseOrganizationText => LicensingStatus.License?.Payload.Organization ?? "-";

    public string LicenseEditionText => LicensingStatus.License?.Payload.Edition ?? "-";

    public string LicenseTypeText => LicensingStatus.License?.Payload.LicenseType ?? "-";

    public string LicenseNumberText => LicensingStatus.License?.Payload.LicenseNumber ?? "-";

    public string LicenseExpirationText => FormatDate(LicensingStatus.License?.Payload.ExpiresAt);

    public string LicenseGraceText => FormatDate(LicensingStatus.License?.Payload.GraceUntil);

    public string LicenseValidatedText => FormatDate(LicensingStatus.LastSuccessfulValidationUtc);

    public string LicenseSigningKeyText => LicensingStatus.License?.Envelope.KeyId ?? "-";

    public string ManagedIdentitiesText => FormatNumericEntitlement(HilopEntitlements.ManagedIdentities);

    public string AdministratorsText => FormatNumericEntitlement(HilopEntitlements.Administrators);

    public string DirectoriesText => FormatNumericEntitlement(HilopEntitlements.Directories);

    public async Task LoadAsync(string repositoryRoot, CancellationToken cancellationToken = default)
    {
        _repositoryRoot = repositoryRoot;
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
            await LoadLicensingStatusAsync(cancellationToken).ConfigureAwait(true);
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

    public async Task LoadSelectedProfileConfigurationAsync(CancellationToken cancellationToken = default)
    {
        if (_profileManagementService is null || SelectedProfile is null || string.IsNullOrWhiteSpace(_repositoryRoot))
        {
            ProfileConfiguration = new RuntimeProfileConfigurationDraft();
            return;
        }

        var result = await _profileManagementService.GetProfileConfigurationAsync(_repositoryRoot, SelectedProfile.Name, CorrelationId.New(), cancellationToken)
            .ConfigureAwait(true);
        if (result.Succeeded && result.Value is not null)
        {
            ProfileConfiguration = result.Value;
            ErrorMessage = string.Empty;
        }
        else
        {
            ErrorMessage = string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
        }
    }

    public async Task SaveProfileConfigurationAsync(RuntimeProfileConfigurationDraft draft, CancellationToken cancellationToken = default)
    {
        if (_profileManagementService is null)
        {
            ErrorMessage = "Profile management service is not configured.";
            return;
        }

        var result = await _profileManagementService.SaveProfileConfigurationAsync(_repositoryRoot, draft, CorrelationId.New(), cancellationToken)
            .ConfigureAwait(true);
        ProgressMessage = result.Succeeded ? result.Value ?? "Profile saved." : "Profile save failed.";
        ErrorMessage = result.Succeeded ? string.Empty : string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
        if (result.Succeeded)
        {
            await LoadAsync(_repositoryRoot, cancellationToken).ConfigureAwait(true);
        }
    }

    public async Task CreateProfileAsync(string profileName, CancellationToken cancellationToken = default)
    {
        if (_profileManagementService is null)
        {
            ErrorMessage = "Profile management service is not configured.";
            return;
        }

        var result = await _profileManagementService.CreateProfileAsync(_repositoryRoot, profileName, CorrelationId.New(), cancellationToken)
            .ConfigureAwait(true);
        ProgressMessage = result.Succeeded ? result.Value ?? "Profile created." : "Profile create failed.";
        ErrorMessage = result.Succeeded ? string.Empty : string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
        if (result.Succeeded)
        {
            await LoadAsync(_repositoryRoot, cancellationToken).ConfigureAwait(true);
            SelectedProfile = Profiles.FirstOrDefault(profile => string.Equals(profile.Name, profileName, StringComparison.OrdinalIgnoreCase)) ?? SelectedProfile;
        }
    }

    public async Task DeleteSelectedProfileAsync(CancellationToken cancellationToken = default)
    {
        if (_profileManagementService is null || SelectedProfile is null)
        {
            ErrorMessage = "Select a profile first.";
            return;
        }

        var result = await _profileManagementService.DeleteProfileAsync(_repositoryRoot, SelectedProfile.Name, CorrelationId.New(), cancellationToken)
            .ConfigureAwait(true);
        ProgressMessage = result.Succeeded ? result.Value ?? "Profile deleted." : "Profile delete failed.";
        ErrorMessage = result.Succeeded ? string.Empty : string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
        if (result.Succeeded)
        {
            await LoadAsync(_repositoryRoot, cancellationToken).ConfigureAwait(true);
        }
    }

    public async Task SetSelectedProfileDefaultAsync(CancellationToken cancellationToken = default)
    {
        if (_profileManagementService is null || SelectedProfile is null)
        {
            ErrorMessage = "Select a profile first.";
            return;
        }

        var result = await _profileManagementService.SetDefaultProfileAsync(_repositoryRoot, SelectedProfile.Name, CorrelationId.New(), cancellationToken)
            .ConfigureAwait(true);
        ProgressMessage = result.Succeeded ? result.Value ?? "Default profile updated." : "Set default failed.";
        ErrorMessage = result.Succeeded ? string.Empty : string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
        if (result.Succeeded)
        {
            await LoadAsync(_repositoryRoot, cancellationToken).ConfigureAwait(true);
        }
    }

    public async Task ExportSelectedProfileAsync(CancellationToken cancellationToken = default)
    {
        if (_profileManagementService is null || SelectedProfile is null)
        {
            ErrorMessage = "Select a profile first.";
            return;
        }

        var result = await _profileManagementService.ExportProfileAsync(_repositoryRoot, SelectedProfile.Name, CorrelationId.New(), cancellationToken)
            .ConfigureAwait(true);
        ProgressMessage = result.Succeeded ? result.Value ?? "Profile exported." : "Profile export failed.";
        ErrorMessage = result.Succeeded ? string.Empty : string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
    }

    public async Task LoadLicensingStatusAsync(CancellationToken cancellationToken = default)
    {
        LicensingStatus = await _licensingService.GetStatusAsync(cancellationToken).ConfigureAwait(true);
    }

    public async Task ActivateLicenseAsync(CancellationToken cancellationToken = default)
    {
        ErrorMessage = string.Empty;
        ProgressMessage = "Activating HILOP license...";
        var result = await _licensingService.ActivateAsync(
            new LicenseActivationRequest(
                ActivationKey,
                Environment.MachineName,
                typeof(RuntimeProfileSelectorViewModel).Assembly.GetName().Version?.ToString() ?? "1.0",
                "HILOP"),
            CorrelationId.New(),
            cancellationToken).ConfigureAwait(true);

        if (result.Succeeded && result.Value is not null)
        {
            ActivationKey = string.Empty;
            LicensingStatus = result.Value;
            ProgressMessage = "License activated.";
            return;
        }

        ProgressMessage = "License activation failed.";
        ErrorMessage = string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
    }

    public async Task RefreshLicenseAsync(CancellationToken cancellationToken = default)
    {
        ErrorMessage = string.Empty;
        ProgressMessage = "Refreshing HILOP license...";
        var result = await _licensingService.RefreshAsync(CorrelationId.New(), cancellationToken).ConfigureAwait(true);
        if (result.Succeeded && result.Value is not null)
        {
            LicensingStatus = result.Value;
            ProgressMessage = "License refreshed.";
            return;
        }

        ProgressMessage = "License refresh failed.";
        ErrorMessage = string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
    }

    public async Task DeactivateLicenseAsync(CancellationToken cancellationToken = default)
    {
        ErrorMessage = string.Empty;
        ProgressMessage = "Deactivating HILOP installation...";
        var result = await _licensingService.DeactivateAsync(CorrelationId.New(), cancellationToken).ConfigureAwait(true);
        if (result.Succeeded && result.Value is not null)
        {
            LicensingStatus = result.Value;
            ProgressMessage = "Installation deactivated.";
            return;
        }

        ProgressMessage = "License deactivation failed.";
        ErrorMessage = string.Join(Environment.NewLine, result.Errors.Select(error => error.Message));
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

    private static ILicensingService CreateDefaultLicensingService()
    {
        var options = new LicensingOptions();
        var store = new FileLocalLicenseStore(options.StorageDirectory);
        var client = new LicensingApiClient(options);
        return new LicensingService(options, store, client);
    }

    private string FormatNumericEntitlement(string entitlementKey)
    {
        var value = LicensingStatus.License is null
            ? null
            : LicenseEntitlementEvaluator.GetNumeric(LicensingStatus.License, entitlementKey);
        return value.HasValue ? value.Value.ToString() : "-";
    }

    private static string FormatDate(DateTimeOffset? value)
    {
        return value.HasValue ? value.Value.UtcDateTime.ToString("u") : "-";
    }
}
