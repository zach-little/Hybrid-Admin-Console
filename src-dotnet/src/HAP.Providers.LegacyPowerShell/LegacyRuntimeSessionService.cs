using HAP.Application.RuntimeProfiles;
using HAP.Contracts;
using HAP.LegacyWorker.Protocol;

namespace HAP.Providers.LegacyPowerShell;

public sealed class LegacyRuntimeSessionService : IRuntimeSessionService
{
    private readonly ILegacyPowerShellWorkerClient _workerClient;

    public LegacyRuntimeSessionService(ILegacyPowerShellWorkerClient workerClient)
    {
        _workerClient = workerClient ?? throw new ArgumentNullException(nameof(workerClient));
    }

    public async Task<OperationResult<RuntimeSessionSummary>> StartAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var result = await _workerClient.StartRuntimeSessionAsync(repositoryRoot, profileName, correlationId, cancellationToken)
            .ConfigureAwait(false);
        if (!result.Succeeded || result.Value is null)
        {
            return OperationResult<RuntimeSessionSummary>.Failure(
                result.CorrelationId,
                result.Errors,
                result.Warnings,
                result.Status);
        }

        return OperationResult<RuntimeSessionSummary>.Success(
            MapSession(result.Value),
            result.CorrelationId,
            result.Warnings,
            result.Status);
    }

    public async Task<OperationResult<bool>> ShutdownAsync(
        string repositoryRoot,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var result = await _workerClient.StopRuntimeSessionAsync(repositoryRoot, correlationId, cancellationToken)
            .ConfigureAwait(false);
        if (!result.Succeeded || result.Value is null)
        {
            return OperationResult<bool>.Failure(result.CorrelationId, result.Errors, result.Warnings, result.Status);
        }

        return OperationResult<bool>.Success(result.Value.Shutdown, result.CorrelationId, result.Warnings, result.Status);
    }

    private static RuntimeSessionSummary MapSession(LegacyRuntimeSessionResult result)
    {
        return new RuntimeSessionSummary
        {
            ProfileName = result.ProfileName,
            RuntimeMode = result.RuntimeMode,
            CloudEnvironment = result.CloudEnvironment,
            OverallStatus = result.OverallStatus,
            DurationMs = result.DurationMs,
            HasErrors = result.HasErrors,
            HasWarnings = result.HasWarnings,
            ProviderHealth = result.ProviderHealth.Select(MapProviderHealth).ToArray()
        };
    }

    private static ProviderHealthSummary MapProviderHealth(LegacyProviderHealthSummary health)
    {
        return new ProviderHealthSummary
        {
            Name = health.Name,
            Mode = health.Mode,
            Enabled = health.Enabled,
            Required = health.Required,
            Status = health.Status,
            Message = health.Message,
            Available = health.Available,
            Connected = health.Connected,
            LastError = health.LastError
        };
    }
}
