namespace HILOP.Application.RuntimeProfiles;

public sealed record RuntimeProfileSummary
{
    public string Name { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string RuntimeMode { get; init; } = string.Empty;

    public string CloudEnvironment { get; init; } = string.Empty;

    public string Organization { get; init; } = string.Empty;

    public string Environment { get; init; } = string.Empty;

    public bool IsValid { get; init; }

    public bool IsDefault { get; init; }

    public bool IsLastUsed { get; init; }

    public IReadOnlyList<string> EnabledProviders { get; init; } = Array.Empty<string>();

    public IReadOnlyList<string> Warnings { get; init; } = Array.Empty<string>();

    public string ErrorMessage { get; init; } = string.Empty;

    public string HealthLabel { get; init; } = string.Empty;

    public string BadgeText { get; init; } = string.Empty;
}
