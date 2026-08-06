namespace HAP.Providers.Abstractions;

public sealed record ProviderHealthResult
{
    public string ProviderId { get; init; } = string.Empty;

    public string Mode { get; init; } = string.Empty;

    public bool Enabled { get; init; }

    public bool Required { get; init; }

    public string Status { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;

    public bool Available { get; init; }

    public bool Connected { get; init; }

    public string LastError { get; init; } = string.Empty;
}
