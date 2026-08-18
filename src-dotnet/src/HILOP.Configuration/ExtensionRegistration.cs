using HILOP.Contracts;

namespace HILOP.Configuration;

public sealed record ExtensionRegistration
{
    public string ProviderId { get; init; } = string.Empty;

    public string ProviderInstanceId { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string Publisher { get; init; } = string.Empty;

    public string Version { get; init; } = string.Empty;

    public string HapApiVersion { get; init; } = string.Empty;

    public ProviderImplementationKind ImplementationKind { get; init; } = ProviderImplementationKind.PowerShellExtension;

    public string InstallationPath { get; init; } = string.Empty;

    public string EntryModule { get; init; } = string.Empty;

    public bool Enabled { get; init; }

    public bool Approved { get; init; }

    public IReadOnlyList<string> ApprovedCapabilities { get; init; } = Array.Empty<string>();

    public IReadOnlyList<string> DeniedCapabilities { get; init; } = Array.Empty<string>();

    public string ConfigurationInstanceId { get; init; } = string.Empty;

    public IReadOnlyDictionary<string, string> FileHashes { get; init; } =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

    public string SignatureState { get; init; } = string.Empty;

    public string SigningIdentity { get; init; } = string.Empty;
}
