using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using HAP.Contracts;
using HAP.Extensions.Abstractions;
using HAP.Plugin.Protocol;

namespace HAP.PowerShellPluginHost;

public static class Program
{
    private const string HostName = "HAP.PowerShellPluginHost";
    private const string HostVersion = "0.1.0";
    private static readonly JsonSerializerOptions ManifestJsonOptions = CreateManifestJsonOptions();
    private static HostContext? _context;

    public static async Task<int> Main()
    {
        await foreach (var line in Console.In.ReadLinesAsync())
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var response = await HandleMessageAsync(line, CancellationToken.None).ConfigureAwait(false);
            await Console.Out.WriteLineAsync(response).ConfigureAwait(false);
            await Console.Out.FlushAsync().ConfigureAwait(false);
        }

        return 0;
    }

    internal static async Task<string> HandleMessageAsync(string json, CancellationToken cancellationToken)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var kind = document.RootElement.GetProperty("kind").Deserialize<HapPluginMessageKind>(HapPluginProtocol.JsonOptions);
            return kind switch
            {
                HapPluginMessageKind.HandshakeRequest => Serialize(HandleHandshake(document.RootElement)),
                HapPluginMessageKind.MetadataRequest => Serialize(HandleMetadata(document.RootElement)),
                HapPluginMessageKind.HealthRequest => Serialize(await HandleHealthAsync(document.RootElement, cancellationToken).ConfigureAwait(false)),
                HapPluginMessageKind.OperationRequest => Serialize(await HandleOperationAsync(document.RootElement, cancellationToken).ConfigureAwait(false)),
                HapPluginMessageKind.ShutdownRequest => Serialize(HandleShutdown(document.RootElement)),
                HapPluginMessageKind.CancellationRequest => Serialize(new HapPluginAcknowledgement
                {
                    Kind = HapPluginMessageKind.CancellationResponse,
                    CorrelationId = ReadCorrelationId(document.RootElement),
                    Accepted = true,
                    Message = "Cancellation acknowledged."
                }),
                _ => Serialize(Failure(ReadCorrelationId(document.RootElement), string.Empty, string.Empty, string.Empty, "PluginHost.UnsupportedMessage", $"Unsupported message kind '{kind}'."))
            };
        }
        catch (Exception ex)
        {
            return Serialize(Failure(CorrelationId.New(), string.Empty, string.Empty, string.Empty, "PluginHost.MessageFailed", "Plugin host failed to process the message.", ex.Message));
        }
    }

    private static HapPluginHandshakeResponse HandleHandshake(JsonElement root)
    {
        var request = root.Deserialize<HapPluginHandshakeRequest>(HapPluginProtocol.JsonOptions);
        if (request is null)
        {
            return new HapPluginHandshakeResponse
            {
                CorrelationId = CorrelationId.New(),
                Accepted = false,
                HostName = HostName,
                HostVersion = HostVersion,
                Message = "Handshake request could not be deserialized."
            };
        }

        if (!string.Equals(request.ProtocolVersion, HapPluginProtocol.Version, StringComparison.OrdinalIgnoreCase))
        {
            return HandshakeRejected(request, "Unsupported plugin protocol version.");
        }

        var manifestPath = Path.GetFullPath(request.ManifestPath);
        if (!File.Exists(manifestPath))
        {
            return HandshakeRejected(request, "Manifest path was not found.");
        }

        var manifest = JsonSerializer.Deserialize<HapExtensionManifest>(File.ReadAllText(manifestPath), ManifestJsonOptions);
        if (manifest is null)
        {
            return HandshakeRejected(request, "Manifest could not be deserialized.");
        }

        if (!string.Equals(manifest.ProviderId, request.ProviderId, StringComparison.OrdinalIgnoreCase))
        {
            return HandshakeRejected(request, "Manifest provider ID does not match requested provider ID.");
        }

        if (manifest.Implementation != HapProviderImplementationKind.PowerShell)
        {
            return HandshakeRejected(request, "PowerShell plugin host can only load PowerShell extension manifests.");
        }

        var validation = new HapExtensionManifestValidator().Validate(manifest, request.CorrelationId);
        if (!validation.Succeeded)
        {
            return HandshakeRejected(request, string.Join("; ", validation.Errors.Select(error => error.Message)));
        }

        var modulePath = ResolveModulePath(manifestPath, manifest.EntryPoint.ModulePath);
        if (!File.Exists(modulePath))
        {
            return HandshakeRejected(request, "Manifest module path was not found.");
        }

        _context = new HostContext(manifestPath, modulePath, manifest);
        return new HapPluginHandshakeResponse
        {
            CorrelationId = request.CorrelationId,
            Accepted = true,
            HostName = HostName,
            HostVersion = HostVersion,
            ProviderId = manifest.ProviderId,
            Message = "Ready"
        };
    }

    private static HapPluginHandshakeResponse HandshakeRejected(HapPluginHandshakeRequest request, string message)
    {
        return new HapPluginHandshakeResponse
        {
            CorrelationId = request.CorrelationId,
            Accepted = false,
            HostName = HostName,
            HostVersion = HostVersion,
            ProviderId = request.ProviderId,
            Message = message
        };
    }

    private static HapPluginMetadataResponse HandleMetadata(JsonElement root)
    {
        var request = root.Deserialize<HapPluginProviderRequest>(HapPluginProtocol.JsonOptions);
        var correlationId = request?.CorrelationId ?? CorrelationId.New();
        if (_context is null)
        {
            return new HapPluginMetadataResponse
            {
                CorrelationId = correlationId,
                Succeeded = false,
                Errors = new[] { OperationError.Create("PluginHost.NotInitialized", "Plugin host handshake has not completed.") }
            };
        }

        if (!IsProviderMatch(request?.ProviderId))
        {
            return new HapPluginMetadataResponse
            {
                CorrelationId = correlationId,
                Succeeded = false,
                Errors = new[] { OperationError.Create("PluginHost.ProviderMismatch", "Requested provider does not match the loaded manifest.") }
            };
        }

        return new HapPluginMetadataResponse
        {
            CorrelationId = correlationId,
            Succeeded = true,
            Metadata = new HapPluginProviderMetadata
            {
                ProviderId = _context.Manifest.ProviderId,
                DisplayName = _context.Manifest.DisplayName,
                Publisher = _context.Manifest.Publisher,
                ProviderVersion = _context.Manifest.ProviderVersion,
                CapabilityIds = _context.Manifest.Capabilities.Select(capability => capability.Id).ToArray()
            }
        };
    }

    private static async Task<HapPluginHealthResponse> HandleHealthAsync(JsonElement root, CancellationToken cancellationToken)
    {
        var request = root.Deserialize<HapPluginProviderRequest>(HapPluginProtocol.JsonOptions);
        var correlationId = request?.CorrelationId ?? CorrelationId.New();
        if (_context is null)
        {
            return new HapPluginHealthResponse
            {
                CorrelationId = correlationId,
                Succeeded = false,
                Status = "NotInitialized",
                Errors = new[] { OperationError.Create("PluginHost.NotInitialized", "Plugin host handshake has not completed.") }
            };
        }

        var response = await InvokePowerShellAsync(
            _context,
            _context.Manifest.Capabilities.First().Id,
            "TestConnection",
            "{}",
            correlationId,
            30000,
            cancellationToken).ConfigureAwait(false);

        return new HapPluginHealthResponse
        {
            CorrelationId = correlationId,
            Succeeded = response.Succeeded,
            Status = response.Succeeded ? "Healthy" : "Failed",
            Message = response.Succeeded ? "Provider responded." : string.Join("; ", response.Errors.Select(error => error.Message)),
            Errors = response.Errors
        };
    }

    private static async Task<HapPluginOperationResponse> HandleOperationAsync(JsonElement root, CancellationToken cancellationToken)
    {
        var request = root.Deserialize<HapPluginOperationRequest>(HapPluginProtocol.JsonOptions);
        if (request is null)
        {
            return Failure(CorrelationId.New(), string.Empty, string.Empty, string.Empty, "PluginHost.InvalidRequest", "Operation request could not be deserialized.");
        }

        if (_context is null)
        {
            return Failure(request.CorrelationId, request.ProviderId, request.CapabilityId, request.Operation, "PluginHost.NotInitialized", "Plugin host handshake has not completed.");
        }

        if (!IsProviderMatch(request.ProviderId))
        {
            return Failure(request.CorrelationId, request.ProviderId, request.CapabilityId, request.Operation, "PluginHost.ProviderMismatch", "Requested provider does not match the loaded manifest.");
        }

        var capability = _context.Manifest.Capabilities.FirstOrDefault(capability => string.Equals(capability.Id, request.CapabilityId, StringComparison.OrdinalIgnoreCase));
        if (capability is null || !capability.Operations.Contains(request.Operation, StringComparer.OrdinalIgnoreCase))
        {
            return Failure(request.CorrelationId, request.ProviderId, request.CapabilityId, request.Operation, "PluginHost.OperationNotDeclared", "Requested operation is not declared by the manifest capability.");
        }

        var payloadJson = request.Payload.HasValue ? request.Payload.Value.GetRawText() : "{}";
        return await InvokePowerShellAsync(_context, request.CapabilityId, request.Operation, payloadJson, request.CorrelationId, request.TimeoutMilliseconds, cancellationToken)
            .ConfigureAwait(false);
    }

    private static HapPluginAcknowledgement HandleShutdown(JsonElement root)
    {
        var correlationId = ReadCorrelationId(root);
        _context = null;
        return new HapPluginAcknowledgement
        {
            Kind = HapPluginMessageKind.ShutdownResponse,
            CorrelationId = correlationId,
            Accepted = true,
            Message = "Shutdown complete."
        };
    }

    private static async Task<HapPluginOperationResponse> InvokePowerShellAsync(
        HostContext context,
        string capabilityId,
        string operation,
        string payloadJson,
        CorrelationId correlationId,
        int timeoutMilliseconds,
        CancellationToken cancellationToken)
    {
        var payloadPath = Path.Combine(Path.GetTempPath(), $"hap-plugin-payload-{Guid.NewGuid():N}.json");
        await File.WriteAllTextAsync(payloadPath, payloadJson, cancellationToken).ConfigureAwait(false);
        try
        {
            var command = string.Join(
                "; ",
                "$ErrorActionPreference='Stop'",
                $"Import-Module -Name '{EscapePowerShellString(context.ModulePath)}' -Force",
                $"$payload = Get-Content -LiteralPath '{EscapePowerShellString(payloadPath)}' -Raw",
                $"Invoke-HapProviderOperation -ProviderId '{EscapePowerShellString(context.Manifest.ProviderId)}' -CapabilityId '{EscapePowerShellString(capabilityId)}' -Operation '{EscapePowerShellString(operation)}' -PayloadJson $payload | ConvertTo-Json -Depth 12 -Compress");

            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "pwsh.exe",
                    Arguments = $"-NoProfile -Command \"{command.Replace("\"", "\\\"", StringComparison.Ordinal)}\"",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    StandardOutputEncoding = Encoding.UTF8,
                    StandardErrorEncoding = Encoding.UTF8
                }
            };

            process.Start();
            var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
            var exitTask = process.WaitForExitAsync(cancellationToken);
            var timeoutTask = Task.Delay(timeoutMilliseconds, cancellationToken);
            var completed = await Task.WhenAny(exitTask, timeoutTask).ConfigureAwait(false);
            if (completed == timeoutTask)
            {
                KillProcessTree(process);
                return Failure(correlationId, context.Manifest.ProviderId, capabilityId, operation, "PluginHost.OperationTimeout", "Provider operation timed out.");
            }

            var stdout = await stdoutTask.ConfigureAwait(false);
            var stderr = await stderrTask.ConfigureAwait(false);
            if (process.ExitCode != 0)
            {
                return Failure(correlationId, context.Manifest.ProviderId, capabilityId, operation, "PluginHost.PowerShellFailed", "Provider PowerShell process failed.", stderr);
            }

            using var document = JsonDocument.Parse(stdout);
            var root = document.RootElement;
            var succeeded = root.TryGetProperty("succeeded", out var succeededProperty) && succeededProperty.GetBoolean();
            return new HapPluginOperationResponse
            {
                CorrelationId = correlationId,
                ProviderId = context.Manifest.ProviderId,
                CapabilityId = capabilityId,
                Operation = operation,
                Succeeded = succeeded,
                Status = succeeded ? "Completed" : "Failed",
                Data = root.TryGetProperty("data", out var data) ? data.Clone() : null,
                Errors = root.TryGetProperty("errors", out var errors)
                    ? errors.Deserialize<IReadOnlyList<OperationError>>(HapPluginProtocol.JsonOptions) ?? Array.Empty<OperationError>()
                    : Array.Empty<OperationError>(),
                Warnings = root.TryGetProperty("warnings", out var warnings)
                    ? warnings.Deserialize<IReadOnlyList<OperationWarning>>(HapPluginProtocol.JsonOptions) ?? Array.Empty<OperationWarning>()
                    : Array.Empty<OperationWarning>()
            };
        }
        catch (Exception ex)
        {
            return Failure(correlationId, context.Manifest.ProviderId, capabilityId, operation, "PluginHost.OperationFailed", "Provider operation failed.", ex.Message);
        }
        finally
        {
            try { File.Delete(payloadPath); }
            catch { }
        }
    }

    private static HapPluginOperationResponse Failure(
        CorrelationId correlationId,
        string providerId,
        string capabilityId,
        string operation,
        string code,
        string message,
        string? diagnosticDetail = null)
    {
        return new HapPluginOperationResponse
        {
            CorrelationId = correlationId,
            ProviderId = providerId,
            CapabilityId = capabilityId,
            Operation = operation,
            Succeeded = false,
            Status = "Failed",
            Errors = new[] { OperationError.Create(code, message, diagnosticDetail: diagnosticDetail) }
        };
    }

    private static CorrelationId ReadCorrelationId(JsonElement root)
    {
        return root.TryGetProperty("correlationId", out var id) && id.ValueKind == JsonValueKind.String
            ? CorrelationId.From(id.GetString()!)
            : CorrelationId.New();
    }

    private static bool IsProviderMatch(string? providerId)
    {
        return _context is not null && string.Equals(_context.Manifest.ProviderId, providerId, StringComparison.OrdinalIgnoreCase);
    }

    private static string ResolveModulePath(string manifestPath, string modulePath)
    {
        return Path.GetFullPath(Path.IsPathRooted(modulePath)
            ? modulePath
            : Path.Combine(Path.GetDirectoryName(manifestPath)!, modulePath));
    }

    private static string EscapePowerShellString(string value)
    {
        return value.Replace("'", "''", StringComparison.Ordinal);
    }

    private static string Serialize<T>(T value)
    {
        return JsonSerializer.Serialize(value, HapPluginProtocol.JsonOptions);
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
        catch { }
    }

    private static JsonSerializerOptions CreateManifestJsonOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };
        options.Converters.Add(new JsonStringEnumConverter());
        return options;
    }

    private sealed record HostContext(string ManifestPath, string ModulePath, HapExtensionManifest Manifest);
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
