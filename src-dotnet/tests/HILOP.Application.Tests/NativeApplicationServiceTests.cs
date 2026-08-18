using HILOP.Application.Capabilities;
using HILOP.Application.Devices;
using HILOP.Application.Status;
using HILOP.Application.UserLookup;
using HILOP.Contracts;
using HILOP.Providers.Abstractions;
using Xunit;

namespace HILOP.Application.Tests;

public sealed class NativeApplicationServiceTests
{
    [Fact]
    public void CapabilityCatalog_ExposesUnsupportedExchangeDispositions()
    {
        var catalog = new BuiltInCapabilityCatalog();

        var delegation = catalog.Get("ExchangeOnline", "ExchangeOnline.MailboxDelegation");
        var unknown = catalog.Get("ExchangeOnline", "Missing");

        Assert.False(delegation.IsInvokableBuiltIn);
        Assert.Equal(CapabilityDisposition.CustomerExtensionCandidate, delegation.Disposition);
        Assert.False(unknown.IsInvokableBuiltIn);
        Assert.Equal(CapabilityDisposition.Unsupported, unknown.Disposition);
    }

    [Fact]
    public async Task UserLookup_AggregatesProvidersAndPreservesPartialFailure()
    {
        var service = new NativeHybridUserLookupService(new (string ProviderId, IUserLookupCapability Provider)[]
        {
            ("AD", new FakeUserLookupProvider(true, new[] { User("amorgan", "ActiveDirectory") })),
            ("Graph", new FakeUserLookupProvider(false, Array.Empty<SimulatorUserSummary>()))
        });

        var result = await service.SearchAsync("amorgan", CorrelationId.From("lookup"));

        Assert.True(result.Succeeded);
        Assert.Equal("Partial", result.Status);
        Assert.Single(result.Value!.Users);
        Assert.Contains(result.Warnings, warning => warning.Code == "HybridUserLookup.ProviderFailed");
    }

    [Fact]
    public async Task ProviderHealth_AggregatesHealthyAndFailedProviders()
    {
        var service = new NativeProviderHealthService(new (string ProviderId, IProviderHealthCapability Provider)[]
        {
            ("AD", new FakeHealthProvider(true)),
            ("ExchangeOnline", new FakeHealthProvider(false))
        });

        var result = await service.GetStatusAsync(CorrelationId.From("health"));

        Assert.True(result.Succeeded);
        Assert.Equal("Degraded", result.Status);
        Assert.Equal(2, result.Value!.Providers.Count);
        Assert.Contains(result.Value.Providers, provider => provider.ProviderId == "ExchangeOnline" && provider.Status == "Failed");
    }

    [Fact]
    public async Task DeviceManagement_DeduplicatesAndSortsDevices()
    {
        var service = new NativeDeviceManagementService(new (string ProviderId, IDeviceReadCapability Provider)[]
        {
            ("Graph", new FakeDeviceProvider(new[] { Device("device-2", "B-LAPTOP"), Device("device-1", "A-LAPTOP") })),
            ("AD", new FakeDeviceProvider(new[] { Device("device-1", "A-LAPTOP") }))
        });

        var result = await service.SearchDevicesAsync("laptop", CorrelationId.From("devices"));

        Assert.True(result.Succeeded);
        Assert.Equal(new[] { "A-LAPTOP", "B-LAPTOP" }, result.Value!.Select(device => device.Name));
    }

    private static SimulatorUserSummary User(string sam, string source)
    {
        return new SimulatorUserSummary
        {
            SamAccountName = sam,
            DisplayName = sam,
            UserPrincipalName = $"{sam}@example.com",
            Source = source,
            Enabled = true
        };
    }

    private static ManagedDeviceSummary Device(string id, string name)
    {
        return new ManagedDeviceSummary { Id = id, Name = name, Source = "Test" };
    }

    private sealed class FakeUserLookupProvider : IUserLookupCapability
    {
        private readonly bool _succeeds;
        private readonly IReadOnlyList<SimulatorUserSummary> _users;

        public FakeUserLookupProvider(bool succeeds, IReadOnlyList<SimulatorUserSummary> users)
        {
            _succeeds = succeeds;
            _users = users;
        }

        public Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> SearchUsersAsync(string query, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            return Task.FromResult(_succeeds
                ? OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(_users, correlationId)
                : OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(correlationId, new[] { OperationError.Create("Fake.Failed", "Provider failed.") }, status: "Failed"));
        }
    }

    private sealed class FakeHealthProvider : IProviderHealthCapability
    {
        private readonly bool _succeeds;

        public FakeHealthProvider(bool succeeds)
        {
            _succeeds = succeeds;
        }

        public Task<OperationResult<ProviderHealthResult>> GetHealthAsync(CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            return Task.FromResult(_succeeds
                ? OperationResult<ProviderHealthResult>.Success(new ProviderHealthResult { ProviderId = "AD", Status = "Connected", Connected = true, Available = true }, correlationId)
                : OperationResult<ProviderHealthResult>.Failure(correlationId, new[] { OperationError.Create("Fake.Failed", "Provider failed.") }, status: "Failed"));
        }
    }

    private sealed class FakeDeviceProvider : IDeviceReadCapability
    {
        private readonly IReadOnlyList<ManagedDeviceSummary> _devices;

        public FakeDeviceProvider(IReadOnlyList<ManagedDeviceSummary> devices)
        {
            _devices = devices;
        }

        public Task<OperationResult<IReadOnlyList<ManagedDeviceSummary>>> GetManagedDevicesAsync(string identity, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            return Task.FromResult(OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Success(_devices, correlationId));
        }

        public Task<OperationResult<IReadOnlyList<ManagedDeviceSummary>>> SearchDevicesAsync(string query, CorrelationId correlationId, CancellationToken cancellationToken = default)
        {
            return Task.FromResult(OperationResult<IReadOnlyList<ManagedDeviceSummary>>.Success(_devices, correlationId));
        }
    }
}
