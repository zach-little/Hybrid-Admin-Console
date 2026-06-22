# Milestone 8 Phase 2 - Runtime Bootstrap Engine

## Status

In progress.

## Purpose

Phase 2 introduces the Runtime Bootstrap Engine as the single startup orchestration boundary for the Hybrid Administration Platform.

The runtime engine loads a Runtime Profile, validates it through the existing Runtime Profile foundation, creates a bootstrap plan, initializes the provider registry, initializes the application service layer, and returns a single runtime context object for later UI and diagnostics phases.

## Added

- `src/Core/Core.Runtime.psm1`
- `src/Core/Core.Runtime.psd1`
- `tests/Test-Milestone8Phase2.ps1`
- `tools/Apply-Milestone8Phase2.ps1`

## Public API

- `Initialize-HybridRuntime`
- `Get-HybridRuntime`
- `Reset-HybridRuntime`

## Runtime context

`Initialize-HybridRuntime` returns a `Hybrid.RuntimeContext` object containing:

- Runtime Profile
- Runtime Mode
- Cloud Environment
- Provider Registry
- Service Registry
- Authentication bootstrap status
- Bootstrap Plan
- Startup diagnostics records
- Startup timing metadata
- Simulation status

## Bootstrap behavior

Phase 2 intentionally does not perform live authentication or provider connectivity checks.

Live providers are registered as deferred bootstrap records so future phases can add provider discovery, health checks, authentication verification, and diagnostics without forcing login during startup.

Simulation mode initializes the Directory Simulator and wires the existing service-backed verticals to simulator providers.

## Service initialization sequence

The runtime engine initializes application services in dependency order:

1. Hybrid User Service
2. Graph Profile Service
3. Authentication Profile Service
4. User Aggregation Service

The UI remains unchanged and provider-agnostic.

## Validation

Run:

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File
Remove-Module Core.Runtime,Core.RuntimeProfile,Core.ServiceRegistry,Application.HybridUserService,Application.GraphProfileService,Application.AuthenticationProfileService,Application.HybridUserAggregationService,Infrastructure.DirectorySimulator -Force -ErrorAction SilentlyContinue
.\tools\Apply-Milestone8Phase2.ps1
.\tests\Test-Milestone8Phase2.ps1
.\tests\Test-Milestone8Phase1.ps1
```

Then run cumulative Milestone 7 tests to confirm no regression.
