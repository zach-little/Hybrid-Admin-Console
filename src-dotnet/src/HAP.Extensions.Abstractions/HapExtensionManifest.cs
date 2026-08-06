using System.Text.Json;

namespace HAP.Extensions.Abstractions;

public sealed record HapExtensionManifest
{
    public string ManifestVersion { get; init; } = "1.0";

    public string ProviderId { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string Publisher { get; init; } = string.Empty;

    public string ProviderVersion { get; init; } = string.Empty;

    public string ApiVersion { get; init; } = ExtensionApiVersion.Current.ToString();

    public HapProviderImplementationKind Implementation { get; init; } = HapProviderImplementationKind.NativeDotNet;

    public HapExtensionEntryPoint EntryPoint { get; init; } = new();

    public IReadOnlyList<HapExtensionCapabilityDeclaration> Capabilities { get; init; } = Array.Empty<HapExtensionCapabilityDeclaration>();

    public IReadOnlyList<string> RequiredPermissions { get; init; } = Array.Empty<string>();

    public JsonElement? ConfigurationSchema { get; init; }
}

public enum HapProviderImplementationKind
{
    NativeDotNet = 0,
    PowerShell = 1
}

public sealed record HapExtensionEntryPoint
{
    public string AssemblyPath { get; init; } = string.Empty;

    public string TypeName { get; init; } = string.Empty;

    public string ModulePath { get; init; } = string.Empty;

    public string RequiredPowerShellEdition { get; init; } = string.Empty;

    public string MinimumPowerShellVersion { get; init; } = string.Empty;
}

public sealed record HapExtensionCapabilityDeclaration
{
    public string Id { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public IReadOnlyList<string> Operations { get; init; } = Array.Empty<string>();
}
