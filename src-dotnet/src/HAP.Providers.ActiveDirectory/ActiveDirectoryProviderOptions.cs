namespace HAP.Providers.ActiveDirectory;

public sealed record ActiveDirectoryProviderOptions
{
    public string Domain { get; init; } = string.Empty;

    public string Server { get; init; } = string.Empty;

    public bool ConnectionAvailable { get; init; } = true;

    public bool AuthenticationSucceeded { get; init; } = true;
}
