using HILOP.Contracts;

namespace HILOP.Configuration;

public sealed record ConfigurationValidationResult
{
    public bool IsValid => Errors.Count == 0;

    public IReadOnlyList<OperationError> Errors { get; init; } = Array.Empty<OperationError>();

    public IReadOnlyList<OperationWarning> Warnings { get; init; } = Array.Empty<OperationWarning>();

    public static ConfigurationValidationResult From(
        IEnumerable<OperationError>? errors = null,
        IEnumerable<OperationWarning>? warnings = null)
    {
        return new ConfigurationValidationResult
        {
            Errors = Array.AsReadOnly(errors?.ToArray() ?? Array.Empty<OperationError>()),
            Warnings = Array.AsReadOnly(warnings?.ToArray() ?? Array.Empty<OperationWarning>())
        };
    }
}
