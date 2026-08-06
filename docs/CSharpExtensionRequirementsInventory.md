# C# Migration Inventory - Extension Requirements

Status: analysis only. This document follows `Migration.MD` Task 2 and does not implement an extension platform.

## Scope

This inventory documents likely customer-provider verticals, capability needs, configuration needs, trust requirements, and the separation between the temporary legacy bridge and the permanent provider SDK. MobilePass is included as a concrete example only.

Primary sources inspected:

- `Migration.MD`
- `docs/ARCHITECTURE.md`
- `docs/ROADMAP.md`
- `docs/EXTENSIBILITY_SDK.md`
- `docs/DESIGN_PRINCIPLES.md`
- `docs/ADR/ADR-0001.md`
- `docs/ADR/ADR-0007.md`
- `docs/Milestones/MILESTONE_11_ADMINISTRATIVE_WORKFLOWS.md`
- `docs/Milestones/MILESTONE_12_ENTERPRISE_OPERATIONS.md`
- `docs/Milestones/MILESTONE_13_ENTERPRISE_PLATFORM.md`
- `src/Core/Core.PluginLoader.psm1`
- `legacy/Atlas_Hybrid_Admin_Console.ps1`
- `legacy/New_User_Wizard.ps1`

## Existing Direction

HAP already treats providers, workflows, plugins, and services as extension points. The existing documentation emphasizes provider contracts, configuration-driven behavior, and avoiding customer-specific source changes.

The current PowerShell plugin loader is not suitable as the target .NET extension model. `Core.PluginLoader.psm1` discovers `*.plugin.psm1` files, imports them into the host process, and registers scriptblock initialization. That is acceptable historical context, but the migration target requires explicit installation, approval, capability grants, exact-path loading, isolation, and no WPF injection.

## Likely Extension Verticals

| Vertical | Why It Belongs in Extension or Provider Contracts | Candidate Capabilities | Configuration Needs | Notes |
|---|---|---|---|---|
| MobilePass / MFA token platform | Customer-specific identity/security operation outside built-in Microsoft providers | `ProviderHealth`, `UserLookup`, `UserCredentialEnrollment`, `CredentialReset`, `TokenRevoke`, `AuditRead` | API endpoint, tenant/realm, auth method, enrollment policy, delivery methods, timeout | Example vertical for SDK design; do not implement during migration foundation |
| JAMIS | External business/ERP integration named in roadmap | `UserLookup`, `UserProvisioning`, `UserUpdate`, `UserDeprovisioning`, `Reporting` | API base URL, environment, cost center mappings, auth profile, field mappings | Good candidate for customer-owned provider or native provider depending product strategy |
| Paxton / Physical access | External access-control system named in roadmap | `UserLookup`, `AccessCredentialProvisioning`, `AccessCredentialDisable`, `AccessGroupMembership`, `AuditRead` | Site/controller endpoint, badge mappings, access group mappings, operator approval rules | Should integrate through operations, not hardcoded employee lifecycle steps |
| SQL reporting | External reporting/data source | `Reporting`, `QueryRead`, `Export`, `ProviderHealth` | Connection reference, approved queries/views, parameter schema, redaction rules | Must avoid arbitrary SQL execution from UI |
| SharePoint automation | External content/workflow integration | `DocumentProvisioning`, `WorkflowTrigger`, `Reporting`, `ProviderHealth` | Site URLs, list/library IDs, app auth, schema mappings | Could also be a first-party Microsoft provider later |
| Sentinel integration | Security operations data provider | `SecurityAlertRead`, `RiskRead`, `InvestigationRead`, `Reporting`, `ProviderHealth` | Workspace IDs, cloud, auth, query templates, data retention | Read-only first; writes need separate elevated capability |
| VMware | Infrastructure provider listed in architecture | `DeviceLookup`, `VirtualMachineRead`, `VirtualMachineAction`, `ProviderHealth` | vCenter endpoint, credential reference, datacenter/folder mappings, action policy | Destructive operations need explicit capability and confirmation |
| Zammad / ticketing | External workflow/ticketing provider listed in architecture | `TicketCreate`, `TicketUpdate`, `TicketSearch`, `WorkflowTrigger`, `ProviderHealth` | API endpoint, project/queue mappings, templates, auth profile | Useful for audit-linked admin actions |
| Teams administration | Roadmap enterprise operation | `TeamsRead`, `TeamsPolicyUpdate`, `GroupMembership`, `Reporting` | Tenant, scopes, policy mappings | Built-in Microsoft provider likely; third-party provider contract still useful |
| Custom dashboards/reports | Milestone 13 extension area | `DashboardDataRead`, `Reporting`, `Export` | Declarative widgets, query/provider references, refresh interval | HAP should render UI; extension supplies schema/data only |

