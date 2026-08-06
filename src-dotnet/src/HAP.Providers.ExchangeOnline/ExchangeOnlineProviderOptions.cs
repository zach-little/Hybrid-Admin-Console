namespace HAP.Providers.ExchangeOnline;

public sealed record ExchangeOnlineProviderOptions
{
    public bool AuthenticationSucceeded { get; init; } = true;

    public bool PermissionValidationSucceeded { get; init; } = true;

    public bool ServiceAvailable { get; init; } = true;
}
