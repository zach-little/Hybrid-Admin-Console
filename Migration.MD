HAP PowerShell-to-.NET Migration Plan

1. Purpose

This document defines the approved migration strategy for converting the Hybrid Administration Platform (HAP) from a PowerShell/WPF application into a compiled C#/.NET desktop application while preserving PowerShell as an optional customer extension language.

The migration must preserve the working business logic already implemented in PowerShell while progressively moving presentation, contracts, configuration, application services, and all first-party providers into .NET.

This is not a full rewrite. It is a controlled strangler-fig migration in which the new .NET application initially calls stable, headless PowerShell adapters and replaces those adapters one workflow or provider at a time.

The final architecture must make a strict distinction between:

Temporary legacy PowerShell infrastructure, used only to preserve existing HAP behavior during migration and removed after native parity is achieved.

Permanent third-party PowerShell extension infrastructure, retained as an optional, isolated plugin mechanism for customer-created providers and verticals such as MobilePass.

All built-in HAP functionality must eventually run without PowerShell. PowerShell may execute after migration only when an administrator has installed, approved, enabled, and invoked a third-party PowerShell provider.

2. Primary Goals

Produce a compiled Windows executable with a maintainable .NET architecture.

Preserve existing HAP behavior during migration.

Separate UI state from runtime and provider state.

Replace the oversized PowerShell UI shell with WPF and MVVM.

Keep live Graph, Exchange, Active Directory, and simulator behavior operational while the migration proceeds.

Make configuration precedence, provider selection, validation, error handling, logging, and cancellation deterministic and testable.

Complete the migration in small, independently testable, commit-sized slices.

Minimize Codex usage by limiting each task to a narrow scope and avoiding repeated full-repository rewrites.

Port every first-party HAP workflow and provider to native .NET so normal built-in operation makes zero PowerShell calls.

Preserve an optional, documented PowerShell provider SDK for customer-created third-party integrations.

Support both native .NET providers and PowerShell providers behind common, versioned capability contracts.

Run customer PowerShell providers outside the main HAP process with explicit approval, isolation, audit, timeout, cancellation, and lifecycle controls.

Ensure that HAP does not launch a PowerShell process or load System.Management.Automation when no enabled PowerShell extension requires it.

3. Non-Goals

The following are explicitly out of scope during the early migration phases:

Rewriting all providers at once.

Recreating the entire UI in one operation.

Redesigning established business workflows unless a documented defect requires it.

Importing the existing large UI script as the backend for the new application.

Allowing raw PSObject instances to escape any PowerShell boundary.

Silently falling back from a native .NET provider to a legacy or third-party PowerShell provider.

Performing unrelated cleanup, renaming, formatting, or architectural changes outside the assigned migration slice.

Deleting or disabling the existing PowerShell application before parity is proven.

Retaining first-party HAP business logic in PowerShell after the associated native provider has passed parity and cutover requirements.

Treating PowerShell runspaces as a complete security sandbox.

Loading arbitrary modules from the user's normal PSModulePath.

Allowing third-party modules to inject WPF controls, code-behind, arbitrary assemblies, or unreviewed UI into the primary HAP process.

Promising compatibility with arbitrary Windows PowerShell 5.1 customer modules in the first public extension SDK.

Automatically installing, updating, enabling, or executing customer modules without administrative approval.

4. Existing Repository Shape

The current HAP repository is rooted at:

D:\Atlas

Important existing locations:

D:\Atlas\src\Core
D:\Atlas\src\Domain\Hybrid.Models.psm1
D:\Atlas\src\Application
D:\Atlas\src\Infrastructure
D:\Atlas\src\UI\Start-HybridAdminConsole.ps1

The existing application already contains useful architectural separation:

Core platform: runtime composition, provider base behavior, shared helpers.

Domain: PowerShell classes and normalized hybrid administration objects.

Application: use cases and workflow services.

Infrastructure: live and simulated providers.

UI: WPF layout, event wiring, workflow orchestration, status handling, and some transformation logic.

The primary architectural problem is that Start-HybridAdminConsole.ps1 mixes too many responsibilities. It must be treated as a behavioral reference, not reused as the new backend.

5. Approved Target Architecture

5.1 Technology choices

Use the following unless a compatibility spike proves a blocking issue:

Language: C#

Framework: .NET 10

Desktop UI: WPF

Presentation pattern: MVVM

Dependency injection: Microsoft.Extensions.DependencyInjection

Configuration: Microsoft.Extensions.Configuration with explicit HAP precedence rules

Logging: Microsoft.Extensions.Logging with structured log events

Testing: xUnit unless the repository already establishes another standard

Temporary legacy PowerShell boundary: Prefer an out-of-process worker

Permanent customer PowerShell extension boundary: Isolated out-of-process plugin host, preferably one worker process per active provider

Initial public PowerShell extension runtime: A pinned and documented PowerShell 7 runtime contract

Target framework:

<TargetFramework>net10.0-windows</TargetFramework>
<UseWPF>true</UseWPF>
<Nullable>enable</Nullable>
<ImplicitUsings>enable</ImplicitUsings>

Add a global.json that pins the approved .NET SDK version used by developers, CI, and Codex.

5.2 Migration-time architectural flow

During migration, existing first-party behavior may temporarily use the legacy adapter:

WPF Views
    ↓
ViewModels
    ↓
C# Application Services
    ↓
Stable C# Contracts
    ↓
Provider Interfaces
    ↓
Temporary Legacy PowerShell Adapter or Native .NET Provider
    ↓
Existing HAP PowerShell Application/Infrastructure Services

5.3 Final built-in runtime flow

After migration, all built-in HAP workflows must use native .NET implementations:

WPF Views
    ↓
ViewModels
    ↓
C# Application Services
    ↓
Stable C# Contracts
    ↓
Provider and Capability Interfaces
    ↓
Native .NET Providers

No built-in provider may depend on .ps1, .psm1, powershell.exe, pwsh.exe, or System.Management.Automation.

5.4 Final third-party extension flow

Customer-created PowerShell providers remain supported through a separate optional extension path:

HAP Application Services
    ↓
Provider/Capability Interfaces
    ↓
PowerShellProviderProxy
    ↓  versioned local IPC
HAP.PowerShellPluginHost.exe
    ↓  isolated runspace/process
Administrator-approved customer .psd1/.psm1 module
    ↓
Third-party service or vertical

The main HAP process must not directly import customer PowerShell modules. The plugin host must not be used as a fallback for built-in HAP providers.

5.5 Runtime state flow

Runtime state must flow as follows:

RuntimeProfile
    ↓
RuntimeSession
    ↓
ProviderRegistry
    ↓
Application Services
    ↓
ViewModels
    ↓
Views

UI controls must never be the source of truth for provider availability, selected runtime mode, authentication requirements, extension approval, or application state.

6. Proposed .NET Solution Layout

Create the new implementation beside the existing PowerShell application:

D:\Atlas\src-dotnet\
  HAP.sln
  global.json
  Directory.Build.props
  Directory.Packages.props

  src\
    HAP.App\
    HAP.Presentation\
    HAP.Application\
    HAP.Contracts\
    HAP.Domain\
    HAP.Configuration\
    HAP.Providers.Abstractions\
    HAP.Extensions.Abstractions\
    HAP.Extensions.Registry\

    HAP.Providers.LegacyPowerShell\
    HAP.LegacyWorker.Protocol\
    HAP.LegacyPowerShellWorker\

    HAP.Providers.Graph\
    HAP.Providers.ActiveDirectory\
    HAP.Providers.ExchangeOnline\
    HAP.Providers.ExchangeOnPremises\
    HAP.Providers.Simulator\

    HAP.Plugin.Protocol\
    HAP.Extensions.PowerShell\
    HAP.PowerShellPluginHost\

  sdk\
    powershell\
      HAP.ProviderSdk.psm1
      templates\
      schemas\
      samples\
      documentation\

  tests\
    HAP.Application.Tests\
    HAP.Configuration.Tests\
    HAP.Contracts.Tests\
    HAP.Providers.LegacyPowerShell.Tests\
    HAP.Extensions.Registry.Tests\
    HAP.Extensions.PowerShell.Tests\
    HAP.IntegrationTests\
    HAP.ContractTests\
    HAP.PluginConformanceTests\

Project responsibilities

HAP.App

WPF executable entry point.

Dependency injection composition root.

Startup and shutdown handling.

Global exception handling.

Window and navigation startup.

No provider-specific implementation logic.

Must not directly reference customer PowerShell modules.

HAP.Presentation

WPF views, ViewModels, commands, navigation, dialogs, and presentation-only models.

Must not reference System.Management.Automation.

Must not directly execute PowerShell.

Renders only HAP-owned UI, including declarative extension forms generated from approved schemas.

HAP.Application

Workflow orchestration and application use cases.

Depends on contracts and provider abstractions.

Must not reference WPF controls or PowerShell types.

Must treat native and extension providers through common capability contracts.

HAP.Contracts

Stable requests, responses, DTOs, errors, warnings, progress events, and operation results.

Must remain independent of WPF and PowerShell.

Treat changes to this project as contract changes requiring tests.

HAP.Domain

Stable domain concepts and business rules.

Add models only when required by an implemented workflow.

Do not perform a speculative bulk port of all PowerShell classes.

HAP.Configuration

Runtime profile loading.

JSON configuration loading and merging.

Validation.

Configuration precedence.

Provider implementation selection.

Extension enablement and approved provider references.

Environment and machine-specific overrides.

HAP.Providers.Abstractions

Interfaces for Graph, Active Directory, Exchange, simulator, authentication, runtime health, and workflow-specific capabilities.

Contains no PowerShell-specific types.

HAP.Extensions.Abstractions

Versioned extension descriptors, capability identifiers, operation contracts, configuration-schema contracts, and lifecycle abstractions.

Shared by native .NET extensions and PowerShell extension proxies.

Contains no WPF or PowerShell runtime dependency.

HAP.Extensions.Registry

Discovers only explicitly registered extensions from approved HAP locations.

Validates manifests, versions, hashes, signatures, capability grants, and enablement state.

Never scans or auto-loads the general PSModulePath.

Temporary legacy projects

HAP.Providers.LegacyPowerShell, HAP.LegacyWorker.Protocol, and HAP.LegacyPowerShellWorker exist only during migration.

They provide:

Request serialization and normalized response deserialization.

Timeout, cancellation, process lifecycle, and protocol validation.

Access to the approved headless legacy bridge.

Isolation of existing module crashes and assembly conflicts.

They must be removed after every first-party workflow and provider has passed native parity and cutover.

Native provider projects

Implement first-party provider interfaces after the corresponding PowerShell behavior has contract tests and parity coverage.

Must be explicitly selected by configuration during migration.

Become the only supported implementation for built-in providers after final cutover.

HAP.Plugin.Protocol

Permanent versioned IPC contract between HAP and extension hosts.

Defines handshake, provider metadata, capabilities, operations, progress, cancellation, errors, and shutdown.

Must remain independent of WPF and PowerShell implementation details.

HAP.Extensions.PowerShell

Permanent C# proxy that represents an approved PowerShell provider through normal HAP interfaces.

Starts the plugin host only when an enabled PowerShell provider is needed.

Does not contain first-party provider business logic.

HAP.PowerShellPluginHost

Permanent optional out-of-process host for customer-created PowerShell providers.

Loads only the exact module registered and approved for the provider instance.

Enforces protocol, lifecycle, timeout, cancellation, logging, and redaction requirements.

