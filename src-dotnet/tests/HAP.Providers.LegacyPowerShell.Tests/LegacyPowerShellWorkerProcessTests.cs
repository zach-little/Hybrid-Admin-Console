using System.Diagnostics;
using System.Text.Json;
using HAP.Contracts;
using HAP.LegacyWorker.Protocol;
using Xunit;

namespace HAP.Providers.LegacyPowerShell.Tests;

public sealed class LegacyPowerShellWorkerProcessTests
{
    [Fact]
    public async Task Worker_HandshakesAndGetsRuntimeProfilesOutOfProcess()
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

        Assert.True(File.Exists(workerPath), $"Worker was not built at {workerPath}.");

        using var process = StartWorker(workerPath);
        try
        {
            var handshake = new LegacyWorkerHandshakeRequest
            {
                ClientName = "HAP.Providers.LegacyPowerShell.Tests"
            };
            await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(handshake, LegacyWorkerProtocol.JsonOptions));
            var handshakeLine = await ReadLineWithTimeoutAsync(process, TimeSpan.FromSeconds(10));
            var handshakeResponse = JsonSerializer.Deserialize<LegacyWorkerHandshakeResponse>(handshakeLine, LegacyWorkerProtocol.JsonOptions);

            Assert.NotNull(handshakeResponse);
            Assert.True(handshakeResponse.Accepted);
            Assert.Contains(LegacyWorkerKnownOperations.GetRuntimeProfiles, handshakeResponse.SupportedOperations);

            var request = LegacyWorkerRequest.Create(
                CorrelationId.From("task9-worker-process"),
                LegacyWorkerKnownOperations.GetRuntimeProfiles,
                new LegacyRuntimeProfilesRequest { RepositoryRoot = repositoryRoot },
                timeoutMilliseconds: 30000);

            await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(request, LegacyWorkerProtocol.JsonOptions));
            var responseLine = await ReadLineWithTimeoutAsync(process, TimeSpan.FromSeconds(30));
            var response = JsonSerializer.Deserialize<LegacyWorkerResponse>(responseLine, LegacyWorkerProtocol.JsonOptions);

            Assert.NotNull(response);
            Assert.True(response.Succeeded, string.Join("; ", response.Errors.Select(error => error.Message)));
            Assert.Equal("task9-worker-process", response.CorrelationId.Value);

            var result = response.Data?.Deserialize<LegacyRuntimeProfilesResult>(LegacyWorkerProtocol.JsonOptions);
            Assert.NotNull(result);
            Assert.True(
                string.Equals(repositoryRoot, result.RepositoryRoot, StringComparison.OrdinalIgnoreCase),
                $"Expected repository root '{repositoryRoot}' but got '{result.RepositoryRoot}'.");
            Assert.NotEmpty(result.Profiles);
        }
        finally
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
    }

    private static Process StartWorker(string workerPath)
    {
        var process = Process.Start(new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = $"\"{workerPath}\"",
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        });

        Assert.NotNull(process);
        return process;
    }

    private static async Task<string> ReadLineWithTimeoutAsync(Process process, TimeSpan timeout)
    {
        var readTask = process.StandardOutput.ReadLineAsync();
        var completed = await Task.WhenAny(readTask, Task.Delay(timeout));
        if (completed != readTask)
        {
            var stderr = await process.StandardError.ReadToEndAsync();
            throw new TimeoutException($"Worker did not respond within {timeout}. stderr: {stderr}");
        }

        return await readTask ?? throw new InvalidOperationException("Worker closed stdout before responding.");
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
