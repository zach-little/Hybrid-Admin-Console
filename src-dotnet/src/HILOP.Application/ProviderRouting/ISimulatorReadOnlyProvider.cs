using HILOP.Contracts;
using HILOP.Providers.Abstractions;

namespace HILOP.Application.ProviderRouting;

public interface ISimulatorReadOnlyProvider
{
    string ProviderId { get; }

    string Implementation { get; }

    bool LaunchesPowerShellProcess { get; }

    Task<OperationResult<ProviderHealthResult>> GetHealthAsync(
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);

    Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> SearchUsersAsync(
        string query,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);
}