Prefer one host process per active provider to contain crashes, hangs, global state, and dependency conflicts.

Must never import the legacy HAP bridge after migration cutover.

sdk\powershell

Public PowerShell provider SDK, JSON schemas, module templates, conformance tests, samples, and documentation.

Defines the supported provider contract and PowerShell runtime version.

Must not expose internal HAP implementation details.

7. PowerShell Hosting Strategy

7.1 Two separate PowerShell use cases

The architecture must never conflate these two hosts:

Host

Purpose

Lifetime

HAP.LegacyPowerShellWorker

Preserve existing first-party PowerShell behavior during migration

Temporary; removed at native cutover

HAP.PowerShellPluginHost

Execute administrator-approved customer providers

Permanent but optional

The permanent plugin host must not call the legacy bridge, and built-in HAP services must not route through the permanent plugin host.

7.2 Required legacy compatibility spike

Do not assume all existing modules can run safely in an embedded PowerShell 7 runspace.

Before committing to the temporary legacy hosting design, test all major components under:

Windows PowerShell 5.1

PowerShell 7

In-process hosting

Out-of-process hosting

Test at least:

Microsoft Graph

Exchange Online

Active Directory

Exchange on-premises

Directory simulator/mock providers

Authentication flows

Module import behavior

Interactive prompt behavior

STA/threading requirements

Object serialization behavior

Cancellation and timeout behavior

Create a compatibility matrix documenting the result.

7.3 Preferred temporary legacy approach

Use an out-of-process legacy PowerShell worker unless the compatibility spike proves in-process hosting is clearly safe across all required modules.

The legacy worker may select powershell.exe or pwsh.exe when required by an existing first-party provider. This compatibility is temporary and does not define the customer extension SDK.

7.4 Permanent extension runtime policy

The initial public PowerShell provider SDK should support one pinned PowerShell 7 runtime contract. Do not promise arbitrary Windows PowerShell 5.1 module compatibility.

A provider manifest must declare at least:

Required PowerShell edition.

Minimum and maximum supported runtime version or approved runtime band.

Module entry point.

Provider SDK/API version.

Declared capabilities.

Required HAP permissions or capability grants.

A separate Windows PowerShell 5.1 extension host may be considered later only after a documented product decision, threat review, test matrix, and support plan.

7.5 IPC and lifecycle requirements

Preferred communication options, in order:

Named pipes with versioned JSON messages.

Standard input/output with one structured JSON message per line for an initial proof of concept.

Another local IPC mechanism only when documented and justified.

Both worker types must support:

Startup handshake and protocol version validation.

Request correlation IDs.

Structured responses and progress events.

Cancellation.

Per-operation timeout.

Clean shutdown.

Forced termination and restart after a hung operation.

Redaction of secrets from logs and error payloads.

Explicit provider identity in every request and log record.

The permanent plugin host must additionally support:

Exact module-path loading from the approved registry.

Manifest, hash, and signature revalidation at launch.

Capability-grant enforcement.

No discovery from general PowerShell module paths.

No automatic module update.

No interactive prompt unless routed through an explicitly supported host-interaction contract.

Process isolation from HAP.App.exe.

Prefer one process per provider instance.

8. Temporary Headless PowerShell Legacy Bridge

Create a new PowerShell compatibility module rather than invoking the large UI script.

Suggested location:

D:\Atlas\src\Compatibility\HAP.LegacyBridge.psm1

This bridge is migration-only. It is not the customer provider SDK and must not become the permanent extension API.

The bridge must expose a small, stable set of headless commands. Initial candidates include:

Get-HapRuntimeProfiles
Get-HapRuntimeProfile
Test-HapRuntimeProfile
Start-HapRuntimeSession
Stop-HapRuntimeSession
Get-HapProviderHealth
Search-HapUser
Get-HapUserDetails
Invoke-HapNewUserPreflight
Invoke-HapNewUserCreation

Only add commands when a migration slice requires them.

Every bridge command must:

Accept simple values or a structured JSON request.

Call an existing Core, Application, Domain, or Infrastructure function.

Normalize the result into a stable DTO.

Return a structured result envelope.

Distinguish warnings from fatal errors.

Include a correlation ID.

Avoid references to WPF controls.

Avoid dependence on UI globals.

Avoid raw human-readable output that the C# application would have to parse.

Never return live PSObject instances across the process boundary.

Never prompt interactively unless a defined host interaction contract exists.

Redact credentials, tokens, secure strings, and sensitive connection details.

Do not import or execute Start-HybridAdminConsole.ps1 from the worker.

The bridge and legacy worker must be deleted after native first-party parity and final cutover. No third-party provider may depend on HAP.LegacyBridge.psm1.

9. Permanent Third-Party Provider Extension Architecture

9.1 Supported extension types

HAP should support two provider implementation models behind common capability contracts:

IHapProvider / capability interfaces
    ├── Native .NET provider
    └── PowerShellProviderProxy
            ↓
       HAP.PowerShellPluginHost
            ↓
       Customer PowerShell module

Native .NET providers are preferred for maximum performance and integration depth. PowerShell providers are supported as the lower-friction customer extension path.

9.2 Provider contract principles

Third-party providers must integrate through versioned HAP contracts rather than arbitrary command discovery.

A provider must declare:

Stable provider ID.

Display name and publisher.

Provider version.

HAP extension API version.

Implementation type.

Capabilities.

Configuration schema.

PowerShell runtime requirements when applicable.

Required permissions or capability grants.

Supported operations.

Optional health-check and lifecycle features.

Reference abstraction:

public interface IHapProvider
{
    ProviderDescriptor Descriptor { get; }

    Task<ProviderHealthResult> TestConnectionAsync(
        ProviderContext context,
        CancellationToken cancellationToken);

    Task<ProviderOperationResult> ExecuteAsync(
        ProviderOperationRequest request,
        IProgress<OperationProgress>? progress,
        CancellationToken cancellationToken);
}

Use narrower capability interfaces where practical instead of one unrestricted universal interface.

9.3 Capability-based integration

Providers must declare supported capabilities such as:

ProviderHealth
UserLookup
UserProvisioning
UserDeprovisioning
DeviceLookup
DeviceEnrollment
DeviceRetirement
CredentialReset
LicenseAssignment
GroupMembership
Reporting

Capabilities are versioned contracts. HAP grants and invokes only approved capabilities. A provider must not receive unrelated operations merely because it is installed.

New verticals such as MobilePass should be introduced by implementing the capabilities they support, not by modifying HAP's built-in UI or core orchestration.

9.4 PowerShell module package

A customer PowerShell provider should use a package similar to:

Contoso.MobilePass\
  Contoso.MobilePass.psd1
  Contoso.MobilePass.psm1
  hap-provider.json
  configuration.schema.json
  operations\
  README.md

Reference hap-provider.json:

{
  "schemaVersion": "1.0",
  "providerId": "contoso.mobilepass",
  "displayName": "MobilePass",
  "publisher": "Contoso",
  "version": "1.2.0",
  "hapApiVersion": "1.0",
  "implementation": "PowerShell",
  "powerShellEdition": "Core",
  "minimumPowerShellVersion": "7.4",
  "entryModule": "Contoso.MobilePass.psd1",
  "configurationSchema": "configuration.schema.json",
  "capabilities": [
    "ProviderHealth",
    "UserLookup",
    "UserProvisioning",
    "CredentialReset"
  ]
}

HAP must validate the JSON manifest before executing module code.

9.5 Standard PowerShell entry points

The public SDK should define a minimal, versioned set of entry points such as:

Initialize-HapProvider
Test-HapProviderConnection
Get-HapProviderCapabilities
Invoke-HapProviderOperation
Disconnect-HapProvider

The exact names may change before the SDK is frozen, but all providers must conform to one documented contract. HAP must not infer behavior from arbitrary exported functions.

Every operation must use structured request and response envelopes. Human-readable console output must not be parsed as application data.

9.6 UI extension policy

Third-party PowerShell modules must not inject WPF views, controls, code-behind, or arbitrary UI assemblies into HAP.

HAP owns the UI. Extensions may provide approved declarative schemas for:

Configuration fields.

Operation input forms.

Validation constraints.

Choice lists when safely retrievable through a declared operation.

Read-only result presentation metadata.

Example operation form schema:

{
  "operation": "MobilePass.EnrollUser",
  "fields": [
    {
      "name": "userPrincipalName",
      "type": "string",
      "required": true
    },
    {
      "name": "deliveryMethod",
      "type": "choice",
      "values": ["Email", "SMS"]
    }
  ]
}

HAP renders the form and sends validated values through the provider contract.

9.7 Installation, registration, and approval

PowerShell providers must be installed only into an HAP-controlled location such as:

C:\ProgramData\HAP\Providers\

Installation or enablement must require administrative approval. The registry must record:

Provider ID and version.

Publisher.

Exact module path.

File hashes.

Signature status and signing identity when available.

Approved capabilities.

Configuration instance ID.

Enabled or disabled state.

Installation and update timestamp.

HAP must not discover or execute modules merely because they appear in PSModulePath.

9.8 Execution and security boundary

A PowerShell provider is installed executable code and must be treated similarly to an installed application, not as untrusted text safely contained by a runspace.

Requirements:

Execute outside the main HAP process.

Prefer one plugin-host process per provider instance.

Use an exact approved module path.

Revalidate manifest, hash, and signature before launch.

Apply operation timeouts and cancellation.

Terminate a hung host without terminating HAP.

Isolate provider global state and module dependencies.

Redact credentials and tokens from protocol payloads and logs.

Record provider ID, version, operation, user, result, and correlation ID in audit logs.

Do not permit silent self-update.

Display clear trust information for unsigned or changed modules.

9.9 No-PowerShell normal mode

When no enabled PowerShell provider is required:

HAP must not launch pwsh.exe, powershell.exe, or HAP.PowerShellPluginHost.exe.

HAP must not load System.Management.Automation into the main application process.

All built-in HAP workflows must remain fully operational through native .NET providers.

This requirement must be covered by automated tests and final cutover validation.

10. Core Contract Standards

9.1 Operation result

All application and provider operations must return a consistent typed result.

Reference shape:

public sealed record OperationResult<T>(
    bool Success,
    T? Data,
    IReadOnlyList<OperationWarning> Warnings,
    IReadOnlyList<OperationError> Errors,
    string CorrelationId,
    bool IsPartial = false);

Reference error shape:

public sealed record OperationError(
    string Code,
    string UserMessage,
    string? DiagnosticMessage,
    bool IsRetryable,
    string? Provider = null);

Reference warning shape:

public sealed record OperationWarning(
    string Code,
    string Message,
    string? Provider = null);

9.2 Required operation behavior

Every long-running operation must define:

Cancellation behavior.

Timeout behavior.

Progress reporting.

Correlation IDs.

Warning versus fatal error semantics.

Partial-result behavior.

Authentication-required behavior.

Provider-unavailable behavior.

Retryability.

User-safe messages.

Diagnostic messages.

Secret redaction.

Reference service pattern:

Task<OperationResult<TResponse>> ExecuteAsync(
    TRequest request,
    IProgress<OperationProgress>? progress,
    CancellationToken cancellationToken);

9.3 Protocol envelope

The worker protocol must be versioned.

Reference request:

{
  "protocolVersion": "1.0",
  "requestId": "guid",
  "operation": "GetRuntimeProfiles",
  "payload": {},
  "timeoutSeconds": 60
}

Reference response:

