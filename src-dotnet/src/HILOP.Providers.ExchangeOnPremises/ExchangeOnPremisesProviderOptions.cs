namespace HILOP.Providers.ExchangeOnPremises;

public sealed record ExchangeOnPremisesProviderOptions
{
    public string Server { get; init; } = string.Empty;

    public string ConnectionUri { get; init; } = string.Empty;

    public string Authentication { get; init; } = string.Empty;

    public bool UsePowerShell { get; init; }

    public bool ConnectionAvailable { get; init; } = true;

    public bool AuthenticationSucceeded { get; init; } = true;

    public bool SupportedManagementApiAvailable { get; init; }
}
