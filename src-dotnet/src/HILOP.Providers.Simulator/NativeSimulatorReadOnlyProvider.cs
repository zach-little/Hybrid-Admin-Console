using HILOP.Application.ProviderRouting;
using HILOP.Contracts;
using HILOP.Providers.Abstractions;

namespace HILOP.Providers.Simulator;

public sealed class NativeSimulatorReadOnlyProvider : ISimulatorReadOnlyProvider
{
    private readonly DirectorySimulatorProvider _provider;

    public NativeSimulatorReadOnlyProvider(DirectorySimulatorProvider provider)
    {
        _provider = provider ?? throw new ArgumentNullException(nameof(provider));
    }

    public string ProviderId => "DirectorySimulator";

    public string Implementation => ProviderRoutingConstants.NativeDotNet;

    public bool LaunchesPowerShellProcess => false;

    public Task<OperationResult<ProviderHealthResult>> GetHealthAsync(
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        return _provider.GetHealthAsync(correlationId, cancellationToken);
    }

    public Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> SearchUsersAsync(
        string query,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        return _provider.SearchUsersAsync(query, correlationId, cancellationToken);
    }
}