{
  "protocolVersion": "1.0",
  "requestId": "guid",
  "success": true,
  "data": {},
  "warnings": [],
  "errors": [],
  "isPartial": false
}

Unknown protocol versions, operations, or fields that invalidate safe execution must fail clearly rather than being silently ignored.

11. Configuration and Runtime Profile Rules

Configuration and runtime-profile behavior must be ported before broad UI work because it determines the validity of every workflow.

11.1 Required capabilities

Load runtime profiles from documented locations.

Merge configuration using one deterministic precedence order.

Validate provider combinations before runtime launch.

Distinguish live, simulation, disabled, legacy-migration, native, and extension provider states.

Identify required authentication modes.

Identify invalid combinations before executing providers.

Produce structured validation results.

Preserve unknown configuration fields where practical during edits.

Avoid hidden fallback values.

Avoid UI controls as configuration storage.

Validate that referenced extensions are installed, approved, compatible, enabled, and granted the requested capabilities.

11.2 Provider implementation selection

Provider selection must be explicit.

Migration-time example:

{
  "providers": {
    "graph": {
      "enabled": true,
      "mode": "Live",
      "implementation": "LegacyPowerShell"
    },
    "activeDirectory": {
      "enabled": true,
      "mode": "Live",
      "implementation": "NativeDotNet"
    },
    "mobilePass": {
      "enabled": true,
      "mode": "Live",
      "implementation": "PowerShellPlugin",
      "providerId": "contoso.mobilepass",
      "instanceId": "mobilepass-production"
    }
  }
}

Validated implementation values may include:

LegacyPowerShell   Temporary migration-only value
NativeDotNet       Built-in or approved native provider
PowerShellPlugin   Approved third-party PowerShell provider
Simulator          HAP simulator implementation
Disabled           No implementation active

LegacyPowerShell must be removed from supported production configuration after final native cutover.

Never implement behavior equivalent to:

Try native .NET.
If it fails, silently execute a legacy or third-party PowerShell provider.

Fallback must require explicit configuration or a visible user decision and must be logged.

11.3 Extension configuration

Extension configuration must reference a registered provider and instance rather than an arbitrary filesystem path supplied by a normal runtime profile.

Secrets must not be stored directly in general JSON configuration. Configuration schemas should identify secret fields so HAP can store them through an approved secure-secret mechanism and provide them to the provider only when required.

12. Migration Phases

Phase 0: Baseline, Inventory, Compatibility, and Extension Requirements

Objectives

Document current behavior, prove how the existing PowerShell modules can be hosted during migration, and inventory the customer-provider scenarios the final extension SDK must support.

Deliverables

docs/CSharpMigrationInventory.md

Service and function mapping table.

Existing workflow inventory.

Provider and module dependency inventory.

Authentication flow inventory.

Global-state and UI-dependency inventory.

Compatibility matrix for Windows PowerShell 5.1, PowerShell 7, in-process, and out-of-process legacy execution.

Golden test fixtures for representative existing behavior.

Initial extension capability inventory, including at least one example vertical such as MobilePass.

Draft separation of temporary legacy bridge contracts from permanent provider SDK contracts.

No production behavior changes.

Required mapping fields

For each existing operation, document:

Current function name.

Source module.

Input parameters.

Output shape.

Side effects.

Required privileges.

Provider dependencies.

Live/simulation differences.

Error behavior.

Prompt behavior.

STA/threading requirements.

Global variables or UI dependencies.

Candidate C# service and method.

Candidate provider capability.

Exit criteria

The team can identify which PowerShell runtime each legacy provider requires.

The first migration workflow is selected.

Golden fixtures exist for that workflow.

Temporary and permanent PowerShell responsibilities are clearly separated.

No unresolved architectural assumption blocks the legacy worker proof of concept.

Phase 1: .NET Skeleton, Contracts, Configuration, and Extension Abstractions

Objectives

Create the solution foundation without changing live provider behavior.

Deliverables

.NET 10 solution and projects.

global.json.

Shared build properties.

Dependency injection composition root.

Logging foundation.

Contract result types.

Legacy-worker and plugin-protocol request/response foundations kept separate.

Runtime-profile models.

Configuration loading and deterministic merging.

Runtime-profile validation.

Provider and capability abstractions with no PowerShell dependency.

Extension descriptor and registration models.

Unit tests for configuration precedence, invalid combinations, and disabled-extension behavior.

Minimal application window capable of displaying startup failures.

Exit criteria

dotnet restore, dotnet build, and dotnet test pass.

The application starts without importing or launching PowerShell.

Runtime profiles can be loaded and validated by C# tests.

Extension descriptors can be validated without executing provider code.

No provider operation is executed yet.

Phase 2: Temporary Headless Bridge and Legacy PowerShell Worker

Objectives

Establish a stable, testable boundary to the existing first-party PowerShell implementation.

Initial scope

Implement only the operations needed for runtime profile discovery, validation comparison, runtime initialization, and provider health.

Deliverables

HAP.LegacyBridge.psm1.

Legacy worker protocol version 1.0.

Worker startup handshake.

One end-to-end command such as Get-HapRuntimeProfiles.

Timeout and cancellation.

Worker restart after fault or hang.

Structured error mapping.

Integration tests using a controlled fixture or simulator.

Tests proving the legacy worker cannot load arbitrary third-party modules.

Exit criteria

The C# process can start the legacy worker and validate the handshake.

The worker returns structured profile data.

Invalid requests fail predictably.

Timeout and cancellation behavior are tested.

No raw PowerShell objects cross the boundary.

The legacy protocol is not presented as the public provider SDK.

Phase 3: First Read-Only Vertical Slice

Approved first workflow

Launch HAP
    ↓
Load runtime profiles
    ↓
Select a profile
    ↓
Validate the profile
    ↓
Initialize the selected runtime
    ↓
Display provider health
    ↓
Shut down cleanly

Deliverables

Runtime Profile selector View.

Runtime Profile selector ViewModel.

Runtime session application service.

Legacy PowerShell-backed runtime adapter.

Provider health DTOs and UI presentation.

Progress and cancellation handling.

Structured logs with correlation IDs.

Contract tests comparing normalized PowerShell results with expected fixtures.

Exit criteria

The .NET application can launch a valid simulation profile.

Invalid profile combinations are rejected before provider execution.

Provider health is displayed from normalized application state.

Closing the application shuts down the runtime and legacy worker cleanly.

No UI control acts as the source of provider state.

Phase 4: User Lookup Vertical Slice

Workflow

Search user
    ↓
Query configured providers
    ↓
Normalize results
    ↓
Display a hybrid user summary

Deliverables

IUserQueryService or equivalent focused interface.

SearchUserRequest and response DTOs.

Incremental domain models required by this workflow.

Legacy PowerShell-backed adapter.

User Lookup View and ViewModel.

Partial-result behavior when one provider is unavailable.

Golden contract fixtures for representative users, including mailboxless and partially available users.

Exit criteria

Results match normalized PowerShell behavior for approved fixtures.

Missing provider data is distinguishable from operation failure.

The UI presents warnings separately from fatal errors.

Phase 5: Remaining UI Workflows

Migrate workflows individually in this general order:

Runtime Profile selector and launch status.

User Lookup.

Graph, authentication, Exchange, and Active Directory status cards.

Device Management.

New User Wizard preflight.

New User Wizard creation.

User administration actions and dialogs.

Group, licensing, mailbox, reporting, and export workflows.

Every workflow must include:

C# View.

ViewModel.

Application service interface.

Request and response contracts.

Legacy PowerShell-backed adapter while required.

Unit tests.

Contract or integration tests.

Documented parity checklist.

Do not migrate multiple major workflows in one Codex task.

Phase 6: Native First-Party Provider Migration

Port providers only after the UI and application workflows consume stable contracts.

Recommended order:

Simulator/mock provider.

Microsoft Graph.

Exchange Online.

Active Directory.

Exchange on-premises.

For each provider:

Preserve the existing provider and capability interfaces.

Add a native implementation project.

Add provider contract tests.

Run the same fixtures against legacy PowerShell and native implementations.

Document expected differences.

Require explicit configuration to select the native implementation during migration.

Keep the legacy implementation available only until parity and operational testing are approved.

Remove the legacy implementation after cutover rather than retaining it as a permanent fallback.

Exit criteria for each provider

Read workflows pass parity tests.

Write workflows pass controlled integration tests.

Authentication behavior is documented and repeatable.

Timeout, retry, cancellation, and error mapping are consistent.

Provider can be selected explicitly in a runtime profile.

No silent fallback occurs.

The first-party provider no longer requires PowerShell after its cutover.

Phase 7: Permanent Provider Extension Platform

Objectives

Create the supported provider SDK and isolated execution path for customer-created verticals without preserving first-party PowerShell dependencies.

Recommended implementation order

Freeze version 1.0 provider descriptors and capability contracts.

Implement the extension registry and HAP-controlled provider directory.

Implement manifest, schema, version, hash, and signature validation.

Implement HAP.Plugin.Protocol independently of the legacy worker protocol.

Implement PowerShellProviderProxy.

Implement HAP.PowerShellPluginHost with one-provider-per-process support.

Implement the PowerShell SDK module, templates, and conformance tests.

Implement HAP-owned declarative configuration and operation forms.

Build a sample provider for a non-core vertical such as MobilePass or a safe mock equivalent.

Validate disabled/no-plugin operation without launching PowerShell.

Deliverables

Versioned extension manifest schema.

Versioned capability and operation contracts.

Extension registry and administrative approval workflow.

HAP-controlled provider installation directory.

Permanent plugin protocol.

Isolated PowerShell plugin host.

PowerShell provider proxy.

SDK module, templates, samples, and author documentation.

Conformance-test harness.

Sample third-party provider.

Audit and trust-status UI.

Declarative form rendering for approved schemas.

Exit criteria

A sample provider can be installed, approved, configured, enabled, health-tested, and invoked without modifying HAP source code.

The sample provider cannot inject UI into the main process.

A hung provider host can be terminated without closing HAP.

Changed hashes or invalid signatures produce a visible block or warning according to policy.

Undeclared capabilities cannot be invoked.

Disabling the provider prevents host launch.

With no enabled PowerShell provider, no PowerShell process is launched.

The permanent plugin host does not import or call the legacy bridge.

Phase 8: Parity, Packaging, Native Cutover, and Legacy Removal

Objectives

Prove the .NET application can replace the PowerShell UI, retire every first-party PowerShell provider, and retain only the optional third-party extension host.

Deliverables

Full workflow parity matrix.

Side-by-side validation results.

Self-contained Windows publish configuration.

Installer or approved deployment package.

Upgrade and rollback procedure.

Configuration migration tool or documented migration procedure.

Operational logging and diagnostic collection procedure.

Signed executable if organizational requirements call for code signing.

Removal of the legacy bridge, legacy worker, and legacy provider adapter projects after approved cutover.

Packaging options that either include or omit the optional PowerShell extension runtime according to product policy.

Cutover criteria

A first-party PowerShell workflow or provider may be retired only when:

Functional parity is approved.

Required tests pass.

Live validation is complete.

Rollback is documented.

Support diagnostics are available.

The old implementation is not required by another unmigrated workflow.

Final cutover is complete only when:

All built-in workflows use native .NET providers.

HAP.LegacyBridge.psm1, HAP.LegacyPowerShellWorker, its protocol, and its adapter are removed from production packaging.

No built-in configuration supports LegacyPowerShell.

HAP passes all built-in workflow tests on a system where no PowerShell provider is enabled.

