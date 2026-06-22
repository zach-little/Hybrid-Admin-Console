
## v0.8.2 — Milestone 8.2 Branding & Theme System

- Added Runtime Home Branding & Theme action.
- Added runtime profile theme editor overlay with preview.
- Added profile/organization brand package support.
- Added dynamic window title, color token, logo, icon, and splash path theme model fields.
- Added `New-HybridUiBrandPackage` and `Get-HybridUiBrandingPackagePath`.
- Renamed XAML token application to approved PowerShell verb `Set-HybridUiThemeToXaml`.
- Added Milestone 8.2 branding/theme validation tests.

# Changelog

## v0.8.2 - Runtime Platform Hardening

- Aligned root launcher to the runtime/profile WPF entry point.
- Added UI modules for runtime home, profile manager, profile wizard, launch button behavior, dashboard helpers, status bar helpers, and dynamic themes.
- Improved responsive startup layout and action footer behavior for smaller screens and RDP sessions.
- Updated Launch button to wrap full profile names instead of truncating them.
- Added dynamic theme support from runtime profile branding, organization branding, and optional repository theme overrides.
- Normalized runtime hardening version labels to v0.8.2.
- Added cumulative Milestone 8.1 hardening tests.

## v0.8.0

- Completed Milestone 8 Runtime Platform.
- Added Runtime Profile Foundation.
- Added Runtime Bootstrap Engine.
- Added Runtime Provider Modes.
- Added Startup Diagnostics Engine.
- Added Startup Shell and dashboard layout foundation.
- Added Runtime Profile Wizard and improved multi-step UX.
- Added Deployment and Packaging support.
- Added Runtime Profile Manager with discovery, cards, profile operations, launch workflow, and persistent status.
- Maintained no Device Code authentication policy.

## v0.8.2 - Final Brand Polish

- Added the HAP application icon asset and wired it into the Runtime Home, main console header, summary tile, and window icon.
- Refined Runtime Home footer button sizing, selected profile highlighting, dynamic Launch profile labeling, and colorized runtime status values.

## Milestone 8 Final Icon Startup Fix

- Fixed WPF startup failure caused by declaring a PNG file as the `Window.Icon` in XAML.
- Centralized HAP brand asset resolution.
- Uses PNG branding inside the UI and ICO branding for the native window/taskbar icon.
