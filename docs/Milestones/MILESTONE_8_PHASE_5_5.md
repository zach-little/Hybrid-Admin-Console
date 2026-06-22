# Milestone 8 Phase 5.5 — Shell & Dashboard Layout Foundation

## Status

Complete.

## Purpose

Phase 5.5 refines the Phase 5 startup shell before the Runtime Profile Wizard is introduced. The goal is to establish stable shell regions and a cleaner dashboard flow without changing application behavior or provider/service logic.

## Scope

This phase is intentionally UI-structural only.

Implemented:

- Named shell regions:
  - `StartupRegion`
  - `MainRegion`
  - `StatusBarRegion`
  - `OverlayRegion`
- A persistent shell root.
- A reserved overlay host for future guided workflows.
- A bottom status bar foundation.
- A three-column dashboard layout:
  - User identity and directory facts.
  - Operational/service-backed user cards.
  - Runtime, Graph, authentication, and aggregation cards.
- Preservation of all existing card names and data bindings.
- Preservation of the Phase 5 single-window startup shell behavior.

## Non-Goals

This phase does not add the Runtime Profile Wizard, does not change runtime profile JSON, does not alter provider behavior, does not add new service capabilities, and does not change the startup/runtime bootstrap contract.

## Validation

Run:

```powershell
.\tests\Test-Milestone8Phase5_5.ps1
.\tests\Test-Milestone8Phase5.ps1
.\tests\Test-Milestone8Phase4.ps1
.\tests\Test-Milestone8Phase3.ps1
.\tests\Test-Milestone8Phase2.ps1
.\tests\Test-Milestone8Phase1.ps1
```

Optional UI smoke test:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\src\UI\Start-HybridAdminConsole.ps1 -Mock -InitialQuery Alex
```

Expected UI behavior:

- Start screen appears first.
- Launch button reveals the dashboard.
- Existing search behavior works.
- Existing cards still populate.
- No new wizard behavior appears yet.
