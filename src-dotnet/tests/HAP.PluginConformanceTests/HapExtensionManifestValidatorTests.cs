using HAP.Contracts;
using HAP.Extensions.Abstractions;
using Xunit;

namespace HAP.PluginConformanceTests;

public sealed class HapExtensionManifestValidatorTests
{
    [Fact]
    public void Validate_AcceptsCompatibleNativeManifestWithDeclaredCapability()
    {
        var validator = new HapExtensionManifestValidator(new ExtensionApiVersion(1, 0));

        var result = validator.Validate(CreateNativeManifest(), CorrelationId.From("manifest-valid"));

        Assert.True(result.Succeeded, string.Join("; ", result.Errors.Select(error => error.Message)));
        Assert.NotNull(result.Value);
        Assert.True(result.Value.IsCompatible);
        Assert.Contains("identity.user.read", result.Value.CapabilityIds);
    }

    [Fact]
    public void Validate_RejectsUnsupportedMajorApiVersion()
    {
        var validator = new HapExtensionManifestValidator(new ExtensionApiVersion(1, 0));
        var manifest = CreateNativeManifest() with { ApiVersion = "2.0" };

        var result = validator.Validate(manifest, CorrelationId.From("manifest-version"));

        Assert.False(result.Succeeded);
        Assert.Contains(result.Errors, error => error.Code == "Extension.ApiVersionUnsupported");
    }

    [Fact]
    public void Validate_RejectsPowerShellManifestWithoutPinnedRuntimeEntryPoint()
    {
        var validator = new HapExtensionManifestValidator();
        var manifest = CreateNativeManifest() with
        {
            Implementation = HapProviderImplementationKind.PowerShell,
            EntryPoint = new HapExtensionEntryPoint { ModulePath = @".\Provider.psm1" }
        };

        var result = validator.Validate(manifest, CorrelationId.From("manifest-pwsh"));

        Assert.False(result.Succeeded);
        Assert.Contains(result.Errors, error => error.Code == "Extension.PowerShellEditionRequired");
        Assert.Contains(result.Errors, error => error.Code == "Extension.PowerShellVersionRequired");
    }

    [Fact]
    public void Validate_RejectsDuplicateCapabilityDeclarations()
    {
        var validator = new HapExtensionManifestValidator();
        var capability = new HapExtensionCapabilityDeclaration
        {
            Id = "identity.user.read",
            Operations = new[] { "SearchUser" }
        };
        var manifest = CreateNativeManifest() with { Capabilities = new[] { capability, capability } };

        var result = validator.Validate(manifest, CorrelationId.From("manifest-duplicate"));

        Assert.False(result.Succeeded);
        Assert.Contains(result.Errors, error => error.Code == "Extension.CapabilityDuplicate");
    }

    private static HapExtensionManifest CreateNativeManifest()
    {
        return new HapExtensionManifest
        {
            ManifestVersion = "1.0",
            ProviderId = "contoso.identity",
            DisplayName = "Contoso Identity",
            Publisher = "Contoso",
            ProviderVersion = "1.2.3",
            ApiVersion = "1.0",
            Implementation = HapProviderImplementationKind.NativeDotNet,
            EntryPoint = new HapExtensionEntryPoint
            {
                AssemblyPath = @".\Contoso.Identity.dll",
                TypeName = "Contoso.Identity.Provider"
            },
            Capabilities = new[]
            {
                new HapExtensionCapabilityDeclaration
                {
                    Id = "identity.user.read",
                    DisplayName = "Read users",
                    Operations = new[] { "SearchUser", "GetUserDetails" }
                }
            },
            RequiredPermissions = new[] { "Directory.Read.All" }
        };
    }
}
