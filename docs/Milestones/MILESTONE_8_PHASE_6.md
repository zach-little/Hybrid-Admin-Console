# Milestone 8 Phase 6 — Runtime Profile Wizard

## Status

Complete.

## Purpose

Phase 6 turns the Start Screen's Runtime Profile action into a guided, shell-hosted workflow for creating, validating, and saving runtime profiles without requiring administrators to hand-edit JSON files.

## Scope

This phase is intentionally UI and runtime-profile focused. It does not perform live authentication, provider connectivity checks, or production deployment packaging.

## Added

- Runtime Profile Wizard hosted in `OverlayRegion`.
- Enabled `Edit Runtime Profile` button on the Start Screen.
- Profile metadata inputs:
  - Profile Name
  - Organization
  - Tenant ID
- Cloud selector:
  - Commercial
  - GCCHigh
  - DoD
- Runtime mode selector:
  - Simulation
  - Live
  - Hybrid
- Provider selectors for:
  - Directory Simulator
  - Active Directory
  - Microsoft Graph
  - Exchange Online
- Wizard validation routine.
- Runtime profile JSON save routine under `profiles\Runtime`.
- Phase 6 validation test.
- Phase 6 apply script.

## Architecture

The wizard is hosted inside the existing single-window shell through `OverlayRegion`. This preserves the shell architecture introduced in Phase 5 and refined in Phase 5.5.

The wizard creates runtime profile JSON using the same profile shape introduced by Phase 1:

- `ProfileName`
- `Mode`
- `Cloud`
- `Environment`
- `Organization`
- `TenantId`
- `Providers`

Provider entries include:

- `Enabled`
- `Mode`
- `Required`
- `Authentication`

## Boundaries

This phase does not add:

- Live provider connectivity tests.
- Interactive authentication prompts.
- Device Code authentication.
- Deployment packaging.
- Provider-specific UI beyond generic runtime provider selection.

## Validation

Run:

```powershell
.\tests\Test-Milestone8Phase6.ps1
.\tests\Test-Milestone8Phase5_5.ps1
.\tests\Test-Milestone8Phase5.ps1
.\tests\Test-Milestone8Phase4.ps1
.\tests\Test-Milestone8Phase3.ps1
.\tests\Test-Milestone8Phase2.ps1
.\tests\Test-Milestone8Phase1.ps1
```
