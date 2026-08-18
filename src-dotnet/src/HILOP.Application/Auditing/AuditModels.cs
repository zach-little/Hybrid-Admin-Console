using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace HILOP.Application.Auditing;

public sealed record AuditEvent
{
    public Guid EventId { get; init; } = Guid.NewGuid();
    public DateTimeOffset TimestampUtc { get; init; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? CompletedAtUtc { get; init; }
    public string ProfileId { get; init; } = string.Empty;
    public string SessionId { get; init; } = string.Empty;
    public string CorrelationId { get; init; } = string.Empty;
    public string Category { get; init; } = string.Empty;
    public string EventType { get; init; } = string.Empty;
    public string Action { get; init; } = string.Empty;
    public string Outcome { get; init; } = string.Empty;
    public string Severity { get; init; } = "Information";
    public string ProviderId { get; init; } = string.Empty;
    public string TargetType { get; init; } = string.Empty;
    public string TargetId { get; init; } = string.Empty;
    public string TargetDisplayName { get; init; } = string.Empty;
    public string ActorUserName { get; init; } = string.Empty;
    public string ActorDomain { get; init; } = string.Empty;
    public string ActorIdentity { get; init; } = string.Empty;
    public string MachineName { get; init; } = string.Empty;
    public int ProcessId { get; init; }
    public string ApplicationVersion { get; init; } = string.Empty;
    public long? DurationMs { get; init; }
    public string Message { get; init; } = string.Empty;
    public JsonObject PreviousValues { get; init; } = new();
    public JsonObject NewValues { get; init; } = new();
    public JsonObject Metadata { get; init; } = new();
    public JsonArray Errors { get; init; } = new();
    public JsonArray Warnings { get; init; } = new();
    public string PreviousHash { get; init; } = string.Empty;
    public string EventHash { get; init; } = string.Empty;
}

public sealed record AuditEventRequest
{
    public string CorrelationId { get; init; } = string.Empty;
    public string Category { get; init; } = string.Empty;
    public string EventType { get; init; } = string.Empty;
    public string Action { get; init; } = string.Empty;
    public string Outcome { get; init; } = string.Empty;
    public string Severity { get; init; } = "Information";
    public string ProviderId { get; init; } = string.Empty;
    public string TargetType { get; init; } = string.Empty;
    public string TargetId { get; init; } = string.Empty;
    public string TargetDisplayName { get; init; } = string.Empty;
    public DateTimeOffset? StartedAtUtc { get; init; }
    public DateTimeOffset? CompletedAtUtc { get; init; }
    public string Message { get; init; } = string.Empty;
    public object? PreviousValues { get; init; }
    public object? NewValues { get; init; }
    public object? Metadata { get; init; }
    public IEnumerable<object>? Errors { get; init; }
    public IEnumerable<object>? Warnings { get; init; }
}

public sealed record AuditQuery
{
    public string SearchText { get; init; } = string.Empty;
    public string Category { get; init; } = string.Empty;
    public string Outcome { get; init; } = string.Empty;
    public DateTimeOffset? FromUtc { get; init; }
    public DateTimeOffset? ToUtc { get; init; }
    public int Limit { get; init; } = 1000;
}

public interface IAuditLog
{
    string ProfileId { get; }
    string StorageStatus { get; }
    Task<AuditEvent> WriteAsync(AuditEventRequest request, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<AuditEvent>> QueryAsync(AuditQuery query, CancellationToken cancellationToken = default);
}

public sealed class ProfileAuditLog : IAuditLog
{
    private readonly IAuditStore _store;
    private readonly string _sessionId = Guid.NewGuid().ToString("N");

    public ProfileAuditLog(string profileId, IAuditStore store)
    {
        ProfileId = string.IsNullOrWhiteSpace(profileId) ? "Unknown" : profileId.Trim();
        _store = store;
    }

    public string ProfileId { get; }
    public string StorageStatus => _store.StorageStatus;

    public async Task<AuditEvent> WriteAsync(AuditEventRequest request, CancellationToken cancellationToken = default)
    {
        var started = request.StartedAtUtc ?? DateTimeOffset.UtcNow;
        var completed = request.CompletedAtUtc ?? DateTimeOffset.UtcNow;
        var actor = Environment.UserName;
        var domain = Environment.UserDomainName;
        var value = new AuditEvent
        {
            TimestampUtc = started,
            CompletedAtUtc = completed,
            ProfileId = ProfileId,
            SessionId = _sessionId,
            CorrelationId = request.CorrelationId,
            Category = request.Category,
            EventType = request.EventType,
            Action = request.Action,
            Outcome = request.Outcome,
            Severity = request.Severity,
            ProviderId = request.ProviderId,
            TargetType = request.TargetType,
            TargetId = request.TargetId,
            TargetDisplayName = request.TargetDisplayName,
            ActorUserName = actor,
            ActorDomain = domain,
            ActorIdentity = string.IsNullOrWhiteSpace(domain) ? actor : $"{domain}\\{actor}",
            MachineName = Environment.MachineName,
            ProcessId = Environment.ProcessId,
            ApplicationVersion = typeof(ProfileAuditLog).Assembly.GetName().Version?.ToString() ?? "Unknown",
            DurationMs = Math.Max(0, (long)(completed - started).TotalMilliseconds),
            Message = AuditRedactor.CleanText(request.Message),
            PreviousValues = AuditRedactor.ToObject(request.PreviousValues),
            NewValues = AuditRedactor.ToObject(request.NewValues),
            Metadata = AuditRedactor.ToObject(request.Metadata),
            Errors = AuditRedactor.ToArray(request.Errors),
            Warnings = AuditRedactor.ToArray(request.Warnings)
        };
        return await _store.AppendAsync(value, cancellationToken).ConfigureAwait(false);
    }

