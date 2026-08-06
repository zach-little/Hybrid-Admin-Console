namespace HAP.LegacyWorker.Protocol;

public sealed record LegacyRuntimeSessionRequest
{
    public required string RepositoryRoot { get; init; }

    public string ProfileName { get; init; } = "Simulation";

    public string ProfilePath { get; init; } = string.Empty;
}
