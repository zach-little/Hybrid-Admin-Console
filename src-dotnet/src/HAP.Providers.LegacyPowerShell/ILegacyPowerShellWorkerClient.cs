using HAP.Contracts;
using HAP.LegacyWorker.Protocol;

namespace HAP.Providers.LegacyPowerShell;

public interface ILegacyPowerShellWorkerClient
{
    Task<OperationResult<LegacyRuntimeProfilesResult>> GetRuntimeProfilesAsync(
        string repositoryRoot,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);

    Task<OperationResult<LegacyRuntimeSessionResult>> StartRuntimeSessionAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);

    Task<OperationResult<LegacyRuntimeShutdownResult>> StopRuntimeSessionAsync(
        string repositoryRoot,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);
}
