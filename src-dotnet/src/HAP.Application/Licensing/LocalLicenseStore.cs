using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HAP.Contracts;

namespace HAP.Application.Licensing;

public interface ILocalLicenseStore
{
    Task<string> GetOrCreateInstallationIdAsync(CancellationToken cancellationToken = default);

    Task<LicenseEnvelope?> LoadLicenseEnvelopeAsync(CancellationToken cancellationToken = default);

    Task SaveLicenseEnvelopeAsync(LicenseEnvelope envelope, CancellationToken cancellationToken = default);

    Task<string?> LoadInstallationCredentialAsync(CancellationToken cancellationToken = default);

    Task SaveInstallationCredentialAsync(string credential, CancellationToken cancellationToken = default);

    Task ClearInstallationCredentialAsync(CancellationToken cancellationToken = default);
}

public sealed class FileLocalLicenseStore : ILocalLicenseStore
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private readonly string _storageDirectory;
    private readonly ISecretProtector _secretProtector;

    public FileLocalLicenseStore(string storageDirectory, ISecretProtector? secretProtector = null)
    {
        _storageDirectory = string.IsNullOrWhiteSpace(storageDirectory)
            ? throw new ArgumentException("Storage directory cannot be empty.", nameof(storageDirectory))
            : storageDirectory;
        _secretProtector = secretProtector ?? new DpapiSecretProtector();
    }

    public async Task<string> GetOrCreateInstallationIdAsync(CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(_storageDirectory);
        var path = InstallationIdPath;
        if (File.Exists(path))
        {
            var existing = (await File.ReadAllTextAsync(path, cancellationToken).ConfigureAwait(false)).Trim();
            if (!string.IsNullOrWhiteSpace(existing))
            {
                return existing;
            }
        }

        var installationId = $"hilop-{Guid.NewGuid():N}";
        await File.WriteAllTextAsync(path, installationId, cancellationToken).ConfigureAwait(false);
        return installationId;
    }

    public async Task<LicenseEnvelope?> LoadLicenseEnvelopeAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(LicensePath))
        {
            return null;
        }

        var json = await File.ReadAllTextAsync(LicensePath, cancellationToken).ConfigureAwait(false);
        return JsonSerializer.Deserialize<LicenseEnvelope>(json);
    }

    public Task SaveLicenseEnvelopeAsync(LicenseEnvelope envelope, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(_storageDirectory);
        return File.WriteAllTextAsync(LicensePath, JsonSerializer.Serialize(envelope, JsonOptions), cancellationToken);
    }

    public async Task<string?> LoadInstallationCredentialAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(CredentialPath))
        {
            return null;
        }

        var protectedText = await File.ReadAllTextAsync(CredentialPath, cancellationToken).ConfigureAwait(false);
        return _secretProtector.Unprotect(protectedText);
    }

    public Task SaveInstallationCredentialAsync(string credential, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(credential))
        {
            throw new ArgumentException("Installation credential cannot be empty.", nameof(credential));
        }

        Directory.CreateDirectory(_storageDirectory);
        return File.WriteAllTextAsync(CredentialPath, _secretProtector.Protect(credential), cancellationToken);
    }

    public Task ClearInstallationCredentialAsync(CancellationToken cancellationToken = default)
    {
        if (File.Exists(CredentialPath))
        {
            File.Delete(CredentialPath);
        }

        return Task.CompletedTask;
    }

    private string InstallationIdPath => Path.Combine(_storageDirectory, "installation.id");

    private string LicensePath => Path.Combine(_storageDirectory, "license-envelope.json");

    private string CredentialPath => Path.Combine(_storageDirectory, "installation-credential.bin");
}

public interface ISecretProtector
{
    string Protect(string secret);

    string Unprotect(string protectedSecret);
}

public sealed class DpapiSecretProtector : ISecretProtector
{
    private const string DpapiPrefix = "dpapi:";
    private const string PlainPrefix = "plain:";

    public string Protect(string secret)
    {
        var bytes = Encoding.UTF8.GetBytes(secret);
        if (OperatingSystem.IsWindows())
        {
            var protectedBytes = ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser);
            return DpapiPrefix + Convert.ToBase64String(protectedBytes);
        }

        return PlainPrefix + Convert.ToBase64String(bytes);
    }

    public string Unprotect(string protectedSecret)
    {
        if (protectedSecret.StartsWith(DpapiPrefix, StringComparison.Ordinal))
        {
            if (!OperatingSystem.IsWindows())
            {
                return string.Empty;
            }

            var bytes = Convert.FromBase64String(protectedSecret[DpapiPrefix.Length..]);
            return Encoding.UTF8.GetString(ProtectedData.Unprotect(bytes, null, DataProtectionScope.CurrentUser));
        }

        if (protectedSecret.StartsWith(PlainPrefix, StringComparison.Ordinal))
        {
            return Encoding.UTF8.GetString(Convert.FromBase64String(protectedSecret[PlainPrefix.Length..]));
        }

        return string.Empty;
    }
}

public interface ILicensingAuditSink
{
    void Record(string eventName, IReadOnlyDictionary<string, string> metadata);
}

public sealed class NullLicensingAuditSink : ILicensingAuditSink
{
    public void Record(string eventName, IReadOnlyDictionary<string, string> metadata)
    {
    }
}

public static class LicensingErrors
{
    public static OperationResult<T> Failure<T>(CorrelationId correlationId, string code, string message, string? detail = null)
    {
        return OperationResult<T>.Failure(
            correlationId,
            new[] { OperationError.Create(code, message, diagnosticDetail: Redact(detail)) },
            status: "Failed");
    }

    public static string Redact(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        return value
            .Replace("installation_token", "installation_credential", StringComparison.OrdinalIgnoreCase)
            .Replace("activation_key", "activation_key_redacted", StringComparison.OrdinalIgnoreCase);
    }
}