The optional plugin host remains separate and is launched only for approved third-party PowerShell providers.

The original PowerShell application must remain available as a rollback path only until final cutover is formally accepted.

13. Testing Strategy

13.1 Unit tests

Cover:

Configuration precedence.

Runtime-profile validation.

DTO validation.

Error and warning mapping.

ViewModel state transitions.

Cancellation and timeout logic.

Provider selection.

Secret redaction.

Extension manifest and schema validation.

Capability grants.

Registry enable/disable behavior.

No-plugin startup behavior.

13.2 Contract tests

Use normalized fixtures to assert that legacy PowerShell and C# boundaries agree during migration on:

Request shape.

Response shape.

Nullability.

Warnings.

Errors.

Partial results.

Provider attribution.

Correlation IDs.

Permanent extension contract tests must separately verify:

Plugin handshake and API version negotiation.

Manifest compatibility.

Capability declaration and enforcement.

Operation request and response envelopes.

Progress, cancellation, timeout, and shutdown.

Unsupported-operation behavior.

Protocol behavior for malformed or unknown fields.

Do not reuse the legacy worker protocol as the provider SDK contract.

13.3 Integration tests

Prefer simulator or isolated test environments. Live integration tests must be explicitly marked and must not run automatically against production systems.

Plugin integration tests must execute sample providers outside the main HAP process and verify process termination, restart, auditing, and module isolation.

13.4 Golden fixtures

Capture representative cases such as:

Valid simulation runtime profile.

Invalid simulation-directory configuration.

Valid live profile.

Mixed live and simulation providers.

Required authentication unavailable.

Provider unavailable.

Normal hybrid user.

Mailboxless user.

Graph-only or AD-only result.

Partial provider failure.

New User Wizard validation failure.

Successful preflight without performing a write.

Valid third-party provider manifest.

Unsupported HAP API version.

Changed module hash.

Disabled provider.

Undeclared capability request.

Hung provider operation.

No enabled PowerShell extensions.

Golden fixtures must contain sanitized data only.

13.5 Required no-PowerShell tests

Final built-in acceptance tests must verify that, with no enabled PowerShell extension:

All built-in workflows complete successfully.

No pwsh.exe or powershell.exe process is created by HAP.

HAP.PowerShellPluginHost.exe is not launched.

No legacy worker files are required.

No built-in provider imports a .ps1 or .psm1 file.

14. Security and Secrets

The migration and extension platform must not weaken existing security behavior.

General requirements:

Never log passwords, tokens, refresh tokens, client secrets, secure strings, or full authorization headers.

Do not place secrets in JSON protocol payloads unless absolutely required and explicitly protected.

Prefer OS-provided secure storage or established authentication libraries.

Redact secrets from exception messages before returning them to the UI.

Separate user-safe errors from diagnostic details.

Avoid persisting access tokens in application configuration.

Maintain least-privilege Graph and administrative permissions.

Document elevated operations.

Validate all worker and plugin operation names and payloads.

Third-party provider requirements:

Treat installed modules as executable code, not as safely sandboxed scripts.

Require administrative installation or approval.

Load only exact registered module paths under HAP control.

Validate provider ID, API version, manifest schema, hash, and signature policy before execution.

Do not scan or load the general PSModulePath.

Do not permit silent self-update or path substitution.

Record approved capabilities and block undeclared operations.

Prefer one plugin-host process per provider instance.

Terminate hung providers without terminating HAP.

Display publisher, version, signature state, and trust warnings to administrators.

Keep provider credentials scoped to the provider instance and operation.

Do not expose unrelated HAP secrets to a provider.

Maintain auditable installation, update, enablement, invocation, and removal events.

Do not add PowerShell execution-policy bypasses without documented justification and product approval.

A constrained runspace may reduce accidental access, but it must not be represented as a complete hostile-code sandbox.

15. Logging and Diagnostics

Every operation must include a correlation ID shared across:

ViewModel action.

Application service.

Provider adapter.

Worker request.

PowerShell bridge execution.

Result or exception.

Logs should capture:

Operation name.

Runtime profile ID or safe name.

Provider name.

Provider ID, publisher, and version when an extension is involved.

Implementation type.

Start and completion timestamps.

Duration.

Success, warning, partial, cancellation, timeout, or failure state.

Sanitized diagnostic details.

Logs must not capture secrets or unnecessarily sensitive user data.

16. Codex Execution Rules

Codex must follow these rules for every migration task:

Inspect relevant existing files before changing code.

Modify only the directories and files explicitly allowed by the task.

Do not perform unrelated cleanup.

Do not rewrite providers unless the task explicitly requests a provider port.

Do not modify the existing PowerShell UI unless extracting an approved headless bridge dependency.

Do not use Start-HybridAdminConsole.ps1 as the backend.

Do not expose PSObject outside a PowerShell worker or adapter boundary.

Do not invent configuration fallbacks.

Do not silently fall back between provider implementations.

Do not change public contracts without updating contract tests and migration documentation.

Add or update tests for every behavior change.

Run restore, build, and relevant tests before completing the task.

Report exactly what changed, tests run, and any unresolved risks.

Stop after completing the assigned slice.

Do not continue into the next migration phase without a new task.

Keep the legacy worker protocol and permanent plugin protocol separate.

Do not add first-party business logic to HAP.PowerShellPluginHost or the PowerShell provider SDK.

Do not retain a legacy PowerShell provider after its native cutover merely as a convenience fallback.

Do not let customer modules inject WPF UI or load inside HAP.App.exe.

Do not discover extensions from the general PSModulePath.

Do not launch a PowerShell host when no enabled PowerShell provider requires it.

Treat extension manifest, capability, signature, hash, and registry checks as security-sensitive behavior requiring tests.

Expected commands after the solution exists

cd D:\Atlas\src-dotnet

dotnet restore .\HAP.sln
dotnet build .\HAP.sln --no-restore
dotnet test .\HAP.sln --no-build

A task may use narrower project-level commands when only a subset is affected, but the full solution must be run at phase checkpoints.

17. Recommended Codex Task Sequence

Each item below should be a separate Codex task and normally a separate commit.

Migration foundation

Task 1: Inventory the first workflow

Analyze runtime-profile loading, validation, runtime initialization, and provider-health behavior. Produce documentation only. Make no production code changes.

Task 2: Inventory extension requirements

Document likely customer-provider verticals, capability needs, configuration needs, and trust requirements. Include MobilePass as a concrete example without implementing it.

Task 3: Perform the legacy PowerShell compatibility spike

Test required modules and workflows under Windows PowerShell 5.1, PowerShell 7, in-process, and out-of-process execution. Produce the compatibility matrix and recommendation. Do not begin the application rewrite.

Task 4: Create the .NET 10 solution skeleton

Create only the approved projects, shared build files, SDK pinning, and empty tests. Do not add provider behavior or UI workflows.

Task 5: Add core result and capability contracts

Implement OperationResult<T>, errors, warnings, progress, correlation ID types, provider descriptors, and initial capability identifiers with tests. Do not implement PowerShell hosting.

Task 6: Add runtime-profile and extension-registration models

Implement configuration models, deterministic merge behavior, validation, extension references, and tests. Do not execute providers.

Temporary legacy path

Task 7: Define legacy worker protocol version 1.0

Implement legacy request and response envelopes and serialization tests. Do not start a PowerShell process yet.

Task 8: Create the minimal headless legacy bridge

Add only Get-HapRuntimeProfiles and any narrowly required internal helpers. Do not import the UI script.

Task 9: Build the out-of-process legacy worker proof of concept

Start the approved legacy PowerShell runtime, perform a handshake, execute Get-HapRuntimeProfiles, and return typed JSON. Include timeout, cancellation, and process cleanup.

Task 10: Add the legacy PowerShell provider adapter

Wrap the legacy worker client behind a C# interface. Map protocol errors into OperationResult<T>. Do not build WPF UI yet.

Task 11: Build the Runtime Profile selector ViewModel

Implement loading, selection, validation, progress, cancellation, and errors. Do not add provider-specific logic to the ViewModel.

Task 12: Build the minimal Runtime Profile selector View

Bind the ViewModel to WPF. Keep code-behind limited to presentation concerns.

Task 13: Complete the first vertical slice

Add runtime initialization, provider-health display, shutdown, tests, and parity documentation. Stop after the read-only slice passes.

Permanent extension platform

Do not begin these tasks until the base provider and capability contracts are stable enough for versioning.

Task 14: Define plugin manifest schema and API versioning

Create the extension manifest schema, compatibility rules, capability declarations, and validation tests. Do not execute modules.

Task 15: Implement the extension registry

Register only administrator-approved providers from HAP-controlled paths. Add hash, signature-state, enablement, and capability-grant tests.

Task 16: Define HAP.Plugin.Protocol version 1.0

Create a permanent protocol separate from the legacy worker protocol. Include handshake, metadata, health, operation, progress, cancellation, and shutdown contracts.

Task 17: Implement the isolated PowerShell plugin host

Load one exact approved sample module, enforce the manifest and provider identity, and return structured results. Do not reuse the legacy bridge.

Task 18: Implement PowerShellProviderProxy

Expose the sample provider through normal HAP capability interfaces. Start the host only when the enabled provider is invoked.

Task 19: Create the PowerShell provider SDK and sample

Add templates, SDK helpers, schemas, documentation, conformance tests, and a safe sample provider modeled after a MobilePass-style vertical.

Task 20: Add declarative extension forms

Render HAP-owned configuration and operation forms from approved schemas. Do not permit custom WPF injection.

Task 21: Prove the Extension Host Stays Dormant

Add automated tests showing that merely installing extension support does not launch HAP.PowerShellPluginHost.exe, pwsh.exe, or powershell.exe. The permanent plugin host may start only when an administrator-approved, enabled PowerShell provider is actually invoked.

During the migration, built-in workflows may still use the temporary legacy worker until their native cutover tasks are complete. The final proof that all built-in workflows make zero PowerShell calls is Task 58.

Native first-party migration and final cutover

Tasks 22 through 60 assume Tasks 1 through 21 have been completed and accepted. Each task must be executed as a separate Codex assignment and should normally produce one focused commit. Codex must stop after the assigned task and must not continue automatically.

Rules for every task from Task 22 onward

Before changing code, Codex must:

Read this migration document and the most recent migration status report.

Inspect the relevant existing PowerShell implementation and current .NET contracts.

Run git status and report unrelated existing changes before modifying files.

Identify the exact files and projects it intends to modify.

Preserve public contracts unless the task explicitly authorizes a versioned contract change.

For every implementation task, Codex must:

Keep each change inside the named provider, workflow, tests, and migration documentation.

Use existing request, response, result, progress, cancellation, correlation, and logging contracts.

Add or update unit, contract, parity, and integration tests appropriate to the slice.

Never silently fall back from NativeDotNet to LegacyPowerShell.

Never add first-party functionality to HAP.PowerShellPluginHost or the customer PowerShell SDK.

Never execute customer plugins inside HAP.App.exe.

Never expose raw PowerShell objects outside a temporary legacy boundary.

Never use undocumented service endpoints, reverse-engineered private APIs, or direct directory-attribute manipulation that Microsoft does not support for the operation.

Treat unavailable supported APIs as a product-scope decision, not permission to preserve hidden first-party PowerShell calls.

Update the parity matrix, migration status, known blockers, and rollback notes before completing the task.

Run restore, build, relevant tests, and the full solution test suite at phase checkpoints.

