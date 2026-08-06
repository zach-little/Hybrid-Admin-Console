# C# Migration Inventory - Runtime Profile Launch Slice

Status: analysis only. This document follows `Migration.MD` Prompt 1 and does not change PowerShell behavior.

## Scope

This inventory covers runtime profile selection, configuration loading, runtime validation, provider initialization, provider registration, provider health, and the WPF startup/launch workflow that binds those pieces together.

Primary sources inspected:

- `Migration.MD`
- `docs/ARCHITECTURE.md`
- `docs/Engineering/OBJECT_MODEL_GUIDE.md`
- `docs/Engineering/PROVIDER_DEVELOPMENT_GUIDE.md`
- `docs/ROADMAP.md`
- `src/UI/Start-HybridAdminConsole.ps1`
- `src/Application/Application.RuntimeProfileManager.psm1`
- `src/Application/Application.HybridUserService.psm1`
- `src/Application/Application.NewUserWizardService.psm1`
- `src/Application/Application.DeviceManagementService.psm1`
- `src/Core/Core.Runtime.psm1`
- `src/Core/Core.RuntimeProfile.psm1`
- `src/Core/Core.ProviderBase.psm1`
- `src/Domain/Hybrid.Models.psm1`

## Workflow Summary

Startup shows a runtime-profile picker in `Start-HybridAdminConsole.ps1`. The picker calls `Get-HybridRuntimeProfileSummary`, picks a current profile through `Get-HybridRuntimeProfileSelection`, stores it in `$script:SelectedRuntimeProfileSummary`, and updates multiple WPF controls. Launch persists the selected path with `Set-HybridRuntimeProfileSelection`, calls `Initialize-HybridRuntime -ProfilePath ... -Force`, checks launch readiness, and then shows the workflow selector.

`Initialize-HybridRuntime` is the headless core boundary today. It builds a `Hybrid.RuntimeContext`, imports core modules, loads and validates the selected `runtime.json`, initializes simulation or live providers, registers application services, runs diagnostics, stores the runtime in `$script:HybridRuntimeState.Runtime`, and returns the context.

## Function Inventory

