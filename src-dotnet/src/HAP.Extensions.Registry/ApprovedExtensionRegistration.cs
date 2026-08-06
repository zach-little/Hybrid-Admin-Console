namespace HAP.Extensions.Registry;

public sealed record ApprovedExtensionRegistration
{
    public required string ManifestPath { get; init; }

    public required string ApprovedSha256 { get; init; }

    public bool Enabled { get; init; }

    public HapExtensionSignatureState SignatureState { get; init; } = HapExtensionSignatureState.Unknown;

    public IReadOnlyList<string> GrantedCapabilities { get; init; } = Array.Empty<string>();
}

public enum HapExtensionSignatureState
{
    Unknown = 0,
    NotSigned = 1,
    Trusted = 2,
    Untrusted = 3
}
