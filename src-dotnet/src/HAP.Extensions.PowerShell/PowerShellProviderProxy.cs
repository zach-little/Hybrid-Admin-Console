using System.Diagnostics;
using System.Text.Json;
using HAP.Contracts;
using HAP.Extensions.Registry;
using HAP.Plugin.Protocol;

namespace HAP.Extensions.PowerShell;

public sealed class PowerShellProviderProxy : IPowerShellProviderProxy
{
    private readonly ExtensionRegistryEntry _entry;
    private readonly PowerShellProviderProxyOptions _options;

    public PowerShellProviderProxy(ExtensionRegistryEntry entry, PowerShellProviderProxyOptions options)
    {
        _entry = entry ?? throw new ArgumentNullException(nameof(entry));
        _options = options ?? throw new ArgumentNullException(nameof(options));
    }

    public async Task<OperationResult<HapPluginProviderMetadata>> GetMetadataAsync(
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var preflight = ValidateLaunch(correlationId);
        if (preflight is not null)
        {
            return OperationResult<HapPluginProviderMetadata>.Failure(correlationId, preflight);
        }

        var result = await WithHostAsync(
            correlationId,
            async process =>
            {
                await WriteAsync(process, new HapPluginProviderRequest
                {
                    Kind = HapPluginMessageKind.MetadataRequest,
                    CorrelationId = correlationId,
                    ProviderId = _entry.Manifest.ProviderId
                }, cancellationToken).ConfigureAwait(false);
                var response = JsonSerializer.Deserialize<HapPluginMetadataResponse>(
                    await ReadLineWithTimeoutAsync(process, cancellationToken).ConfigureAwait(false),
                    HapPluginProtocol.JsonOptions);
                return response is { Succeeded: true, Metadata: not null }
                    ? OperationResult<HapPluginProviderMetadata>.Success(response.Metadata, correlationId)
                    : OperationResult<HapPluginProviderMetadata>.Failure(
                        correlationId,
                        response?.Errors.Count > 0 ? response.Errors : new[] { OperationError.Create("PowerShellProxy.MetadataFailed", "Plugin metadata request failed.") });
            },
            cancellationToken).ConfigureAwait(false);

        return result;
    }

    public async Task<OperationResult<HapPluginHealthResponse>> TestConnectionAsync(
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var preflight = ValidateLaunch(correlationId);
        if (preflight is not null)
        {
            return OperationResult<HapPluginHealthResponse>.Failure(correlationId, preflight);
        }

        return await WithHostAsync(
            correlationId,
            async process =>
            {
                await WriteAsync(process, new HapPluginProviderRequest
                {
                    Kind = HapPluginMessageKind.HealthRequest,
                    CorrelationId = correlationId,
                    ProviderId = _entry.Manifest.ProviderId
                }, cancellationToken).ConfigureAwait(false);
                var response = JsonSerializer.Deserialize<HapPluginHealthResponse>(
                    await ReadLineWithTimeoutAsync(process, cancellationToken).ConfigureAwait(false),
                    HapPluginProtocol.JsonOptions);
                return response is { Succeeded: true }
                    ? OperationResult<HapPluginHealthResponse>.Success(response, correlationId)
                    : OperationResult<HapPluginHealthResponse>.Failure(
                        correlationId,
                        response?.Errors.Count > 0 ? response.Errors : new[] { OperationError.Create("PowerShellProxy.HealthFailed", "Plugin health request failed.") });
            },
            cancellationToken).ConfigureAwait(false);
    }

    public async Task<OperationResult<JsonElement>> InvokeOperationAsync(
        string capabilityId,
        string operation,
        JsonElement payload,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var preflight = ValidateOperation(capabilityId, operation, correlationId);
        if (preflight is not null)
        {
            return OperationResult<JsonElement>.Failure(correlationId, preflight);
        }

        return await WithHostAsync(
            correlationId,
            async process =>
            {
                await WriteAsync(process, new HapPluginOperationRequest
                {
                    CorrelationId = correlationId,
                    ProviderId = _entry.Manifest.ProviderId,
                    CapabilityId = capabilityId,
                    Operation = operation,
                    TimeoutMilliseconds = _options.TimeoutMilliseconds,
                    Payload = payload
                }, cancellationToken).ConfigureAwait(false);
                var response = JsonSerializer.Deserialize<HapPluginOperationResponse>(
                    await ReadLineWithTimeoutAsync(process, cancellationToken).ConfigureAwait(false),
                    HapPluginProtocol.JsonOptions);

                if (response is { Succeeded: true } && response.Data.HasValue)
                {
                    return OperationResult<JsonElement>.Success(response.Data.Value, correlationId, response.Warnings, response.Status);
                }

                return OperationResult<JsonElement>.Failure(
                    correlationId,
                    response?.Errors.Count > 0 ? response.Errors : new[] { OperationError.Create("PowerShellProxy.OperationFailed", "Plugin operation failed.") },
                    response?.Warnings,
                    response?.Status);
            },
            cancellationToken).ConfigureAwait(false);
    }

