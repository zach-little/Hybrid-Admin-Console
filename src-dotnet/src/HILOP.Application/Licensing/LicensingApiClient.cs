using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using HILOP.Contracts;

namespace HILOP.Application.Licensing;

public interface ILicensingApiClient
{
    Task<OperationResult<LicensingApiActivationResponse>> ActivateAsync(
        string installationId,
        LicenseActivationRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);

    Task<OperationResult<LicensingApiRefreshResponse>> RefreshAsync(
        string installationCredential,
        LicenseRefreshRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);

    Task<OperationResult<string>> DeactivateAsync(
        string installationCredential,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default);
}

public sealed class LicensingApiClient : ILicensingApiClient, IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private readonly HttpClient _client;
    private readonly bool _disposeClient;

    public LicensingApiClient(LicensingOptions options, HttpMessageHandler? handler = null)
    {
        if (options.BaseUri.Scheme != Uri.UriSchemeHttps)
        {
            throw new ArgumentException("Licensing API base URL must use HTTPS.", nameof(options));
        }

        _client = handler is null ? new HttpClient() : new HttpClient(handler);
        _disposeClient = true;
        _client.BaseAddress = options.BaseUri;
        _client.Timeout = options.HttpTimeout;
        _client.DefaultRequestHeaders.UserAgent.ParseAdd("HILOP/1.0");
    }

    public async Task<OperationResult<LicensingApiActivationResponse>> ActivateAsync(
        string installationId,
        LicenseActivationRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var body = new
        {
            activation_key = request.ActivationKey,
            installation_id = installationId,
            hostname = request.Hostname,
            version = request.Version,
            display_name = request.DisplayName
        };

        return await SendAsync<LicensingApiActivationResponse>(
            HttpMethod.Post,
            "/api/v1/hilop/activate",
            body,
            bearerToken: null,
            correlationId,
            cancellationToken).ConfigureAwait(false);
    }

    public async Task<OperationResult<LicensingApiRefreshResponse>> RefreshAsync(
        string installationCredential,
        LicenseRefreshRequest request,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        var body = new { hostname = request.Hostname, version = request.Version };
        return await SendAsync<LicensingApiRefreshResponse>(
            HttpMethod.Post,
            "/api/v1/hilop/license/refresh",
            body,
            installationCredential,
            correlationId,
            cancellationToken).ConfigureAwait(false);
    }

    public async Task<OperationResult<string>> DeactivateAsync(
        string installationCredential,
        CorrelationId correlationId,
        CancellationToken cancellationToken = default)
    {
        using var message = new HttpRequestMessage(HttpMethod.Post, "/api/v1/hilop/deactivate");
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", installationCredential);

        try
        {
            using var response = await _client.SendAsync(message, cancellationToken).ConfigureAwait(false);
            if (response.StatusCode == HttpStatusCode.NoContent || response.IsSuccessStatusCode)
            {
                return OperationResult<string>.Success("Installation deactivated.", correlationId, status: "Deactivated");
            }

            var detail = await SafeReadAsync(response, cancellationToken).ConfigureAwait(false);
            return LicensingErrors.Failure<string>(
                correlationId,
                $"Licensing.Api.{(int)response.StatusCode}",
                FriendlyError(response.StatusCode, detail),
                detail);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return LicensingErrors.Failure<string>(correlationId, "Licensing.Api.Timeout", "The licensing service did not respond before the timeout.");
        }
        catch (HttpRequestException ex)
        {
            return LicensingErrors.Failure<string>(correlationId, "Licensing.Api.Unavailable", "The licensing service is unavailable.", ex.Message);
        }
    }

    public void Dispose()
    {
        if (_disposeClient)
        {
            _client.Dispose();
        }
    }

    private async Task<OperationResult<T>> SendAsync<T>(
        HttpMethod method,
        string path,
        object body,
        string? bearerToken,
        CorrelationId correlationId,
        CancellationToken cancellationToken)
    {
        using var message = new HttpRequestMessage(method, path)
        {
            Content = JsonContent.Create(body, options: JsonOptions)
        };

        if (!string.IsNullOrWhiteSpace(bearerToken))
        {
            message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearerToken);
        }

        try
        {
            using var response = await _client.SendAsync(message, cancellationToken).ConfigureAwait(false);
            var text = await SafeReadAsync(response, cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                return LicensingErrors.Failure<T>(
                    correlationId,
                    $"Licensing.Api.{(int)response.StatusCode}",
                    FriendlyError(response.StatusCode, text),
                    text);
            }

            var value = JsonSerializer.Deserialize<T>(text, JsonOptions);
            return value is null
                ? LicensingErrors.Failure<T>(correlationId, "Licensing.Api.EmptyResponse", "The licensing service returned an empty response.")
                : OperationResult<T>.Success(value, correlationId, status: "OK");
        }
        catch (JsonException ex)
        {
            return LicensingErrors.Failure<T>(correlationId, "Licensing.Api.MalformedResponse", "The licensing service returned malformed JSON.", ex.Message);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return LicensingErrors.Failure<T>(correlationId, "Licensing.Api.Timeout", "The licensing service did not respond before the timeout.");
        }
        catch (HttpRequestException ex)
        {
            return LicensingErrors.Failure<T>(correlationId, "Licensing.Api.Unavailable", "The licensing service is unavailable.", ex.Message);
        }
    }

    private static async Task<string> SafeReadAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        return response.Content is null ? string.Empty : await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
    }

    private static string FriendlyError(HttpStatusCode statusCode, string detail)
    {
        return statusCode switch
        {
            HttpStatusCode.Unauthorized => "The activation key or installation credential was rejected.",
            HttpStatusCode.Conflict => ExtractDetail(detail) ?? "The licensing request conflicts with the current license state.",
            HttpStatusCode.Forbidden => "The credential is not authorized for HILOP licensing.",
            HttpStatusCode.ServiceUnavailable => "The licensing service is temporarily unavailable.",
            _ => ExtractDetail(detail) ?? "The licensing service returned an error."
        };
    }

    private static string? ExtractDetail(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.TryGetProperty("detail", out var detail) ? detail.GetString() : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
