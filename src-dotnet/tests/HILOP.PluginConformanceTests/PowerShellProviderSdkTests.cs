using System.Text.Json;
using System.Text.Json.Serialization;
using HILOP.Contracts;
using HILOP.Extensions.Abstractions;
using Xunit;

namespace HILOP.PluginConformanceTests;

public sealed class PowerShellProviderSdkTests
{
    private static readonly JsonSerializerOptions JsonOptions = CreateJsonOptions();

    [Fact]
    public void SampleManifest_ConformsToExtensionManifestRules()
    {
        var solutionRoot = FindSolutionRoot();
        var manifestPath = Path.Combine(solutionRoot, "sdk", "powershell", "samples", "Contoso.Identity", "manifest.json");
        var manifest = JsonSerializer.Deserialize<HapExtensionManifest>(File.ReadAllText(manifestPath), JsonOptions);

        Assert.NotNull(manifest);
        var result = new HapExtensionManifestValidator().Validate(manifest, CorrelationId.From("sdk-sample"));

        Assert.True(result.Succeeded, string.Join("; ", result.Errors.Select(error => error.Message)));
        Assert.Contains("identity.user.read", result.Value!.CapabilityIds);
    }

    [Fact]
    public void SdkFiles_DoNotReferenceTemporaryLegacyBridge()
    {
        var solutionRoot = FindSolutionRoot();
        var sdkRoot = Path.Combine(solutionRoot, "sdk", "powershell");
        var files = Directory.GetFiles(sdkRoot, "*.*", SearchOption.AllDirectories)
            .Where(path => path.EndsWith(".psm1", StringComparison.OrdinalIgnoreCase) ||
                           path.EndsWith(".md", StringComparison.OrdinalIgnoreCase) ||
                           path.EndsWith(".json", StringComparison.OrdinalIgnoreCase));

        foreach (var file in files)
        {
            Assert.DoesNotContain("HILOP.LegacyBridge.psm1", File.ReadAllText(file), StringComparison.OrdinalIgnoreCase);
        }
    }

    private static string FindSolutionRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "HILOP.sln")))
        {
            directory = directory.Parent;
        }

        Assert.NotNull(directory);
        return directory.FullName;
    }

    private static JsonSerializerOptions CreateJsonOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };
        options.Converters.Add(new JsonStringEnumConverter());
        return options;
    }
}