    public Task<IReadOnlyList<AuditEvent>> QueryAsync(AuditQuery query, CancellationToken cancellationToken = default) =>
        _store.QueryAsync(ProfileId, query, cancellationToken);
}

public interface IAuditStore
{
    string StorageStatus { get; }
    Task<AuditEvent> AppendAsync(AuditEvent value, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<AuditEvent>> QueryAsync(string profileId, AuditQuery query, CancellationToken cancellationToken = default);
}

internal static class AuditRedactor
{
    private static readonly string[] SensitiveTerms =
    {
        "password", "secret", "token", "credential", "authorization", "recoverykey", "recovery_key",
        "privatekey", "private_key", "clientsecret", "client_secret", "temporarypassword", "unicodepwd",
        "ms-mcs-admpwd", "mslaps-password"
    };

    public static JsonObject ToObject(object? value)
    {
        if (value is null) return new JsonObject();
        var node = JsonSerializer.SerializeToNode(value, JsonOptions) ?? new JsonObject();
        var cleaned = Redact(node, null);
        return cleaned as JsonObject ?? new JsonObject { ["value"] = cleaned };
    }

    public static JsonArray ToArray(IEnumerable<object>? values)
    {
        if (values is null) return new JsonArray();
        var array = new JsonArray();
        foreach (var value in values) array.Add(Redact(JsonSerializer.SerializeToNode(value, JsonOptions), null));
        return array;
    }

    public static string CleanText(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return string.Empty;
        var cleaned = value;
        foreach (var term in SensitiveTerms)
        {
            cleaned = System.Text.RegularExpressions.Regex.Replace(
                cleaned,
                $"(?i)({System.Text.RegularExpressions.Regex.Escape(term)}\\s*[:=]\\s*)[^,;\\s]+",
                "$1[REDACTED]");
        }
        return cleaned.Length <= 16000 ? cleaned : cleaned[..16000] + "…";
    }

    private static JsonNode? Redact(JsonNode? node, string? propertyName)
    {
        if (node is null) return null;
        if (IsSensitive(propertyName)) return JsonValue.Create("[REDACTED]");
        if (node is JsonObject obj)
        {
            var result = new JsonObject();
            foreach (var property in obj) result[property.Key] = Redact(property.Value, property.Key);
            return result;
        }
        if (node is JsonArray array)
        {
            var result = new JsonArray();
            foreach (var item in array) result.Add(Redact(item, propertyName));
            return result;
        }
        if (node is JsonValue jsonValue && jsonValue.TryGetValue<string>(out var text)) return JsonValue.Create(CleanText(text));
        return node.DeepClone();
    }

    private static bool IsSensitive(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return false;
        var normalized = name.Replace("-", string.Empty).Replace("_", string.Empty).ToLowerInvariant();
        if (normalized is "secretkind" or "secretwasreturned" or "passwordlastchanged" or "passwordlastchangeddatetime") return false;
        return SensitiveTerms.Any(term =>
        {
            var sensitive = term.Replace("-", string.Empty).Replace("_", string.Empty).ToLowerInvariant();
            return normalized.Equals(sensitive, StringComparison.Ordinal) ||
                   normalized.EndsWith(sensitive, StringComparison.Ordinal) ||
                   normalized.Contains("clientsecret", StringComparison.Ordinal) ||
                   normalized.Contains("temporarypassword", StringComparison.Ordinal) ||
                   normalized.Contains("recoverykey", StringComparison.Ordinal) ||
                   normalized.Contains("unicodepwd", StringComparison.Ordinal) ||
                   normalized.Contains("admpwd", StringComparison.Ordinal);
        });
    }

    internal static string ComputeHash(AuditEvent value, string previousHash)
    {
        var canonical = string.Join("|", value.EventId, value.TimestampUtc.ToUniversalTime().ToString("O"), value.ProfileId,
            value.SessionId, value.CorrelationId, value.Category, value.EventType, value.Action, value.Outcome,
            value.ProviderId, value.TargetType, value.TargetId, value.ActorIdentity, value.MachineName,
            value.PreviousValues.ToJsonString(), value.NewValues.ToJsonString(), value.Metadata.ToJsonString(),
            value.Errors.ToJsonString(), value.Warnings.ToJsonString(), previousHash);
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(canonical))).ToLowerInvariant();
    }

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
}