    private async Task<OperationResult<T>> WithHostAsync<T>(
        CorrelationId correlationId,
        Func<Process, Task<OperationResult<T>>> action,
        CancellationToken cancellationToken)
    {
        if (!File.Exists(_options.PluginHostPath))
        {
            return OperationResult<T>.Failure(
                correlationId,
                new[] { OperationError.Create("PowerShellProxy.HostMissing", "PowerShell plugin host was not found.", _options.PluginHostPath) });
        }

        using var process = StartHost();
        try
        {
            await WriteAsync(process, new HapPluginHandshakeRequest
            {
                CorrelationId = correlationId,
                ClientName = nameof(PowerShellProviderProxy),
                ProviderId = _entry.Manifest.ProviderId,
                ManifestPath = _entry.ManifestPath
            }, cancellationToken).ConfigureAwait(false);

            var handshake = JsonSerializer.Deserialize<HapPluginHandshakeResponse>(
                await ReadLineWithTimeoutAsync(process, cancellationToken).ConfigureAwait(false),
                HapPluginProtocol.JsonOptions);
            if (handshake is not { Accepted: true })
            {
                return OperationResult<T>.Failure(
                    correlationId,
                    new[] { OperationError.Create("PowerShellProxy.HandshakeFailed", handshake?.Message ?? "Plugin host handshake failed.") });
            }

            var result = await action(process).ConfigureAwait(false);
            await WriteAsync(process, new HapPluginShutdownRequest { CorrelationId = correlationId }, cancellationToken).ConfigureAwait(false);
            _ = await ReadLineWithTimeoutAsync(process, cancellationToken).ConfigureAwait(false);
            return result;
        }
        catch (Exception ex)
        {
            return OperationResult<T>.Failure(
                correlationId,
                new[] { OperationError.Create("PowerShellProxy.InvocationFailed", "PowerShell provider proxy invocation failed.", diagnosticDetail: ex.Message) });
        }
        finally
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
    }

    private IReadOnlyList<OperationError>? ValidateOperation(
        string capabilityId,
        string operation,
        CorrelationId correlationId)
    {
        var launch = ValidateLaunch(correlationId);
        if (launch is not null)
        {
            return launch;
        }

        if (!_entry.GrantedCapabilities.Contains(capabilityId, StringComparer.OrdinalIgnoreCase))
        {
            return new[] { OperationError.Create("PowerShellProxy.CapabilityNotGranted", "Capability is not granted for this provider.", capabilityId) };
        }

        var capability = _entry.Manifest.Capabilities.FirstOrDefault(item => string.Equals(item.Id, capabilityId, StringComparison.OrdinalIgnoreCase));
        if (capability is null || !capability.Operations.Contains(operation, StringComparer.OrdinalIgnoreCase))
        {
            return new[] { OperationError.Create("PowerShellProxy.OperationNotDeclared", "Operation is not declared by the provider manifest.", operation) };
        }

        return null;
    }

    private IReadOnlyList<OperationError>? ValidateLaunch(CorrelationId correlationId)
    {
        _ = correlationId;
        if (!_entry.Enabled)
        {
            return new[] { OperationError.Create("PowerShellProxy.ProviderDisabled", "PowerShell provider is disabled.", _entry.Manifest.ProviderId) };
        }

        return null;
    }

    private Process StartHost()
    {
        var process = Process.Start(new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = $"\"{_options.PluginHostPath}\"",
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        });

        return process ?? throw new InvalidOperationException("Failed to start PowerShell plugin host.");
    }

    private async Task<string> ReadLineWithTimeoutAsync(Process process, CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(_options.TimeoutMilliseconds);
        var line = await process.StandardOutput.ReadLineAsync(timeout.Token).ConfigureAwait(false);
        if (line is null)
        {
            var stderr = await process.StandardError.ReadToEndAsync(cancellationToken).ConfigureAwait(false);
            throw new InvalidOperationException($"Plugin host closed stdout before responding. stderr: {stderr}");
        }

        return line;
    }

    private static async Task WriteAsync<T>(Process process, T message, CancellationToken cancellationToken)
    {
        await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(message, HapPluginProtocol.JsonOptions).AsMemory(), cancellationToken)
            .ConfigureAwait(false);
        await process.StandardInput.FlushAsync(cancellationToken).ConfigureAwait(false);
    }
}
