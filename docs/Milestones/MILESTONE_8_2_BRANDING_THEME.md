# Milestone 8.2 — Branding & Theme System

## Version

v0.8.2

## Status

Complete.

## Summary

Milestone 8.2 promotes HAP branding from static assets into a runtime-profile-aware branding and theme system.

The application now supports a profile/organization brand package that can define colors, window title, display name, and brand asset paths without changing UI code.

## Completed

- Branding & Theme action exposed from Runtime Home.
- Runtime theme editor overlay added to the profile management experience.
- Theme editor supports package name, window title, organization display name, color tokens, logo path, icon path, and splash path.
- Theme preview surface added for quick color validation.
- Theme save workflow writes `profiles/<Organization>/<Package>/theme.json`.
- Runtime profile JSON is updated with a `Branding` reference.
- Theme resolver now supports brand packages, organization branding files, repository theme overrides, and runtime profile overrides.
- XAML token replacement uses approved PowerShell verb naming.
- Brand package example added under `assets/themes`.
- Runtime/Profile Manager version labels advanced to v0.8.2.

## Branding Package Layout

```text
profiles/
  Atlas/
    Branding/
      theme.json
      logo.png
      icon.ico
      splash.png
```

Runtime profile reference:

```json
{
  "ProfileName": "Atlas",
  "Organization": "Atlas",
  "Branding": {
    "Package": "Branding",
    "PackagePath": "profiles\\Atlas\\Branding"
  }
}
```

## Validation

```powershell
Get-ChildItem -Path . -Recurse -File | Unblock-File
Remove-Module UI.Theme,UI.RuntimeHome,UI.RuntimeLaunch,UI.RuntimeProfileManager,UI.RuntimeProfileWizard,UI.UserDashboard,UI.StatusBar,Core.Runtime,Application.RuntimeProfileManager -Force -ErrorAction SilentlyContinue
.\tests\Test-Milestone8_1Hardening.ps1
.\tests\Test-Milestone8_1PowerShellHygiene.ps1
.\tests\Test-Milestone8_2BrandingThemeSystem.ps1
```
