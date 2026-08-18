using HILOP.Contracts;

namespace HILOP.Application.Licensing;

public interface ILicensingService
{
    Task<LicensingStatus> GetStatusAsync(CancellationToken cancellationToken = default);

    Task<VerifiedLicense?> GetLicenseAsync(CancellationToken cancellationToken = default);

    Task<bool> HasEntitlementAsync(string entitlementKey, CancellationToken cancellationToken = default);

    Task<int?> GetNumericEntitlementAsync(string entitlementKey, CancellationToken cancellationToken = default);

    Task<bool> IsWithinNumericLimitAsync(string entitlementKey, int currentUsage, CancellationToken cancellationToken = default);

    Task<OperationResult<LicensingStatus>> ActivateAsync(LicenseActivationRequest request, CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<LicensingStatus>> RefreshAsync(CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<LicensingStatus>> DeactivateAsync(CorrelationId correlationId, CancellationToken cancellationToken = default);
}

public sealed class LicensingService : ILicensingService
{
    private readonly LicensingOptions _options;
    private readonly ILocalLicenseStore _store;
    private readonly ILicensingApiClient _apiClient;
    private readonly ILicenseEnvelopeVerifier _verifier;
    private readonly ILicensingAuditSink _auditSink;

    public LicensingService(
        LicensingOptions options,
        ILocalLicenseStore store,
        ILicensingApiClient apiClient,
        ILicenseEnvelopeVerifier? verifier = null,
        ILicensingAuditSink? auditSink = null)
    {
        _options = options;
        _store = store;
        _apiClient = apiClient;
        _verifier = verifier ?? new Ed25519LicenseEnvelopeVerifier();
        _auditSink = auditSink ?? new NullLicensingAuditSink();
    }

    public async Task<LicensingStatus> GetStatusAsync(CancellationToken cancellationToken = default)
    {
        var installationId = await _store.GetOrCreateInstallationIdAsync(cancellationToken).ConfigureAwait(false);
        var envelope = await _store.LoadLicenseEnvelopeAsync(cancellationToken).ConfigureAwait(false);
        if (envelope is null)
        {
            return new LicensingStatus
            {
                State = LicenseState.Unlicensed,
                InstallationId = installationId,
                Message = "No license has been activated."
            };
        }

        var verified = _verifier.Verify(envelope, installationId, _options, CorrelationId.New());
        if (!verified.Succeeded || verified.Value is null)
        {
            return new LicensingStatus
            {
                State = LicenseState.Invalid,
                InstallationId = installationId,
                Message = string.Join(Environment.NewLine, verified.Errors.Select(error => error.Message))
            };
        }

        return StatusFromLicense(installationId, verified.Value, serverUnavailable: false);
    }

    public async Task<VerifiedLicense?> GetLicenseAsync(CancellationToken cancellationToken = default)
    {
        return (await GetStatusAsync(cancellationToken).ConfigureAwait(false)).License;
    }

    public async Task<bool> HasEntitlementAsync(string entitlementKey, CancellationToken cancellationToken = default)
    {
        return LicenseEntitlementEvaluator.HasBoolean(await GetLicenseAsync(cancellationToken).ConfigureAwait(false), entitlementKey);
    }

    public async Task<int?> GetNumericEntitlementAsync(string entitlementKey, CancellationToken cancellationToken = default)
    {
        return LicenseEntitlementEvaluator.GetNumeric(await GetLicenseAsync(cancellationToken).ConfigureAwait(false), entitlementKey);
    }

    public async Task<bool> IsWithinNumericLimitAsync(string entitlementKey, int currentUsage, CancellationToken cancellationToken = default)
    {
        return LicenseEntitlementEvaluator.IsWithinNumericLimit(
            await GetLicenseAsync(cancellationToken).ConfigureAwait(false),
            entitlementKey,
            currentUsage);
    }

    public async Task<OperationResult<LicensingStatus>> ActivateAsync(
        LicenseActivationRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        if (!LooksLikeActivationKey(request.ActivationKey))
        {
            return LicensingErrors.Failure<LicensingStatus>(
                correlationId,
                "Licensing.ActivationKeyFormat",
                "Enter a HILOP activation key in the expected HILOP-XXXX-XXXX-XXXX-XXXX format.");
        }

        var installationId = await _store.GetOrCreateInstallationIdAsync(cancellationToken).ConfigureAwait(false);
        var response = await _apiClient.ActivateAsync(installationId, request, correlationId, cancellationToken).ConfigureAwait(false);
        if ((!response.Succeeded || response.Value is null) && IsInstallationAssignedToAnotherLicense(response.Errors))
        {
            await _store.ClearInstallationCredentialAsync(cancellationToken).ConfigureAwait(false);
            await _store.ClearLicenseEnvelopeAsync(cancellationToken).ConfigureAwait(false);
            installationId = await _store.RotateInstallationIdAsync(cancellationToken).ConfigureAwait(false);
            _auditSink.Record("INSTALLATION_ID_ROTATED_FOR_LICENSE_SWITCH", new Dictionary<string, string> { ["installation_id"] = installationId });
            response = await _apiClient.ActivateAsync(installationId, request, correlationId, cancellationToken).ConfigureAwait(false);
        }

        if (!response.Succeeded || response.Value is null)
        {
            _auditSink.Record("LICENSE_ACTIVATION_FAILED", new Dictionary<string, string> { ["installation_id"] = installationId });
            return OperationResult<LicensingStatus>.Failure(correlationId, response.Errors, status: "Failed");
        }

        if (response.Value.License is null || string.IsNullOrWhiteSpace(response.Value.InstallationToken))
        {
            return LicensingErrors.Failure<LicensingStatus>(correlationId, "Licensing.ActivationMalformed", "The licensing service did not return a complete activation response.");
        }

        var verified = _verifier.Verify(response.Value.License, installationId, _options, correlationId);
        if (!verified.Succeeded || verified.Value is null)
        {
            return OperationResult<LicensingStatus>.Failure(correlationId, verified.Errors, status: "Invalid");
        }

        await _store.SaveInstallationCredentialAsync(response.Value.InstallationToken, cancellationToken).ConfigureAwait(false);
        await _store.SaveLicenseEnvelopeAsync(response.Value.License, cancellationToken).ConfigureAwait(false);
        _auditSink.Record("LICENSE_ACTIVATED", SafeMetadata(verified.Value));
        return OperationResult<LicensingStatus>.Success(StatusFromLicense(installationId, verified.Value, serverUnavailable: false), correlationId, status: verified.Value.State.ToString());
    }

    public async Task<OperationResult<LicensingStatus>> RefreshAsync(CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var installationId = await _store.GetOrCreateInstallationIdAsync(cancellationToken).ConfigureAwait(false);
        var credential = await _store.LoadInstallationCredentialAsync(cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(credential))
        {
            return LicensingErrors.Failure<LicensingStatus>(correlationId, "Licensing.CredentialMissing", "No installation credential is available. Activate HILOP first.");
        }

        var response = await _apiClient.RefreshAsync(
            credential,
            new LicenseRefreshRequest(Environment.MachineName, GetVersion()),
            correlationId,
            cancellationToken).ConfigureAwait(false);
        if (!response.Succeeded || response.Value is null)
        {
            return PreserveCachedStatusOnFailure(response, installationId, correlationId);
        }

        if (response.Value.License is null)
        {
            return LicensingErrors.Failure<LicensingStatus>(correlationId, "Licensing.RefreshMalformed", "The licensing service did not return a signed license.");
        }

        var verified = _verifier.Verify(response.Value.License, installationId, _options, correlationId);
        if (!verified.Succeeded || verified.Value is null)
        {
            _auditSink.Record("LICENSE_INVALID", new Dictionary<string, string> { ["installation_id"] = installationId });
            return OperationResult<LicensingStatus>.Failure(correlationId, verified.Errors, status: "Invalid");
        }

        await _store.SaveLicenseEnvelopeAsync(response.Value.License, cancellationToken).ConfigureAwait(false);
        _auditSink.Record("LICENSE_REFRESHED", SafeMetadata(verified.Value));
        return OperationResult<LicensingStatus>.Success(StatusFromLicense(installationId, verified.Value, serverUnavailable: false), correlationId, status: verified.Value.State.ToString());
    }

    public async Task<OperationResult<LicensingStatus>> DeactivateAsync(CorrelationId correlationId, CancellationToken cancellationToken = default)
    {
        var installationId = await _store.GetOrCreateInstallationIdAsync(cancellationToken).ConfigureAwait(false);
        var credential = await _store.LoadInstallationCredentialAsync(cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(credential))
        {
            await _store.ClearLicenseEnvelopeAsync(cancellationToken).ConfigureAwait(false);
            var newInstallationId = await _store.RotateInstallationIdAsync(cancellationToken).ConfigureAwait(false);
            _auditSink.Record("INSTALLATION_DEACTIVATED_LOCAL", new Dictionary<string, string> { ["installation_id"] = installationId, ["new_installation_id"] = newInstallationId });
            return OperationResult<LicensingStatus>.Success(
                UnlicensedStatus(newInstallationId, "No installation credential was available. Local cached license material has been removed."),
                correlationId,
                status: "Deactivated");
        }

        var result = await _apiClient.DeactivateAsync(credential, correlationId, cancellationToken).ConfigureAwait(false);
        if (!result.Succeeded)
        {
            return PreserveCachedStatusOnFailure(result, installationId, correlationId);
        }

        await _store.ClearInstallationCredentialAsync(cancellationToken).ConfigureAwait(false);
        await _store.ClearLicenseEnvelopeAsync(cancellationToken).ConfigureAwait(false);
        var rotatedInstallationId = await _store.RotateInstallationIdAsync(cancellationToken).ConfigureAwait(false);
        _auditSink.Record("INSTALLATION_DEACTIVATED", new Dictionary<string, string> { ["installation_id"] = installationId, ["new_installation_id"] = rotatedInstallationId });
        return OperationResult<LicensingStatus>.Success(
            UnlicensedStatus(rotatedInstallationId, "Installation deactivated. Existing configuration was preserved."),
            correlationId,
            status: "Deactivated");
    }

    private OperationResult<LicensingStatus> PreserveCachedStatusOnFailure<T>(
        OperationResult<T> failedResult,
        string installationId,
        CorrelationId correlationId)
    {
        var cached = GetStatusAsync().GetAwaiter().GetResult();
        var status = cached with
        {
            ServerUnavailable = true,
            Message = cached.License?.IsOperational == true
                ? "Licensing service is unavailable or rejected the request; continuing with the last verified cached license."
                : string.Join(Environment.NewLine, failedResult.Errors.Select(error => error.Message))
        };
        _auditSink.Record("LICENSE_REFRESH_FAILED", new Dictionary<string, string> { ["installation_id"] = installationId });

        return cached.License?.IsOperational == true
            ? OperationResult<LicensingStatus>.Success(status, correlationId, failedResult.Warnings, status: cached.State.ToString())
            : OperationResult<LicensingStatus>.Failure(correlationId, failedResult.Errors, status: "Failed");
    }

    private LicensingStatus StatusFromLicense(string installationId, VerifiedLicense license, bool serverUnavailable)
    {
        return new LicensingStatus
        {
            State = license.State,
            InstallationId = installationId,
            License = license,
            LastSuccessfulValidationUtc = license.ValidatedAtUtc,
            ServerUnavailable = serverUnavailable,
            Message = license.State switch
            {
                LicenseState.Trial => "Trial license is active.",
                LicenseState.Active => "License is active.",
                LicenseState.ExpiringSoon => "License is active and nearing expiration.",
                LicenseState.GracePeriod => "License is in grace period. Renew soon to avoid restricted mode.",
                LicenseState.Expired => "License is expired. HILOP is in restricted mode.",
                LicenseState.Revoked => "License is revoked. HILOP is in restricted mode.",
                LicenseState.Invalid => "License is invalid.",
                _ => "No active license."
            }
        };
    }

    private static LicensingStatus UnlicensedStatus(string installationId, string message)
    {
        return new LicensingStatus
        {
            State = LicenseState.Unlicensed,
            InstallationId = installationId,
            Message = message
        };
    }

    private static bool IsInstallationAssignedToAnotherLicense(IReadOnlyList<OperationError> errors)
    {
        return errors.Any(error =>
            ContainsAssignmentConflict(error.Code) ||
            ContainsAssignmentConflict(error.Message) ||
            ContainsAssignmentConflict(error.DiagnosticDetail));
    }

    private static bool ContainsAssignmentConflict(string? value)
    {
        return !string.IsNullOrWhiteSpace(value) &&
            value.Contains("installation", StringComparison.OrdinalIgnoreCase) &&
            value.Contains("assigned", StringComparison.OrdinalIgnoreCase) &&
            value.Contains("another license", StringComparison.OrdinalIgnoreCase);
    }

    private static bool LooksLikeActivationKey(string activationKey)
    {
        var value = activationKey.Trim().ToUpperInvariant();
        return value.StartsWith("HILOP-", StringComparison.Ordinal) && value.Length is >= 20 and <= 128;
    }

    private static IReadOnlyDictionary<string, string> SafeMetadata(VerifiedLicense license)
    {
        return new Dictionary<string, string>
        {
            ["license_id"] = license.Payload.LicenseId,
            ["license_number"] = license.Payload.LicenseNumber,
            ["installation_id"] = license.Payload.InstallationId,
            ["key_id"] = license.Envelope.KeyId,
            ["state"] = license.State.ToString()
        };
    }

    private static string GetVersion()
    {
        return typeof(LicensingService).Assembly.GetName().Version?.ToString() ?? "1.0";
    }
}

public sealed class LicensingRefreshLoop
{
    private readonly ILicensingService _licensingService;
    private readonly LicensingOptions _options;
    private readonly Random _random = new();

    public LicensingRefreshLoop(ILicensingService licensingService, LicensingOptions options)
    {
        _licensingService = licensingService;
        _options = options;
    }

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            var jitter = TimeSpan.FromMinutes(_random.Next(0, 60));
            await Task.Delay(_options.RefreshInterval + jitter, cancellationToken).ConfigureAwait(false);
            await _licensingService.RefreshAsync(CorrelationId.New(), cancellationToken).ConfigureAwait(false);
        }
    }
}
