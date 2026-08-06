namespace HAP.LegacyWorker.Protocol;

public sealed record LegacyRuntimeProfilesRequest
{
    public required string RepositoryRoot { get; init; }
}
