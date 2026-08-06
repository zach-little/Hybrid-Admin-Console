# Provider Parity Matrix

## Task 22: Directory Simulator First Native Slice

| Provider | Capability | Operation | Legacy Source | Native Target | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| DirectorySimulator | ProviderHealth | `GetHealth` | `src/Infrastructure/Mock/Infrastructure.DirectorySimulator.psm1` provider scriptblocks | `HAP.Providers.Simulator.DirectorySimulatorProvider.GetHealthAsync` via `SimulatorReadOnlyWorkflowRouter` | Complete | Explicit `NativeDotNet` routes native only. Built-in `LegacyPowerShell` simulator selection is retired. No silent fallback. |
| DirectorySimulator | UserLookup | `SearchUser` | `Search-HybridDirectorySimulatorUser` -> `Get-HybridDirectorySimulatorUser` | `HAP.Providers.Simulator.DirectorySimulatorProvider.SearchUsersAsync` via `SimulatorReadOnlyWorkflowRouter` | Native route implemented | Focused parity tests cover the Task 22 fixture set. Route diagnostics include PowerShell launch state. |
| DirectorySimulator | DirectoryReads | manager, groups, direct reports | `Get-HybridDirectorySimulatorManager`, `Get-HybridDirectorySimulatorGroups`, `Get-HybridDirectorySimulatorDirectReports` | `DirectorySimulatorProvider` read capabilities | Complete | Deterministic sorting and native DTOs. |
| DirectorySimulator | DeviceReads | managed device lookup/search | `Get-HybridDirectorySimulatorDevices`, `Search-HybridDirectorySimulatorDevices` | `DirectorySimulatorProvider` device capabilities | Complete | Stable timestamps and identifiers. |
| DirectorySimulator | GraphReads | graph profile, auth posture, licenses, PIM | Directory simulator graph/auth verticals | `DirectorySimulatorProvider` graph capabilities | Complete | Friendly license names and seeded PIM roles. |
| DirectorySimulator | ExchangeReads | mailbox, statistics, delegation, distribution groups | Directory simulator Exchange scriptblocks | `DirectorySimulatorProvider` exchange capabilities | Complete | Simulator-only; not a statement about live Exchange Online API support. |
| DirectorySimulator | Writes | create/update/manager/groups/forwarding/reset | Legacy simulator state mutations | `DirectorySimulatorProvider` write capabilities | Complete | In-memory deterministic state with reset. |
| MicrosoftGraph | Auth/Health/Reads | Graph profile, auth posture, device/license/PIM reads | `Core.Provider.MicrosoftGraph.psm1` and graph modules | `HAP.Providers.Graph.MicrosoftGraphProvider` | Foundation implemented | Live calls and writes are gated; no PowerShell dependency in native provider. |
| ActiveDirectory | Connection/Reads/Writes | AD user/group/manager/admin workflows | `Infrastructure.ActiveDirectory.psm1` | `HAP.Providers.ActiveDirectory.ActiveDirectoryProvider` | Foundation implemented | Writes return gated results until lab opt-in validation. |
| ExchangeOnline | Auth/LimitedReads | Mailbox and recipient administration | `Core.Provider.ExchangeOnline.psm1` | `HAP.Providers.ExchangeOnline.ExchangeOnlineProvider` | Supportability gated | Unsupported admin operations return explicit unsupported results. |
| ExchangeOnline | Writes | mailbox forwarding, DG membership, recipient actions | `Core.Provider.ExchangeOnline.psm1` | `ExchangeOnlineProvider` write contract | Dispositioned | Unsupported writes return audited unsupported results; customer extension candidates are cataloged. |
| ExchangeOnPremises | Health/LimitedReads/Writes | remote mailbox and DG administration | `Infrastructure.ExchangeOnPremises.psm1` | `HAP.Providers.ExchangeOnPremises.ExchangeOnPremisesProvider` | Supportability gated | Built-in provider does not use EMS, remote PowerShell, or direct Exchange-owned AD edits. |
| Application | UserLookup | hybrid aggregation | legacy application services/worker routing | `NativeHybridUserLookupService` | Foundation implemented | Partial success and provider attribution are preserved. |
| Application | ProviderHealth | status cards/runtime status | legacy polling/UI state | `NativeProviderHealthService` | Foundation implemented | UI should consume provider contracts rather than control state. |
| Application | DeviceManagement | device search | legacy Graph/AD routing | `NativeDeviceManagementService` | Foundation implemented | Native providers only; unsupported actions are catalog-driven. |
| Application | NewUserWizard | preflight/execution | PowerShell application service | `NativeNewUserPreflightService`, `NativeNewUserExecutionService` | Foundation implemented | Preflight is read-only; execution follows typed plan steps. |
| Application | UserAdministration | selected user actions | PowerShell application service/provider operations | `NativeUserAdministrationService` | Foundation implemented | Invokable only when capability catalog allows native built-in execution. |
| Application | WorkflowExport | reports/exports | script-shaped exports | `NativeWorkflowExportService` | Foundation implemented | Deterministic JSON export schema. |
| Configuration | Migration/Rollback | legacy runtime profiles/config | PowerShell/config scripts | `NativeConfigurationMigrationService` | Foundation implemented | Dry-run and legacy-value detection implemented; file rollback integration remains gated. |
| Runtime | Legacy migration infrastructure | temporary worker/bridge/protocol/adapter | `HAP.Providers.LegacyPowerShell`, `HAP.LegacyWorker.Protocol`, `HAP.LegacyPowerShellWorker`, `HAP.LegacyBridge.psm1` | Removed | Complete | Removed from solution/source after full build and test validation. |
| Release | Packaging/Diagnostics | script packaging/manual support bundles | `NativeFrameworkDependent` publish profile, `SupportBundleService` | Foundation implemented | Publish output generated; installer/live validation remains pending. |

