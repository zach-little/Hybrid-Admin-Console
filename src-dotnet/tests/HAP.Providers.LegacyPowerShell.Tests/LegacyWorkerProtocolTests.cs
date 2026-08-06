using System.Text.Json;
using HAP.Contracts;
using HAP.LegacyWorker.Protocol;
using Xunit;

namespace HAP.Providers.LegacyPowerShell.Tests;

public sealed class LegacyWorkerProtocolTests
{
    [Fact]
    public void Request_RoundTripsWithCorrelationTimeoutAndPayload()
    {
        var request = LegacyWorkerRequest.Create(
            CorrelationId.From("runtime-profiles-1"),
            LegacyWorkerKnownOperations.GetRuntimeProfiles,
            new { RepositoryRoot = @"D:\Atlas" },
            timeoutMilliseconds: 15000,
            cancellationId: "cancel-1");

        var json = JsonSerializer.Serialize(request, LegacyWorkerProtocol.JsonOptions);
        var roundTrip = JsonSerializer.Deserialize<LegacyWorkerRequest>(json, LegacyWorkerProtocol.JsonOptions);

        Assert.NotNull(roundTrip);
        Assert.Equal(LegacyWorkerProtocol.Version, roundTrip.ProtocolVersion);
        Assert.Equal(LegacyWorkerMessageKind.OperationRequest, roundTrip.Kind);
        Assert.Equal("runtime-profiles-1", roundTrip.CorrelationId.Value);
        Assert.Equal(LegacyWorkerKnownOperations.GetRuntimeProfiles, roundTrip.Operation);
        Assert.Equal(15000, roundTrip.TimeoutMilliseconds);
        Assert.Equal("cancel-1", roundTrip.CancellationId);
        Assert.Equal(@"D:\Atlas", roundTrip.Payload?.GetProperty("RepositoryRoot").GetString());
    }

    [Fact]
    public void Response_SeparatesDataWarningsErrorsAndStreams()
    {
        var response = LegacyWorkerResponse.Success(
            CorrelationId.From("runtime-profiles-1"),
            LegacyWorkerKnownOperations.GetRuntimeProfiles,
            new[] { new { ProfileName = "Simulation", IsValid = true } },
            warnings: new[] { OperationWarning.Create("Profile.Warning", "Profile has warnings.") },
            streams: new[]
            {
                LegacyWorkerStreamRecord.Create(LegacyWorkerStreamKind.Warning, "Legacy warning stream text.")
            });

        var json = JsonSerializer.Serialize(response, LegacyWorkerProtocol.JsonOptions);
        var roundTrip = JsonSerializer.Deserialize<LegacyWorkerResponse>(json, LegacyWorkerProtocol.JsonOptions);

        Assert.NotNull(roundTrip);
        Assert.True(roundTrip.Succeeded);
        Assert.Single(roundTrip.Warnings);
        Assert.Empty(roundTrip.Errors);
        Assert.Single(roundTrip.Streams);
        Assert.Equal(LegacyWorkerStreamKind.Warning, roundTrip.Streams[0].Stream);
        Assert.Equal("Simulation", roundTrip.Data?.EnumerateArray().Single().GetProperty("ProfileName").GetString());
    }

    [Fact]
    public void Failure_RequiresAtLeastOneStructuredError()
    {
        Assert.Throws<ArgumentException>(() =>
            LegacyWorkerResponse.Failure(
                CorrelationId.From("failed-1"),
                LegacyWorkerKnownOperations.GetRuntimeProfiles,
                Array.Empty<OperationError>()));
    }

    [Fact]
    public void HandshakeResponse_AdvertisesVersionEditionAndOperations()
    {
        var response = new LegacyWorkerHandshakeResponse
        {
            Accepted = true,
            WorkerName = "HAP.LegacyPowerShellWorker",
            WorkerVersion = "0.1.0",
            Edition = LegacyPowerShellEdition.PowerShell7,
            SupportedOperations = new[]
            {
                LegacyWorkerKnownOperations.GetRuntimeProfiles,
                LegacyWorkerKnownOperations.GetRuntimeDiagnostics
            }
        };

        var json = JsonSerializer.Serialize(response, LegacyWorkerProtocol.JsonOptions);
        var roundTrip = JsonSerializer.Deserialize<LegacyWorkerHandshakeResponse>(json, LegacyWorkerProtocol.JsonOptions);

        Assert.NotNull(roundTrip);
        Assert.True(roundTrip.Accepted);
        Assert.Equal(LegacyWorkerProtocol.Version, roundTrip.ProtocolVersion);
        Assert.Equal(LegacyWorkerMessageKind.HandshakeResponse, roundTrip.Kind);
        Assert.Equal(LegacyPowerShellEdition.PowerShell7, roundTrip.Edition);
        Assert.Contains(LegacyWorkerKnownOperations.GetRuntimeProfiles, roundTrip.SupportedOperations);
    }

    [Fact]
    public void CancellationRequest_RoundTripsWithoutStartingWorker()
    {
        var request = new LegacyWorkerCancellationRequest
        {
            CorrelationId = CorrelationId.From("cancel-correlation"),
            CancellationId = "cancel-1",
            Reason = "User requested cancellation."
        };

        var json = JsonSerializer.Serialize(request, LegacyWorkerProtocol.JsonOptions);
        var roundTrip = JsonSerializer.Deserialize<LegacyWorkerCancellationRequest>(json, LegacyWorkerProtocol.JsonOptions);

        Assert.NotNull(roundTrip);
        Assert.Equal(LegacyWorkerMessageKind.CancellationRequest, roundTrip.Kind);
        Assert.Equal("cancel-1", roundTrip.CancellationId);
        Assert.Equal("User requested cancellation.", roundTrip.Reason);
    }
}
