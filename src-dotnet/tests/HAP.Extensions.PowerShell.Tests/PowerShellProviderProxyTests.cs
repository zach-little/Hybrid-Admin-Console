using System.Text.Json;
using System.Text.Json.Serialization;
using HAP.Contracts;
using HAP.Extensions.Abstractions;
using HAP.Extensions.Registry;
using HAP.Plugin.Protocol;
using Xunit;

namespace HAP.Extensions.PowerShell.Tests;

public sealed class PowerShellProviderProxyTests
{
    private static readonly JsonSerializerOptions ManifestJsonOptions = CreateManifestJsonOptions();

    [Fact]
    public async Task InvokeOperationAsync_DoesNotLaunchHostWhenProviderDisabled()
    {
        using var workspace = TempWorkspace.Create();
        var entry = workspace.CreateRegistryEntry(enabled: false);
        var proxy = new PowerShellProviderProxy(entry, new PowerShellProviderProxyOptions
        {
            PluginHostPath = @"Z:\missing\HAP.PowerShellPluginHost.dll"
        });

        var result = await proxy.InvokeOperationAsync(
            "identity.user.read",
            "GetSampleUser",
            JsonSerializer.SerializeToElement(new { UserPrincipalName = "ada@example.test" }, HapPluginProtocol.JsonOptions),
            CorrelationId.From("task18-disabled"));

        Assert.False(result.Succeeded);
        Assert.Contains(result.Errors, error => error.Code == "PowerShellProxy.ProviderDisabled");
    }

    [Fact]
    public async Task InvokeOperationAsync_StartsHostForEnabledProvider()
    {
        var solutionRoot = FindSolutionRoot();
        var hostPath = Path.Combine(solutionRoot, "src", "HAP.PowerShellPluginHost", "bin", "Debug", "net10.0", "HAP.PowerShellPluginHost.dll");
        using var workspace = TempWorkspace.Create();
        var entry = workspace.CreateRegistryEntry(enabled: true);
        var proxy = new PowerShellProviderProxy(entry, new PowerShellProviderProxyOptions
        {
            PluginHostPath = hostPath,
            TimeoutMilliseconds = 30000
        });

        var result = await proxy.InvokeOperationAsync(
            "identity.user.read",
            "GetSampleUser",
            JsonSerializer.SerializeToElement(new { UserPrincipalName = "ada@example.test" }, HapPluginProtocol.JsonOptions),
            CorrelationId.From("task18-enabled"));

        Assert.True(result.Succeeded, string.Join("; ", result.Errors.Select(error => error.Message)));
        Assert.Equal("ada@example.test", result.Value.GetProperty("userPrincipalName").GetString());
    }

    private static string FindSolutionRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "HAP.sln")))
        {
            directory = directory.Parent;
        }

        Assert.NotNull(directory);
        return directory.FullName;
    }

    private static JsonSerializerOptions CreateManifestJsonOptions()
    {
        var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
        options.Converters.Add(new JsonStringEnumConverter());
        return options;
    }

    private sealed class TempWorkspace : IDisposable
    {
        private TempWorkspace(string root)
        {
            Root = root;
        }

        private string Root { get; }

        public static TempWorkspace Create()
        {
            var root = Path.Combine(Path.GetTempPath(), "hap-powershell-proxy-tests", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            return new TempWorkspace(root);
        }

        public ExtensionRegistryEntry CreateRegistryEntry(bool enabled)
        {
            var modulePath = Path.Combine(Root, "Contoso.Identity.Provider.psm1");
            File.WriteAllText(modulePath, """
function Invoke-HapProviderOperation {
    param(
        [string]$ProviderId,
        [string]$CapabilityId,
        [string]$Operation,
        [string]$PayloadJson
    )

    $payload = $PayloadJson | ConvertFrom-Json
    [pscustomobject]@{
        succeeded = $true
        data = [pscustomobject]@{ userPrincipalName = [string]$payload.UserPrincipalName }
        warnings = @()
        errors = @()
    }
}
Export-ModuleMember -Function Invoke-HapProviderOperation
""");

            var manifest = new HapExtensionManifest
            {
                ManifestVersion = "1.0",
                ProviderId = "contoso.identity",
                DisplayName = "Contoso Identity",
                Publisher = "Contoso",
                ProviderVersion = "1.0.0",
                ApiVersion = "1.0",
                Implementation = HapProviderImplementationKind.PowerShell,
                EntryPoint = new HapExtensionEntryPoint
                {
                    ModulePath = ".\\Contoso.Identity.Provider.psm1",
                    RequiredPowerShellEdition = "PowerShell7",
                    MinimumPowerShellVersion = "7.4"
                },
                Capabilities = new[]
                {
                    new HapExtensionCapabilityDeclaration
                    {
                        Id = "identity.user.read",
                        Operations = new[] { "TestConnection", "GetSampleUser" }
                    }
                }
            };
            var manifestPath = Path.Combine(Root, "manifest.json");
            File.WriteAllText(manifestPath, JsonSerializer.Serialize(manifest, ManifestJsonOptions));
            return new ExtensionRegistryEntry
            {
                Manifest = manifest,
                ManifestPath = manifestPath,
                ManifestSha256 = ApprovedExtensionRegistry.ComputeSha256(manifestPath),
                SignatureState = HapExtensionSignatureState.Trusted,
                Enabled = enabled,
                GrantedCapabilities = new[] { "identity.user.read" }
            };
        }

        public void Dispose()
        {
            if (Directory.Exists(Root))
            {
                Directory.Delete(Root, recursive: true);
            }
        }
    }
}
