namespace HAP.LegacyWorker.Protocol;

public sealed record LegacyRuntimeProfilesResult
{
    public required string RepositoryRoot { get; init; }

    public IReadOnlyList<LegacyRuntimeProfileSummary> Profiles { get; init; } = Array.Empty<LegacyRuntimeProfileSummary>();
}

public sealed record LegacyRuntimeProfileSummary
{
    public string Name { get; init; } = string.Empty;

    public string ProfileName { get; init; } = string.Empty;

    public string FolderName { get; init; } = string.Empty;

    public string FileName { get; init; } = string.Empty;

    public string Path { get; init; } = string.Empty;

    public string ProfileRoot { get; init; } = string.Empty;

    public string RuntimeMode { get; init; } = string.Empty;

    public string CloudEnvironment { get; init; } = string.Empty;

    public string Organization { get; init; } = string.Empty;

    public string Environment { get; init; } = string.Empty;

    public bool IsValid { get; init; }

    public bool IsDefault { get; init; }

    public bool IsLastUsed { get; init; }

    public IReadOnlyList<string> EnabledProviders { get; init; } = Array.Empty<string>();

    public int EnabledProviderCount { get; init; }

    public IReadOnlyList<string> Warnings { get; init; } = Array.Empty<string>();

    public string ErrorMessage { get; init; } = string.Empty;

    public string HealthLabel { get; init; } = string.Empty;

    public string BadgeText { get; init; } = string.Empty;
}
