using HAP.Contracts;

namespace HAP.Providers.Abstractions;

public interface IProviderHealthCapability
{
    Task<OperationResult<ProviderHealthResult>> GetHealthAsync(
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);
}
