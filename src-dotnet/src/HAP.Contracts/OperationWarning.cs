namespace HAP.Contracts;

public sealed record OperationWarning(
    string Code,
    string Message,
    string? Target = null)
{
    public static OperationWarning Create(string code, string message, string? target = null)
    {
        if (string.IsNullOrWhiteSpace(code))
        {
            throw new ArgumentException("Warning code cannot be empty.", nameof(code));
        }

        if (string.IsNullOrWhiteSpace(message))
        {
            throw new ArgumentException("Warning message cannot be empty.", nameof(message));
        }

        return new OperationWarning(code.Trim(), message.Trim(), target);
    }
}
