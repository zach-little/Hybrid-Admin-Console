namespace HAP.Providers.ExchangeOnPremises;

public sealed record ExchangeOnPremisesProviderOptions
{
    public string Server { get; init; } = string.Empty;

    public bool ConnectionAvailable { get; init; } = true;

    public bool AuthenticationSucceeded { get; init; } = true;

    public bool SupportedManagementApiAvailable { get; init; }
}
