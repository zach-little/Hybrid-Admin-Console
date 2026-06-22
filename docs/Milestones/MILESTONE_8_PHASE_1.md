# Milestone 8 Phase 1 - Runtime Profile Foundation

## Status

In progress.

## Purpose

Milestone 8 begins the transition from a simulation-first development harness to a deployable platform that can choose providers at runtime.

Phase 1 introduces runtime profiles as the canonical source of truth for startup mode, cloud environment, organization, tenant, enabled providers, provider mode, provider requirement level, and provider authentication intent.

## Added

- `Core.RuntimeProfile.psm1`
- `profiles/Runtime/Simulation.json`
- `profiles/Runtime/Atlas-GCCHigh-Live.example.json`
- `Test-Milestone8Phase1.ps1`

## Runtime modes

- `Simulation` - Directory Simulator is the active provider source.
- `Live` - live providers are intended for Active Directory, Microsoft Graph, and Exchange Online.
- `Hybrid` - reserved for scenarios where live providers and simulator providers are intentionally mixed.

## Provider behavior

Runtime profiles do not belong to the UI. The UI remains provider-agnostic and continues to consume the service layer.

The runtime profile is consumed by the bootstrap/provider initialization layer to decide which providers should be enabled, skipped, or initialized later.

## Validation

Run:

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File
.\tools\Apply-Milestone8Phase1.ps1
.\tests\Test-Milestone8Phase1.ps1
```

Then run cumulative Milestone 7 tests to confirm no regression.
