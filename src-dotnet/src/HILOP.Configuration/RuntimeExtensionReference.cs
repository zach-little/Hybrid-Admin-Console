namespace HILOP.Configuration;

public sealed record RuntimeExtensionReference
{
    public string ProviderInstanceId { get; init; } = string.Empty;

    public string ProviderId { get; init; } = string.Empty;

    public bool Required { get; init; }

    public IReadOnlyList<string> RequestedCapabilities { get; init; } = Array.Empty<string>();
}
