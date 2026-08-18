namespace HILOP.Contracts;

public sealed record OperationError(
    string Code,
    string Message,
    string? Target = null,
    string? DiagnosticDetail = null)
{
    public static OperationError Create(
        string code,
        string message,
        string? target = null,
        string? diagnosticDetail = null)
    {
        if (string.IsNullOrWhiteSpace(code))
        {
            throw new ArgumentException("Error code cannot be empty.", nameof(code));
        }

        if (string.IsNullOrWhiteSpace(message))
        {
            throw new ArgumentException("Error message cannot be empty.", nameof(message));
        }

        return new OperationError(code.Trim(), message.Trim(), target, diagnosticDetail);
    }
}
