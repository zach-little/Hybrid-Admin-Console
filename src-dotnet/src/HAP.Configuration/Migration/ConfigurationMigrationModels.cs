namespace HAP.Configuration.Migration;

public sealed record ConfigurationMigrationRequest
{
    public string SourceJson { get; init; } = string.Empty;

    public string SourceVersion { get; init; } = string.Empty;

    public bool DryRun { get; init; }
}

public sealed record ConfigurationMigrationResult
{
    public string TargetVersion { get; init; } = "native-1.0";

    public string MigratedJson { get; init; } = string.Empty;

    public string BackupName { get; init; } = string.Empty;

    public bool RequiresUserAction { get; init; }

    public IReadOnlyList<string> Messages { get; init; } = Array.Empty<string>();
}
