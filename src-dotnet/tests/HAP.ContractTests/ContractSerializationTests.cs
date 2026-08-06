using System.Text.Json;
using HAP.Contracts;
using Xunit;

namespace HAP.ContractTests;

public sealed class ContractSerializationTests
{
    [Fact]
    public void OperationResult_RoundTripsAsJson()
    {
        var source = OperationResult<ProviderDescriptor>.Success(
            ProviderDescriptor.Create(
                "contoso.mobilepass",
                "MobilePass",
                "Contoso",
                "1.2.0",
                "1.0",
                ProviderImplementationKind.PowerShellExtension,
                new[]
                {
                    ProviderCapability.Create(ProviderCapabilityIds.ProviderHealth, "Provider Health"),
                    ProviderCapability.Create(ProviderCapabilityIds.CredentialEnrollment, "Credential Enrollment")
                }),
            CorrelationId.From("serialize-1"),
            new[] { OperationWarning.Create("Preview", "This is a contract preview.") },
            "Completed");

        var json = JsonSerializer.Serialize(source);
        var roundTrip = JsonSerializer.Deserialize<OperationResult<ProviderDescriptor>>(json);

        Assert.NotNull(roundTrip);
        Assert.True(roundTrip.Succeeded);
        Assert.Equal("serialize-1", roundTrip.CorrelationId.Value);
        Assert.Equal("contoso.mobilepass", roundTrip.Value?.ProviderId);
        Assert.Equal(ProviderImplementationKind.PowerShellExtension, roundTrip.Value?.ImplementationKind);
        Assert.Single(roundTrip.Warnings);
        Assert.Empty(roundTrip.Errors);
    }

    [Fact]
    public void ProviderDescriptor_SerializesCapabilityIdentifiers()
    {
        var descriptor = ProviderDescriptor.Create(
            "hap.simulator",
            "Directory Simulator",
            "HAP",
            "1.0.0",
            "1.0",
            ProviderImplementationKind.Native,
            new[]
            {
                ProviderCapability.Create(ProviderCapabilityIds.ProviderHealth, "Provider Health"),
                ProviderCapability.Create(ProviderCapabilityIds.UserLookup, "User Lookup"),
                ProviderCapability.Create(ProviderCapabilityIds.DeviceLookup, "Device Lookup")
            });

        var json = JsonSerializer.Serialize(descriptor);

        Assert.Contains(ProviderCapabilityIds.ProviderHealth, json);
        Assert.Contains(ProviderCapabilityIds.UserLookup, json);
        Assert.Contains(ProviderCapabilityIds.DeviceLookup, json);
    }
}
