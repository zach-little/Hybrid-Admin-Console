namespace HAP.LegacyWorker.Protocol;

public sealed record LegacyWorkerStreamRecord(
    LegacyWorkerStreamKind Stream,
    string Message,
    DateTimeOffset Timestamp)
{
    public static LegacyWorkerStreamRecord Create(LegacyWorkerStreamKind stream, string message)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            throw new ArgumentException("Stream message cannot be empty.", nameof(message));
        }

        return new LegacyWorkerStreamRecord(stream, message.Trim(), DateTimeOffset.UtcNow);
    }
}
