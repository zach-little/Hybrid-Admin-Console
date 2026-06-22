# Milestone 8 Phase 6.1 - Runtime Profile Wizard UX

## Status

Complete.

## Purpose

Phase 6.1 improves the Runtime Profile Wizard user experience without changing the runtime profile model, bootstrap logic, provider logic, authentication behavior, or save path.

## Changes

- Converted the wizard from a single scrolling form into a focused multi-step overlay workflow.
- Added explicit wizard steps:
  - Profile
  - Environment
  - Runtime Mode
  - Providers
  - Validation
  - Summary
- Added Back, Next, Finish, and close behavior.
- Retained Validate Profile and Save Profile behavior.
- Preserved all existing wizard input control names so Phase 6 tests and bindings remain compatible.
- Replaced Unicode dash punctuation with ASCII-safe labels to avoid PowerShell/WPF encoding issues on Windows.
- Kept the wizard hosted inside the existing shell overlay region.

## Non-Goals

- No runtime profile schema changes.
- No live provider connectivity testing.
- No authentication prompts.
- No Device Code authentication.
- No deployment or packaging changes.

## Validation

Run:

```powershell
.\tests\Test-Milestone8Phase6_1.ps1
.\tests\Test-Milestone8Phase6.ps1
.\tests\Test-Milestone8Phase5_5.ps1
.\tests\Test-Milestone8Phase5.ps1
.\tests\Test-Milestone8Phase4.ps1
.\tests\Test-Milestone8Phase3.ps1
.\tests\Test-Milestone8Phase2.ps1
.\tests\Test-Milestone8Phase1.ps1
```
