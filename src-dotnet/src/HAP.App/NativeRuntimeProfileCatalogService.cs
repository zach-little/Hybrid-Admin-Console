using HAP.Application.RuntimeProfiles;
using HAP.Contracts;

namespace HAP.App;

internal sealed class NativeRuntimeProfileCatalogService : IRuntimeProfileCatalogService
{
    public Task<OperationResult<IReadOnlyList<RuntimeProfileSummary>>> GetRuntimeProfilesAsync(
        string repositoryRoot,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        _ = repositoryRoot;
        _ = cancellationToken;
        IReadOnlyList<RuntimeProfileSummary> profiles = new[]
        {
            new RuntimeProfileSummary
            {
                Name = "NativeSimulation",
                DisplayName = "Native Simulation",
                RuntimeMode = "Simulation",
                CloudEnvironment = "Simulated",
                Organization = "HAP",
                Environment = "Migration",
                IsValid = true,
                IsDefault = true,
                EnabledProviders = new[]
                {
                    "DirectorySimulator",
                    "MicrosoftGraph",
                    "ActiveDirectory",
                    "ExchangeOnline",
                    "ExchangeOnPremises"
                },
                HealthLabel = "Ready",
                BadgeText = "Native"
            }
        };

        return Task.FromResult(OperationResult<IReadOnlyList<RuntimeProfileSummary>>.Success(
            profiles,
            correlationId,
            status: "Completed"));
    }
}
