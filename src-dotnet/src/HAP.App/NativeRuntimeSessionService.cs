using System.Diagnostics;
using HAP.Application.RuntimeProfiles;
using HAP.Contracts;

namespace HAP.App;

internal sealed class NativeRuntimeSessionService : IRuntimeSessionService
{
    public Task<OperationResult<RuntimeSessionSummary>> StartAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        _ = repositoryRoot;
        _ = cancellationToken;
        var stopwatch = Stopwatch.StartNew();
        var summary = new RuntimeSessionSummary
        {
            ProfileName = profileName,
            RuntimeMode = "Simulation",
            CloudEnvironment = "Simulated",
            OverallStatus = "Native migration runtime initialized",
            DurationMs = (int)stopwatch.ElapsedMilliseconds,
            ProviderHealth = new[]
            {
                Health("DirectorySimulator", "NativeDotNet", "Connected", "Native simulator provider is available.", true),
                Health("MicrosoftGraph", "NativeDotNet", "Limited", "Native Graph foundation is available; live tenant calls remain gated.", true),
                Health("ActiveDirectory", "NativeDotNet", "Limited", "Native AD foundation is available; lab writes remain gated.", true),
                Health("ExchangeOnline", "NativeDotNet", "Limited", "Unsupported Exchange admin actions are deferred or extension candidates.", true),
                Health("ExchangeOnPremises", "NativeDotNet", "Limited", "No approved non-PowerShell management API is configured.", false)
            }
        };

        return Task.FromResult(OperationResult<RuntimeSessionSummary>.Success(summary, correlationId, status: "Completed"));
    }

    public Task<OperationResult<bool>> ShutdownAsync(
        string repositoryRoot,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        _ = repositoryRoot;
        _ = cancellationToken;
        return Task.FromResult(OperationResult<bool>.Success(true, correlationId, status: "Stopped"));
    }

    private static ProviderHealthSummary Health(
        string name,
        string mode,
        string status,
        string message,
        bool connected)
    {
        return new ProviderHealthSummary
        {
            Name = name,
            Mode = mode,
            Enabled = true,
            Required = false,
            Status = status,
            Message = message,
            Available = true,
            Connected = connected
        };
    }
}