| Function | Source | Inputs | Output Shape | Side Effects | Privileges/Auth | Provider Dependencies | Simulation vs Live | Error/Warning Behavior | UI/Global Dependencies | STA/Prompt Concerns | Proposed C# Mapping |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `Get-HybridRuntimeProfileSummary` | `src/Application/Application.RuntimeProfileManager.psm1` | `RepositoryRoot` | Array of `Hybrid.RuntimeProfileSummary` PSObjects | Reads `profiles/*/runtime.json`, `config.json`, `branding.json`, and `profiles/active.json` | File read only | None | Same scan logic for all modes; mode reported from JSON | Invalid JSON becomes invalid summary with `ErrorMessage`; missing config/branding become warnings | None direct | None | `IRuntimeProfileCatalog.ListAsync()` returning typed summaries |
| `Get-HybridRuntimeProfileSelection` | `src/Application/Application.RuntimeProfileManager.psm1` | `RepositoryRoot` | One summary object or `$null` | Reads `profiles/active.json`; reads summaries | File read only | None | Prefers active, default, Simulation, first valid, first profile | Falls through on missing/invalid active path | None direct | None | `IRuntimeProfileSelectionService.GetSelectionAsync()` |
| `Set-HybridRuntimeProfileSelection` | `src/Application/Application.RuntimeProfileManager.psm1` | `RepositoryRoot`, `ProfileName` or `ProfilePath` | Selected summary | Writes `profiles/active.json` | File write to profile root | None | Same behavior for live/simulation | Throws when profile cannot be found or is invalid | None direct | None | `IRuntimeProfileSelectionService.SetSelectionAsync()` |
| `Resolve-HybridRuntimeProfilePath` | `src/Core/Core.RuntimeProfile.psm1` | `Name`, `RootPath`, `Path` | Resolved file path | Reads `profiles/active.json`; scans profile folders | File read only | None | Defaults to Simulation when active name is absent | Throws when explicit path/name cannot resolve | `$PSScriptRoot` fallback | None | `IRuntimeProfileResolver.ResolveAsync()` |
| `Initialize-HybridRuntimeProfile` | `src/Core/Core.RuntimeProfile.psm1` | `Name` or `Path`, `RootPath`, optional `Context` | `Hybrid.RuntimeProfile` PSObject | Reads JSON; updates `$script:RuntimeProfileState`; mutates context | File read only | None directly | Normalizes profile mode, cloud, auth, providers | Throws for invalid JSON or failed validation | Module script state and optional runtime context | None | `IRuntimeProfileLoader.LoadAsync()` plus `IRuntimeProfileValidator` |
| `Test-HybridRuntimeProfile` | `src/Core/Core.RuntimeProfile.psm1` | `Profile` | `Hybrid.RuntimeProfileValidationResult` | None | None | None | Requires `DirectorySimulator` for simulation profiles | Returns success flag and messages instead of throwing for normal validation | None | None | `IRuntimeProfileValidator.Validate()` |
| `New-HybridRuntimeBootstrapPlan` | `src/Core/Core.RuntimeProfile.psm1` | `Profile` | `Hybrid.RuntimeBootstrapPlan` with provider steps | None | None | Provider settings from profile | Computes provider actions for disabled/simulation/live | No normal throw beyond malformed object access | None | None | `IRuntimeBootstrapPlanner.CreatePlan()` |
| `Initialize-HybridRuntime` | `src/Core/Core.Runtime.psm1` | `ProfileName` or `ProfilePath`, `RootPath`, `Force` | `Hybrid.RuntimeContext` | Imports modules; writes logs/diagnostics; updates `$script:HybridRuntimeState.Runtime`; registers services/events; may authenticate | Live providers may require domain/network/Microsoft auth | AD, Graph, Exchange Online, Exchange On-Prem, DirectorySimulator, service registry | Simulation registers simulator-backed logical providers; live initializes or defers per provider | Catches bootstrap failures, updates diagnostics, logs, rethrows | `$script:HybridRuntimeState`; service registry script state | Graph delegated auth can open browser during launch; must remain STA-safe from WPF | `IRuntimeSessionFactory.StartAsync()` returning `RuntimeSession` |
| `Initialize-HybridRuntimeServiceRegistry` | `src/Core/Core.Runtime.psm1` | `RootPath`, `Context` | None | Imports service/event modules; registers services; mutates context service registry | None | Core service registry/event bus/runtime services | Same | Throws if required module import fails | Global service registry | None | `IServiceRegistry`, `IRuntimeEventBus`, `IRuntimeTaskOrchestrator` |
| `Initialize-HybridRuntimeSimulationProviders` | `src/Core/Core.Runtime.psm1` | Provider registry, provider settings, profile providers, runtime mode, records | Simulator provider object | Imports simulator; registers provider records | None | `Infrastructure.DirectorySimulator` | Pure simulation exposes AD, Graph, ExchangeOnline, ExchangeOnPrem logical providers | Failed simulation dependency recorded as provider failure | Provider registry hashtable | None | `IProviderBootstrapper<DirectorySimulator>` and simulator adapters |
| `Initialize-HybridRuntimeLiveActiveDirectoryProvider` | `src/Core/Core.Runtime.psm1` | Root, registry, provider settings, context, records | Provider record | Imports AD modules; writes `logs/ad-runtime-diagnostics.log`; registers provider | Domain joined or RSAT/AD module access depending provider internals | `Infrastructure.ActiveDirectory` | Live only | Exceptions become failed provider records and persistent diagnostics | Provider registry | May perform live connectivity checks; should not run on UI thread | `IProviderBootstrapper<ActiveDirectoryProvider>` |
| `Initialize-HybridRuntimeLiveMicrosoftGraphProvider` | `src/Core/Core.Runtime.psm1` | Root, registry, provider settings, context, records | Lazy Graph service and provider record | Imports auth/MSAL/Graph modules; registers MSAL adapters; may force auth; records lazy errors | Tenant ID; app-only cert or delegated interactive permissions | Cloud environment, tenant context, auth manager, MSAL, Graph provider | Simulation handled elsewhere; live can be deferred or connected | Missing tenant throws; other failures become failed provider record with capability state `Failed` | Provider registry and closure-local lazy state | Delegated mode forces interactive browser during launch and must coordinate with WPF STA | `IMicrosoftGraphProviderFactory`, `IInteractiveAuthBroker`, `IProviderBootstrapper<GraphProvider>` |
| `Initialize-HybridRuntimeLiveExchangeOnlineProvider` | `src/Core/Core.Runtime.psm1` | Root, registry, provider settings, context, records | Provider record and service | Imports EXO/auth modules; registers MSAL adapters; defers connection | ExchangeOnlineManagement/app-only or delegated as provider supports | `Core.Provider.ExchangeOnline` | Live only; connection normally deferred | Health statuses include `NotConfigured`, `ModuleMissing`, `AuthenticationUnavailable`, `Connected`, `Failed` | Provider registry | Potential module/auth threading constraints when connection occurs | `IProviderBootstrapper<ExchangeOnlineProvider>` |
| `Initialize-HybridRuntimeLiveExchangeOnPremisesProvider` | `src/Core/Core.Runtime.psm1` | Root, registry, provider settings, records | Provider record and service | Imports Exchange on-prem module; creates deferred provider | Kerberos/remote PowerShell endpoint access | `Infrastructure.ExchangeOnPremises` | Live only; connection deferred until recipient data | Health `LastError` maps to unavailable; exceptions become failed record | Provider registry | Windows PowerShell/remoting compatibility risk | `IProviderBootstrapper<ExchangeOnPremProvider>` |
| `Initialize-HybridRuntimeApplicationServices` | `src/Core/Core.Runtime.psm1` | Root, provider registry, service registry, records, context | None | Imports application modules; reads profile `config.json`; registers services | Depends on provider auth already established or deferred | HybridUser, GraphProfile, AuthenticationProfile, UserAggregation, UserAdministration, NewUserWizard, DeviceManagement | Same service names backed by sim or live provider implementations | Config read failures for New User Wizard fall back to profile/defaults | Service registry and context | None directly | `IApplicationServiceComposer.Compose(session)` |
| `Get-HybridRuntimeProviderRegistration` | `src/Core/Core.Runtime.psm1` | Provider name, optional runtime | Provider record | None | None | Runtime provider registry | Same | Throws when runtime/provider missing | `$script:HybridRuntimeState` if runtime omitted | None | `IProviderRegistry.Get(name)` |
| `Get-HybridRuntimeDiagnostics` | `src/Core/Core.Runtime.psm1` | Optional runtime | `Hybrid.RuntimeDiagnostics` | None | None | Runtime context | Same | Throws when runtime/diagnostics missing | `$script:HybridRuntimeState` if runtime omitted | None | `IRuntimeDiagnosticsService.GetDiagnostics()` |
| `Test-HybridRuntimeDiagnostics` | `src/Core/Core.Runtime.psm1` | Optional runtime | `Hybrid.RuntimeDiagnosticResult` | None | None | Runtime diagnostics | Same | Converts diagnostics to healthy/unhealthy result | `$script:HybridRuntimeState` if runtime omitted | None | `IRuntimeDiagnosticsService.Test()` |
| `Get-HybridProviderHealth` | `src/Core/Core.ProviderBase.psm1` | Provider state | `Hybrid.ProviderHealth` | None | None | Provider state object | Same | No connection attempt; reports last error/last command | Provider state PSObject | None | `IProviderHealthReporter.GetHealth()` |
| `Invoke-HybridProviderCommand` | `src/Core/Core.ProviderBase.psm1` | Provider state, command name, scriptblock, operation | Command result | Updates provider command history and `LastError` | Operation-dependent | Operation scriptblock | Same | Rethrows operation exceptions after recording failure | Provider state PSObject | Operation-dependent | `IProviderCommandInvoker.InvokeAsync()` with telemetry |
| `New-HybridProviderService` | `src/Core/Core.ProviderBase.psm1` | Provider state, operation scriptblocks | `Hybrid.ProviderService` PSObject | Captures provider state in closures | Operation-dependent | Any provider | Same | Operation exceptions flow through delegates | Closure over mutable state | Depends on operation | Replace with typed provider interfaces plus legacy adapter |
| `Initialize-HybridRuntimeProfileList` | `src/UI/Start-HybridAdminConsole.ps1` | None; uses `$repoRoot`, `$Profile` | None | Mutates list box, script selected profile state | File reads via manager | Runtime profile manager | Same | Displays fallback text when manager/profiles missing | `$controls`, `$script:RuntimeProfileSummaries`, `$script:SelectedRuntimeProfileSummary` | WPF UI thread only | `RuntimeProfilePickerViewModel.LoadAsync()` |
| `Set-HybridSelectedRuntimeProfile` | `src/UI/Start-HybridAdminConsole.ps1` | Profile, `Persist` | None | Updates script selected profile; optionally writes active profile; updates WPF status | File write only when persisted | Runtime profile manager | Same | Silently swallows persistence failures | `$controls`, `$repoRoot`, UI update functions | WPF UI thread only | `RuntimeProfileSelectionViewModel.Select(profile)` |
| `Get-HybridRuntimeProfileEnabledProviderNames` | `src/UI/Start-HybridAdminConsole.ps1` | Profile summary | String array | May read raw profile JSON if summary lacks providers | File read fallback | None | Same | Swallows fallback read errors | None | None | Move to profile summary model/provider view model |
| `Update-HybridStartupView` | `src/UI/Start-HybridAdminConsole.ps1` | None; reads current runtime/selection | None | Writes many WPF labels/cards/buttons | None direct | Runtime/profile objects | Same | Uses status text instead of throwing | `$controls`, `$script:HybridRuntime`, `$script:SelectedRuntimeProfileSummary`, `$Mock` | WPF UI thread only | `StartupViewModel` bound properties |
| `Assert-HapRuntimeLaunchReadiness` | `src/UI/Start-HybridAdminConsole.ps1` | Runtime | None | None | Depends on Graph delegated state | Provider registry | Skips delegated check for simulation Graph | Throws for required provider failure or incomplete Graph delegated sign-in | Runtime provider registry | Must understand delegated prompt lifecycle | Move to `IRuntimeLaunchReadinessPolicy` in core/application |
| `Invoke-HybridRuntimeProfileLaunch` | `src/UI/Start-HybridAdminConsole.ps1` | None; uses selected profile | None | Disables button; manipulates overlay/progress; persists selection; initializes runtime; writes status | May trigger Graph delegated browser prompt | Full runtime bootstrap | Same bootstrap but simulation skips live auth | Catches and displays launch failure; does not rethrow | `$controls`, `$script:HybridRuntimeLaunchInProgress`, `$script:SelectedRuntimeProfileSummary`, `$script:HybridRuntime`, `$repoRoot` | Runs blocking work on UI thread today; uses `DoEvents`; delegated browser prompt must be serialized | `LaunchRuntimeCommand` plus async `IRuntimeSessionFactory` |
| `Show-HybridWorkflowSelector` | `src/UI/Start-HybridAdminConsole.ps1` | None | None | Shows workflow selector overlay and status | None | Runtime already launched | Same | None beyond control null risks | `$controls`, `$script:SelectedRuntimeProfileSummary` | WPF UI thread only | `ShellNavigationService.ShowWorkflowSelector()` |
| `Show-HybridConsoleView` | `src/UI/Start-HybridAdminConsole.ps1` | None | None | Can initialize runtime again; hides overlay; shows console; may run initial search | May trigger provider/auth again if forced | Full runtime bootstrap and user search | Same | Displays launch failure text | `$controls`, `$script:SelectedRuntimeProfileSummary`, `$script:HybridRuntime`, `$InitialQuery` | WPF UI thread; duplicate runtime init/auth risk | Replace with single runtime session owned by shell |
| `Update-HybridUiHealth` | `src/UI/Start-HybridAdminConsole.ps1` | None | None | Updates provider health text/dot | None direct | `Get-HybridUserServiceHealth` | Same | Displays generic provider health error on exception | `$controls` | WPF UI thread only | `ProviderHealthViewModel.RefreshAsync()` |
| `Initialize-HybridUserService` | `src/Application/Application.HybridUserService.psm1` | Provider service objects | `Hybrid.UserService` PSObject with delegate operations | Stores providers in `$script:HybridUserServiceState`; clears caches | Provider-dependent | AD, Graph, ExchangeOnline, ExchangeOnPrem | Same service over sim/live provider objects | Throws later if uninitialized; operation errors tracked in service state | Module script state/cache | Operation-dependent | `IHybridUserService` with provider dependencies injected |
| `Get-HybridUserServiceHealth` | `src/Application/Application.HybridUserService.psm1` | None | `Hybrid.UserServiceHealth` | None | None directly | Provider health snapshots | Same | Reports `LastError`; does not throw normally | `$script:HybridUserServiceState` | None | `IHealthCheck<HybridUserService>` |

