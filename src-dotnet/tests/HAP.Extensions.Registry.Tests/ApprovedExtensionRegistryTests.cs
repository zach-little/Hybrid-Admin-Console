using System.Text.Json;
using System.Text.Json.Serialization;
using HAP.Contracts;
using HAP.Extensions.Abstractions;
using HAP.Extensions.Registry;
using Xunit;

namespace HAP.Extensions.Registry.Tests;

public sealed class ApprovedExtensionRegistryTests
{
    private static readonly JsonSerializerOptions JsonOptions = CreateJsonOptions();

    [Fact]
    public void LoadApproved_ReturnsEnabledEntryWhenHashAndGrantsMatch()
    {
        using var workspace = TempWorkspace.Create();
        var manifestPath = workspace.WriteManifest(CreateManifest());
        var registry = new ApprovedExtensionRegistry(new[] { workspace.Root });

        var result = registry.LoadApproved(
            new[]
            {
                new ApprovedExtensionRegistration
                {
                    ManifestPath = manifestPath,
                    ApprovedSha256 = ApprovedExtensionRegistry.ComputeSha256(manifestPath),
                    Enabled = true,
                    SignatureState = HapExtensionSignatureState.Trusted,
                    GrantedCapabilities = new[] { "identity.user.read" }
                }
            },
            CorrelationId.From("registry-valid"));

        Assert.True(result.Succeeded, string.Join("; ", result.Errors.Select(error => error.Message)));
        Assert.Single(result.Value!);
        Assert.True(result.Value![0].Enabled);
        Assert.Equal(HapExtensionSignatureState.Trusted, result.Value![0].SignatureState);
    }

    [Fact]
    public void LoadApproved_RejectsManifestOutsideControlledRoots()
    {
        using var controlled = TempWorkspace.Create();
        using var outside = TempWorkspace.Create();
        var manifestPath = outside.WriteManifest(CreateManifest());
        var registry = new ApprovedExtensionRegistry(new[] { controlled.Root });

        var result = registry.LoadApproved(
            new[]
            {
                new ApprovedExtensionRegistration
                {
                    ManifestPath = manifestPath,
                    ApprovedSha256 = ApprovedExtensionRegistry.ComputeSha256(manifestPath),
                    Enabled = true
                }
            },
            CorrelationId.From("registry-root"));

        Assert.False(result.Succeeded);
        Assert.Contains(result.Errors, error => error.Code == "ExtensionRegistry.PathOutsideControlledRoot");
    }

    [Fact]
    public void LoadApproved_RejectsChangedManifestHash()
    {
        using var workspace = TempWorkspace.Create();
        var manifestPath = workspace.WriteManifest(CreateManifest());
        var registry = new ApprovedExtensionRegistry(new[] { workspace.Root });

        var result = registry.LoadApproved(
            new[]
            {
                new ApprovedExtensionRegistration
                {
                    ManifestPath = manifestPath,
                    ApprovedSha256 = "not-the-approved-hash",
                    Enabled = true
                }
            },
            CorrelationId.From("registry-hash"));

        Assert.False(result.Succeeded);
        Assert.Contains(result.Errors, error => error.Code == "ExtensionRegistry.HashMismatch");
    }

    [Fact]
    public void LoadApproved_RejectsCapabilityGrantsNotDeclaredByManifest()
    {
        using var workspace = TempWorkspace.Create();
        var manifestPath = workspace.WriteManifest(CreateManifest());
        var registry = new ApprovedExtensionRegistry(new[] { workspace.Root });

        var result = registry.LoadApproved(
            new[]
            {
                new ApprovedExtensionRegistration
                {
                    ManifestPath = manifestPath,
                    ApprovedSha256 = ApprovedExtensionRegistry.ComputeSha256(manifestPath),
                    Enabled = true,
                    GrantedCapabilities = new[] { "identity.user.write" }
                }
            },
            CorrelationId.From("registry-grant"));

        Assert.False(result.Succeeded);
        Assert.Contains(result.Errors, error => error.Code == "ExtensionRegistry.UndeclaredCapabilityGrant");
    }

    private static HapExtensionManifest CreateManifest()
    {
        return new HapExtensionManifest
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
                ModulePath = @".\Contoso.Identity.Provider.psm1",
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
    }

    private static JsonSerializerOptions CreateJsonOptions()
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

        public string Root { get; }

        public static TempWorkspace Create()
        {
            var root = Path.Combine(Path.GetTempPath(), "hap-extension-registry-tests", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            return new TempWorkspace(root);
        }

        public string WriteManifest(HapExtensionManifest manifest)
        {
            var path = Path.Combine(Root, "manifest.json");
            File.WriteAllText(path, JsonSerializer.Serialize(manifest, JsonOptions));
            return path;
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
