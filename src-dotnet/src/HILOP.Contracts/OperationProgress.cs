namespace HILOP.Contracts;

public sealed record OperationProgress(
    CorrelationId CorrelationId,
    string Stage,
    string Message,
    int? PercentComplete = null)
{
    public static OperationProgress Create(
        CorrelationId correlationId,
        string stage,
        string message,
        int? percentComplete = null)
    {
        if (string.IsNullOrWhiteSpace(stage))
        {
            throw new ArgumentException("Progress stage cannot be empty.", nameof(stage));
        }

        if (string.IsNullOrWhiteSpace(message))
        {
            throw new ArgumentException("Progress message cannot be empty.", nameof(message));
        }

        if (percentComplete is < 0 or > 100)
        {
            throw new ArgumentOutOfRangeException(nameof(percentComplete), "Progress percentage must be between 0 and 100.");
        }

        return new OperationProgress(correlationId, stage.Trim(), message.Trim(), percentComplete);
    }
}