## Data and State Shapes to Preserve

- Runtime profile summary: `Name`, `ProfileName`, `FolderName`, `Path`, `ProfileRoot`, `RuntimeMode`, `CloudEnvironment`, `Organization`, `IsValid`, `IsDefault`, `IsLastUsed`, `EnabledProviders`, `ProviderModes`, `Warnings`, `ErrorMessage`, `HealthLabel`, `BadgeText`.
- Runtime profile: `ProfileName`, `ProfilePath`, `ProfileRoot`, `ConfigPath`, `BrandingPath`, `DefaultsPath`, `MappingsPath`, `KeyPath`, `Mode`, `Cloud`, `Environment`, `TenantId`, `Organization`, `Authentication`, `Providers`, `Raw`, `LoadedUtc`.
- Runtime context: `Version`, `RootPath`, `Paths`, `Profile`, `RuntimeMode`, `CloudEnvironment`, `Authentication`, `ProviderRegistry`, `ServiceRegistry`, `Diagnostics`, `BootstrapPlan`, `StartupTimeUtc`, `InitializedUtc`, `DurationMs`, `IsSimulation`, `ProviderModes`.
- Provider record: `Name`, `Mode`, `Enabled`, `Required`, `Authentication`, `Status`, `Service`, `Message`, `CapabilityStates`.
- Provider health: `Name`, `Initialized`, `Available`, `Connected`, `LastError`, `Capabilities`, `CommandCount`, `LastCommand`, `ResponseTimeMs`.

