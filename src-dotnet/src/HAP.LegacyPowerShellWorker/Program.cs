using System.Diagnostics;
using System.Text;
using System.Text.Json;
using HAP.Contracts;
using HAP.LegacyWorker.Protocol;

namespace HAP.LegacyPowerShellWorker;

public static class Program
{
    private const string WorkerName = "HAP.LegacyPowerShellWorker";
    private const string WorkerVersion = "0.1.0";

    private static readonly string[] SupportedOperations =
    {
        LegacyWorkerKnownOperations.GetRuntimeProfiles,
        LegacyWorkerKnownOperations.StartRuntimeSession,
        LegacyWorkerKnownOperations.StopRuntimeSession
    };

    public static async Task<int> Main()
    {
        await foreach (var line in Console.In.ReadLinesAsync())
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var output = await HandleMessageAsync(line, CancellationToken.None).ConfigureAwait(false);
            await Console.Out.WriteLineAsync(output).ConfigureAwait(false);
            await Console.Out.FlushAsync().ConfigureAwait(false);
        }

        return 0;
    }

    internal static async Task<string> HandleMessageAsync(string json, CancellationToken cancellationToken)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var kind = document.RootElement.GetProperty(nameof(LegacyWorkerRequest.Kind)).Deserialize<LegacyWorkerMessageKind>(LegacyWorkerProtocol.JsonOptions);

            return kind switch
            {
                LegacyWorkerMessageKind.HandshakeRequest => Serialize(CreateHandshakeResponse(document.RootElement)),
                LegacyWorkerMessageKind.OperationRequest => Serialize(await ExecuteOperationAsync(document.RootElement, cancellationToken).ConfigureAwait(false)),
                LegacyWorkerMessageKind.ShutdownRequest => Serialize(new
                {
                    ProtocolVersion = LegacyWorkerProtocol.Version,
                    Kind = LegacyWorkerMessageKind.ShutdownResponse,
                    Accepted = true
                }),
                _ => Serialize(LegacyWorkerResponse.Failure(
                    CorrelationId.New(),
                    "Unknown",
                    new[] { OperationError.Create("LegacyWorker.UnsupportedMessage", $"Unsupported worker message kind '{kind}'.") }))
            };
        }
        catch (Exception ex)
        {
            var failure = LegacyWorkerResponse.Failure(
                CorrelationId.New(),
                "Unknown",
                new[] { OperationError.Create("LegacyWorker.MessageFailed", "Worker failed to process the message.", diagnosticDetail: ex.Message) });
            return Serialize(failure);
        }
    }

    private static LegacyWorkerHandshakeResponse CreateHandshakeResponse(JsonElement root)
    {
        var request = root.Deserialize<LegacyWorkerHandshakeRequest>(LegacyWorkerProtocol.JsonOptions);
        var accepted = request is not null &&
                       request.SupportedProtocolVersions.Contains(LegacyWorkerProtocol.Version, StringComparer.OrdinalIgnoreCase);

        return new LegacyWorkerHandshakeResponse
        {
            Accepted = accepted,
            WorkerName = WorkerName,
            WorkerVersion = WorkerVersion,
            Edition = LegacyPowerShellEdition.PowerShell7,
            SupportedOperations = SupportedOperations,
            Message = accepted ? "Ready" : "Unsupported protocol version."
        };
    }

    private static async Task<LegacyWorkerResponse> ExecuteOperationAsync(JsonElement root, CancellationToken cancellationToken)
    {
        var request = root.Deserialize<LegacyWorkerRequest>(LegacyWorkerProtocol.JsonOptions);
        if (request is null)
        {
            return LegacyWorkerResponse.Failure(
                CorrelationId.New(),
                "Unknown",
                new[] { OperationError.Create("LegacyWorker.InvalidRequest", "Worker request could not be deserialized.") });
        }

        if (!SupportedOperations.Contains(request.Operation, StringComparer.OrdinalIgnoreCase))
        {
            return LegacyWorkerResponse.Failure(
                request.CorrelationId,
                request.Operation,
                new[] { OperationError.Create("LegacyWorker.UnsupportedOperation", $"Unsupported legacy operation '{request.Operation}'.") });
        }

        var repositoryRoot = ResolveRepositoryRoot(request);
        if (string.IsNullOrWhiteSpace(repositoryRoot))
        {
            return LegacyWorkerResponse.Failure(
                request.CorrelationId,
                request.Operation,
                new[] { OperationError.Create("LegacyWorker.InvalidPayload", $"{request.Operation} requires RepositoryRoot.") });
        }

        return await InvokeBridgeAsync(request, repositoryRoot, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<LegacyWorkerResponse> InvokeBridgeAsync(
        LegacyWorkerRequest request,
        string repositoryRoot,
        CancellationToken cancellationToken)
    {
        var executable = request.PreferredEdition == LegacyPowerShellEdition.WindowsPowerShell51 ? "powershell.exe" : "pwsh.exe";
        var bridgePath = Path.Combine(repositoryRoot, "src", "Compatibility", "HAP.LegacyBridge.psm1");
        if (!File.Exists(bridgePath))
        {
            return LegacyWorkerResponse.Failure(
                request.CorrelationId,
                request.Operation,
                new[] { OperationError.Create("LegacyWorker.BridgeMissing", "Legacy bridge module was not found.", bridgePath) });
        }

        var bridgeCommand = CreateBridgeCommand(request, repositoryRoot);
        var command = string.Join(
            "; ",
            "$ErrorActionPreference='Stop'",
            $"Import-Module -Name '{EscapePowerShellString(bridgePath)}' -Force",
            $"{bridgeCommand} | ConvertTo-Json -Depth 12 -Compress");

        using var process = new Process();
        process.StartInfo = new ProcessStartInfo
        {
            FileName = executable,
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"{command.Replace("\"", "\\\"")}\"",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        try
        {
            process.Start();
        }
        catch (Exception ex)
        {
            return LegacyWorkerResponse.Failure(
                request.CorrelationId,
                request.Operation,
                new[] { OperationError.Create("LegacyWorker.PowerShellStartFailed", $"Failed to start '{executable}'.", diagnosticDetail: ex.Message) });
        }

        var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
        var timeoutTask = Task.Delay(request.TimeoutMilliseconds, cancellationToken);
        var exitTask = process.WaitForExitAsync(cancellationToken);
        var completed = await Task.WhenAny(exitTask, timeoutTask).ConfigureAwait(false);

        if (completed == timeoutTask)
        {
            KillProcessTree(process);
            return LegacyWorkerResponse.Failure(
                request.CorrelationId,
                request.Operation,
                new[] { OperationError.Create("LegacyWorker.Timeout", $"Legacy PowerShell operation exceeded {request.TimeoutMilliseconds} ms.") });
        }

        var stdout = await stdoutTask.ConfigureAwait(false);
        var stderr = await stderrTask.ConfigureAwait(false);
        var streams = string.IsNullOrWhiteSpace(stderr)
            ? Array.Empty<LegacyWorkerStreamRecord>()
            : new[] { LegacyWorkerStreamRecord.Create(LegacyWorkerStreamKind.Error, stderr) };

        if (process.ExitCode != 0)
        {
            return LegacyWorkerResponse.Failure(
                request.CorrelationId,
                request.Operation,
                new[] { OperationError.Create("LegacyWorker.PowerShellFailed", $"Legacy PowerShell exited with code {process.ExitCode}.", diagnosticDetail: stderr) },
                streams: streams);
        }

        return ConvertBridgeEnvelope(request, stdout, streams);
    }

    private static LegacyWorkerResponse ConvertBridgeEnvelope(
        LegacyWorkerRequest request,
        string bridgeJson,
        IReadOnlyList<LegacyWorkerStreamRecord> streams)
    {
        try
        {
            using var document = JsonDocument.Parse(bridgeJson);
            var root = document.RootElement;
            var succeeded = root.GetProperty("Succeeded").GetBoolean();
            var status = root.GetProperty("Status").GetString() ?? string.Empty;
            var warnings = root.TryGetProperty("Warnings", out var warningElement)
                ? warningElement.Deserialize<IReadOnlyList<OperationWarning>>(LegacyWorkerProtocol.JsonOptions) ?? Array.Empty<OperationWarning>()
                : Array.Empty<OperationWarning>();
            var errors = root.TryGetProperty("Errors", out var errorElement)
                ? errorElement.Deserialize<IReadOnlyList<OperationError>>(LegacyWorkerProtocol.JsonOptions) ?? Array.Empty<OperationError>()
                : Array.Empty<OperationError>();

            if (!succeeded)
            {
                return LegacyWorkerResponse.Failure(
                    request.CorrelationId,
                    request.Operation,
                    errors.Count == 0
                        ? new[] { OperationError.Create("LegacyWorker.BridgeFailed", "Legacy bridge reported failure without structured errors.") }
                        : errors,
                    warnings,
                    streams,
                    status);
            }

            return new LegacyWorkerResponse
            {
                CorrelationId = request.CorrelationId,
                Operation = request.Operation,
                Succeeded = true,
                Status = status,
                Data = root.GetProperty("Data").Clone(),
                Warnings = warnings,
                Errors = Array.Empty<OperationError>(),
                Streams = streams
            };
        }
        catch (Exception ex)
        {
            return LegacyWorkerResponse.Failure(
                request.CorrelationId,
                request.Operation,
                new[] { OperationError.Create("LegacyWorker.BridgeJsonInvalid", "Legacy bridge returned invalid JSON.", diagnosticDetail: ex.Message) },
                streams: streams);
        }
    }

    private static string Serialize<T>(T value)
    {
        return JsonSerializer.Serialize(value, LegacyWorkerProtocol.JsonOptions);
    }

    private static string ResolveRepositoryRoot(LegacyWorkerRequest request)
    {
        if (!request.Payload.HasValue)
        {
            return string.Empty;
        }

        return request.Operation switch
        {
            LegacyWorkerKnownOperations.GetRuntimeProfiles =>
                request.Payload.Value.Deserialize<LegacyRuntimeProfilesRequest>(LegacyWorkerProtocol.JsonOptions)?.RepositoryRoot ?? string.Empty,
            LegacyWorkerKnownOperations.StartRuntimeSession or LegacyWorkerKnownOperations.StopRuntimeSession =>
                request.Payload.Value.Deserialize<LegacyRuntimeSessionRequest>(LegacyWorkerProtocol.JsonOptions)?.RepositoryRoot ?? string.Empty,
            _ => string.Empty
        };
    }

    private static string CreateBridgeCommand(LegacyWorkerRequest request, string repositoryRoot)
    {
        var escapedRoot = EscapePowerShellString(repositoryRoot);
        var escapedCorrelation = EscapePowerShellString(request.CorrelationId.Value);
        return request.Operation switch
        {
            LegacyWorkerKnownOperations.GetRuntimeProfiles =>
                $"Get-HapRuntimeProfiles -RepositoryRoot '{escapedRoot}' -CorrelationId '{escapedCorrelation}'",
            LegacyWorkerKnownOperations.StopRuntimeSession =>
                $"Stop-HapRuntimeSession -RepositoryRoot '{escapedRoot}' -CorrelationId '{escapedCorrelation}'",
            LegacyWorkerKnownOperations.StartRuntimeSession =>
                CreateStartRuntimeCommand(request, escapedRoot, escapedCorrelation),
            _ => throw new NotSupportedException($"Unsupported operation '{request.Operation}'.")
        };
    }

    private static string CreateStartRuntimeCommand(
        LegacyWorkerRequest request,
        string escapedRepositoryRoot,
        string escapedCorrelation)
    {
        var payload = request.Payload?.Deserialize<LegacyRuntimeSessionRequest>(LegacyWorkerProtocol.JsonOptions);
        if (payload is not null && !string.IsNullOrWhiteSpace(payload.ProfilePath))
        {
            return $"Start-HapRuntimeSession -RepositoryRoot '{escapedRepositoryRoot}' -ProfilePath '{EscapePowerShellString(payload.ProfilePath)}' -CorrelationId '{escapedCorrelation}'";
        }

        var profileName = EscapePowerShellString(payload?.ProfileName ?? "Simulation");
        return $"Start-HapRuntimeSession -RepositoryRoot '{escapedRepositoryRoot}' -ProfileName '{profileName}' -CorrelationId '{escapedCorrelation}'";
    }

    private static string EscapePowerShellString(string value)
    {
        return value.Replace("'", "''", StringComparison.Ordinal);
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
            // Best effort cleanup after timeout/cancellation.
        }
    }
}

internal static class TextReaderExtensions
{
    public static async IAsyncEnumerable<string> ReadLinesAsync(this TextReader reader)
    {
        while (await reader.ReadLineAsync().ConfigureAwait(false) is { } line)
        {
            yield return line;
        }
    }
}
