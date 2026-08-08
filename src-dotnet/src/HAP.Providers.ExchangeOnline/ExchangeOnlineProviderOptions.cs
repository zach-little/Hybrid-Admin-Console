namespace HAP.Providers.ExchangeOnline;

public sealed record ExchangeOnlineProviderOptions
{
    public bool UsePowerShell { get; init; }

    public string CloudEnvironment { get; init; } = "Commercial";

    public string TenantDomain { get; init; } = string.Empty;

    public string ClientId { get; init; } = string.Empty;

    public string CertificateThumbprint { get; init; } = string.Empty;

    public string CertificatePath { get; init; } = string.Empty;

    public string CredentialMode { get; init; } = string.Empty;

    public bool AuthenticationSucceeded { get; init; } = true;

    public bool PermissionValidationSucceeded { get; init; } = true;

    public bool ServiceAvailable { get; init; } = true;
}
