using HILOP.Contracts;

namespace HILOP.Providers.Abstractions;

public interface IUserLookupCapability
{
    Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> SearchUsersAsync(
        string query,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);
}
