using System.Collections.ObjectModel;

namespace HAP.Contracts;

public sealed record OperationResult<T>
{
    public required CorrelationId CorrelationId { get; init; }

    public required bool Succeeded { get; init; }

    public T? Value { get; init; }

    public IReadOnlyList<OperationWarning> Warnings { get; init; } = Array.Empty<OperationWarning>();

    public IReadOnlyList<OperationError> Errors { get; init; } = Array.Empty<OperationError>();

    public string? Status { get; init; }

    public static OperationResult<T> Success(
        T value,
        CorrelationId correlationId,
        IEnumerable<OperationWarning>? warnings = null,
        string? status = null)
    {
        return new OperationResult<T>
        {
            CorrelationId = correlationId,
            Succeeded = true,
            Value = value,
            Warnings = Freeze(warnings),
            Errors = Array.Empty<OperationError>(),
            Status = status
        };
    }

    public static OperationResult<T> Failure(
        CorrelationId correlationId,
        IEnumerable<OperationError> errors,
        IEnumerable<OperationWarning>? warnings = null,
        string? status = null)
    {
        var frozenErrors = Freeze(errors);
        if (frozenErrors.Count == 0)
        {
            throw new ArgumentException("A failed operation must include at least one error.", nameof(errors));
        }

        return new OperationResult<T>
        {
            CorrelationId = correlationId,
            Succeeded = false,
            Value = default,
            Warnings = Freeze(warnings),
            Errors = frozenErrors,
            Status = status
        };
    }

    private static ReadOnlyCollection<TItem> Freeze<TItem>(IEnumerable<TItem>? values)
    {
        return Array.AsReadOnly(values?.ToArray() ?? Array.Empty<TItem>());
    }
}
