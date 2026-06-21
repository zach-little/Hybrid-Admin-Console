# Milestone 8 Phase 5 — Start Screen / Startup Shell

## Status

Complete when `Test-Milestone8Phase5.ps1` and cumulative Milestone 8 tests pass.

## Purpose

Phase 5 introduces the first user-facing runtime platform experience. The application now starts in a single-window startup shell that displays runtime profile, cloud, provider, and diagnostics information before the main console is shown.

This phase intentionally uses one WPF window and swaps views rather than opening a separate splash window. That keeps one dispatcher, one resource scope, one runtime context, and a clean path for the Phase 6 Runtime Profile Wizard.

## Scope

Included:

- Startup shell view inside `Start-HybridAdminConsole.ps1`
- Runtime summary cards
- Provider summary
- Startup diagnostics summary
- Launch transition into the existing console view
- Disabled `Edit Runtime Profile` placeholder for Phase 6
- Exit button
- Static and runtime validation tests

Excluded:

- Runtime profile editing
- Runtime profile wizard
- Provider connectivity checks
- Authentication prompts
- New live provider behavior
- Separate splash window

## Architecture

Startup flow:

```text
Start-HybridAdminConsole.ps1
        |
        v
Initialize-HybridRuntime
        |
        v
Startup Shell View
        |
        +-- Launch Hybrid Admin Console -> existing console view
        +-- Edit Runtime Profile -> disabled until Phase 6
        +-- Exit
```

The runtime is initialized once and remains alive for the life of the application.

## Validation

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File

Remove-Module Core.Runtime,Core.RuntimeProfile,Core.ServiceRegistry,Application.HybridUserService,Application.GraphProfileService,Application.AuthenticationProfileService,Application.HybridUserAggregationService,Infrastructure.DirectorySimulator -Force -ErrorAction SilentlyContinue

.\tools\Apply-Milestone8Phase5.ps1
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

- Startup screen appears first.
- Runtime Profile, Cloud Environment, Runtime Mode, Version, Provider Summary, and Diagnostics Summary are populated.
- `Edit Runtime Profile` is visible but disabled.
- `Launch Hybrid Admin Console` reveals the existing console.
- Initial query loads after launch.
- Existing search/cards continue to work.
