# Milestone 7 Phase 2

## Live Active Directory Vertical Slice

### Roadmap Context

Milestone 7 delivers the first end-to-end Hybrid Admin Console vertical slice.

- Phase 1: Vertical Slice Foundation - complete
- Phase 2: Live Active Directory - this deliverable
- Phase 3: Live Microsoft Graph
- Phase 4: Live Exchange Online
- Phase 5: Unified Search Experience
- Phase 6: User Overview

### Objective

Phase 2 moves the vertical slice beyond mock-only search by allowing the `HybridUserService` application service to consume a real Active Directory provider service while preserving the established architecture:

```text
UI
  -> Application.HybridUserService
      -> Active Directory provider service
          -> canonical Hybrid.User output
```

The UI still talks only to the application service. The application service aggregates provider results and returns canonical `Hybrid.User` objects. Provider-native objects remain behind provider contracts.

### Delivered Changes

#### Application Service / Provider Integration

- Expanded `Application.HybridUserService.psm1` so Active Directory can act as the first live provider source for the vertical slice.
- Preserved mock-provider compatibility from Phase 1.
- Added live AD source status metadata to composite users.
- Added provider health snapshots to service health and source status output.
- Added Active Directory-backed properties to the composite user model where available:
  - `Company`
  - `Office`
  - `EmployeeId`
  - `DistinguishedName`
  - `Enabled`
  - `LockedOut`
  - `ActiveDirectory`
- Added Phase 2 automated tests using a live-provider-shaped Active Directory service object.

#### UI Vertical Slice Completion

- Reopened Phase 2 to complete the visible UI portion of the Live Active Directory slice.
- Updated `src/UI/Start-HybridAdminConsole.ps1` so the user-facing shell clearly reflects live AD search through `HybridUserService`.
- Added an Active Directory provider health badge.
- Added a search activity panel with progress state and elapsed-time feedback.
- Added a live Active Directory properties card for company, office, employee ID, account state, and distinguished name.
- Added better no-result and search-error presentation inside the result pane.
- Preserved the rule that the UI never calls providers or Active Directory directly.
- Added static UI validation tests that confirm service-driven search, health indicators, busy-state handling, and AD property presentation.

### Files Changed

```text
src/Application/Application.HybridUserService.psm1
tests/Test-Milestone7Phase2.ps1
src/UI/Start-HybridAdminConsole.ps1
tests/Test-Milestone7Phase2UI.ps1
docs/Milestones/MILESTONE_7_PHASE_2.md
MANIFEST.txt
```

### Validation Commands

Run from the repository root:

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File
Remove-Module Application.HybridUserService,Infrastructure.ActiveDirectory,Core.ProviderBase,ActiveDirectory,Hybrid.Models -Force -ErrorAction SilentlyContinue
.\tests\Test-Milestone7Phase1.ps1
.\tests\Test-Milestone7Phase2.ps1
.\tests\Test-Milestone7Phase2UI.ps1
```

Optional UI smoke test in mock mode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\src\UI\Start-HybridAdminConsole.ps1 -Mock -InitialQuery Alex
```

Optional broader regression pass:

```powershell
.\tests\Test-Milestone6.ps1
.\tests\Test-Milestone7Phase1.ps1
.\tests\Test-Milestone7Phase2.ps1
.\tests\Test-Milestone7Phase2UI.ps1
```

### Completion Notes

This phase is complete when the Phase 1, Phase 2 service, and Phase 2 UI tests pass on the `feature/milestone7-service-layer` branch after extracting the drop-in ZIP into the repository root.

No project-level status, roadmap, changelog, or version files were updated because Milestone 7 is not complete.