These should become versioned C# DTOs before the WPF shell consumes them.

## First-Party vs Extension Contract

First-party native C# responsibilities:

- Runtime profile catalog, profile selection, JSON loading, schema validation, and config precedence.
- Runtime session lifecycle, provider registry, service registry, diagnostics, launch-readiness policy, cancellation, progress, and logging.
- Native first-party providers as they are migrated: Active Directory, Microsoft Graph, Exchange Online, Exchange On-Premises, Directory Simulator.
- WPF/MVVM shell, startup profile picker, launch progress, workflow navigation, and provider health display.

Reusable extension contract responsibilities:

- Provider descriptor metadata: provider name, display name, version, supported capabilities, authentication modes, cloud compatibility.
- Provider health shape and capability status shape.
- Command invocation envelope: request ID, operation name, normalized input DTO, timeout/cancellation, structured result, warnings, structured errors.
- Optional extension-host lifecycle: initialize, health, invoke, dispose.

Do not make runtime profile selection or core launch policy an extension concern. Extensions should plug into the provider/capability layer after the first-party runtime decides what is enabled.

## Architectural Risks

- The UI script owns business decisions today. `Assert-HapRuntimeLaunchReadiness`, duplicate calls to `Initialize-HybridRuntime`, and many profile-preview helpers live in `Start-HybridAdminConsole.ps1`.
- Runtime state is script-global. `$script:HybridRuntimeState`, `$script:RuntimeProfileState`, `$script:HybridUserServiceState`, and UI `$script:*` variables are mutable singletons that will not translate cleanly into testable C# services.
- Provider services are dynamic PSObjects with scriptblock delegates. C# needs typed interfaces, while the legacy bridge must preserve dynamic operation discovery during transition.
- Graph delegated authentication is launch-time and interactive. The migration must prevent duplicate prompts, must not block the WPF dispatcher, and must serialize delegated auth requests.
- Exchange On-Premises and some AD/Exchange modules may require Windows PowerShell 5.1 or process isolation. Treat them as candidates for out-of-process legacy hosting until proven safe in PowerShell 7.
- Error behavior is mixed. Some functions throw, some return invalid summaries, some catch and store provider records, and some update WPF status text only.
- Current bootstrap imports modules dynamically and uses command discovery. C# must make module loading explicit in the legacy bridge and expose structured missing-module failures.
- Profile/config precedence is implicit: runtime profile paths point to `config.json`, `branding.json`, `defaults.json`, `mappings.json`, and `key.json`; application services may read profile config again.
- Blocking launch work currently runs on the UI thread with `DoEvents`. C# should move launch to an async command with progress events and cancellation.