Report exact commands executed, test results, changed files, remaining risks, and the recommended next task.

The recommended shared migration records are:

D:\Atlas\docs\migration\MigrationStatus.md
D:\Atlas\docs\migration\ProviderParityMatrix.md
D:\Atlas\docs\migration\CapabilityDisposition.md
D:\Atlas\docs\migration\LiveValidationRunbook.md

If these files do not exist, Task 22 may create them. Later tasks must update rather than replace their history.

Task 22: Plan the First Native Provider Parity Slice

Objective: Select and fully specify the first native .NET provider slice without changing production behavior.

Use the Directory Simulator as the first provider. Select ProviderHealth and one read-only UserLookup operation as the initial capability slice unless repository inspection proves a smaller existing capability is more appropriate.

Allowed scope: Migration documentation, parity fixtures, test data, and analysis-only additions. Do not implement provider behavior or change routing.

Required work:

Inventory the existing simulator modules, exported functions, configuration, state files, generated identifiers, timestamps, warnings, errors, and global dependencies.

Map the selected PowerShell functions to existing C# provider and capability contracts.

Define normalized request and response fixtures for success, not found, invalid request, unavailable provider, invalid configuration, cancellation, timeout, multiple matches, and partial user data.

Define normalization rules for nondeterministic values such as timestamps, generated IDs, ordering, and environment-specific paths.

Record the exact native project, classes, tests, and configuration keys planned for Task 23.

Create or update the provider parity matrix and migration status records.

Acceptance criteria:

The first capability has an explicit request, response, error, warning, progress, timeout, and cancellation contract.

Fixtures do not depend on PowerShell formatting or PSObject serialization details.

No production routing or provider implementation changes are made.

The plan names all files expected to be created or modified in Task 23.

Suggested commit: docs(migration): define first native simulator parity slice

Task 23: Implement the First Native Simulator Slice

Objective: Implement native .NET ProviderHealth and the selected read-only simulator UserLookup capability behind existing contracts.

Allowed scope: HAP.Providers.Simulator, provider abstractions/contracts only when strictly required, simulator tests, fixtures, and migration documentation. Do not modify WPF views or route production workflows yet.

Required work:

Add native provider registration metadata and deterministic configuration validation.

Implement structured success, warning, error, partial-result, timeout, and cancellation behavior.

Preserve correlation IDs and audit-safe structured logs.

Ensure deterministic simulator data and thread-safe access to simulator state.

Add unit tests and parity tests using the Task 22 fixtures.

Prove this provider project does not reference or launch PowerShell.

Acceptance criteria:

Native results match normalized legacy results for all approved fixtures.

The implementation does not reference System.Management.Automation, pwsh.exe, powershell.exe, .ps1, .psm1, the legacy worker, or the plugin host.

Provider code has no WPF dependencies.

The existing application continues using its previously configured implementation because routing has not changed.

Suggested commit: feat(simulator): add native health and user lookup slice

Task 24: Cut Over One Read-Only Simulator Workflow

Objective: Route the runtime-profile health and user-lookup vertical slice through the native simulator by explicit configuration.

Allowed scope: Provider registration/factory, runtime-profile implementation selection, the affected application service and ViewModel, routing tests, and migration documentation.

Required work:

Support explicit implementation values NativeDotNet and LegacyPowerShell during migration.

Route NativeDotNet exclusively to the native simulator.

Route LegacyPowerShell exclusively to the temporary legacy simulator.

Return a structured validation error for unknown implementation values.

Add diagnostics recording provider ID, implementation, capability, correlation ID, duration, status, and whether any PowerShell process was launched.

Add tests proving native failure does not trigger legacy fallback.

Acceptance criteria:

The selected read-only workflow completes entirely through native .NET when configured for NativeDotNet.

The UI consumes the same application contracts in both modes.

Switching between implementations requires configuration only, not code changes.

Native execution launches no PowerShell process.

No silent fallback exists.

Suggested commit: feat(runtime): cut over first simulator workflow to native provider

Task 25: Complete Native Simulator Read Capabilities

Objective: Port every remaining read-only simulator capability required by built-in HAP workflows.

Allowed scope: Simulator provider, affected capability contracts only when justified, simulator parity fixtures/tests, and migration documentation. Do not port mutations in this task.

Required work:

Inventory and implement remaining simulator reads in small internal commits if necessary, including applicable user, group, license, mailbox, device, provider-health, configuration-preview, and reporting queries.

Preserve partial-result and cross-provider attribution semantics.

Add deterministic sorting and stable normalized identifiers.

Add parity fixtures for empty collections, missing optional properties, malformed state, and large result sets.

Add cancellation, timeout, concurrency, and pagination tests where applicable.

Acceptance criteria:

Every simulator read capability used by HAP has native parity coverage.

No read workflow requires the legacy simulator when NativeDotNet is selected.

No first-party PowerShell dependency is introduced.

Remaining simulator write capabilities are explicitly listed for Task 26.

Suggested commit: feat(simulator): complete native read capability parity

Task 26: Complete Native Simulator Write and State Capabilities

Objective: Port all simulator mutations and state-management behavior required by built-in HAP workflows.

Allowed scope: Simulator provider, simulator state persistence, write contracts only when justified, tests, and migration documentation.

Required work:

Implement applicable create, update, delete, membership, licensing, mailbox, device, credential, and New User Wizard simulator operations.

Preserve validation order, generated values, idempotency expectations, and documented side effects.

Add transactional or compensating behavior for multi-step simulated operations.

Protect state persistence from partial writes and concurrent access.

Add reset/seed support for repeatable tests without exposing test controls in production UI.

Add parity tests for success, validation failure, duplicate request, partial failure, cancellation, timeout, rollback, and restart persistence.

Acceptance criteria:

All built-in simulator operations have native implementations and parity coverage.

Failed multi-step operations do not leave undocumented partial state.

Tests can reset and reproduce state deterministically.

Legacy simulator remains selectable only until Task 27 cutover.

Suggested commit: feat(simulator): complete native write and state parity

Task 27: Retire the Legacy Simulator Implementation

Objective: Make the native simulator the only built-in simulator implementation and remove its legacy PowerShell path.

Allowed scope: Simulator registration/configuration, legacy adapter mappings specific to the simulator, tests, documentation, and packaging references.

Required work:

Run the full simulator parity suite and all affected workflow tests.

Make native simulator selection the only supported built-in simulator configuration.

Reject or migrate old LegacyPowerShell simulator configuration with a clear message.

Remove simulator operations from the legacy bridge and worker routing.

Remove dead simulator-specific legacy code only after proving no other workflow uses it.

Update migration, configuration-upgrade, and rollback documentation.

Acceptance criteria:

No built-in simulator workflow can invoke PowerShell.

No runtime profile can select a legacy simulator implementation.

Full solution tests pass.

The simulator provider is marked complete in the parity matrix.

Suggested commit: refactor(simulator): retire legacy PowerShell implementation

Task 28: Inventory Microsoft Graph Capability and API Coverage

Objective: Produce a complete mapping from existing Graph-related PowerShell behavior to supported native Microsoft Graph APIs and SDK operations.

Allowed scope: Documentation, sanitized fixtures, parity plans, and analysis-only test scaffolding. Do not implement Graph calls yet.

Required work:

Inventory Graph authentication, users, groups, memberships, licenses, devices, directory roles, organization data, and any other current operations.

Record delegated versus application permission requirements and current consent assumptions.

Map each operation to a supported public API and classify it as read, write, destructive, long-running, or unsupported.

Identify paging, throttling, retry, eventual-consistency, batch, and partial-result behavior.

Define sanitized parity fixtures and a controlled live-validation plan.

Explicitly separate Graph directory/device operations from Exchange administration operations.

Acceptance criteria:

Every current Graph-backed operation has a disposition: native supported, redesign required, duplicate of another provider, or unsupported.

No undocumented/private endpoint is proposed.

Required permissions and authentication modes are documented per capability.

Task 29 scope is precisely defined.

Suggested commit: docs(graph): map native API coverage and parity plan

Task 29: Implement Native Graph Authentication and Session Foundation

Objective: Implement Graph authentication, token/session lifecycle, health checks, and client construction without porting business capabilities yet.

Allowed scope: HAP.Providers.Graph, authentication abstractions required by Graph, configuration, tests, and documentation. Do not modify unrelated providers or UI workflows.

Required work:

Implement the approved delegated and application authentication modes used by HAP.

Keep secrets and tokens out of logs and plain configuration.

Implement permission/consent validation, token refresh handling, cancellation, timeout, and deterministic error mapping.

Add provider health checks that distinguish configuration, authentication, authorization, network, throttling, and service failures.

Add test doubles so unit tests do not require live tenants.

Add a separately gated live smoke test and runbook.

Acceptance criteria:

Graph client/session creation is native .NET and testable.

Authentication-required state is represented through normal HAP contracts.

No Graph PowerShell module or legacy worker is used.

No live destructive tests run automatically.

Suggested commit: feat(graph): add native authentication and session foundation

Task 30: Implement Native Graph Read Capabilities

Objective: Port Graph-backed read operations used by HAP.

Allowed scope: Graph provider, applicable application capability adapters, tests, fixtures, and documentation. Do not port Graph writes in this task.

Required work:

Implement the approved user, group, membership, license, organization, device, and other read capabilities from Task 28.

Implement paging, retry/backoff, throttling mapping, cancellation, timeout, and eventual-consistency options where required.

Normalize Graph results into existing HAP DTOs without leaking SDK types.

Preserve provider attribution and partial-result semantics.

Add unit, contract, parity, and gated live-read tests.

Acceptance criteria:

All approved Graph read fixtures pass.

SDK types do not escape the provider boundary.

Read failures are categorized consistently.

No legacy fallback occurs when native Graph is selected.

Suggested commit: feat(graph): port native read capabilities

Task 31: Implement Native Graph Write Capabilities

Objective: Port approved Graph-backed mutations used by HAP.

Allowed scope: Graph provider, Graph write application adapters, tests, fixtures, and documentation.

Required work:

Implement approved create/update/delete, group-membership, license, device, credential, and related operations identified in Task 28.

Add request validation before remote calls.

Add idempotency and duplicate-request handling where the API supports or requires it.

Map asynchronous and partial operations into structured HAP results.

Add compensating behavior or explicit partial-failure reporting for multi-call operations.

Add gated non-production live tests and a manual validation runbook.

Acceptance criteria:

Approved write parity fixtures pass.

Destructive tests cannot run without an explicit opt-in and non-production target.

Failures never trigger legacy fallback.

Secrets and sensitive payloads are redacted.

Suggested commit: feat(graph): port native write capabilities

Task 32: Port Native Device Management Workflows

Objective: Complete native device-management behavior using the approved Graph/management APIs and existing HAP capability contracts.

Allowed scope: Graph device capabilities, Device Management application services/ViewModels/Views, tests, fixtures, and documentation.

Required work:

Inventory the current Device Management workflow and separate directory-device operations from any product-specific management operations.

Implement only operations with supported public APIs.

Preserve search, status, ownership, enable/disable, delete/retire, and other existing behavior where supported.

Add explicit unsupported-capability results rather than hidden PowerShell calls.

Add permission, partial-result, cancellation, timeout, and destructive-action confirmation tests.

Acceptance criteria:

The supported Device Management workflow runs natively.

Unsupported operations are visible and documented.

No Graph or device PowerShell module is invoked.

UI behavior remains contract-driven.

Suggested commit: feat(devices): cut over supported device management operations

