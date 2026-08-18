using System.Text.Json;
using HILOP.Contracts;

namespace HILOP.Plugin.Protocol;

public sealed record HapPluginHandshakeRequest
{
    public string ProtocolVersion { get; init; } = HapPluginProtocol.Version;

    public HapPluginMessageKind Kind { get; init; } = HapPluginMessageKind.HandshakeRequest;

    public required CorrelationId CorrelationId { get; init; }

    public required string ClientName { get; init; }

    public required string ProviderId { get; init; }

    public required string ManifestPath { get; init; }
}

public sealed record HapPluginHandshakeResponse
{
    public string ProtocolVersion { get; init; } = HapPluginProtocol.Version;

    public HapPluginMessageKind Kind { get; init; } = HapPluginMessageKind.HandshakeResponse;

    public required CorrelationId CorrelationId { get; init; }

    public required bool Accepted { get; init; }

    public required string HostName { get; init; }

    public required string HostVersion { get; init; }

    public string ProviderId { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;
}

public sealed record HapPluginProviderMetadata
{
    public required string ProviderId { get; init; }

    public required string DisplayName { get; init; }

    public required string Publisher { get; init; }

    public required string ProviderVersion { get; init; }

    public IReadOnlyList<string> CapabilityIds { get; init; } = Array.Empty<string>();
}

public sealed record HapPluginProviderRequest
{
    public string ProtocolVersion { get; init; } = HapPluginProtocol.Version;

    public required HapPluginMessageKind Kind { get; init; }

    public required CorrelationId CorrelationId { get; init; }

    public required string ProviderId { get; init; }
}

public sealed record HapPluginMetadataResponse
{
    public string ProtocolVersion { get; init; } = HapPluginProtocol.Version;

    public HapPluginMessageKind Kind { get; init; } = HapPluginMessageKind.MetadataResponse;

    public required CorrelationId CorrelationId { get; init; }

    public required bool Succeeded { get; init; }

    public HapPluginProviderMetadata? Metadata { get; init; }

    public IReadOnlyList<OperationError> Errors { get; init; } = Array.Empty<OperationError>();
}

public sealed record HapPluginHealthResponse
{
    public string ProtocolVersion { get; init; } = HapPluginProtocol.Version;

    public HapPluginMessageKind Kind { get; init; } = HapPluginMessageKind.HealthResponse;

    public required CorrelationId CorrelationId { get; init; }

    public required bool Succeeded { get; init; }

    public string Status { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;

    public IReadOnlyList<OperationError> Errors { get; init; } = Array.Empty<OperationError>();
}

public sealed record HapPluginOperationRequest
{
    public string ProtocolVersion { get; init; } = HapPluginProtocol.Version;

    public HapPluginMessageKind Kind { get; init; } = HapPluginMessageKind.OperationRequest;

    public required CorrelationId CorrelationId { get; init; }

    public required string ProviderId { get; init; }

    public required string CapabilityId { get; init; }

    public required string Operation { get; init; }

    public int TimeoutMilliseconds { get; init; } = 30000;

    public JsonElement? Payload { get; init; }
}

public sealed record HapPluginOperationResponse
{
    public string ProtocolVersion { get; init; } = HapPluginProtocol.Version;

    public HapPluginMessageKind Kind { get; init; } = HapPluginMessageKind.OperationResponse;

    public required CorrelationId CorrelationId { get; init; }

    public required string ProviderId { get; init; }

    public required string CapabilityId { get; init; }

    public required string Operation { get; init; }

    public required bool Succeeded { get; init; }

    public string Status { get; init; } = string.Empty;

    public JsonElement? Data { get; init; }

    public IReadOnlyList<OperationWarning> Warnings { get; init; } = Array.Empty<OperationWarning>();

    public IReadOnlyList<OperationError> Errors { get; init; } = Array.Empty<OperationError>();
}

public sealed record HapPluginProgress
{
    public string ProtocolVersion { get; init; } = HapPluginProtocol.Version;

    public HapPluginMessageKind Kind { get; init; } = HapPluginMessageKind.Progress;

    public required CorrelationId CorrelationId { get; init; }

    public required string Message { get; init; }

    public int? PercentComplete { get; init; }
}

public sealed record HapPluginCancellationRequest
{
    public string ProtocolVersion { get; init; } = HapPluginProtocol.Version;

    public HapPluginMessageKind Kind { get; init; } = HapPluginMessageKind.CancellationRequest;

    public required CorrelationId CorrelationId { get; init; }

    public required string Reason { get; init; }
}

public sealed record HapPluginShutdownRequest
{
    public string ProtocolVersion { get; init; } = HapPluginProtocol.Version;

    public HapPluginMessageKind Kind { get; init; } = HapPluginMessageKind.ShutdownRequest;

    public required CorrelationId CorrelationId { get; init; }
}

public sealed record HapPluginAcknowledgement
{
    public string ProtocolVersion { get; init; } = HapPluginProtocol.Version;

    public required HapPluginMessageKind Kind { get; init; }

    public required CorrelationId CorrelationId { get; init; }

    public required bool Accepted { get; init; }

    public string Message { get; init; } = string.Empty;
}
