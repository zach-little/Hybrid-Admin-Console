namespace HAP.Providers.Graph;

public sealed record GraphProviderOptions
{
    public string TenantId { get; init; } = string.Empty;

    public string ClientId { get; init; } = string.Empty;

    public string AuthenticationMode { get; init; } = "Delegated";

    public IReadOnlyList<string> Scopes { get; init; } = Array.Empty<string>();

    public bool AuthenticationSucceeded { get; init; } = true;

    public bool PermissionValidationSucceeded { get; init; } = true;

    public bool ServiceAvailable { get; init; } = true;
}
