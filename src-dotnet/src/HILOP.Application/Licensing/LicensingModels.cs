using System.Text.Json;
using System.Text.Json.Serialization;

namespace HILOP.Application.Licensing;

public static class HilopEntitlements
{
    public const string ActiveDirectory = "active_directory";
    public const string EntraId = "entra_id";
    public const string ExchangeOnline = "exchange_online";
    public const string ExchangeOnPremises = "exchange_onprem";
    public const string Automation = "automation";
    public const string AdvancedWorkflows = "advanced_workflows";
    public const string Reporting = "reporting";
    public const string ApiAccess = "api_access";
    public const string ManagedIdentities = "managed_identities";
    public const string Administrators = "administrators";
    public const string Directories = "directories";
}

public enum LicenseState
{
    Unlicensed,
    Trial,
    Active,
    ExpiringSoon,
    GracePeriod,
    Expired,
    Revoked,
    Invalid
}

public sealed record LicensingOptions
{
    public Uri BaseUri { get; init; } = new("https://littleinnovation.tech");

    public TimeSpan HttpTimeout { get; init; } = TimeSpan.FromSeconds(30);

    public TimeSpan RefreshInterval { get; init; } = TimeSpan.FromHours(24);

    public TimeSpan ExpiringSoonWindow { get; init; } = TimeSpan.FromDays(14);

    public string ProductCode { get; init; } = "HILOP";

    public string LicenseSchema { get; init; } = "hilop-license/v1";

    public string InstallationDisplayName { get; init; } = "HILOP";

    public string StorageDirectory { get; init; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        "Little Innovation Tech",
        "HILOP",
        "Licensing");

    public IReadOnlyDictionary<string, string> TrustedPublicKeys { get; init; } =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["lit-hilop-2026-01"] = "EShwwr6DqojApPGzmR1pHQ0tyRt1w3DJ_Io-vOfTDaw"
        };
}

public sealed record LicenseEnvelope
{
    [JsonPropertyName("document_id")]
    public string DocumentId { get; init; } = string.Empty;

    [JsonPropertyName("payload")]
    public JsonElement? Payload { get; init; }

    [JsonPropertyName("payload_b64")]
    public string PayloadBase64 { get; init; } = string.Empty;

    [JsonPropertyName("signature")]
    public string Signature { get; init; } = string.Empty;

    [JsonPropertyName("algorithm")]
    public string Algorithm { get; init; } = string.Empty;

    [JsonPropertyName("key_id")]
    public string KeyId { get; init; } = string.Empty;
}

public sealed record LicensePayload
{
    [JsonPropertyName("schema")]
    public string Schema { get; init; } = string.Empty;

    [JsonPropertyName("license_id")]
    public string LicenseId { get; init; } = string.Empty;

    [JsonPropertyName("license_number")]
    public string LicenseNumber { get; init; } = string.Empty;

    [JsonPropertyName("installation_id")]
    public string InstallationId { get; init; } = string.Empty;

    [JsonPropertyName("product")]
    public string Product { get; init; } = string.Empty;

    [JsonPropertyName("organization")]
    public string Organization { get; init; } = string.Empty;

    [JsonPropertyName("license_type")]
    public string LicenseType { get; init; } = string.Empty;

    [JsonPropertyName("edition")]
    public string Edition { get; init; } = string.Empty;

    [JsonPropertyName("status")]
    public string Status { get; init; } = string.Empty;

    [JsonPropertyName("issued_at")]
    public DateTimeOffset? IssuedAt { get; init; }

    [JsonPropertyName("not_before")]
    public DateTimeOffset? NotBefore { get; init; }

    [JsonPropertyName("expires_at")]
    public DateTimeOffset? ExpiresAt { get; init; }

    [JsonPropertyName("grace_until")]
    public DateTimeOffset? GraceUntil { get; init; }

    [JsonPropertyName("maintenance_until")]
    public DateTimeOffset? MaintenanceUntil { get; init; }

    [JsonPropertyName("entitlements")]
    public IReadOnlyDictionary<string, JsonElement> Entitlements { get; init; } =
        new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);

    [JsonPropertyName("signing")]
    public LicenseSigningInfo Signing { get; init; } = new();
}

public sealed record LicenseSigningInfo
{
    [JsonPropertyName("algorithm")]
    public string Algorithm { get; init; } = string.Empty;

    [JsonPropertyName("key_id")]
    public string KeyId { get; init; } = string.Empty;
}

public sealed record VerifiedLicense
{
    public required LicenseEnvelope Envelope { get; init; }

    public required LicensePayload Payload { get; init; }

    public required byte[] VerifiedPayloadBytes { get; init; }

    public required LicenseState State { get; init; }

    public DateTimeOffset ValidatedAtUtc { get; init; } = DateTimeOffset.UtcNow;

    public bool IsOperational =>
        State is LicenseState.Trial or LicenseState.Active or LicenseState.ExpiringSoon or LicenseState.GracePeriod;
}

public sealed record LicensingStatus
{
    public LicenseState State { get; init; } = LicenseState.Unlicensed;

    public string InstallationId { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;

    public VerifiedLicense? License { get; init; }

    public DateTimeOffset? LastSuccessfulValidationUtc { get; init; }

    public bool ServerUnavailable { get; init; }

    public bool IsOperational =>
        (State is LicenseState.Trial or LicenseState.Active or LicenseState.ExpiringSoon or LicenseState.GracePeriod) &&
        License?.IsOperational == true;
}

public sealed record LicenseActivationRequest(
    string ActivationKey,
    string Hostname,
    string Version,
    string? DisplayName = null);

public sealed record LicenseRefreshRequest(string Hostname, string Version);

public sealed record LicensingApiActivationResponse
{
    [JsonPropertyName("success")]
    public bool Success { get; init; }

    [JsonPropertyName("installation_id")]
    public string InstallationId { get; init; } = string.Empty;

    [JsonPropertyName("installation_token")]
    public string InstallationToken { get; init; } = string.Empty;

    [JsonPropertyName("license")]
    public LicenseEnvelope? License { get; init; }
}

public sealed record LicensingApiRefreshResponse
{
    [JsonPropertyName("success")]
    public bool Success { get; init; }

    [JsonPropertyName("license")]
    public LicenseEnvelope? License { get; init; }
}
