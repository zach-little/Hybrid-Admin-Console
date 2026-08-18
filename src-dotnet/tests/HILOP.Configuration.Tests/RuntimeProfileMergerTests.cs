using HILOP.Configuration;
using Xunit;

namespace HILOP.Configuration.Tests;

public sealed class RuntimeProfileMergerTests
{
    [Fact]
    public void Merge_OverlaysScalarValuesAndKeepsBaselineFallbacks()
    {
        var baseline = new RuntimeProfile
        {
            ProfileName = "Base",
            Organization = "Org",
            Cloud = "Commercial",
            Environment = "Development",
            TenantId = "tenant-1",
            Authentication = new RuntimeAuthenticationSettings
            {
                AppOnly = new AppOnlyAuthenticationSettings
                {
                    Enabled = true,
                    TenantId = "tenant-1",
                    ClientId = "client-1",
                    CertificateThumbprint = "thumbprint"
                }
            }
        };
        var overlay = new RuntimeProfile
        {
            ProfileName = "Overlay",
            Cloud = "GCCHigh",
            Authentication = new RuntimeAuthenticationSettings
            {
                AppOnly = new AppOnlyAuthenticationSettings
                {
                    Enabled = false,
                    ClientId = "client-2"
                }
            }
        };

        var merged = RuntimeProfileMerger.Merge(baseline, overlay);

        Assert.Equal("Overlay", merged.ProfileName);
        Assert.Equal("Org", merged.Organization);
        Assert.Equal("GCCHigh", merged.Cloud);
        Assert.Equal("tenant-1", merged.Authentication.AppOnly.TenantId);
        Assert.Equal("client-2", merged.Authentication.AppOnly.ClientId);
        Assert.False(merged.Authentication.AppOnly.Enabled);
    }

    [Fact]
    public void Merge_CombinesProvidersDeterministicallyByName()
    {
        var baseline = new RuntimeProfile
        {
            Providers = new Dictionary<string, RuntimeProviderSettings>(StringComparer.OrdinalIgnoreCase)
            {
                ["MicrosoftGraph"] = new() { Name = "MicrosoftGraph", Enabled = false, Mode = ProviderMode.Disabled },
                ["ActiveDirectory"] = new() { Name = "ActiveDirectory", Enabled = true, Mode = ProviderMode.Live }
            }
        };
        var overlay = new RuntimeProfile
        {
            Providers = new Dictionary<string, RuntimeProviderSettings>(StringComparer.OrdinalIgnoreCase)
            {
                ["MicrosoftGraph"] = new() { Name = "MicrosoftGraph", Enabled = true, Mode = ProviderMode.Live },
                ["DirectorySimulator"] = new() { Name = "DirectorySimulator", Enabled = true, Mode = ProviderMode.Simulation }
            }
        };

        var merged = RuntimeProfileMerger.Merge(baseline, overlay);

        Assert.Equal(new[] { "ActiveDirectory", "DirectorySimulator", "MicrosoftGraph" }, merged.Providers.Keys.ToArray());
        Assert.True(merged.Providers["MicrosoftGraph"].Enabled);
        Assert.Equal(ProviderMode.Live, merged.Providers["MicrosoftGraph"].Mode);
    }
}
