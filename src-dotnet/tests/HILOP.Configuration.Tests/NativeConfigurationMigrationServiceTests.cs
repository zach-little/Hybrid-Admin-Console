using HILOP.Configuration.Migration;
using HILOP.Contracts;
using Xunit;

namespace HILOP.Configuration.Tests;

public sealed class NativeConfigurationMigrationServiceTests
{
    [Fact]
    public void Migrate_AddsNativeSchemaAndBackupMetadata()
    {
        var service = new NativeConfigurationMigrationService();

        var result = service.Migrate(
            new ConfigurationMigrationRequest { SourceJson = "{\"SchemaVersion\":\"legacy\",\"ProviderImplementation\":\"NativeDotNet\"}", DryRun = true },
            CorrelationId.From("config-migrate"));

        Assert.True(result.Succeeded);
        Assert.Equal("DryRun", result.Status);
        Assert.Contains("\"SchemaVersion\": \"native-1.0\"", result.Value!.MigratedJson);
        Assert.StartsWith("hap-config-backup-", result.Value.BackupName, StringComparison.Ordinal);
        Assert.False(result.Value.RequiresUserAction);
    }

    [Fact]
    public void Migrate_FlagsRemainingLegacyPowerShellValues()
    {
        var service = new NativeConfigurationMigrationService();

        var result = service.Migrate(
            new ConfigurationMigrationRequest { SourceJson = "{\"ProviderImplementation\":\"LegacyPowerShell\"}" },
            CorrelationId.From("config-legacy"));

        Assert.True(result.Succeeded);
        Assert.True(result.Value!.RequiresUserAction);
    }
}
