using System.Text.Json;
using HILOP.Contracts;
using HILOP.Plugin.Protocol;

namespace HILOP.Extensions.PowerShell;

public interface IPowerShellProviderProxy
{
    Task<OperationResult<HapPluginProviderMetadata>> GetMetadataAsync(CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<HapPluginHealthResponse>> TestConnectionAsync(CorrelationId correlationId, CancellationToken cancellationToken = default);

    Task<OperationResult<JsonElement>> InvokeOperationAsync(
        string capabilityId,
        string operation,
        JsonElement payload,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);
}
