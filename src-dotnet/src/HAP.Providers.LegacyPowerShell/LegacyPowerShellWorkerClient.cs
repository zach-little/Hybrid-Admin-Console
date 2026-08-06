using System.Diagnostics;
using System.Text.Json;
using HAP.Contracts;
using HAP.LegacyWorker.Protocol;

namespace HAP.Providers.LegacyPowerShell;

public sealed class LegacyPowerShellWorkerClient : ILegacyPowerShellWorkerClient
{
    private readonly LegacyPowerShellWorkerOptions _options;

    public LegacyPowerShellWorkerClient(LegacyPowerShellWorkerOptions options)
    {
        _options = options ?? throw new ArgumentNullException(nameof(options));
        if (string.IsNullOrWhiteSpace(_options.WorkerPath))
        {
            throw new ArgumentException("Worker path is required.", nameof(options));
        }
    }

    public async Task<OperationResult<LegacyRuntimeProfilesResult>> GetRuntimeProfilesAsync(
        string repositoryRoot,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(repositoryRoot))
        {
            return OperationResult<LegacyRuntimeProfilesResult>.Failure(
                correlationId,
                new[] { OperationError.Create("LegacyWorker.RepositoryRootRequired", "Repository root is required.") });
        }

        if (!File.Exists(_options.WorkerPath))
        {
            return OperationResult<LegacyRuntimeProfilesResult>.Failure(
                correlationId,
                new[] { OperationError.Create("LegacyWorker.WorkerMissing", "Legacy worker executable was not found.", _options.WorkerPath) });
        }

        var request = LegacyWorkerRequest.Create(
            correlationId,
            LegacyWorkerKnownOperations.GetRuntimeProfiles,
            new LegacyRuntimeProfilesRequest { RepositoryRoot = repositoryRoot },
            _options.TimeoutMilliseconds,
            preferredEdition: _options.PreferredEdition);

        var response = await SendRequestAsync(request, cancellationToken).ConfigureAwait(false);
        return LegacyWorkerResponseMapper.ToOperationResult<LegacyRuntimeProfilesResult>(response);
    }

    public async Task<OperationResult<LegacyRuntimeSessionResult>> StartRuntimeSessionAsync(
        string repositoryRoot,
        string profileName,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(repositoryRoot))
        {
            return OperationResult<LegacyRuntimeSessionResult>.Failure(
                correlationId,
                new[] { OperationError.Create("LegacyWorker.RepositoryRootRequired", "Repository root is required.") });
        }

        var request = LegacyWorkerRequest.Create(
            correlationId,
            LegacyWorkerKnownOperations.StartRuntimeSession,
            new LegacyRuntimeSessionRequest
            {
                RepositoryRoot = repositoryRoot,
                ProfileName = string.IsNullOrWhiteSpace(profileName) ? "Simulation" : profileName
            },
            _options.TimeoutMilliseconds,
            preferredEdition: _options.PreferredEdition);

        var response = await SendRequestAsync(request, cancellationToken).ConfigureAwait(false);
        return LegacyWorkerResponseMapper.ToOperationResult<LegacyRuntimeSessionResult>(response);
    }

    public async Task<OperationResult<LegacyRuntimeShutdownResult>> StopRuntimeSessionAsync(
        string repositoryRoot,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(repositoryRoot))
        {
            return OperationResult<LegacyRuntimeShutdownResult>.Failure(
                correlationId,
                new[] { OperationError.Create("LegacyWorker.RepositoryRootRequired", "Repository root is required.") });
        }

        var request = LegacyWorkerRequest.Create(
            correlationId,
            LegacyWorkerKnownOperations.StopRuntimeSession,
            new LegacyRuntimeSessionRequest { RepositoryRoot = repositoryRoot },
            _options.TimeoutMilliseconds,
            preferredEdition: _options.PreferredEdition);

        var response = await SendRequestAsync(request, cancellationToken).ConfigureAwait(false);
        return LegacyWorkerResponseMapper.ToOperationResult<LegacyRuntimeShutdownResult>(response);
    }

    private async Task<LegacyWorkerResponse> SendRequestAsync(
        LegacyWorkerRequest request,
        CancellationToken cancellationToken)
    {
        using var process = StartWorker();
        try
        {
            var handshake = new LegacyWorkerHandshakeRequest { ClientName = nameof(LegacyPowerShellWorkerClient) };
            await WriteLineAsync(process, handshake, cancellationToken).ConfigureAwait(false);
            var handshakeLine = await ReadLineWithTimeoutAsync(process, TimeSpan.FromMilliseconds(_options.TimeoutMilliseconds), cancellationToken)
                .ConfigureAwait(false);
            var handshakeResponse = JsonSerializer.Deserialize<LegacyWorkerHandshakeResponse>(handshakeLine, LegacyWorkerProtocol.JsonOptions);
            if (handshakeResponse is null || !handshakeResponse.Accepted)
            {
                return LegacyWorkerResponse.Failure(
                    request.CorrelationId,
                    request.Operation,
                    new[] { OperationError.Create("LegacyWorker.HandshakeFailed", handshakeResponse?.Message ?? "Legacy worker handshake failed.") });
            }

            await WriteLineAsync(process, request, cancellationToken).ConfigureAwait(false);
            var responseLine = await ReadLineWithTimeoutAsync(process, TimeSpan.FromMilliseconds(request.TimeoutMilliseconds), cancellationToken)
                .ConfigureAwait(false);
            return JsonSerializer.Deserialize<LegacyWorkerResponse>(responseLine, LegacyWorkerProtocol.JsonOptions)
                ?? LegacyWorkerResponse.Failure(
                    request.CorrelationId,
                    request.Operation,
                    new[] { OperationError.Create("LegacyWorker.ResponseInvalid", "Legacy worker returned an empty response.") });
        }
        catch (OperationCanceledException)
        {
            KillProcessTree(process);
            return LegacyWorkerResponse.Failure(
                request.CorrelationId,
                request.Operation,
                new[] { OperationError.Create("LegacyWorker.Cancelled", "Legacy worker request was cancelled.") },
                status: "Cancelled");
        }
        catch (Exception ex)
        {
            KillProcessTree(process);
            return LegacyWorkerResponse.Failure(
                request.CorrelationId,
                request.Operation,
                new[] { OperationError.Create("LegacyWorker.ClientFailed", "Legacy worker client failed.", diagnosticDetail: ex.Message) });
        }
        finally
        {
            if (!process.HasExited)
            {
                KillProcessTree(process);
            }
        }
    }

    private Process StartWorker()
    {
        var process = Process.Start(new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = $"\"{_options.WorkerPath}\"",
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        });

        return process ?? throw new InvalidOperationException("Failed to start legacy worker process.");
    }

    private static async Task WriteLineAsync<T>(Process process, T value, CancellationToken cancellationToken)
    {
        await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(value, LegacyWorkerProtocol.JsonOptions).AsMemory(), cancellationToken)
            .ConfigureAwait(false);
        await process.StandardInput.FlushAsync(cancellationToken).ConfigureAwait(false);
    }

    private static async Task<string> ReadLineWithTimeoutAsync(
        Process process,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout);

        var line = await process.StandardOutput.ReadLineAsync(timeoutSource.Token).ConfigureAwait(false);
        if (line is null)
        {
            var stderr = await process.StandardError.ReadToEndAsync(cancellationToken).ConfigureAwait(false);
            throw new InvalidOperationException($"Legacy worker closed stdout before responding. stderr: {stderr}");
        }

        return line;
    }

    private static void KillProcessTree(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // Process cleanup is best effort after cancellation/failure.
        }
    }
}
