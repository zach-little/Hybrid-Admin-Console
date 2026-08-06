using HAP.Contracts;
using HAP.LegacyWorker.Protocol;
using HAP.Providers.LegacyPowerShell;
using Xunit;

namespace HAP.Providers.LegacyPowerShell.Tests;

public sealed class LegacyPowerShellWorkerClientTests
{
    [Fact]
    public async Task Client_ReturnsRuntimeProfilesAsOperationResult()
    {
        var solutionRoot = FindSolutionRoot();
        var repositoryRoot = Directory.GetParent(solutionRoot)?.FullName
            ?? throw new InvalidOperationException($"Could not resolve repository root above {solutionRoot}.");
        var workerPath = Path.Combine(
            solutionRoot,
            "src",
            "HAP.LegacyPowerShellWorker",
            "bin",
            "Debug",
            "net10.0",
            "HAP.LegacyPowerShellWorker.dll");

        var client = new LegacyPowerShellWorkerClient(new LegacyPowerShellWorkerOptions
        {
            WorkerPath = workerPath,
            TimeoutMilliseconds = 30000
        });

        var result = await client.GetRuntimeProfilesAsync(repositoryRoot, CorrelationId.From("task10-client"));

        Assert.True(result.Succeeded, string.Join("; ", result.Errors.Select(error => error.Message)));
        Assert.NotNull(result.Value);
        Assert.NotEmpty(result.Value.Profiles);
        Assert.Equal("task10-client", result.CorrelationId.Value);
    }

    [Fact]
    public async Task Client_StartsAndStopsSimulationRuntimeSession()
    {
        var solutionRoot = FindSolutionRoot();
        var repositoryRoot = Directory.GetParent(solutionRoot)?.FullName
            ?? throw new InvalidOperationException($"Could not resolve repository root above {solutionRoot}.");
        var workerPath = Path.Combine(
            solutionRoot,
            "src",
            "HAP.LegacyPowerShellWorker",
            "bin",
            "Debug",
            "net10.0",
            "HAP.LegacyPowerShellWorker.dll");
        var client = new LegacyPowerShellWorkerClient(new LegacyPowerShellWorkerOptions
        {
            WorkerPath = workerPath,
            TimeoutMilliseconds = 30000
        });
        var service = new LegacyRuntimeSessionService(client);

        var start = await service.StartAsync(repositoryRoot, "Simulation", CorrelationId.From("task13-start"));

        Assert.True(start.Succeeded, string.Join("; ", start.Errors.Select(error => error.Message)));
        Assert.NotNull(start.Value);
        Assert.Equal("Simulation", start.Value.ProfileName);
        Assert.NotEmpty(start.Value.ProviderHealth);

        var stop = await service.ShutdownAsync(repositoryRoot, CorrelationId.From("task13-stop"));

        Assert.True(stop.Succeeded, string.Join("; ", stop.Errors.Select(error => error.Message)));
        Assert.True(stop.Value);
    }

    [Fact]
    public void Mapper_PreservesStructuredProtocolErrors()
    {
        var response = LegacyWorkerResponse.Failure(
            CorrelationId.From("task10-errors"),
            LegacyWorkerKnownOperations.GetRuntimeProfiles,
            new[] { OperationError.Create("LegacyWorker.Test", "Mapped failure.") },
            status: "Failed");

        var result = LegacyWorkerResponseMapper.ToOperationResult<LegacyRuntimeProfilesResult>(response);

        Assert.False(result.Succeeded);
        Assert.Single(result.Errors);
        Assert.Equal("LegacyWorker.Test", result.Errors[0].Code);
        Assert.Equal("Failed", result.Status);
    }

    private static string FindSolutionRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "HAP.sln")))
        {
            directory = directory.Parent;
        }

        Assert.NotNull(directory);
        return directory.FullName;
    }
}
