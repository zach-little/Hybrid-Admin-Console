using HAP.Application.RuntimeProfiles;
using HAP.Contracts;
using HAP.LegacyWorker.Protocol;

namespace HAP.Providers.LegacyPowerShell;

public sealed class LegacyRuntimeProfileCatalogService : IRuntimeProfileCatalogService
{
    private readonly ILegacyPowerShellWorkerClient _workerClient;

    public LegacyRuntimeProfileCatalogService(ILegacyPowerShellWorkerClient workerClient)
    {
        _workerClient = workerClient ?? throw new ArgumentNullException(nameof(workerClient));
    }

    public async Task<OperationResult<IReadOnlyList<RuntimeProfileSummary>>> GetRuntimeProfilesAsync(
        string repositoryRoot,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var result = await _workerClient.GetRuntimeProfilesAsync(repositoryRoot, correlationId, cancellationToken).ConfigureAwait(false);
        if (!result.Succeeded || result.Value is null)
        {
            return OperationResult<IReadOnlyList<RuntimeProfileSummary>>.Failure(
                result.CorrelationId,
                result.Errors,
                result.Warnings,
                result.Status);
        }

        var profiles = result.Value.Profiles.Select(MapProfile).ToArray();
        return OperationResult<IReadOnlyList<RuntimeProfileSummary>>.Success(
            profiles,
            result.CorrelationId,
            result.Warnings,
            result.Status);
    }

    private static RuntimeProfileSummary MapProfile(LegacyRuntimeProfileSummary profile)
    {
        return new RuntimeProfileSummary
        {
            Name = FirstNonEmpty(profile.Name, profile.ProfileName, profile.FolderName),
            DisplayName = FirstNonEmpty(profile.ProfileName, profile.Name, profile.FolderName),
            RuntimeMode = profile.RuntimeMode,
            CloudEnvironment = profile.CloudEnvironment,
            Organization = profile.Organization,
            Environment = profile.Environment,
            IsValid = profile.IsValid,
            IsDefault = profile.IsDefault,
            IsLastUsed = profile.IsLastUsed,
            EnabledProviders = profile.EnabledProviders,
            Warnings = profile.Warnings,
            ErrorMessage = profile.ErrorMessage,
            HealthLabel = profile.HealthLabel,
            BadgeText = profile.BadgeText
        };
    }

    private static string FirstNonEmpty(params string[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;
    }
}
