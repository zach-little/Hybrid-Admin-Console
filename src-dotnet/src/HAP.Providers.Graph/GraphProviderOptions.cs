namespace HAP.Providers.Graph;

public sealed record GraphProviderOptions
{
    public string TenantId { get; init; } = string.Empty;

    public string ClientId { get; init; } = string.Empty;

    public string ClientSecret { get; init; } = string.Empty;

    public string CertificateThumbprint { get; init; } = string.Empty;

    public string CertificatePath { get; init; } = string.Empty;

    public string CredentialMode { get; init; } = string.Empty;

    public string CloudEnvironment { get; init; } = "Commercial";

    public string AuthenticationMode { get; init; } = "Delegated";

    public IReadOnlyList<string> Scopes { get; init; } = Array.Empty<string>();

    public bool UseLiveGraph { get; init; }

    public bool AuthenticationSucceeded { get; init; } = true;

    public bool PermissionValidationSucceeded { get; init; } = true;

    public bool ServiceAvailable { get; init; } = true;
}
