using HAP.Application.ProviderRouting;
using HAP.Contracts;
using HAP.Providers.Abstractions;
using Xunit;

namespace HAP.Application.Tests;

public sealed class SimulatorReadOnlyWorkflowRouterTests
{
    [Fact]
    public async Task SearchUsersAsync_WhenNativeDotNet_RoutesOnlyToNativeProvider()
    {
        var native = FakeSimulatorProvider.NativeSuccess();
        var legacy = FakeSimulatorProvider.LegacySuccess();
        var router = new SimulatorReadOnlyWorkflowRouter(native, legacy);

        var result = await router.SearchUsersAsync(
            ProviderRoutingConstants.NativeDotNet,
            "amorgan",
            CorrelationId.From("native-search"));

        Assert.True(result.Succeeded);
        Assert.NotNull(result.Value);
        Assert.Equal(1, native.SearchCallCount);
        Assert.Equal(0, legacy.SearchCallCount);
        Assert.Equal("amorgan", Assert.Single(result.Value.Value).SamAccountName);
        Assert.Equal(ProviderRoutingConstants.NativeDotNet, result.Value.Diagnostic.Implementation);
        Assert.Equal(ProviderCapabilityIds.UserLookup, result.Value.Diagnostic.Capability);
        Assert.False(result.Value.Diagnostic.PowerShellProcessLaunched);
    }

    [Fact]
    public async Task GetHealthAsync_WhenLegacyPowerShell_ReturnsRetiredSimulatorError()
    {
        var native = FakeSimulatorProvider.NativeSuccess();
        var legacy = FakeSimulatorProvider.LegacySuccess();
        var router = new SimulatorReadOnlyWorkflowRouter(native, legacy);

        var result = await router.GetHealthAsync(
            ProviderRoutingConstants.LegacyPowerShell,
            CorrelationId.From("legacy-health"));

        Assert.False(result.Succeeded);
        Assert.Equal(0, native.HealthCallCount);
        Assert.Equal(0, legacy.HealthCallCount);
        Assert.Equal("ProviderRouting.LegacySimulatorRetired", Assert.Single(result.Errors).Code);
        Assert.Equal("LegacySimulatorRetired", result.Status);
    }

    [Fact]
    public async Task SearchUsersAsync_WhenImplementationUnknown_ReturnsStructuredValidationError()
    {
        var router = new SimulatorReadOnlyWorkflowRouter(
            FakeSimulatorProvider.NativeSuccess(),
            FakeSimulatorProvider.LegacySuccess());

        var result = await router.SearchUsersAsync(
            "Native",
            "amorgan",
            CorrelationId.From("unknown-implementation"));

        Assert.False(result.Succeeded);
        var error = Assert.Single(result.Errors);
        Assert.Equal("ProviderRouting.UnknownImplementation", error.Code);
        Assert.Equal("implementation", error.Target);
        Assert.Equal("ValidationFailed", result.Status);
    }

    [Fact]
    public async Task SearchUsersAsync_WhenNativeFails_DoesNotFallbackToLegacy()
    {
        var native = FakeSimulatorProvider.NativeFailure("Provider exploded");
        var legacy = FakeSimulatorProvider.LegacySuccess();
        var router = new SimulatorReadOnlyWorkflowRouter(native, legacy);

        var result = await router.SearchUsersAsync(
            ProviderRoutingConstants.NativeDotNet,
            "amorgan",
            CorrelationId.From("native-failure"));

        Assert.False(result.Succeeded);
        Assert.Equal(1, native.SearchCallCount);
        Assert.Equal(0, legacy.SearchCallCount);
        var error = Assert.Single(result.Errors);
        Assert.Equal("Fake.NativeFailure", error.Code);
        Assert.Contains(ProviderRoutingConstants.NativeDotNet, error.DiagnosticDetail, StringComparison.Ordinal);
        Assert.Contains("\"PowerShellProcessLaunched\":false", error.DiagnosticDetail, StringComparison.Ordinal);
    }

    private sealed class FakeSimulatorProvider : ISimulatorReadOnlyProvider
    {
        private readonly bool _succeed;
        private readonly string _failureMessage;

        private FakeSimulatorProvider(
            string implementation,
            bool launchesPowerShellProcess,
            bool succeed,
            string failureMessage)
        {
            Implementation = implementation;
            LaunchesPowerShellProcess = launchesPowerShellProcess;
            _succeed = succeed;
            _failureMessage = failureMessage;
        }

        public string ProviderId => "DirectorySimulator";

        public string Implementation { get; }

        public bool LaunchesPowerShellProcess { get; }

        public int HealthCallCount { get; private set; }

        public int SearchCallCount { get; private set; }

        public static FakeSimulatorProvider NativeSuccess()
        {
            return new FakeSimulatorProvider(ProviderRoutingConstants.NativeDotNet, false, true, string.Empty);
        }

        public static FakeSimulatorProvider LegacySuccess()
        {
            return new FakeSimulatorProvider(ProviderRoutingConstants.LegacyPowerShell, true, true, string.Empty);
        }

        public static FakeSimulatorProvider NativeFailure(string message)
        {
            return new FakeSimulatorProvider(ProviderRoutingConstants.NativeDotNet, false, false, message);
        }

        public Task<OperationResult<ProviderHealthResult>> GetHealthAsync(
            CorrelationId correlationId,
            CancellationToken cancellationToken = default)
        {
            _ = cancellationToken;
            HealthCallCount++;
            if (!_succeed)
            {
                return Task.FromResult(OperationResult<ProviderHealthResult>.Failure(
                    correlationId,
                    new[] { OperationError.Create("Fake.NativeFailure", _failureMessage) },
                    status: "Failed"));
            }

            return Task.FromResult(OperationResult<ProviderHealthResult>.Success(
                new ProviderHealthResult
                {
                    ProviderId = ProviderId,
                    Mode = "Simulation",
                    Status = "Connected",
                    Available = true,
                    Connected = true
                },
                correlationId,
                status: "Connected"));
        }

        public Task<OperationResult<IReadOnlyList<SimulatorUserSummary>>> SearchUsersAsync(
            string query,
            CorrelationId correlationId,
            CancellationToken cancellationToken = default)
        {
            _ = cancellationToken;
            SearchCallCount++;
            if (!_succeed)
            {
                return Task.FromResult(OperationResult<IReadOnlyList<SimulatorUserSummary>>.Failure(
                    correlationId,
                    new[] { OperationError.Create("Fake.NativeFailure", _failureMessage) },
                    status: "Failed"));
            }

            return Task.FromResult(OperationResult<IReadOnlyList<SimulatorUserSummary>>.Success(
                new[]
                {
                    new SimulatorUserSummary
                    {
                        DisplayName = "Alex Morgan",
                        SamAccountName = query,
                        Source = ProviderId
                    }
                },
                correlationId,
                status: "Completed"));
        }
    }
}
