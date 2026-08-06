namespace HAP.LegacyWorker.Protocol;

public sealed record LegacyRuntimeSessionResult
{
    public string ProfileName { get; init; } = string.Empty;

    public string RuntimeMode { get; init; } = string.Empty;

    public string CloudEnvironment { get; init; } = string.Empty;

    public string InitializedUtc { get; init; } = string.Empty;

    public int DurationMs { get; init; }

    public string OverallStatus { get; init; } = string.Empty;

    public bool HasErrors { get; init; }

    public bool HasWarnings { get; init; }

    public IReadOnlyList<LegacyProviderHealthSummary> ProviderHealth { get; init; } = Array.Empty<LegacyProviderHealthSummary>();
}

public sealed record LegacyProviderHealthSummary
{
    public string Name { get; init; } = string.Empty;

    public string Mode { get; init; } = string.Empty;

    public bool Enabled { get; init; }

    public bool Required { get; init; }

    public string Status { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;

    public bool Available { get; init; }

    public bool Connected { get; init; }

    public string LastError { get; init; } = string.Empty;
}
