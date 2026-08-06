using System.Text.Json;
using HAP.Contracts;
using HAP.Plugin.Protocol;

namespace HAP.Extensions.PowerShell;

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
