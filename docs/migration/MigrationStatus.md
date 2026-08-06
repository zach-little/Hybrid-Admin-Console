# Migration Status

## Current Slice

Tasks 41-55: Exchange disposition/cutover records, native workflow service boundaries, and configuration migration tooling.

Status: Implemented as provider-level native foundations with explicit live/destructive gates. Production WPF routing is not fully cut over yet.

Selected provider: Directory Simulator.

Selected initial capabilities:

- Provider health.
- Read-only user lookup.

Selected initial workflow target for later cutover:

- Runtime-profile health and simulator user lookup through explicit `NativeDotNet` or `LegacyPowerShell` configuration.

## Completed Foundation

- Temporary legacy bridge exists for migration-time read-only runtime profile/session operations.
- Legacy worker and adapter exist as temporary infrastructure.
- Permanent plugin manifest, registry, protocol, isolated PowerShell plugin host, provider proxy, SDK sample, declarative extension forms, and no-PowerShell normal-mode launch policy exist.

## Task 22 Findings

- The legacy Directory Simulator is deterministic for seeded users but not for all generated values.
- Seeded users are stored in module-global state and are lazily initialized.
- Search always returns one user because unknown queries generate a fallback user instead of returning no result.
- Provider health is exposed through scriptblocks on generated provider objects rather than standalone typed health services.
- Several simulator values are nondeterministic or runtime-sensitive: timestamps, GUIDs, and `.NET string.GetHashCode()` derived values.

## Task 23 Implementation

Implemented:

- `HAP.Providers.Abstractions.IProviderHealthCapability`
- `HAP.Providers.Abstractions.IUserLookupCapability`
- `HAP.Providers.Simulator.DirectorySimulatorProvider`
- Deterministic seed data for the initial simulator users.
- Focused simulator tests for provider health, seeded lookup, generated fallback, invalid query, unavailable provider, invalid configuration, cancellation, timeout, multiple matches, partial data, and no PowerShell assembly reference.

## Task 24 Implementation

Implemented:

- `HAP.Application.ProviderRouting.SimulatorReadOnlyWorkflowRouter`
- Explicit implementation values: `NativeDotNet` and `LegacyPowerShell`
- Structured validation failure for unknown implementation values.
- Route diagnostics for provider ID, implementation, capability, correlation ID, duration, status, and PowerShell launch state.
- Native simulator read-only adapter with `PowerShellProcessLaunched = false`.
- Routing tests proving native and legacy selections are exclusive, unknown implementations fail, and native failure does not trigger legacy fallback.

## Tasks 25-27 Implementation

Implemented:

- Native simulator read coverage for manager, groups, direct reports, devices, Graph profile, authentication posture, mailbox, mailbox statistics, mailbox delegations, distribution groups, configuration preview, and reporting.
- Native simulator write/state coverage for create user, update user attributes, manager changes, group membership, mailbox forwarding, and deterministic reset.
- Built-in simulator routing now rejects `LegacyPowerShell` with `ProviderRouting.LegacySimulatorRetired`.
- Simulator targeted tests cover 15 cases.

## Tasks 28-33 Implementation State

Implemented:

- Graph capability coverage gate in `docs/migration/GraphCapabilityCoverage.md`.
- Native `MicrosoftGraphProvider` foundation for health, user lookup, Graph profile, authentication posture, device reads, and explicit unsupported write results.
- Mailboxless ADM-style seeded profile coverage in provider tests/scaffolding.

Gated:

- Live Graph calls and destructive writes remain manual opt-in only.

## Tasks 34-38 Implementation State

Implemented:

- AD capability coverage gate in `docs/migration/ActiveDirectoryCapabilityCoverage.md`.
- Native `ActiveDirectoryProvider` foundation for health, user search, user lookup, manager, groups, and direct reports.
- AD write operations are represented with explicit gated/unsupported results until lab validation is configured.

Gated:

- Live LDAP writes, password operations, and object moves require a lab opt-in profile.

## Tasks 39-40 Implementation State

Implemented:

- Exchange Online supportability gate in `docs/migration/ExchangeOnlineSupportabilityGate.md`.
- Native `ExchangeOnlineProvider` foundation for limited health and approved basic mailbox identity reads.
- Unsupported Exchange administration operations return explicit unsupported results.

Gated:

- Mailbox delegation, mailbox statistics, distribution group administration, forwarding, and GAL visibility require product decisions or customer extension handling.

## Tasks 41-43 Implementation State

Implemented:

- Exchange Online write operations are represented through the native write contract and return audited explicit unsupported results.
- Built-in capability catalog records Exchange Online dispositions: limited mailbox identity reads, deferred unavailable actions, and customer-extension candidates.
- No Exchange Online write path uses hidden PowerShell, private endpoints, or legacy worker fallback.

## Tasks 44-46 Implementation State

Implemented:

- Exchange on-premises supportability gate in `docs/migration/ExchangeOnPremisesSupportabilityGate.md`.
- Native `ExchangeOnPremisesProvider` foundation for health and explicit unsupported Exchange administration results.
- Built-in capability catalog records Exchange on-premises deferred and customer-extension dispositions.

Gated:

- On-premises recipient administration requires an approved non-PowerShell management path or an approved customer extension.

## Tasks 47-49 Implementation State

Implemented:

- `NativeHybridUserLookupService` aggregates native provider user results with provider attribution, partial-success warnings, and deterministic identity normalization.
- `NativeProviderHealthService` aggregates built-in provider health without UI-derived state.
- `NativeDeviceManagementService` aggregates and de-duplicates native device reads.

## Tasks 50-51 Implementation State

Implemented:

- `NativeNewUserPreflightService` builds deterministic execution plans without performing writes.
- `NativeNewUserExecutionService` executes approved plan steps through provider write contracts and rejects blocked plans.
- Application tests cover duplicate preflight, ready plans, blocked execution, ordered execution, capability dispositions, lookup aggregation, provider health, and device de-duplication.

## Task 52 Implementation State

Implemented:

- `NativeUserAdministrationService` routes retained actions through native writer contracts only when the capability catalog marks them invokable.
- Deferred Exchange Online/on-premises actions return available-state results with explanatory messages instead of attempting hidden PowerShell.
- Tests cover unavailable Exchange forwarding and an available simulator group-membership action.

## Task 53 Implementation State

Implemented:

- `NativeWorkflowExportService` produces deterministic JSON export payloads with stable schema version, sorted columns, and sorted rows.
- Export tests cover deterministic ordering.

Gated:

- Group, licensing, mailbox, reporting, and export UI cutover remains a later composition/ViewModel integration step.

## Task 54 Implementation State

Documented partial state:

- UI parity/performance validation is not complete because WPF full-solution validation is blocked in the sandbox by Windows SDK path access.
- Existing native application services are cancellation-aware and contract-driven, but WPF ViewModel integration still needs a WPF-capable validation pass.

## Task 55 Implementation State

Implemented:

- `NativeConfigurationMigrationService` supports dry-run/migration output, backup naming, native schema stamping, and user-action detection for remaining `LegacyPowerShell` values.
- Configuration tests cover dry-run migration metadata and remaining legacy value detection.

Gated:

- File backup/rollback integration is modeled but not wired to installer/runtime packaging yet.

## Next Task

Task 56 should remove legacy implementation selection only after full-solution WPF-capable validation is available.

Tasks 41-55 do not authorize hidden first-party PowerShell fallback.
