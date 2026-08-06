using System.Text.Json;
using HAP.Contracts;

namespace HAP.LegacyWorker.Protocol;

public sealed record LegacyWorkerResponse
{
    public string ProtocolVersion { get; init; } = LegacyWorkerProtocol.Version;

    public LegacyWorkerMessageKind Kind { get; init; } = LegacyWorkerMessageKind.OperationResponse;

    public required CorrelationId CorrelationId { get; init; }

    public required string Operation { get; init; }

    public bool Succeeded { get; init; }

    public string Status { get; init; } = string.Empty;

    public JsonElement? Data { get; init; }

    public IReadOnlyList<OperationWarning> Warnings { get; init; } = Array.Empty<OperationWarning>();

    public IReadOnlyList<OperationError> Errors { get; init; } = Array.Empty<OperationError>();

    public IReadOnlyList<LegacyWorkerStreamRecord> Streams { get; init; } = Array.Empty<LegacyWorkerStreamRecord>();

    public static LegacyWorkerResponse Success<TData>(
        CorrelationId correlationId,
        string operation,
        TData data,
        IEnumerable<OperationWarning>? warnings = null,
        IEnumerable<LegacyWorkerStreamRecord>? streams = null,
        string status = "Completed")
    {
        RequireOperation(operation);
        return new LegacyWorkerResponse
        {
            CorrelationId = correlationId,
            Operation = operation.Trim(),
            Succeeded = true,
            Status = status,
            Data = JsonSerializer.SerializeToElement(data, LegacyWorkerProtocol.JsonOptions),
            Warnings = Array.AsReadOnly(warnings?.ToArray() ?? Array.Empty<OperationWarning>()),
            Errors = Array.Empty<OperationError>(),
            Streams = Array.AsReadOnly(streams?.ToArray() ?? Array.Empty<LegacyWorkerStreamRecord>())
        };
    }

    public static LegacyWorkerResponse Failure(
        CorrelationId correlationId,
        string operation,
        IEnumerable<OperationError> errors,
        IEnumerable<OperationWarning>? warnings = null,
        IEnumerable<LegacyWorkerStreamRecord>? streams = null,
        string status = "Failed")
    {
        RequireOperation(operation);
        var errorList = errors.ToArray();
        if (errorList.Length == 0)
        {
            throw new ArgumentException("Failed worker responses require at least one error.", nameof(errors));
        }

        return new LegacyWorkerResponse
        {
            CorrelationId = correlationId,
            Operation = operation.Trim(),
            Succeeded = false,
            Status = status,
            Warnings = Array.AsReadOnly(warnings?.ToArray() ?? Array.Empty<OperationWarning>()),
            Errors = Array.AsReadOnly(errorList),
            Streams = Array.AsReadOnly(streams?.ToArray() ?? Array.Empty<LegacyWorkerStreamRecord>())
        };
    }

    private static void RequireOperation(string operation)
    {
        if (string.IsNullOrWhiteSpace(operation))
        {
            throw new ArgumentException("Operation cannot be empty.", nameof(operation));
        }
    }
}
