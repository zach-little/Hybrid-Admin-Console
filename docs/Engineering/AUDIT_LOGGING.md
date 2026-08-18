# Audit Logging

HILOP records all state-changing provider operations, workflow definition changes, workflow runs and actions, device lifecycle actions, protected-secret access, and utility-tool runs. Searches and passive reads are intentionally excluded.

## Profile Scope

Every event includes the runtime profile identifier. The Audit Log tab queries only the currently loaded profile; records from other profiles are never included in that view.

## Captured Information

Audit events capture, where applicable:

- UTC start and completion timestamps and duration.
- Signed-in Windows user, domain-qualified identity, workstation, process, session, and application version.
- Runtime profile, provider, category, action, event type, outcome, and severity.
- Target type, identifier, and display name.
- Correlation ID linking a workflow run, workflow action, and provider changes.
- Previous and new provider snapshots.
- Requested inputs, provider results, changed/no-change state, warnings, errors, and diagnostic messages.
- A SHA-256 hash chain linking each local event to the preceding event.

Passwords, OAuth tokens, authorization headers, client secrets, private keys, BitLocker recovery keys, LAPS passwords, installation credentials, and similarly named sensitive fields are replaced with `[REDACTED]`. A protected-secret reveal is audited, including who revealed which secret type for which device, but the secret value is never stored.

## Storage

The append-only journal and PostgreSQL configuration are stored alongside licensing information:

```text
%ProgramData%\Little Innovation Tech\HILOP\Licensing\
    audit-events.jsonl
    audit-postgresql.json
    audit-postgresql.example.json
```

The local JSON-lines journal is a durable outbox and remains available if PostgreSQL is offline. When PostgreSQL is configured, HILOP creates the `hilop_audit.audit_events` table and indexes, synchronizes journaled events with idempotent inserts, and installs a database trigger that rejects updates and deletes. PostgreSQL manages its physical database files; the connection configuration and durable outbox are the audit artifacts co-located with licensing data.

Use the `HILOP_AUDIT_POSTGRES` environment variable for the connection string when possible:

```powershell
$env:HILOP_AUDIT_POSTGRES = 'Host=localhost;Port=5432;Database=hilop;Username=hilop_audit;Password=...;SSL Mode=Require'
```

Alternatively, copy `audit-postgresql.example.json` to `audit-postgresql.json` in the licensing directory and protect that file with restrictive filesystem permissions. The configured PostgreSQL identity needs permission to create the selected schema, table, indexes, function, and trigger on first use, and then to select and insert audit rows.

## Reliability Boundary

Provider edits write an attempted audit record before calling the provider. If the durable local journal cannot accept that record, the provider edit is not started. A second event records completion, failure, post-change state, and provider diagnostics. PostgreSQL outages do not discard events: synchronization is retried whenever a new event is written or the Audit Log tab is refreshed.

## Interface

The Audit Log tab appears immediately after Utilities. It provides profile-scoped filtering by category and outcome, free-text search, a chronological event grid, PostgreSQL synchronization status, and a full JSON detail view containing before/after values and hash-chain evidence.
