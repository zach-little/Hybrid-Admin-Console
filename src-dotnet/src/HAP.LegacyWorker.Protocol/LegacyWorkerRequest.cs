using System.Text.Json;
using HAP.Contracts;

namespace HAP.LegacyWorker.Protocol;

public sealed record LegacyWorkerRequest
{
    public string ProtocolVersion { get; init; } = LegacyWorkerProtocol.Version;

    public LegacyWorkerMessageKind Kind { get; init; } = LegacyWorkerMessageKind.OperationRequest;

    public required CorrelationId CorrelationId { get; init; }

    public required string Operation { get; init; }

    public int TimeoutMilliseconds { get; init; } = 30000;

    public string CancellationId { get; init; } = string.Empty;

    public LegacyPowerShellEdition PreferredEdition { get; init; } = LegacyPowerShellEdition.PowerShell7;

    public JsonElement? Payload { get; init; }

    public static LegacyWorkerRequest Create<TPayload>(
        CorrelationId correlationId,
        string operation,
        TPayload payload,
        int timeoutMilliseconds = 30000,
        string cancellationId = "",
        LegacyPowerShellEdition preferredEdition = LegacyPowerShellEdition.PowerShell7)
    {
        if (string.IsNullOrWhiteSpace(operation))
        {
            throw new ArgumentException("Operation cannot be empty.", nameof(operation));
        }

        if (timeoutMilliseconds <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(timeoutMilliseconds), "Timeout must be greater than zero.");
        }

        return new LegacyWorkerRequest
        {
            CorrelationId = correlationId,
            Operation = operation.Trim(),
            TimeoutMilliseconds = timeoutMilliseconds,
            CancellationId = cancellationId,
            PreferredEdition = preferredEdition,
            Payload = JsonSerializer.SerializeToElement(payload, LegacyWorkerProtocol.JsonOptions)
        };
    }
}
