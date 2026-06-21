# Milestone 7 Phase 4 - Exchange Vertical and Directory Simulator

## Objective

Deliver the Exchange Online user mailbox vertical slice while replacing ad-hoc mock user records with a deterministic directory simulator.

Phase 4 expands the service-backed user dashboard so a technician can search a user and see mailbox state, recipient type, forwarding, mailbox delegation, and distribution group context through the application service layer.

## Scope

### Service Layer

- Added `Get-HybridUserMailboxDetails`.
- Added mailbox-specific cache tracking.
- Added `MailboxDetails`, `ExchangeLoaded`, and `ExchangeRetrievedOn` to the composite user flow.
- Aggregates Exchange mailbox, forwarding, statistics, delegations, and distribution groups through provider operations only.

### UI

- Added an Exchange Mailbox card.
- Added recipient type, mailbox status, forwarding, delegation, and distribution group fields.
- Manual search now refreshes Exchange panels along with Active Directory detail panels.
- Empty Exchange states are explicit rather than blank.

### Directory Simulator

- Added `Infrastructure.DirectorySimulator.psm1`.
- Mock mode now uses a deterministic simulated directory instead of hard-coded records inside the UI.
- Simulated manager/direct-report relationships are coherent and avoid impossible AD relationships such as a user being their own manager or direct report.
- Simulator provides Active Directory, Microsoft Graph, and Exchange provider objects for service-layer testing.

### Documentation

- Added directory simulator expectations to engineering coding standards.
- Updated only the active phase documentation for Milestone 7 Phase 4.

## Validation

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File
Remove-Module Application.HybridUserService,Infrastructure.DirectorySimulator,Infrastructure.ActiveDirectory,Core.ProviderBase,ActiveDirectory,Hybrid.Models -Force -ErrorAction SilentlyContinue
.\tests\Test-Milestone7Phase1.ps1
.\tests\Test-Milestone7Phase2.ps1
.\tests\Test-Milestone7Phase2UI.ps1
.\tests\Test-Milestone7Phase3.ps1
.\tests\Test-Milestone7Phase3UIInteraction.ps1
.\tests\Test-Milestone7Phase4.ps1
.\tests\Test-Milestone7Phase4UIInteraction.ps1
```

## UI Smoke Test

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\src\UI\Start-HybridAdminConsole.ps1 -Mock -InitialQuery Alex
```

## Status

In progress pending validation.


## Consolidation fix

This phase preserves the cumulative Phase 2 and Phase 3 UI/service validation markers while adding the Exchange vertical. The directory simulator exports the user, manager, group, direct-report, mailbox, delegation, distribution group, and provider health commands needed by the application service and by direct simulator validation.


## Consolidated Stability Fix

This patch restores cumulative Phase 2/Phase 3 expectations while preserving the Phase 4 Exchange vertical. The Directory Simulator now resolves seeded users deterministically, avoids impossible self-manager/self-report relationships, and the UI launches cleanly in mock mode.