## Capability Inventory

Capabilities should be versioned, narrow, and grantable. The first SDK should avoid a single unrestricted "invoke anything" permission.

Suggested initial capability families:

- `ProviderHealth`: test connection, return status, version, latency, last error, and safe diagnostics.
- `UserLookup`: read user identity by UPN, email, employee ID, badge ID, external ID, or provider-native key.
- `UserProvisioning`: create or onboard a user into an external system.
- `UserUpdate`: update allowed user attributes in an external system.
- `UserDeprovisioning`: disable, remove, or offboard a user from an external system.
- `GroupMembership`: list, add, and remove user memberships in provider-owned groups.
- `DeviceLookup`: read devices, compliance state, ownership, and last activity.
- `DeviceAction`: sync, retire, wipe, disable, or other controlled device operations.
- `CredentialEnrollment`: enroll, reset, revoke, or report credential/token state.
- `LicenseAssignment`: assign, remove, and report licenses where the provider owns licensing.
- `Ticketing`: create, update, link, and search workflow tickets.
- `Reporting`: return typed report datasets with filters and export metadata.
- `SecurityRead`: read alerts, risks, posture, investigation facts, or audit events.
- `WorkflowTrigger`: invoke provider-owned external workflows with typed inputs.
- `ChoiceLookup`: return safe value lists for declarative forms.

Write capabilities should be split from read capabilities. Destructive capabilities should be separate from routine write capabilities and require stronger confirmation and audit policy.

## MobilePass Example

MobilePass should be modeled as a customer PowerShell provider behind permanent extension contracts, not as a built-in HAP workflow and not through the temporary legacy bridge.

Example provider identity:

- Provider ID: `contoso.mobilepass`
- Display name: `MobilePass`
- Implementation: `PowerShell`
- Runtime: pinned PowerShell 7 SDK contract
- Capabilities: `ProviderHealth`, `UserLookup`, `CredentialEnrollment`, `CredentialReset`, `TokenRevoke`, `AuditRead`
- Configuration schema: endpoint, tenant/realm, credential reference, allowed delivery methods, enrollment policy, lookup attribute mapping
- Operations: `MobilePass.GetUser`, `MobilePass.GetTokenStatus`, `MobilePass.EnrollUser`, `MobilePass.ResetToken`, `MobilePass.RevokeToken`, `MobilePass.GetAuditEvents`

Example operation form metadata:

- `MobilePass.EnrollUser`
- Fields: `userPrincipalName`, `deliveryMethod`, `phoneNumber`, `emailAddress`, `forceReenrollment`
- HAP renders the form and validates field types.
- The provider receives a structured operation request.
- The provider returns a structured result with warnings, errors, and audit-safe details.

This example proves the SDK needs user-scoped lookups, write operations, declarative forms, choice lists, and audit events without letting the provider inject UI or modify HAP core code.

## Configuration Requirements

Permanent extension configuration should be separate from runtime profile JSON, but runtime profiles may reference approved extension instances.

Required registry fields:

- Provider ID, display name, publisher, version, and implementation type.
- Extension API version and manifest schema version.
- Exact installation path controlled by HAP.
- Entry module for PowerShell providers.
- File hashes for manifest and executable/module files.
- Signature state and signing identity when available.
- Enabled/disabled state.
- Approved capabilities and denied capabilities.
- Configuration instance ID.
- Safe configuration values.
- Secret references, not raw secrets.
- Install, update, approval, enablement, disablement, and last validation timestamps.

Runtime profile references should include:

- Provider instance ID.
- Implementation selection: native, PowerShell extension, or disabled.
- Approved capabilities requested by that profile.
- Environment/tenant binding.
- Required/optional status.
- Timeout and retry policy references.

Configuration schema needs:

- JSON Schema-compatible field definitions.
- Required/optional fields.
- Secret reference fields.
- Choice fields and dynamic choice operation references.
- Validation constraints.
- Display metadata owned by HAP, not custom WPF.
- Safe defaults only when explicitly defined by the provider manifest or admin configuration.

## Trust and Security Requirements

PowerShell providers are installed executable code. They should be treated as trusted-but-contained integrations, not as safely sandboxed text.

Required trust controls:

