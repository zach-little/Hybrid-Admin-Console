using HAP.Contracts;

namespace HAP.Application.RuntimeProfiles;

public interface IRuntimeProfileCatalogService
{
    Task<OperationResult<IReadOnlyList<RuntimeProfileSummary>>> GetRuntimeProfilesAsync(
        string repositoryRoot,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);
}
