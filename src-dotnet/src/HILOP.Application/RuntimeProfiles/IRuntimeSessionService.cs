using HILOP.Contracts;

namespace HILOP.Application.RuntimeProfiles;

public interface IRuntimeSessionService
{
    Task<OperationResult<RuntimeSessionSummary>> StartAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);

    Task<OperationResult<bool>> ShutdownAsync(
        string repositoryRoot,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);
}
