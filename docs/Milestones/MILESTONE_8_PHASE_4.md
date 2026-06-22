# Milestone 8 Phase 4 — Startup Diagnostics Engine

## Status

Complete.

## Purpose

Phase 4 formalizes startup diagnostics as a runtime-owned engine that can be consumed by later UI work, including the Start Screen and guided runtime profile creation experience.

The diagnostics engine evaluates the runtime context after bootstrap and reports health without performing live authentication, network connectivity checks, or UI actions.

## Scope

Included:

- Runtime diagnostic checks
- Runtime diagnostic summary
- Overall runtime health state
- Provider registration diagnostics
- Service registration diagnostics
- Runtime profile diagnostics
- Runtime mode diagnostics
- Deferred live-provider warnings
- Public diagnostics accessors

Excluded:

- UI changes
- Start Screen changes
- Profile wizard changes
- Live sign-in
- Graph connectivity validation
- Exchange connectivity validation
- Active Directory connectivity validation

## New Runtime APIs

`Core.Runtime` now exports:

- `Get-HybridRuntimeDiagnostics`
- `Test-HybridRuntimeDiagnostics`

Existing exports remain unchanged.

## Diagnostic Types

- `Hybrid.RuntimeDiagnostics`
- `Hybrid.RuntimeDiagnosticCheck`
- `Hybrid.RuntimeDiagnosticSummary`
- `Hybrid.RuntimeDiagnosticResult`

## Severity Rules

- Initialized simulation providers are informational.
- Deferred live providers are warnings.
- Disabled providers are informational/skipped.
- Failed provider or service registration is an error.
- Deferred authentication during bootstrap is informational and expected.

## Acceptance Criteria

- Diagnostics are attached to the runtime context.
- Diagnostics preserve Phase 2 bootstrap records.
- Simulation runtime reports no errors.
- Live example runtime reports warnings for deferred providers but remains non-fatal.
- Provider diagnostics include mode/status/authentication metadata.
- Application service diagnostics verify registered service objects.
- Public diagnostics APIs are exported.
- Phase 1, Phase 2, and Phase 3 cumulative tests remain compatible.

## Validation

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File

Remove-Module Core.Runtime,Core.RuntimeProfile,Core.ServiceRegistry,Application.HybridUserService,Application.GraphProfileService,Application.AuthenticationProfileService,Application.HybridUserAggregationService,Infrastructure.DirectorySimulator -Force -ErrorAction SilentlyContinue

.\tools\Apply-Milestone8Phase4.ps1
.\tests\Test-Milestone8Phase4.ps1
.\tests\Test-Milestone8Phase3.ps1
.\tests\Test-Milestone8Phase2.ps1
.\tests\Test-Milestone8Phase1.ps1
```
