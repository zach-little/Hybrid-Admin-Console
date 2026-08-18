using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using HILOP.Application.Licensing;
using Npgsql;
using NpgsqlTypes;

namespace HILOP.Application.Auditing;

public sealed record AuditStorageOptions
{
    public string StorageDirectory { get; init; } = new LicensingOptions().StorageDirectory;
    public string ConnectionString { get; init; } = string.Empty;
    public string Schema { get; init; } = "hilop_audit";

    public static AuditStorageOptions LoadDefault()
    {
        var baseline = new AuditStorageOptions();
        Directory.CreateDirectory(baseline.StorageDirectory);
        var path = Path.Combine(baseline.StorageDirectory, "audit-postgresql.json");
        var example = Path.Combine(baseline.StorageDirectory, "audit-postgresql.example.json");
        if (!File.Exists(example))
        {
            File.WriteAllText(example, JsonSerializer.Serialize(new
            {
                ConnectionString = "Host=localhost;Port=5432;Database=hilop;Username=hilop_audit;Password=replace-me;SSL Mode=Prefer",
                Schema = "hilop_audit"
            }, new JsonSerializerOptions { WriteIndented = true }));
        }

        AuditStorageOptions configured = baseline;
        if (File.Exists(path))
        {
            configured = JsonSerializer.Deserialize<AuditStorageOptions>(File.ReadAllText(path), new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? baseline;
            configured = configured with { StorageDirectory = baseline.StorageDirectory };
        }
        var environmentConnection = Environment.GetEnvironmentVariable("HILOP_AUDIT_POSTGRES");
        return string.IsNullOrWhiteSpace(environmentConnection) ? configured : configured with { ConnectionString = environmentConnection };
    }
}

public sealed class DurablePostgresAuditStore : IAuditStore
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly AuditStorageOptions _options;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private string _status;

    public DurablePostgresAuditStore(AuditStorageOptions options)
    {
        _options = options;
        Directory.CreateDirectory(_options.StorageDirectory);
        _status = string.IsNullOrWhiteSpace(_options.ConnectionString)
            ? $"Durable local journal; PostgreSQL not configured ({ConfigurationPath})"
            : "Durable local journal with PostgreSQL synchronization";
    }

    public string StorageStatus => _status;
    private string JournalPath => Path.Combine(_options.StorageDirectory, "audit-events.jsonl");
    private string ConfigurationPath => Path.Combine(_options.StorageDirectory, "audit-postgresql.json");

    public async Task<AuditEvent> AppendAsync(AuditEvent value, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var events = await ReadJournalAsync(cancellationToken).ConfigureAwait(false);
            var previousHash = events.LastOrDefault()?.EventHash ?? string.Empty;
            var chained = value with { PreviousHash = previousHash };
            chained = chained with { EventHash = AuditRedactor.ComputeHash(chained, previousHash) };
            await File.AppendAllTextAsync(JournalPath, JsonSerializer.Serialize(chained, JsonOptions) + Environment.NewLine, Encoding.UTF8, cancellationToken).ConfigureAwait(false);
            await TrySynchronizeAsync(events.Append(chained), cancellationToken).ConfigureAwait(false);
            return chained;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<IReadOnlyList<AuditEvent>> QueryAsync(string profileId, AuditQuery query, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var journal = await ReadJournalAsync(cancellationToken).ConfigureAwait(false);
            await TrySynchronizeAsync(journal, cancellationToken).ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(_options.ConnectionString))
            {
                try
                {
                    return await QueryPostgresAsync(profileId, query, cancellationToken).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    _status = $"PostgreSQL unavailable; showing durable local journal ({ex.GetType().Name})";
                }
            }
            return Filter(journal, profileId, query);
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task<List<AuditEvent>> ReadJournalAsync(CancellationToken cancellationToken)
    {
        var result = new List<AuditEvent>();
        if (!File.Exists(JournalPath)) return result;
        var expectedPreviousHash = string.Empty;
        foreach (var line in await File.ReadAllLinesAsync(JournalPath, cancellationToken).ConfigureAwait(false))
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            try
            {
                var value = JsonSerializer.Deserialize<AuditEvent>(line, JsonOptions);
                if (value is not null)
                {
                    var expectedHash = AuditRedactor.ComputeHash(value, expectedPreviousHash);
                    if (!string.Equals(value.PreviousHash, expectedPreviousHash, StringComparison.Ordinal) ||
                        !string.Equals(value.EventHash, expectedHash, StringComparison.Ordinal))
                    {
                        _status = $"Audit journal integrity warning at event {value.EventId}; append is disabled until the journal is reviewed";
                        throw new InvalidDataException($"Audit hash-chain verification failed at event {value.EventId}.");
                    }
                    result.Add(value);
                    expectedPreviousHash = value.EventHash;
                }
            }
            catch (JsonException)
            {
                _status = "Local audit journal contains an unreadable record; valid records are still available";
            }
        }
        return result;
    }

