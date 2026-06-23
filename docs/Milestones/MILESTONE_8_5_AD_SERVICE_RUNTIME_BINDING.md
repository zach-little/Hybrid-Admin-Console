# Milestone 8.5 — Active Directory Service Runtime Binding Hotfix

Version: v0.8.5

## Purpose

This hotfix aligns Active Directory launch-page readiness, registered provider health, and live console operations.

The launch workflow now initializes the live Active Directory provider through the same service/provider path used by the console. The AD provider writes persistent diagnostics to `logs/ad-runtime-diagnostics.log`, and runtime bootstrap writes `logs/runtime-diagnostics.log` so live-environment failures survive after the WPF process closes.

## Changes

- Live Active Directory is no longer left as a deferred runtime provider.
- Runtime bootstrap imports and initializes `Infrastructure.ActiveDirectory` for live AD profiles.
- AD provider health and AD operations both call `Initialize-HybridActiveDirectoryRuntime`.
- The launch page no longer hardcodes `Active Directory Ready`.
- Console provider health reads the same provider health details exposed by the Hybrid User service.
- Added persistent runtime and AD diagnostic logs.
- Fixed strict-mode theme branding property access noise.
- Fixed legacy service locator `-Context` mismatch noise.

## Validation

Run:

```powershell
.\tests\Test-Milestone8_5ADServiceRuntimeBinding.ps1
```
