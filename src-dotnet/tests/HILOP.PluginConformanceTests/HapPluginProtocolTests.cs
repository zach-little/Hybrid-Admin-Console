using System.Text.Json;
using HILOP.Contracts;
using HILOP.Plugin.Protocol;
using Xunit;

namespace HILOP.PluginConformanceTests;

public sealed class HapPluginProtocolTests
{
    [Fact]
    public void Handshake_RoundTripsWithProviderIdentityAndManifestPath()
    {
        var request = new HapPluginHandshakeRequest
        {
            CorrelationId = CorrelationId.From("plugin-handshake"),
            ClientName = "HILOP.App",
            ProviderId = "contoso.identity",
            ManifestPath = @"D:\HILOP\Extensions\Contoso\manifest.json"
        };

        var json = JsonSerializer.Serialize(request, HapPluginProtocol.JsonOptions);
        var roundTrip = JsonSerializer.Deserialize<HapPluginHandshakeRequest>(json, HapPluginProtocol.JsonOptions);

        Assert.NotNull(roundTrip);
        Assert.Equal(HapPluginProtocol.Version, roundTrip.ProtocolVersion);
        Assert.Equal(HapPluginMessageKind.HandshakeRequest, roundTrip.Kind);
        Assert.Equal("contoso.identity", roundTrip.ProviderId);
    }

    [Fact]
    public void OperationResponse_SeparatesDataWarningsAndErrors()
    {
        var response = new HapPluginOperationResponse
        {
            CorrelationId = CorrelationId.From("plugin-operation"),
            ProviderId = "contoso.identity",
            CapabilityId = "identity.user.read",
            Operation = "GetSampleUser",
            Succeeded = true,
            Status = "Completed",
            Data = JsonSerializer.SerializeToElement(new { UserPrincipalName = "ada@example.test" }, HapPluginProtocol.JsonOptions),
            Warnings = new[] { OperationWarning.Create("Sample.Warning", "Sample warning.") }
        };

        var json = JsonSerializer.Serialize(response, HapPluginProtocol.JsonOptions);
        var roundTrip = JsonSerializer.Deserialize<HapPluginOperationResponse>(json, HapPluginProtocol.JsonOptions);

        Assert.NotNull(roundTrip);
        Assert.True(roundTrip.Succeeded);
        Assert.Single(roundTrip.Warnings);
        Assert.Empty(roundTrip.Errors);
        Assert.Equal("ada@example.test", roundTrip.Data?.GetProperty("userPrincipalName").GetString());
    }
}
