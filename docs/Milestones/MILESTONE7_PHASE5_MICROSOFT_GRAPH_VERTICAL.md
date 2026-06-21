# Milestone 7 Phase 5 - Microsoft Graph Vertical

## Status

In progress / UI integration repair applied.

## Objective

Add a Microsoft Graph vertical that exposes user Graph profile details through the service layer, deterministic Directory Simulator data, UI display helpers, and cumulative validation tests while preserving the stable Phase 4 Exchange baseline.

## Scope

Phase 5 adds:

- `Hybrid.GraphProfile` domain model factory.
- `Application.GraphProfileService` service-layer module.
- Directory Simulator Microsoft Graph profile data for deterministic users.
- A live Microsoft Graph card in the desktop UI.
- `Test-Milestone7Phase5.ps1` validation.
- `Test-Milestone7Phase5GraphCardLive.ps1` validation for live UI integration.

## UI Behavior

The Microsoft Graph section is not a button workflow. It is a real card in the user detail surface and loads automatically whenever a user search populates the current user.

The card displays:

- Graph Object ID
- User Type
- Usage Location
- Preferred Language
- MFA Registered
- MFA Capable
- Authentication Methods
- Last Sign-In
- Password Last Changed
- Risk State

## Directory Simulator Behavior

The Directory Simulator Microsoft Graph provider now exposes dedicated Graph profile operations:

- `GetGraphProfile`
- `GetUserGraphProfile`
- `GetAuthenticationProfile`

These return deterministic Graph-specific data instead of falling back to the generic user object.

## Validation

Run from repository root:

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File
Remove-Module Application.GraphProfileService,Hybrid.GraphProfile,DirectorySimulator.GraphVertical,UI.GraphProfilePanel,Application.HybridUserService,Infrastructure.DirectorySimulator -Force -ErrorAction SilentlyContinue
.	ests\Test-Milestone7Phase1.ps1
.	ests\Test-Milestone7Phase2.ps1
.	ests\Test-Milestone7Phase3.ps1
.	ests\Test-Milestone7Phase4.ps1
.	ests\Test-Milestone7Phase5.ps1
.	ests\Test-Milestone7Phase5GraphCardLive.ps1
```

Launch UI validation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\src\UI\Start-HybridAdminConsole.ps1 -Mock -InitialQuery Alex
```

Expected result: one Microsoft Graph card auto-loads real Graph data for the current populated user and refreshes when a new search is run.