- Administrative approval before enablement.
- Exact-path loading from an HAP-controlled provider directory.
- No discovery from the general `PSModulePath`.
- Manifest schema validation before any module code runs.
- Hash validation before each launch.
- Signature-state capture and optional policy enforcement.
- Capability grants enforced by HAP before invocation.
- One isolated plugin-host process per provider instance where practical.
- Operation timeouts and cancellation.
- Forced termination and clean restart after a hung host.
- Redaction of tokens, passwords, secure strings, connection strings, and authorization headers.
- Separate user-safe error messages from diagnostic details.
- Audit logs for installation, approval, enablement, invocation, failure, timeout, and disablement.
- No WPF control injection, code-behind injection, arbitrary assembly loading into HAP.App, or custom UI inside the main process.

## UI Extension Requirements

HAP owns all UI. Extensions may provide declarative metadata only.

Allowed:

- Configuration forms rendered by HAP from validated schema.
- Operation forms rendered by HAP from validated schema.
- Read-only result metadata such as labels, columns, severity, and grouping.
- Dynamic choice lists through declared read operations with timeout and caching.

Prohibited:

- Custom WPF controls.
- Code-behind.
- Arbitrary XAML from providers.
- Provider-owned windows inside the HAP process.
- Provider callbacks that mutate HAP UI state directly.

## Legacy Bridge vs Permanent SDK Separation

| Concern | Temporary Legacy Bridge | Permanent Provider SDK |
|---|---|---|
| Purpose | Preserve first-party PowerShell behavior during migration | Support administrator-approved customer providers after migration |
| Lifetime | Deleted after native parity/cutover | Permanent optional platform feature |
| Scope | Narrow HAP-owned bridge commands | Public provider contract and capability model |
| Module source | Existing HAP modules only | Exact approved customer provider package |
| Protocol | `HAP.LegacyWorker.Protocol` | `HAP.Plugin.Protocol` |
| Host | `HAP.LegacyPowerShellWorker` | `HAP.PowerShellPluginHost` |
| UI | None | Declarative schemas only; HAP renders UI |
| Fallback behavior | Explicit migration implementation only | Never fallback for built-in providers |
| Security posture | Compatibility isolation | Admin approval, hash/signature/capability enforcement |

The permanent plugin host must never import `HAP.LegacyBridge.psm1`. The legacy bridge must never be documented as the customer provider SDK.

## Contract Shapes Needed Later

The migration should reserve contracts for:

- `ProviderDescriptor`
- `ProviderCapability`
- `ProviderCapabilityGrant`
- `ProviderManifest`
- `ProviderInstallationRecord`
- `ProviderConfigurationSchema`
- `ProviderConfigurationInstance`
- `ProviderHealthRequest`
- `ProviderHealthResult`
- `ProviderOperationRequest`
- `ProviderOperationResult`
- `ProviderOperationError`
- `ProviderOperationWarning`
- `ProviderProgressEvent`
- `ProviderAuditEvent`
- `ExtensionHostHandshake`
- `ExtensionHostShutdown`
- `ExtensionHostCancellation`

All DTOs should be independent of WPF, PowerShell, and provider-native object types.

## Tests Required When Implemented

Future implementation tasks should add tests for:

- Valid manifest accepted.
- Invalid manifest rejected before module load.
- Unsupported HAP extension API version rejected.
- Missing capability denied.
- Disabled provider cannot be invoked.
- Changed module hash blocks launch.
- Signature state captured and policy applied.
- General `PSModulePath` is not searched.
- Plugin host is not launched when no enabled PowerShell extension is referenced.
- Provider cannot request undeclared operation.
- Operation timeout kills or recycles plugin host.
- Cancellation returns a structured cancellation result.
- Secrets are redacted from logs and errors.
- Declarative form schema accepts valid fields and rejects unsafe/custom UI fields.
- MobilePass-style sample manifest validates without executing provider code.

## Open Decisions

- Exact supported initial PowerShell 7 version band for the public SDK.
- Whether native .NET third-party providers are supported in the first SDK or reserved for later.
- Signature enforcement policy: warn, require trusted signer, or organization-configurable.
- Provider installation UX and administrative approval workflow.
- Whether a Windows PowerShell 5.1 extension host is ever supported for customer modules. The migration plan says not to promise this in the first public SDK.

## Recommendation

Build the early .NET migration around provider/capability contracts that are strong enough for the future extension platform, but do not implement the plugin host until the base runtime contracts and legacy worker boundary are stable.

Use MobilePass as a conformance sample later because it exercises the right shape: identity lookup, credential enrollment/reset, write operations, declarative forms, dynamic choices, secrets, audit, and provider health. Keep it outside first-party HAP business logic.