Task 33: Cut Over and Retire the Legacy Graph Provider

Objective: Route all approved Graph-backed built-in workflows to native .NET and remove the legacy Graph path.

Allowed scope: Graph registration/routing, affected workflows, legacy Graph bridge commands, tests, configuration migration, and documentation.

Required work:

Run all Graph parity and gated live validation suites.

Make native Graph the only built-in implementation.

Remove LegacyPowerShell Graph selection and migrate or reject old configuration clearly.

Remove Graph commands from the legacy bridge and worker protocol only when no other provider depends on them.

Update permission, deployment, diagnostics, and rollback documentation.

Acceptance criteria:

No built-in Graph or device workflow can invoke PowerShell.

Native Graph passes approved live-read and controlled write validation.

Full solution tests pass.

Graph is marked complete in the parity matrix.

Suggested commit: refactor(graph): retire legacy PowerShell provider

Task 34: Inventory Active Directory Capability and Support Coverage

Objective: Map every current Active Directory operation to a supported native .NET directory protocol or library.

Allowed scope: Documentation, sanitized fixtures, parity plans, and analysis-only test scaffolding.

Required work:

Inventory connection, search, user, group, membership, password, enable/disable, organizational-unit, attribute, and replication-sensitive operations.

Record LDAP filters, search bases, controls, paging, referrals, global catalog use, credential modes, and required privileges.

Identify operations that are Active Directory responsibilities versus Exchange recipient-management responsibilities.

Define behavior for unreachable domain controllers, partial forests, referrals, stale data, and duplicate identities.

Define a safe lab/live validation plan.

Acceptance criteria:

Every AD operation has a supported native implementation path or an explicit blocker.

Exchange-specific attributes are not assumed safe for direct manipulation.

Task 35 scope and fixtures are complete.

Suggested commit: docs(ad): map native directory capability coverage

Task 35: Implement Native Active Directory Connection and Read Capabilities

Objective: Implement native AD connection/session behavior and all approved read operations.

Allowed scope: HAP.Providers.ActiveDirectory, related configuration and tests, parity fixtures, and documentation.

Required work:

Implement secure connection, credential handling, server/domain discovery according to approved configuration, health checks, paging, referrals, cancellation, and timeout.

Implement approved user, group, membership, OU, and attribute reads.

Normalize directory results into HAP contracts without exposing directory-library types.

Add test doubles or an isolated directory test environment.

Add parity and gated lab integration tests.

Acceptance criteria:

Approved AD read fixtures pass.

Connection/authentication errors are distinct from lookup failures.

No ActiveDirectory PowerShell module or legacy worker is used.

No Exchange-recipient mutation is added.

Suggested commit: feat(ad): add native connection and read capabilities

Task 36: Implement Native Active Directory Write Capabilities

Objective: Port supported AD mutations used by HAP.

Allowed scope: AD provider, AD write application adapters, tests, fixtures, and documentation.

Required work:

Implement approved user, group, membership, password, enable/disable, move, and ordinary directory-attribute operations.

Validate naming, uniqueness, required containers, permissions, and protected-object behavior before writes.

Add idempotency, concurrency, rollback/partial-failure, cancellation, timeout, and audit tests.

Do not directly edit Exchange attributes unless the supportability assessment explicitly approves that exact operation.

Add gated lab write tests.

Acceptance criteria:

Approved AD write parity fixtures pass.

Unsupported or Exchange-owned mutations return explicit capability errors.

No destructive lab test runs without explicit opt-in.

No legacy fallback occurs.

Suggested commit: feat(ad): port native write capabilities

Task 37: Integrate Native AD with Hybrid Application Workflows

Objective: Route AD-backed portions of user lookup, user administration, groups, and New User Wizard preflight through the native provider.

Allowed scope: AD-backed application orchestration, affected ViewModels, routing tests, and documentation. Do not complete the entire New User Wizard write path yet.

Required work:

Replace legacy AD reads and approved mutations in the selected workflows.

Preserve provider attribution and partial-results when other providers are unavailable.

Add tests for AD-only, Graph-only, hybrid, unavailable-AD, duplicate-user, and permission-failure scenarios.

Ensure UI state is derived from application results rather than controls.

Acceptance criteria:

Selected workflows use native AD exclusively when configured.

Native AD failure does not invoke the legacy adapter.

Existing hybrid result presentation remains stable.

Suggested commit: feat(workflows): integrate native Active Directory provider

Task 38: Cut Over and Retire the Legacy Active Directory Provider

Objective: Make native AD the only built-in AD implementation and remove the legacy AD route.

Allowed scope: AD registration/routing, legacy AD bridge commands, configuration migration, tests, and documentation.

Required work:

Complete parity and gated lab validation.

Remove legacy AD implementation selection.

Remove AD commands from the legacy bridge and worker when no other workflow uses them.

Update deployment prerequisites, diagnostics, and rollback documentation.

Acceptance criteria:

No built-in AD workflow invokes PowerShell.

Native AD is the only supported built-in implementation.

Full solution tests pass.

AD is marked complete in the parity matrix.

Suggested commit: refactor(ad): retire legacy PowerShell provider

Task 39: Perform the Exchange Online API Supportability Gate

Objective: Determine which existing Exchange Online operations can be migrated to supported native APIs and which require a product-scope decision.

Allowed scope: Documentation, current-source verification, sanitized fixtures, and analysis-only scaffolding. Do not implement Exchange Online calls in this task.

Required work:

Inventory every Exchange Online cmdlet/function currently used by HAP, including parameters, expected output, permissions, and workflow dependencies.

Map each operation to a currently supported public surface such as Microsoft Graph or the documented Exchange Online Admin API.

Classify each operation as:

NativeSupported

NativeSupportedWithBehaviorChange

DuplicateOfGraphOrADCapability

UnsupportedWithoutPowerShell

RemoveOrDefer

CandidateForCustomerExtension

Verify current Microsoft documentation rather than assuming that the Exchange Online PowerShell module's internal REST calls are a public API.

Prohibit reverse engineering of private endpoints or shipping hidden first-party PowerShell.

Produce a required product-decision list for every unsupported operation.

Acceptance criteria:

Every current Exchange Online operation has a documented disposition and evidence.

No implementation task is authorized for an unsupported/private endpoint.

Tasks 40 and 41 contain only approved supported operations.

The migration status clearly identifies any feature-scope reductions required to achieve zero first-party PowerShell.

Suggested commit: docs(exchange-online): complete API supportability gate

Task 40: Implement Native Exchange Online Authentication and Read Capabilities

Objective: Implement approved supported Exchange Online authentication/session behavior and read operations.

Allowed scope: HAP.Providers.ExchangeOnline, approved shared authentication components, tests, fixtures, and documentation.

Required work:

Implement only the public APIs approved by Task 39.

Implement authentication, permission validation, health, retry/throttling, cancellation, timeout, and error mapping.

Port approved mailbox, organization, domain, group membership, folder permission/delegation, or other supported reads.

Reuse Graph capabilities rather than duplicating them when Task 39 classifies an operation as Graph-owned.

Add unit, contract, parity, and gated live-read tests.

Acceptance criteria:

All approved read fixtures pass.

No Exchange Online PowerShell module, remote PowerShell, legacy worker, or undocumented endpoint is used.

Unsupported reads return explicit capability results and remain listed for disposition.

Suggested commit: feat(exchange-online): add supported native read capabilities

Task 41: Implement Native Exchange Online Write Capabilities

Objective: Implement approved supported Exchange Online mutations.

Allowed scope: Exchange Online provider, affected application adapters, tests, fixtures, and documentation.

Required work:

Implement only write operations approved by Task 39.

Add validation, concurrency, idempotency, partial-failure, cancellation, timeout, and audit behavior.

Add destructive-operation confirmation and gated non-production live tests.

Preserve clear behavior changes documented by the supportability gate.

Acceptance criteria:

Approved write parity fixtures pass.

Unsupported operations are not emulated with hidden PowerShell or private APIs.

Live tests require explicit opt-in and a non-production tenant.

Suggested commit: feat(exchange-online): add supported native write capabilities

Task 42: Resolve Unsupported Exchange Online Capabilities

Objective: Apply an explicit product decision to every Exchange Online operation classified as unsupported without PowerShell.

Allowed scope: Capability catalog, application behavior, UI availability states, customer-extension documentation, migration records, and tests. Do not implement unsupported APIs.

Required work:

For each unsupported operation, implement exactly one approved disposition:

Remove the built-in capability.

Defer it and display a clear unavailable reason.

Replace it with a supported Graph/AD/Exchange operation with documented behavior differences.

Expose only the generic capability contract so a customer-installed PowerShell provider may supply it.

Do not ship a HAP-owned PowerShell module as a concealed continuation of the legacy provider unless product policy is explicitly changed and this migration document is revised.

Acceptance criteria:

No unsupported operation remains ambiguously routed.

UI and contracts report unavailable capabilities clearly.

Customer-extension opportunities use the permanent plugin contract, not the legacy worker.

Tests cover each disposition.

Suggested commit: refactor(exchange-online): apply unsupported capability dispositions

Task 43: Cut Over Exchange Online and Retire Its Legacy Provider

Objective: Route all retained built-in Exchange Online functionality to supported native implementations and remove the legacy Exchange Online path.

Allowed scope: Exchange Online routing/registration, affected workflows, legacy bridge commands, configuration migration, tests, and documentation.

Required work:

Complete parity and approved live validation for retained capabilities.

Remove LegacyPowerShell Exchange Online configuration.

Remove Exchange Online legacy bridge and worker operations.

Verify removed/deferred capabilities cannot accidentally invoke the legacy worker.

Update deployment, permissions, diagnostics, support, and rollback documentation.

Acceptance criteria:

Retained built-in Exchange Online workflows use no PowerShell.

Unsupported capabilities follow their approved Task 42 disposition.

Full solution tests pass.

Exchange Online is marked complete or scope-adjusted in the parity matrix.

Suggested commit: refactor(exchange-online): retire legacy PowerShell provider

Task 44: Perform the Exchange On-Premises Supportability Gate

Objective: Determine whether each current Exchange on-premises operation has a supported non-PowerShell management path.

Allowed scope: Documentation, current-source verification, sanitized fixtures, and analysis-only scaffolding.

Required work:

Inventory every on-premises Exchange command/function, version dependency, RBAC requirement, remote-session assumption, and workflow dependency.

Distinguish mailbox-data APIs from Exchange administration APIs.

Classify every operation using the same disposition categories as Task 39.

Do not assume direct Active Directory attribute editing is a supported replacement for Exchange management tools.

Do not treat embedding or remotely invoking Exchange Management Shell as a native, zero-PowerShell implementation.

Produce explicit product decisions for all operations lacking a supported native path.

Acceptance criteria:

Every on-premises operation has a documented supported path or disposition.

No private endpoint, unsupported directory edit, or concealed PowerShell host is proposed.

Task 45 contains only supported native work.

Suggested commit: docs(exchange-onprem): complete supportability gate

Task 45: Implement Approved Native Exchange On-Premises Capabilities

Objective: Implement only the Exchange on-premises capabilities approved as natively supportable in Task 44.

Allowed scope: HAP.Providers.ExchangeOnPremises, approved shared components, tests, fixtures, and documentation.

Required work:

Implement approved public APIs or supported protocols only.

Add connection, authentication, health, cancellation, timeout, error, and permission behavior.

Add unit, contract, parity, and gated lab integration tests.

