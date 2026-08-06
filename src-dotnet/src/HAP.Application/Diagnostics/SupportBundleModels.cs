namespace HAP.Application.Diagnostics;

public sealed record SupportBundleRequest
{
    public string ProductVersion { get; init; } = string.Empty;

    public IReadOnlyDictionary<string, string> ConfigurationValues { get; init; } = new Dictionary<string, string>();

    public IReadOnlyList<string> RecentEvents { get; init; } = Array.Empty<string>();

    public IReadOnlyList<string> CapabilityDispositions { get; init; } = Array.Empty<string>();
}

public sealed record SupportBundle
{
    public string SchemaVersion { get; init; } = "1.0";

    public string ProductVersion { get; init; } = string.Empty;

    public DateTimeOffset CreatedUtc { get; init; }

    public IReadOnlyDictionary<string, string> ConfigurationValues { get; init; } = new Dictionary<string, string>();

    public IReadOnlyList<string> RecentEvents { get; init; } = Array.Empty<string>();

    public IReadOnlyList<string> CapabilityDispositions { get; init; } = Array.Empty<string>();
}
