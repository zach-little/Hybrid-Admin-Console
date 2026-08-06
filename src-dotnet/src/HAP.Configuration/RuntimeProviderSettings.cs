using HAP.Contracts;

namespace HAP.Configuration;

public sealed record RuntimeProviderSettings
{
    public string Name { get; init; } = string.Empty;

    public bool Enabled { get; init; }

    public ProviderMode Mode { get; init; } = ProviderMode.Disabled;

    public bool Required { get; init; }

    public string Authentication { get; init; } = string.Empty;

    public string Server { get; init; } = string.Empty;

    public string ConnectionUri { get; init; } = string.Empty;

    public ProviderImplementationKind ImplementationKind { get; init; } = ProviderImplementationKind.Native;

    public string ExtensionInstanceId { get; init; } = string.Empty;

    public IReadOnlyList<string> RequestedCapabilities { get; init; } = Array.Empty<string>();
}
