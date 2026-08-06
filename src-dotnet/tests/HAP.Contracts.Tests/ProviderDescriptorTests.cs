using HAP.Contracts;
using Xunit;

namespace HAP.Contracts.Tests;

public sealed class ProviderDescriptorTests
{
    [Fact]
    public void Create_BuildsDescriptorWithCapabilities()
    {
        var descriptor = ProviderDescriptor.Create(
            "hap.graph",
            "Microsoft Graph",
            "HAP",
            "1.0.0",
            "1.0",
            ProviderImplementationKind.Native,
            new[]
            {
                ProviderCapability.Create(ProviderCapabilityIds.ProviderHealth, "Provider Health"),
                ProviderCapability.Create(ProviderCapabilityIds.UserLookup, "User Lookup")
            });

        Assert.Equal("hap.graph", descriptor.ProviderId);
        Assert.Equal(ProviderImplementationKind.Native, descriptor.ImplementationKind);
        Assert.Equal(2, descriptor.Capabilities.Count);
    }

    [Fact]
    public void Create_RejectsMissingProviderId()
    {
        Assert.Throws<ArgumentException>(() =>
            ProviderDescriptor.Create(
                "",
                "Provider",
                "Publisher",
                "1.0.0",
                "1.0",
                ProviderImplementationKind.PowerShellExtension));
    }

    [Fact]
    public void CapabilityCreate_RejectsMissingVersion()
    {
        Assert.Throws<ArgumentException>(() =>
            ProviderCapability.Create("ProviderHealth", "Provider Health", ""));
    }
}
