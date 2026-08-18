using System.Diagnostics;
using System.Text.Json;
using HILOP.Contracts;
using HILOP.Providers.Abstractions;

namespace HILOP.Application.ProviderRouting;

public sealed class SimulatorReadOnlyWorkflowRouter
{
    private const string ProviderId = "DirectorySimulator";

    private readonly ISimulatorReadOnlyProvider _nativeProvider;
    private readonly ISimulatorReadOnlyProvider _legacyProvider;

    public SimulatorReadOnlyWorkflowRouter(
        ISimulatorReadOnlyProvider nativeProvider,
        ISimulatorReadOnlyProvider legacyProvider)
    {
        _nativeProvider = nativeProvider ?? throw new ArgumentNullException(nameof(nativeProvider));
        _legacyProvider = legacyProvider ?? throw new ArgumentNullException(nameof(legacyProvider));
    }

    public Task<OperationResult<ProviderRoutingResult<ProviderHealthResult>>> GetHealthAsync(
        string implementation,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        return RouteAsync(
            implementation,
            ProviderCapabilityIds.ProviderHealth,
            correlationId,
            provider => provider.GetHealthAsync(correlationId, cancellationToken));
    }

    public Task<OperationResult<ProviderRoutingResult<IReadOnlyList<SimulatorUserSummary>>>> SearchUsersAsync(
        string implementation,
        string query,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        return RouteAsync(
            implementation,
            ProviderCapabilityIds.UserLookup,
            correlationId,
            provider => provider.SearchUsersAsync(query, correlationId, cancellationToken));
    }

    private async Task<OperationResult<ProviderRoutingResult<T>>> RouteAsync<T>(
        string implementation,
        string capability,
        CorrelationId correlationId,
        Func<ISimulatorReadOnlyProvider, Task<OperationResult<T>>> execute)
    {
        var provider = SelectProvider(implementation);
        if (provider is null)
        {
            var legacyRetired = string.Equals(implementation, ProviderRoutingConstants.LegacyPowerShell, StringComparison.OrdinalIgnoreCase);
            var diagnostic = CreateDiagnostic(
                implementation,
                capability,
                correlationId,
                0,
                legacyRetired ? "LegacySimulatorRetired" : "ValidationFailed",
                powerShellProcessLaunched: false);

            return OperationResult<ProviderRoutingResult<T>>.Failure(
                correlationId,
                new[]
                {
                    OperationError.Create(
                        legacyRetired ? "ProviderRouting.LegacySimulatorRetired" : "ProviderRouting.UnknownImplementation",
                        legacyRetired
                            ? "LegacyPowerShell is no longer a supported built-in simulator implementation. Use NativeDotNet."
                            : $"Unknown provider implementation '{implementation}'. Expected 'NativeDotNet'.",
                        "implementation")
                },
                status: diagnostic.Status);
        }

        var stopwatch = Stopwatch.StartNew();
        var result = await execute(provider).ConfigureAwait(false);
        stopwatch.Stop();

        var routeStatus = result.Succeeded ? result.Status ?? "Succeeded" : result.Status ?? "Failed";
        var routed = new ProviderRoutingResult<T>
        {
            Value = result.Value!,
            Diagnostic = CreateDiagnostic(
                provider.Implementation,
                capability,
                correlationId,
                stopwatch.ElapsedMilliseconds,
                routeStatus,
                provider.LaunchesPowerShellProcess)
        };

        if (result.Succeeded)
        {
            return OperationResult<ProviderRoutingResult<T>>.Success(
                routed,
                correlationId,
                result.Warnings,
                routeStatus);
        }

        return OperationResult<ProviderRoutingResult<T>>.Failure(
            correlationId,
            AddDiagnosticDetail(result.Errors, routed.Diagnostic),
            result.Warnings,
            routeStatus);
    }

    private ISimulatorReadOnlyProvider? SelectProvider(string implementation)
    {
        if (string.Equals(implementation, ProviderRoutingConstants.NativeDotNet, StringComparison.OrdinalIgnoreCase))
        {
            return _nativeProvider;
        }

        return null;
    }

    private static ProviderRoutingDiagnostic CreateDiagnostic(
        string implementation,
        string capability,
        CorrelationId correlationId,
        long durationMilliseconds,
        string status,
        bool powerShellProcessLaunched)
    {
        return new ProviderRoutingDiagnostic
        {
            ProviderId = ProviderId,
            Implementation = implementation,
            Capability = capability,
            CorrelationId = correlationId.Value,
            DurationMilliseconds = durationMilliseconds,
            Status = status,
            PowerShellProcessLaunched = powerShellProcessLaunched
        };
    }

    private static IReadOnlyList<OperationError> AddDiagnosticDetail(
        IEnumerable<OperationError> errors,
        ProviderRoutingDiagnostic diagnostic)
    {
        var detail = JsonSerializer.Serialize(diagnostic);
        return errors
            .Select(error => error with { DiagnosticDetail = detail })
            .ToArray();
    }
}