## In-Process vs Out-of-Process Legacy PowerShell Hosting

In-process hosting risks:

- Assembly conflicts with WPF, MSAL, Microsoft Graph SDK, and Exchange modules.
- Runspace apartment/threading conflicts with interactive browser auth.
- Harder cleanup after failed remote sessions or module imports.
- Script-global state may leak between profile launches unless runspace lifecycle is carefully controlled.

Out-of-process hosting risks:

- Serialization loss for live PSObjects, scriptblocks, credentials, exceptions, and rich Graph/Exchange objects.
- Higher latency and more packaging work for command envelopes.
- Needs process lifecycle, timeout, cancellation, and log correlation.

Recommendation: use out-of-process for the temporary legacy worker by default, especially for Exchange and delegated Graph auth. Use in-process only for low-risk, non-interactive compatibility tests or simulator-only fast paths.

## Recommended First Headless Bridge Commands

These are the narrow bridge commands to expose before building the C# WPF shell:

- `Get-HapRuntimeProfiles`: wraps `Get-HybridRuntimeProfileSummary`.
- `Get-HapRuntimeProfileSelection`: wraps `Get-HybridRuntimeProfileSelection`.
- `Set-HapRuntimeProfileSelection`: wraps `Set-HybridRuntimeProfileSelection`.
- `Test-HapRuntimeProfile`: wraps `Initialize-HybridRuntimeProfile` plus `Test-HybridRuntimeProfile`, returning structured validation.
- `Start-HapRuntimeSession`: wraps `Initialize-HybridRuntime`, returns normalized runtime context, bootstrap records, diagnostics, provider records, and warnings.
- `Stop-HapRuntimeSession`: wraps `Reset-HybridRuntime` and any provider disposal available.
- `Get-HapProviderHealth`: wraps provider/service health snapshots.
- `Get-HapRuntimeDiagnostics`: wraps `Get-HybridRuntimeDiagnostics` and `Test-HybridRuntimeDiagnostics`.

