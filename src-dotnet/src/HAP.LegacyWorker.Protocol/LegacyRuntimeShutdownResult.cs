namespace HAP.LegacyWorker.Protocol;

public sealed record LegacyRuntimeShutdownResult
{
    public bool Shutdown { get; init; }

    public string RepositoryRoot { get; init; } = string.Empty;
}
