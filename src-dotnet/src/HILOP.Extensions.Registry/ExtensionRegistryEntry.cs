using HILOP.Extensions.Abstractions;

namespace HILOP.Extensions.Registry;

public sealed record ExtensionRegistryEntry
{
    public required HapExtensionManifest Manifest { get; init; }

    public required string ManifestPath { get; init; }

    public required string ManifestSha256 { get; init; }

    public required HapExtensionSignatureState SignatureState { get; init; }

    public required bool Enabled { get; init; }

    public IReadOnlyList<string> GrantedCapabilities { get; init; } = Array.Empty<string>();
}