Do not start with user search, new-user wizard, device management, or mailbox operations. Those should consume the runtime-session boundary after it is stable.

## Capability Mapping

| PowerShell Behavior | C# Interface / Capability |
|---|---|
| Runtime profile list/read/select | `IRuntimeProfileCatalog`, `IRuntimeProfileSelectionService` |
| Runtime profile validation | `IRuntimeProfileValidator` |
| Bootstrap plan generation | `IRuntimeBootstrapPlanner` |
| Runtime launch/session | `IRuntimeSessionFactory`, `IRuntimeSession` |
| Provider registration | `IProviderRegistry` |
| Provider health | `IProviderHealthService` |
| Runtime diagnostics | `IRuntimeDiagnosticsService` |
| Interactive Graph auth | `IInteractiveAuthBroker` |
| Provider bootstrap | `IProviderBootstrapper<TProvider>` |
| Dynamic legacy provider commands | `ILegacyPowerShellProviderHost.InvokeAsync()` |
| WPF profile picker | `RuntimeProfilePickerViewModel` |
| WPF launch command | `LaunchRuntimeCommand` / `StartupViewModel` |

## Compatibility-Test Checklist

Run each test against Windows PowerShell 5.1, PowerShell 7, in-process hosting, and out-of-process hosting where applicable.

- Import `Core.Runtime.psm1`, `Core.RuntimeProfile.psm1`, `Application.RuntimeProfileManager.psm1`, and provider modules from a clean process.
- Enumerate runtime profiles and verify summary fields match current PowerShell output.
- Resolve active profile from `profiles/active.json`, default profile, Simulation fallback, and invalid active path fallback.
- Load a valid simulation profile and validate success.
- Load a malformed profile and verify structured validation/error mapping.
- Start simulation runtime and verify logical providers register for AD, Graph, ExchangeOnline, and ExchangeOnPremises.
- Start live profile with AD enabled and verify connected/unavailable/failed status mapping.
- Start live profile with Graph delegated enabled and verify exactly one prompt, connected status, and clear failure when canceled.
- Start live profile with Graph app-only certificate settings and verify no delegated prompt.
- Start live profile with Exchange Online enabled and verify deferred/not-configured/module-missing statuses.
- Start live profile with Exchange On-Premises enabled and verify deferred connection does not hang launch.
- Read runtime diagnostics and provider health after success and after provider failure.
- Verify timeout/cancellation of provider bootstrap cannot freeze WPF.
- Verify all bridge outputs serialize to JSON DTOs without scriptblocks or unserializable live objects.
- Verify logs and diagnostics preserve enough detail to troubleshoot provider failures.
- Verify repeated launch/reset cycles do not reuse stale script-global state.

## Next Migration Boundary

The first implementation slice should create only the legacy worker contract and DTO schema for the commands above. The C# WPF shell should not be built until the headless bridge can list profiles, select one, launch simulation, launch a live profile with clear provider statuses, and return health/diagnostics without relying on WPF controls.