For unsupported operations, return the approved capability disposition rather than attempting PowerShell.

Acceptance criteria:

Approved native operations pass parity or documented behavior-change tests.

No Exchange Management Shell, remote PowerShell, System.Management.Automation, or undocumented endpoint is used.

Unsupported operations remain explicit and test-covered.

Suggested commit: feat(exchange-onprem): add approved native capabilities

Task 46: Resolve and Cut Over Exchange On-Premises Functionality

Objective: Apply approved dispositions to unsupported on-premises operations, route retained functionality natively, and remove the legacy on-premises provider.

Allowed scope: On-premises routing, capability availability, affected workflows, legacy bridge commands, configuration migration, tests, and documentation.

Required work:

Apply remove, defer, supported replacement, or customer-extension dispositions.

Remove LegacyPowerShell selection for the built-in provider.

Remove on-premises Exchange commands from the legacy bridge and worker.

Ensure a customer extension, when used, is clearly identified as third-party and runs only through the permanent plugin host.

Update deployment and support documentation to reflect any feature-scope change.

Acceptance criteria:

No retained built-in on-premises workflow invokes PowerShell.

No unsupported operation silently remains available.

Full solution tests pass.

On-premises Exchange is marked complete or scope-adjusted in the parity matrix.

Suggested commit: refactor(exchange-onprem): resolve capabilities and retire legacy provider

Task 47: Complete Native Hybrid User Lookup Orchestration

Objective: Complete user lookup and normalized hybrid-user aggregation using only native built-in providers.

Allowed scope: User query application services, domain aggregation models, ViewModel/View behavior, tests, fixtures, and documentation.

Required work:

Aggregate native Graph, AD, Exchange Online, Exchange on-premises, and simulator results according to enabled providers.

Preserve provider attribution, missing-data semantics, partial success, warnings, and deterministic identity matching.

Add tests for cloud-only, on-premises-only, hybrid, mailboxless, duplicate, stale, unavailable-provider, timeout, and cancellation scenarios.

Remove any remaining legacy user-lookup routing.

Acceptance criteria:

User Lookup completes without the legacy worker for all retained built-in configurations.

Missing provider data is distinct from provider failure.

UI behavior remains responsive and cancellation-safe.

Suggested commit: feat(user-lookup): complete native hybrid aggregation

Task 48: Complete Native Provider Health and Status Workflows

Objective: Replace all remaining provider/authentication/status-card behavior with native runtime state.

Allowed scope: Runtime session, provider health aggregation, status ViewModels/Views, tests, and documentation.

Required work:

Remove UI-derived provider state and legacy status polling.

Standardize healthy, degraded, unavailable, authentication-required, unauthorized, misconfigured, timed-out, and unsupported states.

Add refresh, cancellation, startup, shutdown, and partial-profile tests.

Ensure third-party plugin health remains clearly separated from built-in provider health.

Acceptance criteria:

All built-in status cards use native provider/runtime contracts.

No status check launches the legacy worker.

UI controls are not sources of provider state.

Suggested commit: feat(status): complete native provider health workflows

Task 49: Complete Native Device Management Workflow Cutover

Objective: Finish the Device Management UI/application workflow on native supported capabilities and remove all legacy routing.

Allowed scope: Device Management services, ViewModels/Views, provider adapters, tests, and documentation.

Required work:

Route all retained device operations to native providers.

Apply explicit unavailable states to unsupported operations.

Preserve confirmation, progress, cancellation, refresh, and partial-result behavior.

Add end-to-end tests with simulator and gated non-production live providers.

Acceptance criteria:

Device Management never invokes the legacy worker.

Supported operations pass end-to-end tests.

Unsupported operations are visible and cannot be invoked accidentally.

Suggested commit: refactor(devices): complete native workflow cutover

Task 50: Port New User Wizard Preflight to Native Orchestration

Objective: Move all New User Wizard validation, planning, and preflight behavior into native application services without performing writes.

Allowed scope: New User Wizard contracts, application service, ViewModel/View validation behavior, native provider reads, tests, fixtures, and documentation.

Required work:

Inventory current preflight order and dependencies.

Implement deterministic validation for runtime profile, naming, uniqueness, OU, domain, licensing, mailbox options, provider availability, permissions, and configuration.

Produce a typed execution plan showing intended steps, providers, warnings, blockers, and rollback capability.

Add tests for live, simulation, mixed-provider, mailboxless, missing-authentication, invalid-profile, duplicate, and unsupported-capability scenarios.

Do not perform any remote mutation in this task.

Acceptance criteria:

Preflight uses native built-in providers only.

The same inputs produce a deterministic execution plan.

Validation failures are user-safe and diagnostically useful.

No write or legacy PowerShell call occurs.

Suggested commit: feat(new-user): port native preflight and execution planning

Task 51: Port New User Wizard Execution and Compensation

Objective: Execute approved New User Wizard plans through native providers with explicit step tracking and compensation.

Allowed scope: New User Wizard execution service, orchestration/state models, affected provider write adapters, UI progress/results, tests, and documentation.

Required work:

Execute the preflight plan in a documented order.

Record per-step start, success, warning, failure, cancellation, and compensation status.

Implement idempotency/correlation so retries do not silently duplicate created objects.

Add compensation where supported and clear manual-remediation instructions where it is not.

Persist a sanitized operation record for support diagnostics.

Add simulator end-to-end tests and gated non-production live tests.

Acceptance criteria:

Successful execution completes without the legacy worker.

Partial failures are explicit and recoverable according to the plan.

Cancellation does not falsely report success or hide completed steps.

No silent provider fallback occurs.

Suggested commit: feat(new-user): port native execution and compensation

Task 52: Port Remaining User Administration Actions

Objective: Move all retained user-administration dialogs and actions to native application services/providers.

Allowed scope: User administration services, ViewModels/Views, relevant native provider capabilities, tests, and documentation.

Required work:

Inventory and port actions such as enable/disable, password/credential operations, profile changes, group changes, license changes, mailbox/delegation changes, and deletion where retained and supported.

Use explicit capability availability and permission checks before presenting actions.

Add confirmation, progress, cancellation, refresh, audit, partial-failure, and destructive-action tests.

Apply the approved disposition to unsupported actions.

Acceptance criteria:

Every retained user-administration action is native.

Unsupported actions are unavailable with an explanation.

No dialog or action invokes the legacy worker.

Suggested commit: feat(user-admin): complete native action migration

Task 53: Port Group, Licensing, Mailbox, Reporting, and Export Workflows

Objective: Complete remaining built-in workflow migration in bounded capability groups.

Allowed scope: The named workflow services/ViewModels/Views, relevant native provider capabilities, tests, and documentation. Codex may split this task into Task 53A through Task 53E if the repository size makes one commit unsafe, but it must not combine unrelated refactoring.

Required work:

Port retained group-management workflows.

Port retained licensing workflows.

Port retained mailbox/delegation workflows limited to supported capabilities.

Port reporting and export generation without exposing provider SDK types.

Preserve filtering, sorting, pagination, progress, cancellation, partial results, and secure redaction.

Apply explicit unsupported-capability dispositions.

Acceptance criteria:

Every retained built-in workflow is accounted for in the parity matrix.

No retained workflow invokes the legacy worker.

Exported data remains schema-compatible or has a documented versioned change.

Full workflow tests pass.

Suggested commit: feat(workflows): complete remaining native workflow migration

Task 54: Complete UI Parity, Accessibility, and Performance Validation

Objective: Validate the complete WPF application against the approved behavior and usability baseline after native cutover.

Allowed scope: Presentation/ViewModel fixes, performance instrumentation, accessibility metadata, UI tests, and documentation. Do not redesign product workflows.

Required work:

Complete the screen/workflow parity checklist against the original PowerShell application.

Verify keyboard navigation, focus order, labels, validation announcements, high-DPI behavior, resizing, theme behavior, and long-running-operation responsiveness.

Measure startup, profile loading, user lookup, large lists, memory growth, cancellation, and shutdown.

Remove dead UI compatibility code and legacy status assumptions only when tests prove it is unused.

Acceptance criteria:

No critical parity gaps remain for retained functionality.

The UI remains responsive during provider operations.

Accessibility and high-DPI checks pass according to the project baseline.

Performance regressions and accepted exceptions are documented.

Suggested commit: test(ui): complete parity accessibility and performance validation

Task 55: Implement Configuration Migration and Rollback Tooling

Objective: Migrate existing HAP configuration/runtime profiles to the final native schema safely and reversibly.

Allowed scope: Configuration migration utility, schema/version handling, tests, documentation, and installer integration hooks.

Required work:

Detect legacy configuration versions and create a timestamped backup before conversion.

Convert provider implementation settings, runtime profiles, extension registrations, and supported authentication configuration without copying secrets into insecure locations.

Reject ambiguous or unsupported values with actionable diagnostics.

Support dry-run, validation-only, migration, and rollback modes.

Add fixtures for representative old configurations and interrupted migration.

Acceptance criteria:

Migration is deterministic, test-covered, and reversible.

Old LegacyPowerShell built-in provider settings are removed or mapped to supported native/disposition states.

Customer extension registrations remain separate from legacy built-in settings.

Secrets are not logged or copied insecurely.

Suggested commit: feat(config): add native migration and rollback tooling

Task 56: Remove Legacy Implementation Selection and Runtime Dependencies

Objective: Eliminate all runtime routes that can select the temporary legacy provider infrastructure.

Allowed scope: Provider registry/factory, runtime profiles, configuration schemas, dependency injection, tests, and documentation. Do not delete projects until Task 57.

Required work:

Remove LegacyPowerShell as a valid built-in implementation value.

Remove legacy worker registrations from the application composition root.

Remove startup, health, retry, fallback, and shutdown paths related to the legacy worker.

Ensure permanent third-party PowerShell extension registration remains intact and separately named.

Add tests that legacy configuration produces a migration-required error rather than launching PowerShell.

Acceptance criteria:

No production application code can route a built-in capability to the legacy worker.

The permanent plugin host remains launch-on-demand for approved third-party providers only.

Full solution tests pass before project deletion.

Suggested commit: refactor(runtime): remove legacy provider routing

Task 57: Delete the Legacy Bridge, Worker, Protocol, and Adapter

Objective: Remove the temporary PowerShell migration infrastructure from source and production packaging.

Allowed scope: HAP.Providers.LegacyPowerShell, HAP.LegacyWorker.Protocol, HAP.LegacyPowerShellWorker, HAP.LegacyBridge.psm1, related tests, solution/project references, packaging, and documentation.

Required work:

Prove no production or test project depends on the legacy components.

Delete the temporary bridge, worker, protocol, adapter, and obsolete fixtures.

Remove package references used only by the legacy path.

Preserve HAP.Plugin.Protocol, HAP.Extensions.PowerShell, HAP.PowerShellPluginHost, and the customer provider SDK.

Add repository scans that distinguish forbidden legacy references from approved extension-host references.

Acceptance criteria:

The solution restores, builds, and tests without legacy projects/files.

Production packaging contains no legacy bridge or worker artifact.

No built-in module/script is required at runtime.

Permanent plugin infrastructure remains functional and isolated.

Suggested commit: refactor(legacy): remove temporary PowerShell migration infrastructure

Task 58: Prove Final No-PowerShell Built-In Operation

Objective: Provide automated and manual evidence that all retained built-in HAP functionality runs without PowerShell while approved third-party extensions remain optional.

Allowed scope: Acceptance tests, process/file/package inspection, plugin-host regression tests, CI gates, and documentation.

