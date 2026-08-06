namespace HAP.Contracts;

public sealed record ProviderDescriptor
{
    public required string ProviderId { get; init; }

    public required string DisplayName { get; init; }

    public required string Publisher { get; init; }

    public required string Version { get; init; }

    public required string HapApiVersion { get; init; }

    public required ProviderImplementationKind ImplementationKind { get; init; }

    public IReadOnlyList<ProviderCapability> Capabilities { get; init; } = Array.Empty<ProviderCapability>();

    public static ProviderDescriptor Create(
        string providerId,
        string displayName,
        string publisher,
        string version,
        string hapApiVersion,
        ProviderImplementationKind implementationKind,
        IEnumerable<ProviderCapability>? capabilities = null)
    {
        RequireValue(providerId, nameof(providerId));
        RequireValue(displayName, nameof(displayName));
        RequireValue(publisher, nameof(publisher));
        RequireValue(version, nameof(version));
        RequireValue(hapApiVersion, nameof(hapApiVersion));

        return new ProviderDescriptor
        {
            ProviderId = providerId.Trim(),
            DisplayName = displayName.Trim(),
            Publisher = publisher.Trim(),
            Version = version.Trim(),
            HapApiVersion = hapApiVersion.Trim(),
            ImplementationKind = implementationKind,
            Capabilities = Array.AsReadOnly(capabilities?.ToArray() ?? Array.Empty<ProviderCapability>())
        };
    }

    private static void RequireValue(string value, string parameterName)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException("Provider descriptor fields cannot be empty.", parameterName);
        }
    }
}
