# Milestone 8 Phase 8.1 - Runtime Profile Discovery

## Status

Complete when `tests/Test-Milestone8Phase8_1.ps1` and cumulative Milestone 8 tests pass.

## Purpose

Phase 8.1 makes runtime profiles first-class startup objects. The shell no longer assumes a single active profile. It discovers profiles under `profiles/Runtime`, resolves the initial selection, and lets the operator choose the runtime profile before launching the dashboard.

## Scope

- Add `Application.RuntimeProfileManager`.
- Discover runtime profile JSON files.
- Extract lightweight metadata without initializing live providers.
- Resolve initial selection using last-used, default, Simulation, then first valid profile.
- Persist last-used profile selection.
- Add a runtime profile list to the Home/startup shell.
- Refresh startup summary when the selected profile changes.
- Bootstrap the selected profile path when Launch is clicked.

## Non-goals

- No import/export operations yet.
- No delete or duplicate workflow yet.
- No live connectivity checks.
- No Device Code authentication.
- No provider-specific UI logic.

## Architecture

The profile discovery logic lives in the Application layer so the UI does not scan the filesystem directly. The shell asks the Runtime Profile Manager for summaries and renders them as startup choices.

## Validation

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File

Remove-Module Application.RuntimeProfileManager,Core.Deployment,Core.Runtime,Core.RuntimeProfile,Core.ServiceRegistry,Application.HybridUserService,Application.GraphProfileService,Application.AuthenticationProfileService,Application.HybridUserAggregationService,Infrastructure.DirectorySimulator -Force -ErrorAction SilentlyContinue

.\tools\Apply-Milestone8Phase8_1.ps1
.\tests\Test-Milestone8Phase8_1.ps1
.\tests\Test-Milestone8Phase7.ps1
.\tests\Test-Milestone8Phase6_1.ps1
.\tests\Test-Milestone8Phase6.ps1
.\tests\Test-Milestone8Phase5_5.ps1
.\tests\Test-Milestone8Phase5.ps1
.\tests\Test-Milestone8Phase4.ps1
.\tests\Test-Milestone8Phase3.ps1
.\tests\Test-Milestone8Phase2.ps1
.\tests\Test-Milestone8Phase1.ps1
```


## Hotfix 1 - Selected Profile Edit Binding

The startup shell now distinguishes between New and Edit runtime profile flows.

- New opens the wizard with default simulation values.
- Edit loads the currently selected runtime profile JSON into the wizard before displaying it.
- Saves during edit preserve the selected profile source path.

This keeps runtime profile discovery and profile editing aligned with the selected profile on the Home screen.