Required work:

Run every built-in workflow with no PowerShell extension enabled.

Assert that HAP creates no pwsh.exe, powershell.exe, legacy worker, or plugin-host process during built-in-only execution.

Assert that no built-in assembly references System.Management.Automation or loads .ps1, .psm1, or .psd1 files.

Verify the plugin host launches only after an approved enabled third-party provider is invoked.

Verify disabling/removing the provider prevents launch.

Verify sample extension behavior still passes protocol and conformance tests.

Add CI failure gates for forbidden first-party dependencies.

Acceptance criteria:

Built-in-only acceptance suite passes on a clean machine/environment.

Optional PowerShell extension tests pass independently.

Static and runtime scans show no first-party PowerShell dependency.

Evidence is recorded in the final migration report.

Suggested commit: test(migration): prove final no-PowerShell built-in operation

Task 59: Build Production Packaging, Installer, Upgrade, and Diagnostics

Objective: Produce the supported production deployment package for the native HAP application.

Allowed scope: Publish profiles, installer/package project, configuration migration integration, optional extension-host feature selection, signing hooks, diagnostics collection, tests, and deployment documentation.

Required work:

Create the approved self-contained or framework-dependent Windows publish output.

Package the main application and native providers without legacy components.

Package the optional PowerShell plugin host/runtime according to product policy, clearly separated from the core install.

Integrate configuration backup/migration and rollback behavior.

Add install, upgrade, repair, uninstall, path/permission, and clean-machine smoke tests.

Add support-bundle generation with secret redaction.

Add code-signing hooks without embedding private signing material.

Acceptance criteria:

Clean install, in-place upgrade, rollback, repair, and uninstall are validated.

Core installation can run built-in workflows without PowerShell.

Optional extension support can be omitted or disabled according to policy.

Installer and support diagnostics contain no secrets or legacy artifacts.

Suggested commit: build(release): add native packaging upgrade and diagnostics

Task 60: Release Candidate Validation and Final Migration Acceptance

Objective: Complete the final release candidate, operational validation, documentation, and formal migration closure.

Allowed scope: Release-candidate fixes only, final test evidence, deployment/support documentation, migration status, and release notes. No new feature development.

Required work:

Run full restore, build, unit, contract, parity, integration, UI, security, plugin-conformance, packaging, and no-PowerShell suites.

Execute the approved non-production live validation runbook for each retained provider and workflow.

Verify configuration migration from representative customer versions.

Verify rollback to the previous supported release until the acceptance decision is made.

Produce final capability disposition, parity, security, performance, known-issues, deployment, support, and rollback reports.

Mark every migration requirement as passed, accepted exception, removed capability, deferred capability, or blocked.

Remove the original PowerShell application from production packaging only after formal acceptance; retain its source/history according to repository policy.

Final acceptance criteria:

All retained built-in workflows use native .NET providers.

No temporary legacy worker, bridge, protocol, adapter, or built-in PowerShell module remains in production.

Unsupported Exchange capabilities have explicit approved dispositions.

PowerShell runs only for administrator-approved third-party providers through the permanent isolated plugin host.

HAP does not launch PowerShell when no such extension is enabled and invoked.

Installation, upgrade, rollback, diagnostics, and support procedures are validated.

The final migration report is approved and the migration is marked complete.

Suggested commit: chore(release): finalize native HAP migration acceptance

18. Codex Task Template

Use this template for each migration task:

Objective:
<One narrowly defined outcome.>

Allowed scope:
<Exact directories and files Codex may create or modify.>

Required inspection:
<List existing PowerShell or C# files that must be read first.>

Requirements:
- <Specific behavior 1>
- <Specific behavior 2>
- <Specific behavior 3>

Explicitly prohibited:
- Do not modify unrelated files.
- Do not begin the next migration phase.
- Do not rewrite providers unless explicitly requested.
- Do not invoke Start-HybridAdminConsole.ps1 as a backend.
- Do not expose PSObject beyond the adapter boundary.
- Do not add silent fallback behavior.
- Do not mix the legacy worker protocol with the permanent plugin protocol.
- Do not add first-party business logic to the customer plugin host.

Tests:
- <Required unit tests>
- <Required contract tests>
- <Required commands>

Completion report:
- List changed files.
- Summarize behavior implemented.
- List commands run and results.
- List unresolved risks or assumptions.
- Stop after this task.

19. First Codex Prompt

The first implementation-related Codex prompt should be analysis-only:

You are preparing the HAP PowerShell-to-.NET migration described in Migration.MD.

Objective:
Inventory the existing runtime-profile selection, configuration loading, runtime validation, provider initialization, and provider-health workflow. Produce documentation only. Do not change application behavior.

Repository root:
D:\Atlas

Required inspection:
- D:\Atlas\src\Core
- D:\Atlas\src\Application
- D:\Atlas\src\Infrastructure
- D:\Atlas\src\Domain\Hybrid.Models.psm1
- D:\Atlas\src\UI\Start-HybridAdminConsole.ps1

Deliverable:
Create D:\Atlas\docs\CSharpMigrationInventory.md containing:
- Each PowerShell function involved in the workflow.
- Its source file and module.
- Inputs and output shape.
- Side effects.
- Required privileges and authentication.
- Provider dependencies.
- Live versus simulation behavior.
- Error and warning behavior.
- UI-control or global-state dependencies.
- STA/threading or prompt requirements.
- Proposed C# interface, method, and candidate capability mapping.
- Identification of behavior that belongs to first-party native providers versus reusable extension contracts.
- Risks that could affect in-process versus out-of-process legacy PowerShell hosting.
- A recommended boundary for the first headless bridge commands.

Also include a candidate compatibility-test checklist for Windows PowerShell 5.1, PowerShell 7, in-process hosting, and out-of-process hosting.

Explicitly prohibited:
- Do not create the .NET solution yet.
- Do not modify PowerShell behavior.
- Do not refactor Start-HybridAdminConsole.ps1.
- Do not rewrite any provider.
- Do not perform unrelated cleanup.

Completion report:
- List files inspected.
- List the documentation file created.
- Summarize the main architectural risks found.
- Stop after completing the inventory.

20. Risk Register

Risk: Legacy PowerShell module incompatibility

Some existing providers may require Windows PowerShell 5.1 or behave differently in PowerShell 7.

Mitigation: Complete the compatibility spike before fixing the temporary hosting architecture. Prefer an isolated legacy worker and remove it after native cutover.

Risk: Legacy and extension boundaries become conflated

A temporary migration adapter could accidentally become the permanent customer SDK or permanent first-party fallback.

Mitigation: Separate projects, protocols, names, tests, documentation, and removal criteria. The plugin host must never import the legacy bridge.

Risk: UI logic hidden inside the current shell

Business or transformation logic may be embedded in event handlers.

Mitigation: Inventory behavior, extract only headless functions, and add golden tests before replacing each workflow.

Risk: Configuration drift

Existing configuration precedence and fallback behavior may be implicit or inconsistent.

Mitigation: Port configuration early, define precedence explicitly, and cover it with tests.

Risk: Provider behavior divergence

Native C# providers may return different shapes or errors from legacy PowerShell providers.

Mitigation: Stable contracts, normalized DTOs, and contract tests shared across implementations.

Risk: Silent fallback masks failures

Automatic fallback can make environments behave differently and hide native-provider defects.

Mitigation: Require explicit implementation selection and visible fallback decisions. Remove legacy implementations after approved cutover.

Risk: Third-party module compromise or unsafe behavior

A customer provider may be malicious, compromised, defective, or over-privileged.

Mitigation: Treat modules as installed executable code; require administrative approval, exact-path loading, manifest and hash validation, signature policy, capability grants, separate processes, audit logs, timeouts, cancellation, and clear trust status.

Risk: PowerShell is mistaken for a security sandbox

A constrained runspace cannot guarantee containment of hostile code.

Mitigation: Use process isolation and operating-system controls; document the trust model honestly; do not claim runspace restrictions provide complete sandboxing.

Risk: Plugin dependency conflicts

Different providers may require incompatible modules or assemblies.

Mitigation: Prefer one plugin-host process per provider instance and pin the supported PowerShell runtime contract.

Risk: Extension UI destabilizes HAP

Allowing modules to inject controls or code could break presentation, accessibility, or security.

Mitigation: HAP owns all UI. Extensions provide only validated declarative schemas and structured data.

Risk: Unbounded extension contract

An overly generic operation API could allow providers to bypass capability controls.

Mitigation: Use versioned, narrow capability contracts, explicit grants, conformance tests, and protocol validation.

Risk: PowerShell launches during normal built-in operation

Residual wiring could cause PowerShell to remain a hidden dependency after migration.

Mitigation: Add process-level no-PowerShell acceptance tests and remove all legacy projects from final production packaging.

Risk: Codex scope expansion

Large prompts can lead to unrelated refactors, excessive token usage, and difficult reviews.

Mitigation: One narrow task, explicit allowed files, required tests, and a mandatory stop condition.

Risk: Live-system impact

Provider integration tests can modify production resources.

Mitigation: Default to simulator fixtures, mark live tests explicitly, require controlled environments, and separate read from write workflows.

Risk: Authentication and UI threading

Authentication prompts or legacy modules may depend on STA or an interactive desktop.

Mitigation: Include prompt and threading behavior in the compatibility spike and define an explicit host-interaction contract if needed.

21. Definition of Done for the Full Migration

The migration is complete only when:

The primary HAP UI runs as a compiled .NET 10 WPF executable.

All supported built-in workflows use C# contracts and application services.

All first-party providers are implemented natively in .NET.

Configuration and runtime profiles are deterministic and tested.

UI state is separated from runtime and provider state.

All required workflows pass approved parity tests.

No built-in provider silently falls back to another implementation.

The legacy PowerShell UI is no longer required for supported production workflows.

HAP.LegacyBridge.psm1, HAP.LegacyPowerShellWorker, its protocol, and its adapter are removed from production packaging.

No built-in provider or workflow depends on .ps1, .psm1, powershell.exe, pwsh.exe, or System.Management.Automation.

Built-in HAP functionality passes acceptance testing with no PowerShell extension installed or enabled.

With no enabled PowerShell extension, HAP launches no PowerShell process and does not launch HAP.PowerShellPluginHost.exe.

The permanent provider extension platform supports versioned native .NET and PowerShell providers behind common capability contracts.

PowerShell extensions run only through the isolated HAP.PowerShellPluginHost and never inside HAP.App.exe.

A documented sample customer provider can be installed, approved, configured, invoked, audited, disabled, and removed without changing HAP source code.

Third-party modules cannot inject WPF UI and can request only declared and approved capabilities.

Extension manifest, version, hash, signature policy, approval, timeout, cancellation, and audit behavior are tested.

Packaging, deployment, upgrade, rollback, logging, diagnostics, extension installation, and extension removal are documented.

The final cutover has been approved after live validation.

The final state is therefore:

Zero first-party PowerShell calls, with PowerShell retained only as an optional, isolated, administrator-approved third-party provider language.

22. Golden Rule

During migration:
C# owns presentation, state, contracts, configuration, and orchestration first.
The temporary legacy worker preserves proven first-party behavior only until native parity is achieved.

After migration:
All built-in HAP workflows and providers are native .NET.
PowerShell exists only behind the optional isolated customer-provider host.

Every migration decision must preserve the separation between temporary legacy compatibility and the permanent extension platform unless the architecture documentation is explicitly revised and approved.