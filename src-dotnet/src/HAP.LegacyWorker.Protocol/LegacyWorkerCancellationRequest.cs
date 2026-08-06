using HAP.Contracts;

namespace HAP.LegacyWorker.Protocol;

public sealed record LegacyWorkerCancellationRequest
{
    public string ProtocolVersion { get; init; } = LegacyWorkerProtocol.Version;

    public LegacyWorkerMessageKind Kind { get; init; } = LegacyWorkerMessageKind.CancellationRequest;

    public required CorrelationId CorrelationId { get; init; }

    public required string CancellationId { get; init; }

    public string Reason { get; init; } = string.Empty;
}
