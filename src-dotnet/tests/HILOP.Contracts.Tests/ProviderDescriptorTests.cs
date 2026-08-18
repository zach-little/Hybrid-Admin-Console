using HILOP.Contracts;
using Xunit;

namespace HILOP.Contracts.Tests;

public sealed class ProviderDescriptorTests
{
    [Fact]
    public void Create_BuildsDescriptorWithCapabilities()
    {
        var descriptor = ProviderDescriptor.Create(
            "hilop.graph",
            "Microsoft Graph",
            "HILOP",
            "1.0.0",
            "1.0",
            ProviderImplementationKind.Native,
            new[]
            {
                ProviderCapability.Create(ProviderCapabilityIds.ProviderHealth, "Provider Health"),
                ProviderCapability.Create(ProviderCapabilityIds.UserLookup, "User Lookup")
            });

        Assert.Equal("hilop.graph", descriptor.ProviderId);
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