## Legacy Behavior Inventory

Primary module:

- `src/Infrastructure/Mock/Infrastructure.DirectorySimulator.psm1`

Related simulator verticals inspected:

- `src/Infrastructure/DirectorySimulator/DirectorySimulator.GraphVertical.psm1`
- `src/Infrastructure/DirectorySimulator/DirectorySimulator.AuthenticationVertical.psm1`

Runtime profile inspected:

- `profiles/Simulation/runtime.json`

Initial seeded users:

- `rwilliams`: Robert Williams, Information Technology, no manager, direct report `treed`
- `treed`: Taylor Reed, Information Technology, manager `rwilliams`, reports `amorgan`, `jlee`
- `amorgan`: Alex Morgan, Information Technology, manager `treed`
- `jlee`: Jordan Lee, Operations, manager `treed`

Legacy exported functions relevant to the first slice:

- `New-HybridDirectorySimulator`
- `New-HybridDirectorySimulatorProviders`
- `Get-HybridDirectorySimulatorUser`
- `Search-HybridDirectorySimulatorUser`
- Provider scriptblock `GetHealth` on generated ActiveDirectory and MicrosoftGraph simulator provider objects

Deferred to later simulator tasks:

- Manager, group, direct report, device, mailbox, mailbox statistics, mailbox delegation, distribution group, Graph profile, and authentication posture simulation.

## Planned Native Files for Task 23

Production files:

- `src-dotnet/src/HAP.Providers.Abstractions/IProviderHealthCapability.cs`
- `src-dotnet/src/HAP.Providers.Abstractions/IUserLookupCapability.cs`
- `src-dotnet/src/HAP.Providers.Abstractions/UserLookupModels.cs`
- `src-dotnet/src/HAP.Providers.Simulator/DirectorySimulatorProvider.cs`
- `src-dotnet/src/HAP.Providers.Simulator/DirectorySimulatorOptions.cs`
- `src-dotnet/src/HAP.Providers.Simulator/DirectorySimulatorSeedData.cs`

Test files:

- `src-dotnet/tests/HAP.Providers.Simulator.Tests/HAP.Providers.Simulator.Tests.csproj`
- `src-dotnet/tests/HAP.Providers.Simulator.Tests/DirectorySimulatorProviderTests.cs`

Documentation updates:

- `docs/migration/ProviderParityMatrix.md`
- `docs/migration/MigrationStatus.md`

## Contract Mapping

Provider health:

- Request: provider ID, correlation ID, cancellation token.
- Response: `OperationResult<ProviderHealthSummary>`.
- Required fields: provider name, implementation mode, enabled, required, status, message, available, connected, last error.
- Errors: unavailable provider, invalid configuration, timeout, cancellation.

User lookup:

- Request: query string, correlation ID, cancellation token, optional maximum result count.
- Response: `OperationResult<IReadOnlyList<SimulatorUserSummary>>`.
- Required fields: display name, given name, surname, SAM account name, UPN, mail, department, title, company, office, employee ID, distinguished name, manager SAM, direct report SAMs, groups, enabled, locked out, source.
- Errors: invalid empty query, unavailable provider, invalid configuration, timeout, cancellation.
- Warnings: generated fallback user, partial user data, multiple matches.
- Progress: planned `OperationProgress` with at least validation, lookup, normalization, completed.

## Normalization Rules

- Ordering: sort user results by `SamAccountName`, ordinal ignore-case.
- Timestamps: exclude timestamps from Task 23 user lookup fixtures. Later timestamped simulator capabilities must compare ISO 8601 values after replacing relative clock values with fixed fixture timestamps.
- Generated IDs: do not compare runtime GUIDs. For Task 23, avoid generated GUID fields.
- Employee IDs: native simulator should use deterministic fixture values rather than `.NET string.GetHashCode()`, because hash randomization can differ between processes and runtimes.
- Paths: compare provider/configuration paths only after normalizing separators and repository root placeholders.
- PSObject metadata: ignore `PSTypeName` and PowerShell formatting metadata.
- Casing: preserve legacy display casing in returned data; compare query matching case-insensitively.

## Task 23 Acceptance Fixture Names

Fixtures are defined in `docs/migration/fixtures/directory-simulator-userlookup-task22.json`.

- `health.success`
- `userLookup.success.seededExact`
- `userLookup.success.seededUpn`
- `userLookup.warning.generatedFallback`
- `userLookup.failure.invalidRequest`
- `userLookup.failure.unavailableProvider`
- `userLookup.failure.invalidConfiguration`
- `userLookup.failure.cancelled`
- `userLookup.failure.timeout`
- `userLookup.warning.multipleMatches`
- `userLookup.warning.partialUserData`

## Prohibited in Task 23

- Do not route production workflows to the native simulator.
- Do not call `pwsh.exe`, `powershell.exe`, `System.Management.Automation`, the legacy worker, the legacy bridge, or the plugin host from `HAP.Providers.Simulator`.
- Do not add WPF dependencies to provider code.
- Do not use PowerShell `PSObject` shapes as public .NET contracts.

## Task 24 Routing Contract

Supported migration implementation values before simulator retirement:

- `NativeDotNet`
- `LegacyPowerShell`

Unknown implementation values fail with `ProviderRouting.UnknownImplementation`; they do not fall back to either provider.

After Task 27, built-in simulator `LegacyPowerShell` selection fails with `ProviderRouting.LegacySimulatorRetired`.

Routing diagnostics record:

- Provider ID
- Implementation
- Capability
- Correlation ID
- Duration
- Status
- Whether a PowerShell process was launched
