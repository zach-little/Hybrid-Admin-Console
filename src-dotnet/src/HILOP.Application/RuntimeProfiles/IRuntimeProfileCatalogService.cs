using HILOP.Contracts;

namespace HILOP.Application.RuntimeProfiles;

public interface IRuntimeProfileCatalogService
{
    Task<OperationResult<IReadOnlyList<RuntimeProfileSummary>>> GetRuntimeProfilesAsync(
        string repositoryRoot,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);
}
