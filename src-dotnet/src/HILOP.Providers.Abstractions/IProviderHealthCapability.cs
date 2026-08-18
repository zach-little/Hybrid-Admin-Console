using HILOP.Contracts;

namespace HILOP.Providers.Abstractions;

public interface IProviderHealthCapability
{
    Task<OperationResult<ProviderHealthResult>> GetHealthAsync(
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);
}
