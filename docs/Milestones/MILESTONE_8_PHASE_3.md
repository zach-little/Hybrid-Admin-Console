# Milestone 8 Phase 3 — Runtime Provider Modes

## Status

Complete candidate.

## Purpose

Phase 3 formalizes runtime provider modes on top of the Phase 2 bootstrap engine.

The runtime now exposes a provider-mode summary that describes which providers are Live, Simulation, Disabled, Initialized, and Deferred. This gives later startup diagnostics and the Start Screen a stable contract without requiring UI code to inspect profile JSON directly.

## Scope

Included:

- Explicit provider mode summary on the runtime context.
- Runtime provider registration lookup API.
- Runtime provider mode summary API.
- Hybrid runtime profile example.
- Hybrid profile handling where selected providers can be simulator-backed while others are live/deferred.
- Backward-compatible Simulation behavior from Phase 2.
- Phase 3 tests.

Excluded:

- UI changes.
- Startup diagnostics UI.
- Live authentication.
- Live provider connectivity checks.
- Profile wizard behavior.

## Runtime Contract

New runtime context property:

```powershell
$Runtime.ProviderModes
```

Canonical type:

```text
Hybrid.RuntimeProviderModeSummary
```

The summary exposes:

- `Modes`
- `LiveProviders`
- `SimulationProviders`
- `DisabledProviders`
- `DeferredProviders`
- `InitializedProviders`
- `CreatedUtc`

New exported commands:

```powershell
Get-HybridRuntimeProviderRegistration
Get-HybridRuntimeProviderModeSummary
```

## Provider Mode Rules

- `Simulation` providers are backed by `DirectorySimulator`.
- `Live` providers are registered but deferred until authentication/connectivity phases.
- `Disabled` providers are skipped.
- `Hybrid` profiles may combine simulation-backed and live/deferred providers.
- Device Code authentication remains disallowed.

## Validation

Run:

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File
Remove-Module Core.Runtime,Core.RuntimeProfile,Core.ServiceRegistry,Application.HybridUserService,Application.GraphProfileService,Application.AuthenticationProfileService,Application.HybridUserAggregationService,Infrastructure.DirectorySimulator -Force -ErrorAction SilentlyContinue
.\tools\Apply-Milestone8Phase3.ps1
.\tests\Test-Milestone8Phase3.ps1
.\tests\Test-Milestone8Phase2.ps1
.\tests\Test-Milestone8Phase1.ps1
```

Optional UI smoke test:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\src\UI\Start-HybridAdminConsole.ps1 -Mock -InitialQuery Alex
```
