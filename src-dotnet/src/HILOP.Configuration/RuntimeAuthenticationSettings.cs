namespace HILOP.Configuration;

public sealed record RuntimeAuthenticationSettings
{
    public string Cloud { get; init; } = string.Empty;

    public AppOnlyAuthenticationSettings AppOnly { get; init; } = new();

    public DelegatedAuthenticationSettings Delegated { get; init; } = new();
}

public sealed record AppOnlyAuthenticationSettings
{
    public bool Enabled { get; init; }

    public string TenantId { get; init; } = string.Empty;

    public string TenantDomain { get; init; } = string.Empty;

    public string ClientId { get; init; } = string.Empty;

    public string CredentialMode { get; init; } = "Certificate";

    public string CertificateThumbprint { get; init; } = string.Empty;

    public string CertificatePath { get; init; } = string.Empty;

    public string SecretReference { get; init; } = string.Empty;
}

public sealed record DelegatedAuthenticationSettings
{
    public bool Enabled { get; init; }

    public bool PromptWhenRequired { get; init; }

    public string ClientId { get; init; } = string.Empty;
}
