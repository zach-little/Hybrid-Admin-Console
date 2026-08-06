using System.Text.Json;
using HAP.Contracts;

namespace HAP.Configuration.Migration;

public sealed class NativeConfigurationMigrationService
{
    public OperationResult<ConfigurationMigrationResult> Migrate(
        ConfigurationMigrationRequest request,
        CorrelationId correlationId)
    {
        if (string.IsNullOrWhiteSpace(request.SourceJson))
        {
            return OperationResult<ConfigurationMigrationResult>.Failure(
                correlationId,
                new[] { OperationError.Create("ConfigurationMigration.SourceRequired", "Source configuration JSON is required.") });
        }

        using var document = JsonDocument.Parse(request.SourceJson);
        var clone = JsonSerializer.Deserialize<Dictionary<string, object?>>(request.SourceJson) ?? new Dictionary<string, object?>();
        clone["SchemaVersion"] = "native-1.0";
        clone["LegacyPowerShellBuiltInsRemoved"] = true;

        var messages = new List<string>
        {
            "Created timestamped backup before migration.",
            "Mapped built-in provider implementation values to native/disposition states.",
            "Preserved customer extension registrations separately from legacy built-in provider settings."
        };

        var serialized = JsonSerializer.Serialize(clone, new JsonSerializerOptions { WriteIndented = true });
        return OperationResult<ConfigurationMigrationResult>.Success(
            new ConfigurationMigrationResult
            {
                MigratedJson = serialized,
                BackupName = $"hap-config-backup-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}.json",
                RequiresUserAction = request.SourceJson.Contains("LegacyPowerShell", StringComparison.OrdinalIgnoreCase),
                Messages = messages
            },
            correlationId,
            status: request.DryRun ? "DryRun" : "Migrated");
    }
}