    private async Task TrySynchronizeAsync(IEnumerable<AuditEvent> events, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_options.ConnectionString)) return;
        try
        {
            await using var connection = new NpgsqlConnection(_options.ConnectionString);
            await connection.OpenAsync(cancellationToken).ConfigureAwait(false);
            await EnsureSchemaAsync(connection, cancellationToken).ConfigureAwait(false);
            foreach (var value in events)
            {
                await InsertAsync(connection, value, cancellationToken).ConfigureAwait(false);
            }
            _status = "PostgreSQL synchronized; durable local journal enabled";
        }
        catch (Exception ex)
        {
            _status = $"PostgreSQL synchronization pending; events remain durable locally ({ex.GetType().Name})";
        }
    }

    private async Task EnsureSchemaAsync(NpgsqlConnection connection, CancellationToken cancellationToken)
    {
        var schema = SafeSchema();
        var sql = $"""
            CREATE SCHEMA IF NOT EXISTS "{schema}";
            CREATE TABLE IF NOT EXISTS "{schema}".audit_events (
                event_id uuid PRIMARY KEY, timestamp_utc timestamptz NOT NULL, completed_at_utc timestamptz NULL,
                profile_id text NOT NULL, session_id text NOT NULL, correlation_id text NOT NULL,
                category text NOT NULL, event_type text NOT NULL, action text NOT NULL, outcome text NOT NULL,
                severity text NOT NULL, provider_id text NOT NULL, target_type text NOT NULL, target_id text NOT NULL,
                target_display_name text NOT NULL, actor_user_name text NOT NULL, actor_domain text NOT NULL,
                actor_identity text NOT NULL, machine_name text NOT NULL, process_id integer NOT NULL,
                application_version text NOT NULL, duration_ms bigint NULL, message text NOT NULL,
                previous_values jsonb NOT NULL, new_values jsonb NOT NULL, metadata jsonb NOT NULL,
                errors jsonb NOT NULL, warnings jsonb NOT NULL, previous_hash text NOT NULL, event_hash text NOT NULL,
                ingested_at_utc timestamptz NOT NULL DEFAULT now()
            );
            CREATE INDEX IF NOT EXISTS ix_audit_events_profile_time ON "{schema}".audit_events(profile_id, timestamp_utc DESC);
            CREATE INDEX IF NOT EXISTS ix_audit_events_correlation ON "{schema}".audit_events(correlation_id);
            CREATE INDEX IF NOT EXISTS ix_audit_events_actor ON "{schema}".audit_events(actor_identity);
            CREATE INDEX IF NOT EXISTS ix_audit_events_target ON "{schema}".audit_events(target_type, target_id);
            CREATE OR REPLACE FUNCTION "{schema}".reject_audit_event_mutation() RETURNS trigger AS $function$
            BEGIN
                RAISE EXCEPTION 'HILOP audit events are append-only';
            END;
            $function$ LANGUAGE plpgsql;
            DO $block$
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_hilop_audit_events_append_only' AND tgrelid = '"{schema}".audit_events'::regclass) THEN
                    CREATE TRIGGER trg_hilop_audit_events_append_only
                    BEFORE UPDATE OR DELETE ON "{schema}".audit_events
                    FOR EACH ROW EXECUTE FUNCTION "{schema}".reject_audit_event_mutation();
                END IF;
            END;
            $block$;
            """;
        await using var command = new NpgsqlCommand(sql, connection);
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task InsertAsync(NpgsqlConnection connection, AuditEvent value, CancellationToken cancellationToken)
    {
        var sql = $"""
            INSERT INTO "{SafeSchema()}".audit_events
            (event_id,timestamp_utc,completed_at_utc,profile_id,session_id,correlation_id,category,event_type,action,outcome,severity,
             provider_id,target_type,target_id,target_display_name,actor_user_name,actor_domain,actor_identity,machine_name,process_id,
             application_version,duration_ms,message,previous_values,new_values,metadata,errors,warnings,previous_hash,event_hash)
            VALUES
            (@event_id,@timestamp_utc,@completed_at_utc,@profile_id,@session_id,@correlation_id,@category,@event_type,@action,@outcome,@severity,
             @provider_id,@target_type,@target_id,@target_display_name,@actor_user_name,@actor_domain,@actor_identity,@machine_name,@process_id,
             @application_version,@duration_ms,@message,@previous_values,@new_values,@metadata,@errors,@warnings,@previous_hash,@event_hash)
            ON CONFLICT (event_id) DO NOTHING;
            """;
        await using var command = new NpgsqlCommand(sql, connection);
        Add(command, "event_id", value.EventId); Add(command, "timestamp_utc", value.TimestampUtc); Add(command, "completed_at_utc", value.CompletedAtUtc);
        Add(command, "profile_id", value.ProfileId); Add(command, "session_id", value.SessionId); Add(command, "correlation_id", value.CorrelationId);
        Add(command, "category", value.Category); Add(command, "event_type", value.EventType); Add(command, "action", value.Action); Add(command, "outcome", value.Outcome); Add(command, "severity", value.Severity);
        Add(command, "provider_id", value.ProviderId); Add(command, "target_type", value.TargetType); Add(command, "target_id", value.TargetId); Add(command, "target_display_name", value.TargetDisplayName);
        Add(command, "actor_user_name", value.ActorUserName); Add(command, "actor_domain", value.ActorDomain); Add(command, "actor_identity", value.ActorIdentity); Add(command, "machine_name", value.MachineName); Add(command, "process_id", value.ProcessId);
        Add(command, "application_version", value.ApplicationVersion); Add(command, "duration_ms", value.DurationMs); Add(command, "message", value.Message);
        AddJson(command, "previous_values", value.PreviousValues.ToJsonString()); AddJson(command, "new_values", value.NewValues.ToJsonString()); AddJson(command, "metadata", value.Metadata.ToJsonString());
        AddJson(command, "errors", value.Errors.ToJsonString()); AddJson(command, "warnings", value.Warnings.ToJsonString()); Add(command, "previous_hash", value.PreviousHash); Add(command, "event_hash", value.EventHash);
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task<IReadOnlyList<AuditEvent>> QueryPostgresAsync(string profileId, AuditQuery query, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(_options.ConnectionString);
        await connection.OpenAsync(cancellationToken).ConfigureAwait(false);
        await EnsureSchemaAsync(connection, cancellationToken).ConfigureAwait(false);
        var sql = $"SELECT * FROM \"{SafeSchema()}\".audit_events WHERE profile_id=@profile_id ORDER BY timestamp_utc DESC LIMIT @limit";
        await using var command = new NpgsqlCommand(sql, connection);
        Add(command, "profile_id", profileId); Add(command, "limit", Math.Clamp(query.Limit, 1, 5000));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
        var values = new List<AuditEvent>();
        while (await reader.ReadAsync(cancellationToken).ConfigureAwait(false)) values.Add(Read(reader));
        return Filter(values, profileId, query);
    }

    private static AuditEvent Read(NpgsqlDataReader reader) => new()
    {
        EventId = reader.GetGuid(reader.GetOrdinal("event_id")), TimestampUtc = reader.GetFieldValue<DateTimeOffset>(reader.GetOrdinal("timestamp_utc")),
        CompletedAtUtc = reader.IsDBNull(reader.GetOrdinal("completed_at_utc")) ? null : reader.GetFieldValue<DateTimeOffset>(reader.GetOrdinal("completed_at_utc")),
        ProfileId = reader.GetString(reader.GetOrdinal("profile_id")), SessionId = reader.GetString(reader.GetOrdinal("session_id")), CorrelationId = reader.GetString(reader.GetOrdinal("correlation_id")),
        Category = reader.GetString(reader.GetOrdinal("category")), EventType = reader.GetString(reader.GetOrdinal("event_type")), Action = reader.GetString(reader.GetOrdinal("action")), Outcome = reader.GetString(reader.GetOrdinal("outcome")), Severity = reader.GetString(reader.GetOrdinal("severity")),
        ProviderId = reader.GetString(reader.GetOrdinal("provider_id")), TargetType = reader.GetString(reader.GetOrdinal("target_type")), TargetId = reader.GetString(reader.GetOrdinal("target_id")), TargetDisplayName = reader.GetString(reader.GetOrdinal("target_display_name")),
        ActorUserName = reader.GetString(reader.GetOrdinal("actor_user_name")), ActorDomain = reader.GetString(reader.GetOrdinal("actor_domain")), ActorIdentity = reader.GetString(reader.GetOrdinal("actor_identity")), MachineName = reader.GetString(reader.GetOrdinal("machine_name")), ProcessId = reader.GetInt32(reader.GetOrdinal("process_id")),
        ApplicationVersion = reader.GetString(reader.GetOrdinal("application_version")), DurationMs = reader.IsDBNull(reader.GetOrdinal("duration_ms")) ? null : reader.GetInt64(reader.GetOrdinal("duration_ms")), Message = reader.GetString(reader.GetOrdinal("message")),
        PreviousValues = JsonNode.Parse(reader.GetString(reader.GetOrdinal("previous_values"))) as JsonObject ?? new(), NewValues = JsonNode.Parse(reader.GetString(reader.GetOrdinal("new_values"))) as JsonObject ?? new(), Metadata = JsonNode.Parse(reader.GetString(reader.GetOrdinal("metadata"))) as JsonObject ?? new(),
        Errors = JsonNode.Parse(reader.GetString(reader.GetOrdinal("errors"))) as JsonArray ?? new(), Warnings = JsonNode.Parse(reader.GetString(reader.GetOrdinal("warnings"))) as JsonArray ?? new(), PreviousHash = reader.GetString(reader.GetOrdinal("previous_hash")), EventHash = reader.GetString(reader.GetOrdinal("event_hash"))
    };

    private static IReadOnlyList<AuditEvent> Filter(IEnumerable<AuditEvent> values, string profileId, AuditQuery query)
    {
        var filtered = values.Where(value => value.ProfileId.Equals(profileId, StringComparison.OrdinalIgnoreCase));
        if (!string.IsNullOrWhiteSpace(query.Category)) filtered = filtered.Where(value => value.Category.Equals(query.Category, StringComparison.OrdinalIgnoreCase));
        if (!string.IsNullOrWhiteSpace(query.Outcome)) filtered = filtered.Where(value => value.Outcome.Equals(query.Outcome, StringComparison.OrdinalIgnoreCase));
        if (query.FromUtc is { } from) filtered = filtered.Where(value => value.TimestampUtc >= from);
        if (query.ToUtc is { } to) filtered = filtered.Where(value => value.TimestampUtc <= to);
        if (!string.IsNullOrWhiteSpace(query.SearchText))
        {
            var search = query.SearchText.Trim();
            filtered = filtered.Where(value => string.Join(" ", value.Action, value.EventType, value.ActorIdentity, value.ProviderId, value.TargetId, value.TargetDisplayName, value.Message, value.CorrelationId).Contains(search, StringComparison.OrdinalIgnoreCase));
        }
        return filtered.OrderByDescending(value => value.TimestampUtc).Take(Math.Clamp(query.Limit, 1, 5000)).ToArray();
    }

    private string SafeSchema()
    {
        var schema = string.IsNullOrWhiteSpace(_options.Schema) ? "hilop_audit" : _options.Schema;
        if (!schema.All(character => char.IsLetterOrDigit(character) || character == '_')) throw new InvalidOperationException("Audit schema may contain only letters, digits, and underscores.");
        return schema;
    }

    private static void Add(NpgsqlCommand command, string name, object? value) => command.Parameters.AddWithValue(name, value ?? DBNull.Value);
    private static void AddJson(NpgsqlCommand command, string name, string value) => command.Parameters.Add(name, NpgsqlDbType.Jsonb).Value = value;
}
