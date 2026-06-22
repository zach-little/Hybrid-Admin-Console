# Milestone 8.1 — Runtime Platform Hardening

## Version

v0.8.1

## Purpose

Milestone 8.1 hardens the completed Runtime Platform before Milestone 9 begins. The focus is launcher alignment, UI decomposition, responsive layout safety, runtime profile launch UX, stronger validation, and dynamic theming support.

## Completed

- Root launcher now enters the HAP runtime/profile WPF experience instead of the legacy shell path.
- Runtime UI accepts an explicit `-Profile` parameter and still safely falls back to Simulation.
- Runtime Home, profile manager, launch, wizard, dashboard, status bar, and theme helpers now have dedicated UI modules.
- Launch button text wraps instead of truncating long profile names.
- Startup window dimensions were reduced and min-size constraints relaxed for smaller screens and RDP sessions.
- Runtime action footer now scrolls/wraps instead of allowing command tiles to disappear.
- Version strings were normalized to `v0.8.1`.
- Dynamic UI theme resolution was added from runtime profile branding, organization branding, and optional `assets/themes/hap.theme.json`.
- Added a theme example file for organization-specific color compliance.
- Added cumulative hardening tests for launcher, UI modules, responsive layout, launch wrapping, dynamic themes, and runtime profile behavior.

## Theme Resolution Order

The UI theme resolver uses the following order:

1. Built-in HAP Dark defaults.
2. Runtime profile `Branding` or `Theme` object, when present.
3. Organization branding file at `profiles/<Organization>/branding.json`, when the selected runtime profile declares an organization.
4. Optional repository override at `assets/themes/hap.theme.json`.

This allows Atlas or any other organization profile to enforce approved color values without changing UI code.

## Validation

Run:

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File
Remove-Module UI.Theme,UI.RuntimeHome,UI.RuntimeLaunch,UI.RuntimeProfileManager,UI.RuntimeProfileWizard,UI.UserDashboard,UI.StatusBar,Core.Runtime,Application.RuntimeProfileManager -Force -ErrorAction SilentlyContinue
.\tests\Test-Milestone8_1Hardening.ps1
```
